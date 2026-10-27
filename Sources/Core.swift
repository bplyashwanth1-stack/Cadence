import AppKit
import SwiftUI

// MARK: - Log (~/Library/Logs/Cadence.log)

enum Log {
    private static let url = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/Cadence.log")

    static func write(_ message: String) {
        let line = "\(Date()) \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? data.write(to: url)
        }
    }
}

// MARK: - Players (Spotify / Apple Music via AppleScript)

struct Track: Equatable {
    let id: String
    let title: String
    let artist: String
    let album: String
    let duration: Double
    let artworkURL: URL?  // Spotify only; Apple Music artwork is read via AppleScript
}

struct PlayerState {
    let track: Track
    let playing: Bool
    let position: Double
}

enum Player {
    private static let spotify = NSAppleScript(source: """
        if application "Spotify" is running then
            tell application "Spotify"
                set playerState to player state as text
                if playerState is "stopped" then return ""
                set s to character id 31
                set t to current track
                return playerState & s & (id of t) & s & (name of t) & s & (artist of t) & s & (album of t) & s & ((duration of t) as text) & s & (player position as text) & s & (artwork url of t)
            end tell
        end if
        return ""
        """)!

    private static let music = NSAppleScript(source: """
        if application "Music" is running then
            tell application "Music"
                set playerState to player state as text
                if playerState is "stopped" then return ""
                set s to character id 31
                set t to current track
                return playerState & s & (persistent ID of t) & s & (name of t) & s & (artist of t) & s & (album of t) & s & ((duration of t) as text) & s & (player position as text)
            end tell
        end if
        return ""
        """)!

    private static let musicArtwork = NSAppleScript(source: """
        if application "Music" is running then
            tell application "Music" to return raw data of artwork 1 of current track
        end if
        """)!

    private static var lastError: String?

    /// Explicitly asks macOS for permission to control a player, which shows the consent prompt.
    /// Blocks until answered, so call it off the main thread.
    static func requestPermission(bundleID: String) {
        var target = AEAddressDesc()
        let created = bundleID.withCString {
            AECreateDesc(DescType(typeApplicationBundleID), $0, bundleID.utf8.count, &target)
        }
        guard created == noErr else { return }
        let status = AEDeterminePermissionToAutomateTarget(&target, AEEventClass(typeWildCard),
                                                           AEEventID(typeWildCard), true)
        AEDisposeDesc(&target)
        Log.write("permission for \(bundleID): \(status)")
    }

    /// Whichever player is playing (Spotify preferred), else whichever is paused.
    static func state() -> PlayerState? {
        let s = read(spotify, isSpotify: true)
        if s?.playing == true { return s }
        let m = read(music, isSpotify: false)
        if m?.playing == true { return m }
        return s ?? m
    }

    /// Sends a transport command ("next track", "previous track", "playpause") to the player that owns the track.
    static func command(_ verb: String, trackID: String) {
        let app = trackID.hasPrefix("music:") ? "Music" : "Spotify"
        var error: NSDictionary?
        NSAppleScript(source: "tell application \"\(app)\" to \(verb)")?.executeAndReturnError(&error)
        if let error { Log.write("command \(verb) failed: \(error)") }
    }

