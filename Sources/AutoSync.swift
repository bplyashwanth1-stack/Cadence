import Foundation
import IOKit.ps

// MARK: - Auto-fix lyric timing

/// LRCLIB timings are user-submitted and can be a second or two off. While Cadence can hear the music, this
/// compares when the singing band is busy with when the lyrics say someone is singing, finds the shift that
/// lines them up best, and applies it — but only when the match is clear, so it never makes good timing worse.
final class AutoSync {
    static let shared = AutoSync()

    /// Seconds added to lyric time on top of the user's own offset.
    private(set) var offset = 0.0

    private let rate = 10.0  // samples per second
    private let window = 50.0  // seconds of history compared
    private let maxShift = 2.5
    private var samples: [(position: Double, vocal: Double)] = []
    private var trackID: String?
    private var lastPosition = 0.0
    private var candidate: Double?
    private var agreeing = 0
    private var timer: Timer?
    private var tick = 0
    private var remembered = UserDefaults.standard.dictionary(forKey: "autoOffsets") as? [String: Double] ?? [:] {
        didSet { UserDefaults.standard.set(remembered, forKey: "autoOffsets") }
    }
    private var trace: [(position: Double, level: Double)] = []
    private var heard: [LyricLine] = []  // the lyrics the trace belongs to
    private var learned = false
    /// How much longer a video runs than the song in it (an intro, an outro, skits). The song can start anywhere
    /// in that, so the search for the right shift reaches that much further back.
    private var videoGap = 0.0
    private var gapFor = ""

    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1 / rate, repeats: true) { [weak self] _ in self?.sample() }
    }

    private var confirmed = false  // logged that this song's timing checks out

    private func reset() {
        confirmed = false
        samples = []
        candidate = nil
        offset = 0
        trace = []
        heard = []
        learned = false
    }

    /// Learns from what was heard of a song, off the main thread, and saves it for next time.
    private func learn(_ id: String?) {
        guard !learned, let id, !heard.isEmpty, Style.shared.v.learnTiming, !SongTiming.shared.isManual(id),
              !NowPlaying.shared.isEstimated(id), let saved = LyricsStore.load(id), !saved.contains("<") else { return }
        learned = true
        let lines = heard, trace = trace, offset = offset
        DispatchQueue.global(qos: .utility).async {
            guard let result = LearnedTiming.learn(lines: lines, trace: trace, offset: offset) else {
                Log.write("learned timing: too unclear for \(id)")
                return
            }
            LyricsStore.save(result.lrc, for: id)
            DispatchQueue.main.async {
                NowPlaying.shared.forgetCached(id)
                self.remembered[id] = nil
            }
            Log.write(String(format: "learned timing for %@: %d of %d lines, typical move %.2f s", id, result.moved,
                             result.total, result.shift))
        }
    }

    private var listening = false

    private func sample() {
        let player = NowPlaying.shared
        // Listen while music plays — for the lock screen's beat, and so timing is already fixed by the time
        // the Mac is locked.
        let s = Style.shared.v
        let listen = s.audioReactive && (player.stageVisible(s) || (player.isPlaying && s.autoSync))
        if listen != listening {
            listening = listen
            AudioPulse.shared.setRunning(listen)
        }
        tick += 1
        if tick % Int(rate * 2) == 0 { player.outputDelay = s.matchOutput ? AudioPulse.outputDelay() : 0 }
        guard Style.shared.v.autoSync else {
            if offset != 0 { reset() }
            return
        }
        if player.track?.id != trackID {
            learn(trackID)  // what was heard of the last song, if it wasn't learned near its end
            trackID = player.track?.id
            reset()
            // Keeps what earlier plays found, so a replay is right from the first line.
            offset = trackID.flatMap { remembered[$0] } ?? 0
        }
        // A song you've fixed by hand is left alone.
        guard player.isPlaying, !player.lyrics.isEmpty, !SongTiming.shared.isManual(player.track?.id),
              let audio = AudioPulse.shared.snapshot() else { return }
        let position = player.position(at: Date())
        // A seek breaks the history's timeline; start collecting again (the found offset still holds).
        if abs(position - lastPosition - 1 / rate) > 1 { samples = [] }
        lastPosition = position
        samples.append((position, Double(audio.vocal)))
        if samples.count > Int(window * rate) { samples.removeFirst(samples.count - Int(window * rate)) }

        heard = player.lyrics
        for level in AudioPulse.shared.takeLevels() {
            trace.append((player.position(at: level.date), Double(level.level)))
        }
        if position > player.duration * 0.92 { learn(trackID) }
        updateVideoGap()

        if tick % Int(rate * 4) == 0 { solve() }  // every 4 s
    }

    private func updateVideoGap() {
        let player = NowPlaying.shared
        guard let track = player.track, track.video else {
            videoGap = 0
            return
        }
        let key = "\(track.id)|\(player.lyrics.count)|\(player.lyrics.first?.start ?? 0)"
        guard key != gapFor else { return }
        gapFor = key
        let length = LyricsStore.load(track.id).flatMap(LRC.length)
        videoGap = length.map { min(max(track.duration - $0, 0), 180) } ?? 0
        if videoGap > 4 { Log.write(String(format: "auto-sync: video runs %.0f s longer than the song", videoGap)) }
    }

    /// Lines up the moments singing starts (jumps in the vocal band) with the lines' start times, for every shift
    /// in ±2.5 s, and keeps the best. Line starts are the one thing lyric files time exactly; comparing whole
    /// sung spans instead was too blunt to notice even a 1.5 s error.
    private func solve() {
        guard samples.count >= Int(rate * 20) else { return }
        let starts = NowPlaying.shared.lyrics.filter { !$0.words.isEmpty }.map(\.start).sorted()
        // In a video the song can begin well after the video does: lyric time = video time - intro.
        let lowest = videoGap > 4 ? -(videoGap + maxShift) : -maxShift
        let userOffset = Style.shared.v.offset

        // Vocal level smoothed over ~0.5 s; an onset is how much it rose over the last 0.2 s.
        let raw = samples.map(\.vocal)
        let smooth = raw.indices.map { i in
            let lo = max(0, i - 2), hi = min(raw.count - 1, i + 2)
            return raw[lo...hi].reduce(0, +) / Double(hi - lo + 1)
        }
        let onsets = smooth.indices.map { i in i >= 2 ? max(0, smooth[i] - smooth[i - 2]) : 0 }
        guard let vocal = standardised(onsets) else { return }

        // A soft bump around each line start (only those within a second can add anything; found by bisection, as
        // a video's wide search tries hundreds of shifts).
        func bump(_ t: Double) -> Double {
            var lo = 0, hi = starts.count
            while lo < hi {
                let mid = (lo + hi) / 2
                if starts[mid] < t - 1 { lo = mid + 1 } else { hi = mid }
            }
            var sum = 0.0
            while lo < starts.count, starts[lo] <= t + 1 {
                let d = t - starts[lo]
                sum += exp(-d * d / 0.125)
                lo += 1
            }
            return sum
        }

        var scores: [(shift: Double, score: Double)] = []
        for step in Int((lowest * 10).rounded())...Int(maxShift * 10) {
            let shift = Double(step) / 10
            let mask = samples.map { bump($0.position + userOffset + shift) }
            guard let m = standardised(mask) else {
                // No line starts in the window at this shift. Within the usual range that means nothing to go on.
                if lowest == -maxShift { return }
                scores.append((shift, 0))
                continue
            }
            let score = zip(m, vocal).map(*).reduce(0, +) / Double(m.count)
            scores.append((shift, score))
        }
        guard let best = scores.max(by: { $0.score < $1.score }),
              let current = scores.min(by: { abs($0.shift - offset) < abs($1.shift - offset) }) else { return }
        // The best match has to stand out from any match more than 0.6 s away, or it's a repeated section
        // lining up by chance — on real songs those false matches were never more than ~1.15× the runner-up.
        let runnerUp = scores.filter { abs($0.shift - best.shift) > 0.6 }.map(\.score).max() ?? 0
        // A shift beyond the usual range (a video's intro) has to win far more clearly: songs with evenly spaced
        // lines line up just as well a bar or two off, and a wrong big shift made a whole song's lyrics nonsense.
        let wide = abs(best.shift) > maxShift
        let clear = best.score > (wide ? 0.15 : 0.08) && best.score > runnerUp * (wide ? 2.5 : 1.5)

        // Small shifts are within the method's error; real mistimings are half a second or more. A best match at
        // the edge of the search is never trusted.
        guard clear, abs(best.shift - offset) >= 0.4, best.shift > lowest + 0.15, best.shift < maxShift - 0.15,
              best.score > current.score * 1.2 + 0.02 else {
            candidate = nil
            agreeing = 0
            if !confirmed && clear && abs(best.shift - offset) < 0.4 {
                confirmed = true
                Log.write(String(format: "auto-sync: timing checks out at %+.1f s", offset))
            }
            return
        }
        // Three readings in a row (8 s apart in total) must agree before the lyrics jump.
        if let candidate, abs(candidate - best.shift) <= 0.3 {
            agreeing += 1
        } else {
            candidate = best.shift
            agreeing = 1
            return
        }
        if agreeing >= (abs(best.shift) > maxShift ? 6 : 3), let candidate {
            offset = (candidate + best.shift) / 2
            if let trackID { remembered[trackID] = offset }
            self.candidate = nil
            agreeing = 0
            Log.write(String(format: "auto-sync: lyrics shifted %+.1f s (match %.3f, runner-up %.3f)", offset,
                             best.score, runnerUp))
        }
    }

    private func standardised(_ values: [Double]) -> [Double]? {
        let mean = values.reduce(0, +) / Double(values.count)
        let variance = values.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(values.count)
        guard variance > 1e-6 else { return nil }
        let sd = variance.squareRoot()
        return values.map { ($0 - mean) / sd }
    }
}

