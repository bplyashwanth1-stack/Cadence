import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Your own lyrics

/// Lyrics you wrote, fixed or imported for a song. They beat anything downloaded or tapped, and stay until you
/// go back to the downloaded ones.
enum UserLyrics {
    private static let local = URL.applicationSupportDirectory.appendingPathComponent("Cadence/My Lyrics", isDirectory: true)

    /// iCloud Drive's Cadence folder, when iCloud Drive is on: whatever you save there reaches your other Macs.
    private static var cloud: URL? {
        let drive = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs", isDirectory: true)
        guard FileManager.default.fileExists(atPath: drive.path) else { return nil }
        return drive.appendingPathComponent("Cadence/My Lyrics", isDirectory: true)
    }

    /// Where new edits go: iCloud Drive if you've turned that on and it's available, otherwise this Mac.
    private static var folder: URL {
        let url = Style.shared.v.syncLyrics ? cloud ?? local : local
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static func name(_ id: String) -> String {
        id.replacingOccurrences(of: ":", with: "_").replacingOccurrences(of: "/", with: "_") + ".lrc"
    }

    /// Both places, preferred first, so lyrics saved before switching sync on or off are still found.
    private static func files(_ id: String) -> [URL] {
        let preferred = folder.appendingPathComponent(name(id))
        let others = [local, cloud].compactMap { $0?.appendingPathComponent(name(id)) }.filter { $0 != preferred }
        return [preferred] + others
    }

    static func load(_ id: String) -> String? {
        files(id).lazy.compactMap { try? String(contentsOf: $0, encoding: .utf8) }.first
    }

    static func save(_ lrc: String, for id: String) {
        try? lrc.write(to: folder.appendingPathComponent(name(id)), atomically: true, encoding: .utf8)
    }

    static func remove(_ id: String) { files(id).forEach { try? FileManager.default.removeItem(at: $0) } }
    static func has(_ id: String) -> Bool { files(id).contains { FileManager.default.fileExists(atPath: $0.path) } }

    /// Turning sync on copies this Mac's edits into iCloud Drive, so nothing is left behind.
    static func moveToCloud() {
        guard let cloud, let items = try? FileManager.default.contentsOfDirectory(at: local, includingPropertiesForKeys: nil)
        else { return }
        try? FileManager.default.createDirectory(at: cloud, withIntermediateDirectories: true)
        for item in items where item.pathExtension == "lrc" {
            let target = cloud.appendingPathComponent(item.lastPathComponent)
            if !FileManager.default.fileExists(atPath: target.path) { try? FileManager.default.copyItem(at: item, to: target) }
        }
    }
}

extension LRC {
    /// Lyric lines back as LRC text, one "[mm:ss.xx] words" line each, for editing.
    static func text(_ lines: [LyricLine]) -> String {
        lines.map { line in
            let minutes = Int(line.start) / 60
            let words = line.words.map(\.text).joined(separator: " ")
            return String(format: "[%02d:%05.2f] ", minutes, line.start - Double(minutes * 60)) + words
        }.joined(separator: "\n")
    }