    static func seek(to seconds: Double, trackID: String) {
        let app = trackID.hasPrefix("music:") ? "Music" : "Spotify"
        let position = String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), seconds)
        var error: NSDictionary?
        NSAppleScript(source: "tell application \"\(app)\" to set player position to \(position)")?
            .executeAndReturnError(&error)
        if let error { Log.write("seek failed: \(error)") }
    }

    static func musicArtworkData() -> Data? {
        var error: NSDictionary?
        let result = musicArtwork.executeAndReturnError(&error)
        return error == nil ? result.data : nil
    }

    private static func read(_ script: NSAppleScript, isSpotify: Bool) -> PlayerState? {
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        if let error, lastError != error.description {
            lastError = error.description
            Log.write("AppleScript error: \(error)")
        }
        guard let out = result.stringValue, !out.isEmpty else { return nil }
        let f = out.components(separatedBy: "\u{1F}")
        guard f.count >= 7 else { return nil }
        func number(_ s: String) -> Double { Double(s.replacingOccurrences(of: ",", with: ".")) ?? 0 }
        let duration = isSpotify ? number(f[5]) / 1000 : number(f[5])
        let track = Track(id: (isSpotify ? "spotify:" : "music:") + f[1], title: f[2], artist: f[3], album: f[4],
                          duration: duration, artworkURL: isSpotify && f.count > 7 ? URL(string: f[7]) : nil)
        return PlayerState(track: track, playing: f[0] == "playing", position: number(f[6]))
    }
}

// MARK: - Lyrics (LRCLIB + LRC parsing)

struct Word {
    let text: String
    let start: Double
    let end: Double

    func progress(at t: Double) -> Double {
        guard end > start else { return t >= start ? 1 : 0 }
        return min(max((t - start) / (end - start), 0), 1)
    }
}

struct LyricLine: Identifiable {
    let id: Int
    let start: Double
    let end: Double
    let words: [Word]  // empty = instrumental break
}

enum LRCLib {
    private struct Item: Decodable {
        let syncedLyrics: String?
        let duration: Double?
    }

    static func lyrics(for track: Track) async -> String? {
        let exact = await request("get", [
            "track_name": track.title, "artist_name": track.artist,
            "album_name": track.album, "duration": String(Int(track.duration.rounded())),
        ])
        if let data = exact, let item = try? JSONDecoder().decode(Item.self, from: data),
           let synced = item.syncedLyrics, !synced.isEmpty {
            return synced
        }
        // Fall back to a fuzzy search with "- Remastered", "(feat. …)" etc. stripped.
        guard let data = await request("search", ["track_name": clean(track.title), "artist_name": track.artist]),
              let items = try? JSONDecoder().decode([Item].self, from: data) else { return nil }
        return items
            .filter { $0.syncedLyrics?.isEmpty == false }
            .min { abs(($0.duration ?? 0) - track.duration) < abs(($1.duration ?? 0) - track.duration) }?
            .syncedLyrics
    }

    private static func clean(_ title: String) -> String {
        var t = title
        if let dash = t.range(of: " - ") { t = String(t[..<dash.lowerBound]) }
        if let paren = t.range(of: " (") { t = String(t[..<paren.lowerBound]) }
        return t
    }

