import AVFoundation
import AppKit
import SwiftUI

// MARK: - Shareable clips

/// True while the stage is being drawn into a clip, so views that can't be rendered off screen (AppKit-backed
/// ones, like the fisheye lens) draw a plain version instead, and the stage draws whether or not it's on screen.
private struct ClipKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var isClip: Bool {
        get { self[ClipKey.self] }
        set { self[ClipKey.self] = newValue }
    }
}

enum ClipFormat: String, CaseIterable {
    case vertical, square, wide

    var title: String {
        switch self {
        case .vertical: return "Vertical — Stories, Reels, TikTok"
        case .square: return "Square — posts"
        case .wide: return "Widescreen — YouTube, X"
        }
    }

    /// Video size in pixels.
    var pixels: CGSize {
        switch self {
        case .vertical: return CGSize(width: 1080, height: 1920)
        case .square: return CGSize(width: 1080, height: 1080)
        case .wide: return CGSize(width: 1920, height: 1080)
        }
    }

    /// The stage is laid out at this many points per pixel, close to a laptop screen's text size.
    var scale: CGFloat { self == .vertical ? 1.5 : 1.25 }
}

/// What a clip shows: the lock-screen layers (without the now-playing bar), and a small Cadence mark.
struct ClipStage: View {
    let mark: Bool

    var body: some View {
        ZStack {
            Color.black
            StageBackdrop()
            StageDepth(overLyrics: false)
            StageView()
            StageDepth(overLyrics: true)
            if mark {
                Label("Cadence", systemImage: "music.mic")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.75))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(Color.black.opacity(0.35)))
                    .padding(22)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            }
        }
        .environment(\.isClip, true)
    }
}

/// Records ten seconds of the lock-screen view, with the music, to an MP4 in ~/Movies/Cadence.
/// Frames are drawn by SwiftUI straight into the video, so no screen-recording permission is needed; the sound
/// comes from the same system-audio tap that drives the beat.
final class ClipRecorder: ObservableObject {
    static let shared = ClipRecorder()
    static let duration = 10.0
    private static let fps = 30.0
    static let markKey = "clipMark"

    @Published private(set) var recording = false
    /// Whether the clip being (or last) recorded has the music in it.
    private(set) var withSound = false

    private var writer: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var adaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var audioInput: AVAssetWriterInput?
    private var points = CGSize.zero
    private var scale: CGFloat = 1
    private var timer: Timer?
    private var started: CFTimeInterval = 0
    private var size = CGSize.zero
    private var url: URL?
    private var completion: ((Result<URL, Error>) -> Void)?
    private var frames = 0

    // Audio, touched only on `audioQueue`.
    private let audioQueue = DispatchQueue(label: "cadence.clip.audio")
    private var audioFormat: CMAudioFormatDescription?
    private var audioChannels = 0
    private var audioDelay = 0.0
    private var audioSamples = 0

    struct Failure: LocalizedError {
        let errorDescription: String?
    }

    static var withMark: Bool { UserDefaults.standard.object(forKey: markKey) as? Bool ?? true }

    @MainActor func record(_ format: ClipFormat, completion: @escaping (Result<URL, Error>) -> Void) {
        guard !recording else { return }
        let player = NowPlaying.shared
        guard let track = player.track else {
            completion(.failure(Failure(errorDescription: "Play a song first, then record a clip of it.")))
            return
        }
        do {
            let folder = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Cadence", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
            let stamp = formatter.string(from: Date())
            let title = track.title.components(separatedBy: CharacterSet(charactersIn: "/:\\?%*|\"<>")).joined()
            let url = folder.appendingPathComponent("Cadence – \(title.prefix(60)) – \(stamp).mp4")
            try start(format, to: url)
            self.url = url
            self.completion = completion
        } catch {
            completion(.failure(error))
        }
    }