    /// The same lyrics without per-word "<mm:ss.xx>" stamps: one readable line per lyric line.
    static func withoutWordStamps(_ text: String) -> String {
        text.components(separatedBy: .newlines).map { line in
            line.replacingOccurrences(of: #"<\d+:\d+(?:[.:]\d+)?>"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespaces)
        }.joined(separator: "\n")
    }

    /// Whether the text has any "[mm:ss]" timestamps, or is just the words.
    static func isTimed(_ text: String) -> Bool { text.range(of: #"\[\d+:\d+"#, options: .regularExpression) != nil }
}

extension NowPlaying {
    /// Saves your own lyrics for the playing song (timing them roughly if they have no timestamps) and shows
    /// them straight away; nil goes back to the downloaded ones.
    func setUserLyrics(_ text: String?) {
        guard let track else { return }
        if let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let timed = LRC.isTimed(text) ? text : LRC.estimated(text, duration: track.duration)
            UserLyrics.save(timed, for: track.id)
        } else {
            UserLyrics.remove(track.id)
        }
        reloadLyrics()
    }
}

/// The editor: the playing song's lyrics as LRC text you can change, paste over or import from a file.
struct LyricsEditorView: View {
    let close: () -> Void
    @ObservedObject private var player = NowPlaying.shared
    @State private var text = ""
    @State private var loadedFor: String?
    @State private var note = ""
    /// The lyrics as loaded, with any word timing, and whether to show that timing.
    @State private var original = ""
    @State private var wordStamps = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let track = player.track {
                VStack(alignment: .leading, spacing: 2) {
                    Text(track.title).font(.headline).lineLimit(1)
                    Text(track.artist).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                }
                Text("One line per lyric line. Keep a [minutes:seconds] stamp at the start of a line to set when it's sung, or paste plain words and Cadence spreads them over the song for you to fix with Tap to Sync.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                TextEditor(text: $text)
                    .font(.system(size: 13, design: .monospaced))
                    .frame(minHeight: 340)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3)))
                if original.contains("<") {
                    Toggle("Word timestamps", isOn: Binding(get: { wordStamps }, set: { show in
                        // Switching views keeps your edits only when they're made in the full view.
                        text = show ? original : LRC.withoutWordStamps(original)
                        wordStamps = show
                    }))
                    .toggleStyle(.switch)
                    .help("These lyrics are timed word by word. Show every word's stamp, or just one per line.")
                }
                HStack {
                    Button("Insert Current Time") { insertStamp() }
                        .help("Adds the song's current position as a [mm:ss.xx] stamp on a new line")
                    Button("Import File…") { importFile() }
                    Spacer()
                    if UserLyrics.has(track.id) {
                        Button("Use Downloaded Lyrics") {
                            player.setUserLyrics(nil)
                            close()
                        }
                    }
                    Button("Cancel", action: close).keyboardShortcut(.cancelAction)
                    Button("Save") {
                        // Untouched lyrics keep their word timing even when shown line by line.
                        let unchanged = !wordStamps && text == LRC.withoutWordStamps(original)
                        player.setUserLyrics(unchanged ? original : text)
                        close()
                    }
                    .keyboardShortcut("s", modifiers: .command)
                    .buttonStyle(.borderedProminent)
                }
                if !note.isEmpty { Text(note).font(.caption).foregroundStyle(.secondary) }
            } else {
                Text("Play a song to edit its lyrics.").foregroundStyle(.secondary)
                HStack { Spacer(); Button("Close", action: close) }
            }
        }
        .padding(18)
        .frame(width: 560)
        .onAppear(perform: load)
        .onChange(of: player.track?.id) { _, _ in load() }
    }

    private func load() {
        guard let track = player.track, loadedFor != track.id else { return }
        loadedFor = track.id
        original = UserLyrics.load(track.id) ?? LyricsStore.load(track.id) ?? LRC.text(player.lyrics)
        wordStamps = false
        text = LRC.withoutWordStamps(original)
        note = UserLyrics.has(track.id) ? "Showing your own lyrics for this song." : ""
    }

    private func insertStamp() {
        let time = max(0, player.lyricTime(at: Date()))
        let minutes = Int(time) / 60
        let stamp = String(format: "[%02d:%05.2f] ", minutes, time - Double(minutes * 60))
        text += (text.hasSuffix("\n") || text.isEmpty ? "" : "\n") + stamp
    }

    private func importFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "lrc") ?? .plainText, .plainText, .text]
        panel.allowsMultipleSelection = false
        panel.message = "Choose a .lrc file (timed) or a .txt file (just the words)"
        guard panel.runModal() == .OK, let url = panel.url,
              let contents = try? String(contentsOf: url, encoding: .utf8) else { return }
        text = contents
        note = LRC.isTimed(contents) ? "Imported \(url.lastPathComponent). Save to use it."
            : "Imported \(url.lastPathComponent) without timestamps. Save, then Tap to Sync to time it."
    }
}

final class LyricsEditorWindow: NSWindow {
    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 560, height: 520), styleMask: [.titled, .closable, .resizable],
                   backing: .buffered, defer: false)
        title = "Edit Lyrics"
        isReleasedWhenClosed = false
        contentViewController = NSHostingController(rootView: LyricsEditorView { [weak self] in self?.close() })
        center()
    }
}