    private static func request(_ path: String, _ query: [String: String]) async -> Data? {
        var components = URLComponents(string: "https://lrclib.net/api/" + path)!
        components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        var request = URLRequest(url: components.url!)
        request.setValue("Cadence/1.0 (personal lyrics overlay)", forHTTPHeaderField: "User-Agent")
        guard let result = try? await URLSession.shared.data(for: request),
              (result.1 as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return result.0
    }
}

enum LRC {
    private static let lineTag = try! NSRegularExpression(pattern: #"\[(\d+):(\d+(?:[.:]\d+)?)\]"#)
    private static let wordTag = try! NSRegularExpression(pattern: #"<(\d+):(\d+(?:[.:]\d+)?)>"#)

    static func parse(_ lrc: String) -> [LyricLine] {
        var raw: [(time: Double, text: String)] = []
        for line in lrc.components(separatedBy: .newlines) {
            let ns = line as NSString
            let matches = lineTag.matches(in: line, range: NSRange(location: 0, length: ns.length))
            guard let last = matches.last else { continue }
            let text = ns.substring(from: last.range.upperBound).trimmingCharacters(in: .whitespaces)
            for m in matches { raw.append((time(m, in: ns), text)) }
        }
        raw.sort { $0.time < $1.time }
        return raw.enumerated().map { i, item in
            let end = i + 1 < raw.count ? raw[i + 1].time : item.time + 5
            return LyricLine(id: i, start: item.time, end: end, words: words(item.text, start: item.time, end: end))
        }
    }

    private static func time(_ match: NSTextCheckingResult, in ns: NSString) -> Double {
        let minutes = Double(ns.substring(with: match.range(at: 1))) ?? 0
        let seconds = Double(ns.substring(with: match.range(at: 2)).replacingOccurrences(of: ":", with: ".")) ?? 0
        return minutes * 60 + seconds
    }

    private static func words(_ text: String, start: Double, end: Double) -> [Word] {
        let ns = text as NSString
        let tags = wordTag.matches(in: text, range: NSRange(location: 0, length: ns.length))

        // Enhanced LRC: real per-word timestamps.
        if !tags.isEmpty {
            var result: [Word] = []
            for (i, tag) in tags.enumerated() {
                let textEnd = i + 1 < tags.count ? tags[i + 1].range.location : ns.length
                let word = ns.substring(with: NSRange(location: tag.range.upperBound,
                                                      length: textEnd - tag.range.upperBound))
                    .trimmingCharacters(in: .whitespaces)
                guard !word.isEmpty else { continue }
                let wordEnd = i + 1 < tags.count ? time(tags[i + 1], in: ns) : end
                result.append(Word(text: word, start: time(tag, in: ns), end: wordEnd))
            }
            return result
        }

        // Line-level LRC: spread the sung part of the line across words, weighted by length.
        let tokens = text.split(separator: " ").map(String.init)
        guard !tokens.isEmpty else { return [] }
        let span = min((end - start) * 0.92, Double(tokens.count) * 0.5 + 0.8)
        let weights = tokens.map { Double($0.count) + 1.5 }
        let total = weights.reduce(0, +)
        var cursor = start
        return zip(tokens, weights).map { token, weight in
            let duration = span * weight / total
            defer { cursor += duration }
            return Word(text: token, start: cursor, end: cursor + duration)
        }
    }
}

// MARK: - Palette extraction

enum Palette {
    static let fallback: [NSColor] = [
        NSColor(calibratedHue: 0.60, saturation: 0.7, brightness: 1, alpha: 1),
        NSColor(calibratedHue: 0.85, saturation: 0.7, brightness: 1, alpha: 1),
    ]

    /// Picks the two most prominent vivid hues from an image.
    static func colors(from image: NSImage) -> [NSColor] {
        let size = 40
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return fallback }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(x: 0, y: 0, width: size, height: size))
        NSGraphicsContext.restoreGraphicsState()

        let bucketCount = 18
        var weight = [Double](repeating: 0, count: bucketCount)
        var sums = [(h: Double, s: Double, b: Double)](repeating: (0, 0, 0), count: bucketCount)
        for x in 0..<size {
            for y in 0..<size {
                guard let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
                c.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
                let w = Double(s * s * b)  // favour vivid, bright pixels
                guard w > 0.02 else { continue }
                let i = min(Int(h * CGFloat(bucketCount)), bucketCount - 1)
                weight[i] += w
                sums[i].h += Double(h) * w; sums[i].s += Double(s) * w; sums[i].b += Double(b) * w
            }
        }

        let ranked = weight.indices.filter { weight[$0] > 0 }.sorted { weight[$0] > weight[$1] }
        guard let first = ranked.first else { return fallback }

        // Up to four distinct hues, strongest first, skipping neighbours of ones already picked.
        var picked = [first]
        for i in ranked where picked.count < 4 {
            let distinct = picked.allSatisfy { abs($0 - i) > 1 && abs($0 - i) < bucketCount - 1 }
            if distinct { picked.append(i) }
        }

        func color(_ i: Int, hueShift: Double = 0) -> NSColor {
            let w = weight[i]
            let h = (sums[i].h / w + hueShift + 1).truncatingRemainder(dividingBy: 1)
            return NSColor(calibratedHue: h, saturation: max(sums[i].s / w, 0.6),
                           brightness: max(sums[i].b / w, 0.95), alpha: 1)
        }
        var colors = picked.map { color($0) }
        // Album with few hues: fill out with shifted variants of the main one.
        let shifts = [0.08, -0.08, 0.16]
        for shift in shifts where colors.count < 4 { colors.append(color(first, hueShift: shift)) }
        return colors
    }
}

// MARK: - Now playing state

final class NowPlaying: ObservableObject {
    static let shared = NowPlaying()

