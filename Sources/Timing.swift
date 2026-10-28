import AppKit
import SwiftUI

// MARK: - Per-song timing

/// Timing fixes you made for a song, remembered for next time: a nudge (seconds, + shows lyrics earlier) and
/// lyrics you timed yourself with tap-to-sync. Either one turns auto-sync off for that song — you know best.
final class SongTiming: ObservableObject {
    static let shared = SongTiming()

    @Published private(set) var offsets: [String: Double] {
        didSet { UserDefaults.standard.set(offsets, forKey: "songOffsets") }
    }
    @Published private(set) var tappedIDs: Set<String> = []

    private let folder: URL = {
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Cadence/Tapped", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    private init() {
        offsets = UserDefaults.standard.dictionary(forKey: "songOffsets") as? [String: Double] ?? [:]
        let files = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        tappedIDs = Set(files.filter { $0.hasSuffix(".lrc") }.map { Self.id(fromFile: $0) })
    }

    func offset(_ id: String?) -> Double {
        id.flatMap { offsets[$0] } ?? 0
    }

    func nudge(_ id: String, by delta: Double) {
        set(offset(id) + delta, for: id)
    }

    func set(_ value: Double, for id: String) {
        let rounded = (value * 100).rounded() / 100
        offsets[id] = abs(rounded) < 0.01 ? nil : min(max(rounded, -5), 5)
    }

    /// Whether you've fixed this song by hand.
    func isManual(_ id: String?) -> Bool {
        guard let id else { return false }
        return offsets[id] != nil || tappedIDs.contains(id)
    }

    // Tapped lyrics, one LRC file per song.

    private func file(_ id: String) -> URL {
        folder.appendingPathComponent(id.replacingOccurrences(of: ":", with: "_")
            .replacingOccurrences(of: "/", with: "_") + ".lrc")
    }

    private static func id(fromFile name: String) -> String {
        String(name.dropLast(4)).replacingOccurrences(of: "_", with: ":")
    }

    func tapped(_ id: String) -> String? {
        try? String(contentsOf: file(id), encoding: .utf8)
    }

    func saveTapped(_ lrc: String, for id: String) {
        try? lrc.write(to: file(id), atomically: true, encoding: .utf8)
        tappedIDs.insert(id)
        offsets[id] = nil  // the taps already include any nudge
        Log.write("tap-sync saved for \(id)")
    }

    func removeTapped(_ id: String) {
        try? FileManager.default.removeItem(at: file(id))
        tappedIDs.remove(id)
    }
}

// MARK: - Tap to sync

/// You play the song and press Space as each line starts; Cadence keeps your timing for that song forever.
final class TapSync: ObservableObject {
    let track: Track
    let lines: [String]
    private let originalStarts: [Double]
    @Published private(set) var taps: [Double] = []
    @Published private(set) var finished = false

    /// Taps land a little after the line really starts — people react to the voice they hear.
    private let reaction = 0.15

    init?(player: NowPlaying) {
        guard let track = player.track else { return nil }
        let sung = player.lyrics.filter { !$0.words.isEmpty }
        guard !sung.isEmpty else { return nil }
        self.track = track
        lines = sung.map { $0.words.map(\.text).joined(separator: " ") }
        originalStarts = sung.map(\.start)
    }

    var next: Int { taps.count }

    func start() {
        let player = NowPlaying.shared
        // Start a few seconds before the first line so there's time to get ready.
        player.seek(to: max(0, originalStarts[0] - 4))
        if !player.isPlaying { player.control("playpause") }
    }

    func tap() {
        guard !finished, next < lines.count else { return }
        let position = NowPlaying.shared.position(at: Date()) - reaction
        taps.append(max(0, max(position, (taps.last ?? -1) + 0.1)))
        if taps.count == lines.count { save() }
    }

    /// Takes back the last tap and rewinds to just before that line so it can be tapped again.
    func undo() {
        guard let last = taps.popLast() else { return }
        NowPlaying.shared.seek(to: max(0, last - 3))
    }

    /// Saves what's tapped; lines not reached yet keep their old timing, moved by how far off the taps found it.
    func save() {
        guard !taps.isEmpty else { return }
        let drift = zip(taps, originalStarts).map { $0 - $1 }.suffix(5)
        let shift = drift.reduce(0, +) / Double(drift.count)
        let times = lines.indices.map { $0 < taps.count ? taps[$0] : originalStarts[$0] + shift }
        let lrc = zip(times, lines).map { time, text in
            let minutes = Int(time) / 60
            return String(format: "[%02d:%05.2f] %@", minutes, time - Double(minutes * 60), text)
        }.joined(separator: "\n")
        SongTiming.shared.saveTapped(lrc, for: track.id)
        NowPlaying.shared.reloadLyrics()
        finished = true
    }
}

struct TapSyncView: View {
    @ObservedObject var session: TapSync
    let close: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Text(session.track.title).font(.title2.bold())
            if session.finished {
                Spacer()
                Image(systemName: "checkmark.circle.fill").font(.system(size: 56)).foregroundStyle(.green)
                Text("Saved — Cadence will use your timing for this song.").font(.title3)
                Spacer()
                Button("Done", action: close).keyboardShortcut(.defaultAction)
            } else {
                Text("Press **Space** the moment each line starts.")
                    .foregroundStyle(.secondary)
                Spacer()
                line(session.next - 1, size: 18, opacity: 0.35)
                line(session.next, size: 30, opacity: 1)
                line(session.next + 1, size: 18, opacity: 0.35)
                Spacer()
                ProgressView(value: Double(session.next), total: Double(session.lines.count))
                Text("\(session.next) of \(session.lines.count) lines")
                    .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                HStack(spacing: 18) {
                    Label("Undo: Delete", systemImage: "delete.left")
                    Label("Save now: Return", systemImage: "return")
                    Label("Cancel: Esc", systemImage: "escape")
                }
                .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(28)
        .frame(width: 620, height: 420)
    }

    @ViewBuilder
    private func line(_ index: Int, size: CGFloat, opacity: Double) -> some View {
        Text(session.lines.indices.contains(index) ? session.lines[index] : " ")
            .font(.system(size: size, weight: .semibold, design: .rounded))
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .opacity(opacity)
            .frame(maxWidth: .infinity)
    }
}

/// The tap-to-sync window. Keys are read with a local monitor, since Cadence is a menu-bar app.
final class TapSyncWindow: NSWindow {
    private var monitor: Any?
    private let session: TapSync

    init(session: TapSync) {
        self.session = session
        super.init(contentRect: NSRect(x: 0, y: 0, width: 620, height: 420), styleMask: [.titled, .closable],
                   backing: .buffered, defer: false)
        title = "Tap to Sync"
        isReleasedWhenClosed = false
        contentView = NSHostingView(rootView: TapSyncView(session: session) { [weak self] in self?.close() })
        center()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === self, !session.finished else { return event }
            switch event.keyCode {
            case 49: session.tap()  // space
            case 51: session.undo()  // delete
            case 36: session.save()  // return
            case 53: close()  // esc
            default: return event
            }
            return nil
        }
        session.start()
    }

    override func close() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        super.close()
    }
}
