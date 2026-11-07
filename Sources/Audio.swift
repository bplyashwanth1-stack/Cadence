import Accelerate
import AudioToolbox
import CoreAudio
import Foundation

/// Listens to what the Mac is playing through a Core Audio process tap (macOS 14.2+), so the visuals can hit on
/// the real kick drum instead of guessing from lyric timing. Audio never leaves the process; only loudness,
/// bass hits and a 32-band spectrum are kept.
final class AudioPulse {
    static let shared = AudioPulse()

    struct Snapshot {
        var level: Float = 0  // overall loudness, auto-gained to 0...1
        var bass: Float = 0  // low end, auto-gained to 0...1
        var vocal: Float = 0  // the 300 Hz–3 kHz band where singing sits, auto-gained to 0...1
        var bands = [Float](repeating: 0, count: AudioPulse.bandCount)
        var lastBeat = Date.distantPast
        var updated = Date.distantPast
        var lastSound = Date.distantPast  // last time anything above silence came through
    }

    static let bandCount = 32
    private let lock = NSLock()
    private var state = Snapshot()

    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?
    private let queue = DispatchQueue(label: "cadence.audio", qos: .userInteractive)
    private(set) var running = false
    private var failed = false

    // Analysis state, touched only on `queue`.
    private let fftSize = 1024
    private var ring: [Float]
    private var ringPos = 0
    private var window: [Float]
    private let fft: vDSP.FFT<DSPSplitComplex>
    private var real: [Float]
    private var imag: [Float]
    private var sampleRate: Double = 48_000
    private var bandPeak = [Float](repeating: 1e-6, count: AudioPulse.bandCount)
    private var levelPeak: Float = 1e-6
    private var bassPeak: Float = 1e-6
    private var vocalPeak: Float = 1e-6
    private var bassAverage: Float = 0
    private var lastBeat = Date.distantPast
    private var levels: [(date: Date, level: Float)] = []  // singing band, every 20 ms, until collected
    private var lastLevel = Date.distantPast
    private var lastCallback = Date.distantPast
    private var startedAt = Date.distantPast

    private init() {
        ring = [Float](repeating: 0, count: fftSize)
        window = vDSP.window(ofType: Float.self, usingSequence: .hanningDenormalized, count: fftSize, isHalfWindow: false)
        fft = vDSP.FFT(log2n: 10, radix: .radix2, ofType: DSPSplitComplex.self)!
        real = [Float](repeating: 0, count: fftSize / 2)
        imag = [Float](repeating: 0, count: fftSize / 2)
    }

    /// Latest analysis, or nil when the tap isn't delivering (older macOS) or only delivers silence — which is
    /// also what a denied permission looks like — so callers fall back to lyric timing.
    func snapshot() -> Snapshot? {
        lock.lock(); defer { lock.unlock() }
        let now = Date()
        return now.timeIntervalSince(state.updated) < 0.5 && now.timeIntervalSince(state.lastSound) < 2 ? state : nil
    }

    /// Whether Cadence can hear what's playing, for the warning in the menu bar.
    enum Health { case fine, notRunning, noAudio, silent }

    func health() -> Health {
        lock.lock(); defer { lock.unlock() }
        let now = Date()
        guard running, now.timeIntervalSince(startedAt) > 15 else { return running ? .fine : .notRunning }
        // Started a while ago and Core Audio never delivered a single buffer: the tap is stuck.
        if now.timeIntervalSince(lastCallback) > 5 { return .noAudio }
        // Buffers arrive but hold nothing while music plays: usually the recording permission.
        if now.timeIntervalSince(state.lastSound) > 15 { return .silent }
        return .fine
    }

    /// The singing-band levels since the last call, for learning a song's timing.
    func takeLevels() -> [(date: Date, level: Float)] {
        lock.lock(); defer { lock.unlock() }
        let taken = levels
        levels = []
        return taken
    }