    @Published private(set) var track: Track?
    @Published private(set) var isPlaying = false {
        didSet { updateActive() }
    }
    /// Playing, or paused within the last 10 minutes — keeps the lock screen up so playback can be resumed.
    @Published private(set) var active = false
    private var inactiveTimer: DispatchWorkItem?
    @Published private(set) var lyrics: [LyricLine] = [] {
        didSet { words = lyrics.flatMap(\.words) }
    }
    /// Every word of the song in order, for the one-word-at-a-time stack.
    private(set) var words: [Word] = []
    @Published private(set) var status = ""
    @Published private(set) var palette = Palette.fallback
    @Published private(set) var artwork: NSImage?
    @Published private(set) var backdrop: NSImage?  // artwork, small and already blurred
    @Published var locked = false
    @Published var previewing = false  // shows the lock-screen view on the desktop briefly

    // Position is interpolated between polls so animation runs at full frame rate.
    private var basePosition = 0.0
    private var baseTime = Date()
    private var cache: [String: [LyricLine]] = [:]

    func position(at date: Date) -> Double {
        isPlaying ? basePosition + date.timeIntervalSince(baseTime) : basePosition
    }

    var duration: Double { track?.duration ?? 0 }

    private func updateActive() {
        inactiveTimer?.cancel()
        if isPlaying {
            active = true
        } else {
            let timer = DispatchWorkItem { [weak self] in self?.active = false }
            inactiveTimer = timer
            DispatchQueue.main.asyncAfter(deadline: .now() + 600, execute: timer)
        }
    }

    /// Play/pause, next or previous on whichever app is playing, then refresh right away.
    func control(_ verb: String) {
        guard let id = track?.id else { return }
        playerQueue.async {
            Player.command(verb, trackID: id)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { self.poll() }
        }
    }

    /// Jumps to a point in the song. Updates the local clock immediately so lyrics follow without waiting for a poll.
    func seek(to seconds: Double) {
        guard let id = track?.id else { return }
        let target = min(max(seconds, 0), max(duration - 0.5, 0))
        basePosition = target
        baseTime = Date()
        objectWillChange.send()
        playerQueue.async { Player.seek(to: target, trackID: id) }
    }

    /// AppleScript calls block for tens of milliseconds, so they run on their own queue —
    /// on the main thread they caused a visible hitch in the animation every poll.
    private let playerQueue = DispatchQueue(label: "cadence.player")
    private var polling = false

    func poll() {
        guard !polling else { return }
        polling = true
        playerQueue.async {
            let state = Player.state()
            let measured = Date()
            DispatchQueue.main.async {
                self.polling = false
                self.apply(state, measuredAt: measured)
            }
        }
    }

    private func apply(_ state: PlayerState?, measuredAt measured: Date) {
        guard let state else {
            if isPlaying { isPlaying = false }
            return
        }
        if state.track.id != track?.id { trackChanged(state.track) }
        // Only resync on real drift (seek, pause); small jitter would make words jump.
        let drift = abs(position(at: measured) - state.position)
        if state.playing != isPlaying || drift > 0.3 {
            basePosition = state.position
            baseTime = measured
        }
        if state.playing != isPlaying { isPlaying = state.playing }
    }