// MARK: - Battery saver

/// Whether the Mac is running on battery (or in Low Power Mode), so the lock screen can go lighter.
final class Power: ObservableObject {
    static let shared = Power()
    @Published private(set) var onBattery = false

    private init() {
        update()
        let context = Unmanaged.passUnretained(self).toOpaque()
        if let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            Unmanaged<Power>.fromOpaque(context).takeUnretainedValue().update()
        }, context)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
        }
        NotificationCenter.default.addObserver(forName: .NSProcessInfoPowerStateDidChange, object: nil,
                                               queue: .main) { [weak self] _ in self?.update() }
    }

    private func update() {
        let source = IOPSGetProvidingPowerSourceType(nil)?.takeUnretainedValue() as String?
        let battery = source == kIOPMBatteryPowerKey || ProcessInfo.processInfo.isLowPowerModeEnabled
        DispatchQueue.main.async {
            if self.onBattery != battery {
                self.onBattery = battery
                Log.write("power: \(battery ? "battery" : "plugged in")")
            }
        }
    }

    /// Battery saver is on and the Mac is unplugged.
    var saving: Bool { onBattery && Style.shared.v.batterySaver }

    /// Frame rates for the lock-screen layers.
    var backdropFPS: Double { saving ? 20 : 30 }
    var lyricsFPS: Double { saving ? 30 : 60 }
}