    /// How long sound takes to reach your ears after the Mac plays it, in seconds. Bluetooth headphones add a lot.
    static func outputDelay() -> Double {
        func read(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector, _ scope: AudioObjectPropertyScope) -> UInt32 {
            var address = AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
            var value: UInt32 = 0
            var size = UInt32(MemoryLayout<UInt32>.size)
            return AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr ? value : 0
        }
        let device = read(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDefaultOutputDevice,
                          kAudioObjectPropertyScopeGlobal)
        guard device != 0 else { return 0 }
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyNominalSampleRate,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var rate = 0.0
        var size = UInt32(MemoryLayout<Double>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &rate) == noErr, rate > 0 else { return 0 }
        let frames = read(device, kAudioDevicePropertyLatency, kAudioObjectPropertyScopeOutput)
            + read(device, kAudioDevicePropertySafetyOffset, kAudioObjectPropertyScopeOutput)
            + read(device, kAudioDevicePropertyBufferFrameSize, kAudioObjectPropertyScopeGlobal)
        return min(Double(frames) / rate, 0.5)
    }

    /// 1 on a bass hit, decaying to 0.
    func kick(at date: Date) -> Double? {
        guard let s = snapshot() else { return nil }
        let since = date.timeIntervalSince(s.lastBeat)
        return max(exp(-since * 6), Double(s.bass) * 0.35)
    }

    /// Starting the tap can block until the user answers the audio-capture prompt, so it never runs on the main
    /// thread — that froze every animation while the prompt was up.
    private let control = DispatchQueue(label: "cadence.audio.control")

    func setRunning(_ on: Bool) {
        control.async { self.apply(on) }
    }