    /// 1 right as a word starts, decaying to 0 — drives the edge glow in time with the vocals.
    func wordPulse(at time: Double) -> Double {
        guard let line = lyrics.last(where: { $0.start <= time }),
              let word = line.words.last(where: { $0.start <= time }) else { return 0 }
        return exp(-(time - word.start) * 5)
    }

    func reloadLyrics() {
        guard let track else { return }
        cache[track.id] = nil
        loadLyrics(track)
    }

    private func trackChanged(_ track: Track) {
        self.track = track
        loadLyrics(track)
        loadArtwork(track)
    }

    private func loadLyrics(_ track: Track) {
        if let cached = cache[track.id] {
            lyrics = cached
            status = cached.isEmpty ? "No synced lyrics for this song" : ""
            return
        }
        lyrics = []
        status = "Searching lyrics…"
        Task {
            let lines = await LRCLib.lyrics(for: track).map(LRC.parse) ?? []
            await MainActor.run {
                self.cache[track.id] = lines
                Log.write("\(lines.count) lyric lines for \(track.title)")
                guard self.track?.id == track.id else { return }
                self.lyrics = lines
                self.status = lines.isEmpty ? "No synced lyrics for this song" : ""
            }
        }
    }

    private func loadArtwork(_ track: Track) {
        if let url = track.artworkURL {
            URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
                guard let data, let image = NSImage(data: data) else { return }
                self?.apply(artwork: image, for: track)
            }.resume()
        } else {
            playerQueue.async { [weak self] in
                guard let data = Player.musicArtworkData(), let image = NSImage(data: data) else { return }
                self?.apply(artwork: image, for: track)
            }
        }
    }

    /// Runs off the main thread: palette and the pre-blurred backdrop are computed once per song.
    private func apply(artwork image: NSImage, for track: Track) {
        let palette = Palette.colors(from: image)
        let backdrop = Backdrop.blurred(image)
        DispatchQueue.main.async {
            guard self.track?.id == track.id else { return }
            self.palette = palette
            self.artwork = image
            self.backdrop = backdrop
        }
    }
}

// MARK: - Lock screen (private SkyLight space that sits above the lock screen)

enum LockScreen {
    private typealias MainConnectionID = @convention(c) () -> Int32
    private typealias SpaceCreate = @convention(c) (Int32, Int32, Int32) -> UInt64
    private typealias SpaceSetAbsoluteLevel = @convention(c) (Int32, UInt64, Int32) -> Int32
    private typealias ShowSpaces = @convention(c) (Int32, CFArray) -> Int32
    private typealias AddWindows = @convention(c) (Int32, UInt64, CFArray, Int32) -> Int32

    private static let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)

    private static func symbol<T>(_ name: String, as: T.Type) -> T? {
        guard let handle, let sym = dlsym(handle, name) else { return nil }
        return unsafeBitCast(sym, to: T.self)
    }

    private static let space: (connection: Int32, id: UInt64)? = {
        guard let mainConnection = symbol("SLSMainConnectionID", as: MainConnectionID.self),
              let create = symbol("SLSSpaceCreate", as: SpaceCreate.self),
              let setLevel = symbol("SLSSpaceSetAbsoluteLevel", as: SpaceSetAbsoluteLevel.self),
              let show = symbol("SLSShowSpaces", as: ShowSpaces.self) else { return nil }
        let connection = mainConnection()
        let id = create(connection, 1, 0)
        _ = setLevel(connection, id, 400)
        _ = show(connection, [id] as CFArray)
        return (connection, id)
    }()

    /// Moves a window into the lock-screen space so it stays visible while the Mac is locked.
    static func attach(_ window: NSWindow) {
        guard let space, let add = symbol("SLSSpaceAddWindowsAndRemoveFromSpaces", as: AddWindows.self) else {
            NSLog("Cadence: lock screen space unavailable")
            return
        }
        _ = add(space.connection, space.id, [window.windowNumber] as CFArray, 7)
    }
}