    @MainActor private func start(_ format: ClipFormat, to url: URL) throws {
        size = format.pixels
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let video = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(size.width),
            AVVideoHeightKey: Int(size.height),
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 14_000_000,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
            ],
        ])
        video.expectsMediaDataInRealTime = true
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: video, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: Int(size.width),
            kCVPixelBufferHeightKey as String: Int(size.height),
        ])
        guard writer.canAdd(video) else { throw Failure(errorDescription: "Couldn't set up the video.") }
        writer.add(video)

        // The music, when the audio tap is hearing it right now (not just running: another app that taps audio
        // with muting, like an equalizer, leaves it hearing silence).
        let pulse = AudioPulse.shared
        var audio: AVAssetWriterInput?
        if pulse.snapshot() != nil {
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: pulse.tapSampleRate,
                AVNumberOfChannelsKey: 2,
                AVEncoderBitRateKey: 192_000,
            ])
            input.expectsMediaDataInRealTime = true
            if writer.canAdd(input) {
                writer.add(input)
                audio = input
            }
        }
        guard writer.startWriting() else { throw writer.error ?? Failure(errorDescription: "Couldn't start the video.") }
        writer.startSession(atSourceTime: .zero)

        points = CGSize(width: size.width / format.scale, height: size.height / format.scale)
        scale = format.scale

        self.writer = writer
        videoInput = video
        self.adaptor = adaptor
        audioInput = audio
        withSound = audio != nil
        frames = 0
        recording = true
        started = CACurrentMediaTime()
        // The tap hears samples as they leave for the speakers; the listener (and the lyrics) are that much later.
        let delay = AudioPulse.outputDelay()
        audioQueue.sync {
            audioFormat = nil
            audioSamples = 0
            audioDelay = delay
        }
        if audio != nil {
            pulse.setClipSink { [weak self] samples, frames, channels, rate in
                self?.appendAudio(samples, frames: frames, channels: channels, rate: rate, at: CACurrentMediaTime())
            }
        }
        // Show the stage on screen too while it records, so you see what's being captured.
        NowPlaying.shared.previewing = true
        Log.write("clip: recording \(format.rawValue) to \(url.lastPathComponent), audio=\(audio != nil)")

        let timer = Timer(timeInterval: 1 / Self.fps, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.frame() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        frame()
    }

    @MainActor private func frame() {
        let t = CACurrentMediaTime() - started
        guard t < Self.duration else { finish(); return }
        guard let videoInput, videoInput.isReadyForMoreMediaData, let adaptor, let pool = adaptor.pixelBufferPool,
              let image = render() else { return }
        var buffer: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer) == kCVReturnSuccess, let buffer else { return }
        CVPixelBufferLockBaseAddress(buffer, [])
        if let context = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: Int(size.width), height: Int(size.height),
                                   bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                                   space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                   bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) {
            context.draw(image, in: CGRect(origin: .zero, size: size))
        }
        CVPixelBufferUnlockBaseAddress(buffer, [])
        if adaptor.append(buffer, withPresentationTime: CMTime(seconds: t, preferredTimescale: 600)) { frames += 1 }
    }

    /// A fresh renderer each frame: a reused one keeps showing its first drawing of the lyrics.
    @MainActor private func render() -> CGImage? {
        let renderer = ImageRenderer(content: ClipStage(mark: Self.withMark).frame(width: points.width, height: points.height))
        renderer.scale = scale
        renderer.isOpaque = true
        return renderer.cgImage
    }

    private func appendAudio(_ samples: UnsafePointer<Float>, frames: Int, channels: Int, rate: Double, at now: CFTimeInterval) {
        let count = frames * channels
        let copy = Array(UnsafeBufferPointer(start: samples, count: count))
        audioQueue.async { [weak self] in
            guard let self, let input = self.audioInput, input.isReadyForMoreMediaData else { return }
            // These samples end now and play `audioDelay` later; place them where they're heard.
            let time = now - self.started + self.audioDelay - Double(frames) / rate
            guard time >= 0, time < Self.duration else { return }
            if self.audioFormat == nil || self.audioChannels != channels {
                var description = AudioStreamBasicDescription(
                    mSampleRate: rate, mFormatID: kAudioFormatLinearPCM,
                    mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
                    mBytesPerPacket: UInt32(4 * channels), mFramesPerPacket: 1, mBytesPerFrame: UInt32(4 * channels),
                    mChannelsPerFrame: UInt32(channels), mBitsPerChannel: 32, mReserved: 0)
                var format: CMAudioFormatDescription?
                CMAudioFormatDescriptionCreate(allocator: kCFAllocatorDefault, asbd: &description, layoutSize: 0, layout: nil,
                                               magicCookieSize: 0, magicCookie: nil, extensions: nil, formatDescriptionOut: &format)
                self.audioFormat = format
                self.audioChannels = channels
            }
            guard let format = self.audioFormat else { return }
            let bytes = count * MemoryLayout<Float>.size
            var block: CMBlockBuffer?
            guard CMBlockBufferCreateWithMemoryBlock(allocator: kCFAllocatorDefault, memoryBlock: nil, blockLength: bytes,
                                                     blockAllocator: kCFAllocatorDefault, customBlockSource: nil, offsetToData: 0,
                                                     dataLength: bytes, flags: kCMBlockBufferAssureMemoryNowFlag,
                                                     blockBufferOut: &block) == noErr, let block else { return }
            copy.withUnsafeBytes { raw in
                _ = CMBlockBufferReplaceDataBytes(with: raw.baseAddress!, blockBuffer: block, offsetIntoDestination: 0, dataLength: bytes)
            }
            var sample: CMSampleBuffer?
            guard CMAudioSampleBufferCreateReadyWithPacketDescriptions(
                allocator: kCFAllocatorDefault, dataBuffer: block, formatDescription: format, sampleCount: frames,
                presentationTimeStamp: CMTime(seconds: time, preferredTimescale: CMTimeScale(rate)),
                packetDescriptions: nil, sampleBufferOut: &sample) == noErr, let sample else { return }
            if input.append(sample) { self.audioSamples += frames }
        }
    }

    @MainActor private func finish() {
        timer?.invalidate()
        timer = nil
        AudioPulse.shared.setClipSink(nil)
        NowPlaying.shared.previewing = false
        videoInput?.markAsFinished()
        audioQueue.sync { audioInput?.markAsFinished() }
        let writer = writer, url = url, completion = completion, frames = frames
        let seconds = audioQueue.sync { Double(audioSamples) / max(AudioPulse.shared.tapSampleRate, 1) }
        writer?.finishWriting { [weak self] in
            DispatchQueue.main.async {
                guard let self else { return }
                self.recording = false
                self.writer = nil
                self.videoInput = nil
                self.adaptor = nil
                self.audioInput = nil
                self.completion = nil
                Log.write("clip: \(frames) frames, \(String(format: "%.1f", seconds)) s of audio, status \(writer?.status.rawValue ?? -1)")
                if let url, writer?.status == .completed {
                    completion?(.success(url))
                } else {
                    completion?(.failure(writer?.error ?? Failure(errorDescription: "The clip couldn't be saved.")))
                }
            }
        }
    }
}