    private func apply(_ on: Bool) {
        if on && !running && !failed {
            if #available(macOS 14.2, *) {
                do { try start() } catch {
                    failed = true
                    Log.write("audio tap failed: \(error)")
                    stop()
                }
            }
        } else if !on && running {
            stop()
        }
    }

    struct TapError: Error, CustomStringConvertible {
        let step: String
        let status: OSStatus
        var description: String { "\(step) (\(status))" }
    }

    @available(macOS 14.2, *)
    private func start() throws {
        // Tap everything the Mac plays, mixed to stereo, without muting it.
        let description = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        description.uuid = UUID()
        description.name = "Cadence"
        description.isPrivate = true
        description.muteBehavior = .unmuted
        var status = AudioHardwareCreateProcessTap(description, &tapID)
        guard status == noErr else { throw TapError(step: "create tap", status: status) }

        var format = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        var address = AudioObjectPropertyAddress(mSelector: kAudioTapPropertyFormat, mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        if AudioObjectGetPropertyData(tapID, &address, 0, nil, &size, &format) == noErr, format.mSampleRate > 0 {
            sampleRate = format.mSampleRate
        }

        let outputUID = try Self.defaultOutputUID()
        let aggregate: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Cadence Listener",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
            kAudioAggregateDeviceTapListKey: [[kAudioSubTapDriftCompensationKey: true,
                                               kAudioSubTapUIDKey: description.uuid.uuidString]],
        ]
        status = AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &aggregateID)
        guard status == noErr else { throw TapError(step: "create aggregate device", status: status) }

        status = AudioDeviceCreateIOProcIDWithBlock(&procID, aggregateID, queue) { [weak self] _, input, _, _, _ in
            self?.process(input)
        }
        guard status == noErr else { throw TapError(step: "create io proc", status: status) }
        status = AudioDeviceStart(aggregateID, procID)
        guard status == noErr else { throw TapError(step: "start", status: status) }
        running = true
        startedAt = Date()
        Log.write("audio tap running at \(sampleRate) Hz")
    }

    private func stop() {
        if let procID {
            AudioDeviceStop(aggregateID, procID)
            AudioDeviceDestroyIOProcID(aggregateID, procID)
        }
        procID = nil
        if aggregateID != kAudioObjectUnknown { AudioHardwareDestroyAggregateDevice(aggregateID) }
        if #available(macOS 14.2, *), tapID != kAudioObjectUnknown { AudioHardwareDestroyProcessTap(tapID) }
        aggregateID = AudioObjectID(kAudioObjectUnknown)
        tapID = AudioObjectID(kAudioObjectUnknown)
        running = false
    }

    private static func defaultOutputUID() throws -> String {
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultSystemOutputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device)
        guard status == noErr else { throw TapError(step: "default output", status: status) }
        var uid: Unmanaged<CFString>?
        size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        address.mSelector = kAudioDevicePropertyDeviceUID
        status = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &uid)
        guard status == noErr, let uid else { throw TapError(step: "output uid", status: status) }
        return uid.takeRetainedValue() as String
    }

    // MARK: Analysis

    private func process(_ input: UnsafePointer<AudioBufferList>) {
        lock.lock(); lastCallback = Date(); lock.unlock()
        let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
        guard let first = buffers.first, let data = first.mData else { return }
        let channels = Int(max(first.mNumberChannels, 1))
        let frames = Int(first.mDataByteSize) / (MemoryLayout<Float>.size * channels)
        guard frames > 0 else { return }
        let samples = data.assumingMemoryBound(to: Float.self)
        for i in 0..<frames {
            var sum: Float = 0
            for c in 0..<channels { sum += samples[i * channels + c] }
            ring[ringPos] = sum / Float(channels)
            ringPos = (ringPos + 1) % fftSize
        }
        analyse()
    }

    private func analyse() {
        // Oldest-first copy of the ring, windowed.
        let ordered = Array(ring[ringPos...] + ring[..<ringPos])
        let windowed = vDSP.multiply(ordered, window)
        var power = [Float](repeating: 0, count: fftSize / 2)
        real.withUnsafeMutableBufferPointer { realPtr in
            imag.withUnsafeMutableBufferPointer { imagPtr in
                var split = DSPSplitComplex(realp: realPtr.baseAddress!, imagp: imagPtr.baseAddress!)
                windowed.withUnsafeBufferPointer { w in
                    w.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: fftSize / 2) {
                        vDSP_ctoz($0, 2, &split, 1, vDSP_Length(fftSize / 2))
                    }
                }
                fft.forward(input: split, output: &split)
                vDSP.squareMagnitudes(split, result: &power)
            }
        }

        let binHz = Float(sampleRate) / Float(fftSize)
        func energy(_ low: Float, _ high: Float) -> Float {
            let a = max(1, Int(low / binHz)), b = min(power.count - 1, max(a, Int(high / binHz)))
            return vDSP.mean(power[a...b])
        }

        // Each value is divided by a slowly decaying peak, so quiet and loud songs both fill the range.
        func gain(_ value: Float, _ peak: inout Float) -> Float {
            peak = max(value, peak * 0.995)
            return min(1, sqrt(value / max(peak, 1e-9)))
        }

        var bands = [Float](repeating: 0, count: Self.bandCount)
        for i in 0..<Self.bandCount {
            // Log-spaced from 40 Hz to 14 kHz.
            let low = 40 * pow(350, Float(i) / Float(Self.bandCount))
            let high = 40 * pow(350, Float(i + 1) / Float(Self.bandCount))
            bands[i] = gain(energy(low, high), &bandPeak[i])
        }
        let bassEnergy = energy(30, 150)
        let bass = gain(bassEnergy, &bassPeak)
        let level = gain(vDSP.mean(power), &levelPeak)
        let vocal = gain(energy(300, 3000), &vocalPeak)

        // A beat: bass jumps well above its recent average, at most ~4 per second.
        let now = Date()
        if bassEnergy > bassAverage * 1.6, bass > 0.45, now.timeIntervalSince(lastBeat) > 0.23 {
            lastBeat = now
        }
        bassAverage = bassAverage * 0.97 + bassEnergy * 0.03

        lock.lock()
        if now.timeIntervalSince(lastLevel) >= 0.02 {
            lastLevel = now
            levels.append((now, vocal))
            if levels.count > 2000 { levels.removeFirst(levels.count - 2000) }
        }
        // Ease towards the new readings so bars don't flicker between callbacks.
        state.level += (level - state.level) * 0.5
        state.bass += (bass - state.bass) * 0.6
        state.vocal += (vocal - state.vocal) * 0.3
        for i in 0..<Self.bandCount {
            let v = bands[i]
            state.bands[i] = v > state.bands[i] ? v : state.bands[i] * 0.85 + v * 0.15
        }
        state.lastBeat = lastBeat
        state.updated = now
        if vDSP.maximumMagnitude(ring) > 1e-4 {
            if state.lastSound == .distantPast { Log.write("audio: hearing music") }
            state.lastSound = now
        }
        lock.unlock()
    }
}
