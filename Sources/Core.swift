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
    let measuredAt: Date  // midpoint of the AppleScript call, when `position` was most likely read
    let callTime: Double  // how long that call took; the longer, the less exact the reading
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
        let before = Date()
        let result = script.executeAndReturnError(&error)
        // The call takes 10–50 ms; stamping the reading with the time it returned made lyrics run that much late.
        let measuredAt = before.addingTimeInterval(Date().timeIntervalSince(before) / 2)
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
        return PlayerState(track: track, playing: f[0] == "playing", position: number(f[6]), measuredAt: measuredAt,
                           callTime: Date().timeIntervalSince(before))
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
        let trackName: String?
        let artistName: String?
        let syncedLyrics: String?
        let plainLyrics: String?
        let duration: Double?
    }

    private struct NetEaseSearch: Decodable {
        struct Result: Decodable { let songs: [Song]? }
        struct Song: Decodable {
            struct Artist: Decodable { let name: String }
            let id: Int
            let name: String
            let duration: Double  // milliseconds
            let artists: [Artist]
        }
        let result: Result?
    }

    private struct NetEaseLyric: Decodable {
        struct Text: Decodable { let lyric: String? }
        let lrc: Text?
        let yrc: Text?  // real word-by-word timing, on some songs
    }

    enum Found {
        case timed(String)  // LRC
        case plain(String)  // the words, with no timing
    }

    private enum Reply {
        case found(Data)
        case missing
        case failed(String)
    }

    struct Unavailable: Error {
        let reason: String
    }

    /// Works down from the best kind of answer: timed lyrics filed under this artist, timed lyrics filed under
    /// anyone with the same title and length (Indian film songs are often credited to the singer in one place and
    /// the composer in another), NetEase, and finally the plain words. Returns nil when the song has none of these;
    /// throws when a source couldn't be asked, so a busy server isn't mistaken for a song without lyrics.
    static func lyrics(for track: Track) async throws -> Found? {
        // Both at once. The search usually has the most uploads to compare, but once either has good lyrics the song
        // only waits a moment for the other: LRCLIB is often overloaded, and one slow request shouldn't hold it up.
        var searched: Reply = .missing
        var items: [Item] = []
        await withTaskGroup(of: (exact: Bool, reply: Reply?).self) { group in
            group.addTask { await (true, request("get", [
                "track_name": track.title, "artist_name": track.artist,
                "album_name": track.album, "duration": String(Int(track.duration.rounded())),
            ])) }
            // Search with "- Remastered", "(feat. …)" etc. stripped.
            group.addTask { await (false, request("search", ["track_name": clean(track.title), "artist_name": track.artist])) }
            var waiting = 2
            var hurrying = false
            while waiting > 0, let (exact, reply) = await group.next() {
                guard let reply else { break }  // the moment is up
                waiting -= 1
                if !exact { searched = reply }
                if case .found(let data) = reply {
                    if exact, let item = try? JSONDecoder().decode(Item.self, from: data) { items.append(item) }
                    if !exact, let found = try? JSONDecoder().decode([Item].self, from: data) { items += found }
                }
                // A search that answered is enough to go on: the exact lookup often just returns 503 for a song
                // LRCLIB doesn't have.
                var answered = false
                if !exact, case .found = reply { answered = true }
                if !hurrying, answered || best(items, for: track) != nil {
                    hurrying = true
                    group.addTask {
                        try? await Task.sleep(nanoseconds: 1_500_000_000)
                        return (false, nil)
                    }
                }
            }
            group.cancelAll()
        }
        if let lrc = best(items, for: track) { return .timed(lrc) }

        // Both at once, so a busy LRCLIB's retries don't hold up the answer NetEase may already have.
        async let wideReply = request("search", ["track_name": clean(track.title)])
        async let backupReply = Style.shared.v.lyricsBackup ? netEase(track) : (lrc: nil, failure: nil)
        let (wide, backup) = await (wideReply, backupReply)
        if case .found(let data) = wide, let found = try? JSONDecoder().decode([Item].self, from: data) {
            items += found.filter { sameSong($0.trackName, $0.artistName, $0.duration, as: track) }
        }
        if let lrc = best(items, for: track) { return .timed(lrc) }

        if let lrc = backup.lrc {
            Log.write("lyrics for \(track.title) came from NetEase")
            return .timed(lrc)
        }
        let plain = items
            .filter { $0.plainLyrics?.isEmpty == false && sameSong($0.trackName, $0.artistName, $0.duration, as: track) }
            .min { abs(($0.duration ?? 0) - track.duration) < abs(($1.duration ?? 0) - track.duration) }?
            .plainLyrics
        if let plain { return .plain(plain) }

        // "Nothing found" needs the searches to have really answered.
        for reply in [searched, wide] {
            if case .failed(let reason) = reply { throw Unavailable(reason: reason) }
        }
        if let failure = backup.failure { throw Unavailable(reason: failure) }
        return nil
    }

    /// A match by title alone can be a different song, and wrong lyrics are worse than none: the length has to
    /// agree, and without a shared artist name it has to agree closely.
    private static func sameSong(_ title: String?, _ artist: String?, _ duration: Double?, as track: Track) -> Bool {
        guard let title, let duration, key(clean(title)) == key(clean(track.title)), !key(track.title).isEmpty else {
            return false
        }
        let theirs = Set(words(artist ?? ""))
        let shared = words(track.artist).contains(where: theirs.contains)
        return abs(duration - track.duration) <= (shared ? 4 : 1)
    }

    private static func key(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil).filter { $0.isLetter || $0.isNumber }
    }

    private static func words(_ text: String) -> [String] {
        text.lowercased().split { !$0.isLetter }.map(String.init).filter { $0.count >= 3 }
    }

    /// NetEase Music's public web API, which isn't documented or meant for other apps, so it can stop working at
    /// any time. It has plenty of Indian songs LRCLIB is missing.
    private static func netEase(_ track: Track) async -> (lrc: String?, failure: String?) {
        var search = URLComponents(string: "https://music.163.com/api/search/get")!
        search.queryItems = [URLQueryItem(name: "s", value: clean(track.title)), URLQueryItem(name: "type", value: "1"),
                             URLQueryItem(name: "limit", value: "10")]
        let reply = await fetch(netEaseRequest(search.url!))
        guard case .found(let data) = reply else {
            if case .failed(let reason) = reply { return (nil, "NetEase \(reason)") }
            return (nil, nil)
        }
        for song in netEaseMatches(data, track).prefix(3) {
            var lyric = URLComponents(string: "https://music.163.com/api/song/lyric")!
            lyric.queryItems = [URLQueryItem(name: "id", value: String(song.id)), URLQueryItem(name: "lv", value: "1")]
            if case .found(let data) = await fetch(netEaseRequest(lyric.url!)),
               let raw = (try? JSONDecoder().decode(NetEaseLyric.self, from: data))?.lrc?.lyric,
               let lrc = withoutCredits(raw) {
                return (lrc, nil)
            }
        }
        return (nil, nil)
    }

    private static func netEaseMatches(_ data: Data, _ track: Track) -> [NetEaseSearch.Song] {
        let songs = (try? JSONDecoder().decode(NetEaseSearch.self, from: data))?.result?.songs ?? []
        return songs
            .filter { sameSong($0.name, $0.artists.map(\.name).joined(separator: " "), $0.duration / 1000, as: track) }
            .sorted { abs($0.duration / 1000 - track.duration) < abs($1.duration / 1000 - track.duration) }
    }

    /// Real word-by-word timing, when NetEase has it, for upgrading lyrics already on screen. `asked` is false if
    /// NetEase couldn't be reached, so it's worth trying again another day.
    static func wordTimed(_ track: Track) async -> (lrc: String?, asked: Bool) {
        var search = URLComponents(string: "https://music.163.com/api/search/get")!
        search.queryItems = [URLQueryItem(name: "s", value: clean(track.title)), URLQueryItem(name: "type", value: "1"),
                             URLQueryItem(name: "limit", value: "10")]
        guard case .found(let data) = await fetch(netEaseRequest(search.url!)) else { return (nil, false) }
        for song in netEaseMatches(data, track).prefix(3) {
            var lyric = URLComponents(string: "https://music.163.com/api/song/lyric/v1")!
            lyric.queryItems = [URLQueryItem(name: "id", value: String(song.id)), URLQueryItem(name: "lv", value: "1"),
                                URLQueryItem(name: "yv", value: "1"), URLQueryItem(name: "kv", value: "1")]
            guard case .found(let reply) = await fetch(netEaseRequest(lyric.url!)) else { return (nil, false) }
            if let raw = (try? JSONDecoder().decode(NetEaseLyric.self, from: reply))?.yrc?.lyric,
               let lrc = LRC.fromWordTimed(raw).flatMap(withoutCredits) {
                return (lrc, true)
            }
        }
        return (nil, true)
    }

    private static func netEaseRequest(_ url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        request.setValue("https://music.163.com", forHTTPHeaderField: "Referer")
        return request
    }

    /// NetEase timestamps the credits and marks instrumentals with a line of text; nil if no real lyrics are left.
    private static func withoutCredits(_ lrc: String) -> String? {
        let credits = ["作词", "作曲", "编曲", "制作", "混音", "纯音乐", "监制", "母带", "lyricist", "composer", "producer",
                       "lyrics by", "composed by", "written by", "music by", "mixed by", "mastered by"]
        let lines = lrc.components(separatedBy: .newlines).filter { line in
            let lower = line.lowercased()
            return !credits.contains { lower.contains($0) }
        }
        let sung = LRC.parse(lines.joined(separator: "\n")).filter { !$0.words.isEmpty }
        return sung.count >= 8 ? lines.joined(separator: "\n") : nil
    }

    /// LRCLIB entries are user-submitted and some are badly timed — the exact match for "Night Changes" runs
    /// 5 s ahead of the ~20 other uploads. So gather every close match and take the one whose timing agrees
    /// with the rest, instead of trusting the first hit.
    private static func best(_ items: [Item], for track: Track) -> String? {
        // A version more than a few seconds longer or shorter (radio edit, live, extended) has shifted
        // timestamps, which is worse than no lyrics.
        let candidates = items.compactMap { item -> (lrc: String, starts: [Double])? in
            guard let lrc = item.syncedLyrics, !lrc.isEmpty,
                  abs((item.duration ?? track.duration) - track.duration) <= 4 else { return nil }
            let starts = LRC.parse(lrc).filter { !$0.words.isEmpty }.map(\.start)
            return starts.isEmpty ? nil : (lrc, starts)
        }
        guard !candidates.isEmpty else { return nil }

        // How far apart two uploads are timed: median gap between their sung lines, paired in order.
        func distance(_ a: [Double], _ b: [Double]) -> Double {
            let gaps = zip(a, b).map { abs($0 - $1) }.sorted()
            return gaps.isEmpty ? .infinity : gaps[gaps.count / 2]
        }
        let disagreement = candidates.map { c in candidates.map { distance(c.starts, $0.starts) }.reduce(0, +) }
        let best = disagreement.indices.min { disagreement[$0] < disagreement[$1] }!

        // An upload with real per-word timing wins if it agrees with the consensus.
        if let wordTimed = candidates.first(where: {
            $0.lrc.contains("<") && $0.lrc.contains(">") && distance($0.starts, candidates[best].starts) < 0.4
        }) {
            return wordTimed.lrc
        }
        // Timed uploads are sometimes missing lines or mangled; the untimed lyrics of the closest-length upload
        // can fill them in (see LyricsRepair).
        let plain = items
            .filter { $0.plainLyrics?.isEmpty == false }
            .min { abs(($0.duration ?? 0) - track.duration) < abs(($1.duration ?? 0) - track.duration) }?
            .plainLyrics
        if let plain, let repaired = LyricsRepair.repair(synced: candidates[best].lrc, plain: plain) {
            return repaired
        }
        return candidates[best].lrc
    }

    private static func clean(_ title: String) -> String {
        var t = title
        if let dash = t.range(of: " - ") { t = String(t[..<dash.lowerBound]) }
        if let paren = t.range(of: " (") { t = String(t[..<paren.lowerBound]) }
        return t
    }

    /// The shared session waits 60 s on a stalled server and has no overall limit, which leaves the song
    /// sitting on "Searching lyrics…".
    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 6
        config.timeoutIntervalForResource = 8
        return URLSession(configuration: config)
    }()

    private static func request(_ path: String, _ query: [String: String]) async -> Reply {
        var components = URLComponents(string: "https://lrclib.net/api/" + path)!
        components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        var request = URLRequest(url: components.url!)
        request.setValue("Cadence/1.0 (personal lyrics overlay)", forHTTPHeaderField: "User-Agent")
        return await fetch(request)
    }

    private static func fetch(_ request: URLRequest) async -> Reply {
        let path = request.url?.lastPathComponent ?? ""
        var attempt = 1
        while true {
            if Task.isCancelled { return .failed("\(path): cancelled") }
            let data: Data, response: HTTPURLResponse?
            do {
                let result = try await session.data(for: request)
                (data, response) = (result.0, result.1 as? HTTPURLResponse)
            } catch {
                // A stalled connection often works on a fresh one, so it gets one more go.
                guard (error as? URLError)?.code == .timedOut, attempt < 2 else {
                    return .failed("\(path): \(error.localizedDescription)")
                }
                attempt += 1
                continue
            }
            switch response?.statusCode {
            case 200:
                return .found(data)
            case 404:
                return .missing
            case 429, 503:
                // LRCLIB sheds load with a 503 and a Retry-After of a second or so. The wait grows and varies a
                // little, so parallel requests don't all come back at the same instant.
                guard attempt < 5 else { return .failed("\(path): HTTP \(response?.statusCode ?? 0)") }
                let asked = Double(response?.value(forHTTPHeaderField: "Retry-After") ?? "") ?? 1
                let wait = min(max(asked, 0.5) * (0.6 + 0.4 * Double(attempt)), 3) + Double.random(in: 0...0.4)
                try? await Task.sleep(nanoseconds: UInt64(wait * 1e9))
                attempt += 1
            default:
                return .failed("\(path): HTTP \(response?.statusCode ?? 0)")
            }
        }
    }
}

/// Timed lyrics kept on disk, so a song you've played loads instantly, offline, or while LRCLIB is down.
/// Reloading a song's lyrics replaces its file.
enum LyricsStore {
    private static let folder: URL = {
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Cadence/Lyrics", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    private static func file(_ id: String) -> URL {
        folder.appendingPathComponent(id.replacingOccurrences(of: ":", with: "_")
            .replacingOccurrences(of: "/", with: "_") + ".lrc")
    }

    static func load(_ id: String) -> String? { try? String(contentsOf: file(id), encoding: .utf8) }
    static func save(_ lrc: String, for id: String) { try? lrc.write(to: file(id), atomically: true, encoding: .utf8) }
    static func remove(_ id: String) {
        try? FileManager.default.removeItem(at: file(id))
        try? FileManager.default.removeItem(at: checkedFile(id))
    }

    // Whether NetEase has been asked for this song's word timing, so it's only looked up once.
    private static func checkedFile(_ id: String) -> URL { file(id).appendingPathExtension("checked") }
    static func checked(_ id: String) -> Bool { FileManager.default.fileExists(atPath: checkedFile(id).path) }
    static func markChecked(_ id: String) { FileManager.default.createFile(atPath: checkedFile(id).path, contents: nil) }
}

enum LRC {
    private static let lineTag = try! NSRegularExpression(pattern: #"\[(\d+):(\d+(?:[.:]\d+)?)\]"#)
    private static let wordTag = try! NSRegularExpression(pattern: #"<(\d+):(\d+(?:[.:]\d+)?)>"#)

    /// NetEase's word-timed format ("[start,length](start,length,0)word (start,length,0)word") as enhanced LRC.
    /// Pieces with no space after them are parts of one word.
    static func fromWordTimed(_ yrc: String) -> String? {
        let piece = try! NSRegularExpression(pattern: #"\((\d+),(\d+),\d+\)"#)
        func stamp(_ ms: Double, _ open: String, _ close: String) -> String {
            let seconds = ms / 1000, minutes = Int(seconds) / 60
            return open + String(format: "%02d:%05.2f", minutes, seconds - Double(minutes * 60)) + close
        }
        var out: [String] = []
        for line in yrc.components(separatedBy: .newlines) where line.hasPrefix("[") {
            let ns = line as NSString
            let tags = piece.matches(in: line, range: NSRange(location: 0, length: ns.length))
            guard let first = tags.first, let last = tags.last else { continue }
            func number(_ match: NSTextCheckingResult, _ group: Int) -> Double { Double(ns.substring(with: match.range(at: group))) ?? 0 }
            var text = stamp(number(first, 1), "[", "]")
            var fresh = true  // the next piece begins a new word
            for (i, tag) in tags.enumerated() {
                let stop = i + 1 < tags.count ? tags[i + 1].range.location : ns.length
                let word = ns.substring(with: NSRange(location: tag.range.upperBound, length: stop - tag.range.upperBound))
                if word.trimmingCharacters(in: .whitespaces).isEmpty { fresh = true; continue }
                if fresh { text += stamp(number(tag, 1), "<", ">") }
                text += word.trimmingCharacters(in: .whitespaces)
                fresh = word.hasSuffix(" ")
                if fresh { text += " " }
            }
            out.append(text + stamp(number(last, 1) + number(last, 2), "<", ">"))
        }
        return out.isEmpty ? nil : out.joined(separator: "\n")
    }

    /// Plain lyrics spread over the song by length of line. Only a rough guess at the timing, but the words are
    /// on screen, and tap-to-sync can fix them line by line.
    static func estimated(_ plain: String, duration: Double) -> String {
        let lines = plain.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !($0.hasPrefix("[") && $0.hasSuffix("]")) }  // drop "[Chorus]" labels
        let total = lines.reduce(0) { $0 + $1.count }
        guard total > 0 else { return "" }
        let start = min(10, duration * 0.06), span = duration * 0.96 - start
        var sung = 0
        return lines.map { line in
            let time = start + span * Double(sung) / Double(total)
            sung += line.count
            let minutes = Int(time) / 60
            return String(format: "[%02d:%05.2f] %@", minutes, time - Double(minutes * 60), line)
        }.joined(separator: "\n")
    }

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

        // Line-level LRC: spread the sung part of the line across words, weighted by syllables —
        // singing time follows syllables, so letter counts made long words like "through" lag behind.
        let tokens = text.split(separator: " ").map(String.init)
        guard !tokens.isEmpty else { return [] }
        let span = min((end - start) * 0.92, Double(tokens.count) * 0.5 + 0.8)
        let weights = tokens.map { syllables($0) + 0.6 }
        let total = weights.reduce(0, +)
        var cursor = start
        return zip(tokens, weights).map { token, weight in
            let duration = span * weight / total
            defer { cursor += duration }
            return Word(text: token, start: cursor, end: cursor + duration)
        }
    }

    /// Rough syllable count: vowel groups for Latin text, a letter-based guess for other scripts.
    private static func syllables(_ word: String) -> Double {
        let letters = word.lowercased().filter(\.isLetter)
        guard !letters.isEmpty else { return 0.5 }
        guard letters.allSatisfy(\.isASCII) else { return max(1, Double(letters.count) / 2.5) }
        var groups = 0
        var previousVowel = false
        for c in letters {
            let vowel = "aeiouy".contains(c)
            if vowel && !previousVowel { groups += 1 }
            previousVowel = vowel
        }
        if letters.hasSuffix("e") && !letters.hasSuffix("le") && groups > 1 { groups -= 1 }  // silent e
        return Double(max(groups, 1))
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
        didSet {
            words = lyrics.flatMap(\.words)
            wordLines = lyrics.flatMap { line in line.words.map { _ in line.id } }
            let keys = lyrics.map { $0.words.map(\.text).joined(separator: " ").lowercased().filter(\.isLetter) }
            let counts = Dictionary(keys.filter { $0.count > 6 }.map { ($0, 1) }, uniquingKeysWith: +)
            repeated = Set(keys.indices.filter { (counts[keys[$0]] ?? 0) > 1 })
            bursts = words.enumerated().compactMap { i, word in
                Burst.kind(for: word.text).map { (i, word.start, $0) }
            }
        }
    }
    /// Sung words that set off a keyword burst, in order.
    private(set) var bursts: [(index: Int, start: Double, kind: Burst)] = []
    /// When the current song was first seen, and how far into it it was — the title card plays from here.
    private(set) var trackStart = (date: Date.distantPast, position: 0.0)
    /// The lyric line each entry of `words` belongs to.
    private(set) var wordLines: [Int] = []
    /// Lines sung more than once — roughly the chorus, where the visuals push harder.
    private(set) var repeated: Set<Int> = []
    /// Every word of the song in order, for the one-word-at-a-time stack.
    private(set) var words: [Word] = []
    @Published private(set) var status = ""
    @Published private(set) var palette = Palette.fallback
    @Published private(set) var artwork: NSImage?
    @Published private(set) var backdrop: NSImage?  // artwork, small and already blurred
    @Published private(set) var wallpaper: NSImage?  // artwork, sharp and capped in size
    @Published private(set) var duotone: NSImage?  // artwork printed in two album colours
    @Published private(set) var cutout: NSImage?  // just the person/subject of `wallpaper`, transparent elsewhere
    @Published private(set) var duotoneCutout: NSImage?
    @Published var locked = false
    @Published var previewing = false  // shows the lock-screen view on the desktop briefly

    // Position is interpolated between polls so animation runs at full frame rate.
    private var basePosition = 0.0
    private var baseTime = Date()
    private var cache: [String: [LyricLine]] = [:]
    @Published private(set) var untimed = false  // showing plain lyrics with estimated timing
    private var untimedIDs: Set<String> = []

    func position(at date: Date) -> Double {
        isPlaying ? basePosition + date.timeIntervalSince(baseTime) : basePosition
    }

    /// Word changes are animated (springs, pop-ins of ~0.3 s), so a word drawn exactly at its timestamp only
    /// lands visibly a beat late. Leading slightly makes the animation arrive with the voice.
    private let visualLead = 0.12
    /// Time from the Mac playing a sound to you hearing it; lyrics hold back to match your ears.
    var outputDelay = 0.0 {
        didSet {
            if abs(outputDelay - oldValue) > 0.005 { Log.write("output delay: \(Int(outputDelay * 1000)) ms") }
        }
    }

    /// The song time lyrics are drawn at: playback position plus the animation lead and the user's offset.
    func lyricTime(at date: Date) -> Double {
        position(at: date) + (isPlaying ? visualLead - outputDelay : 0) + Style.shared.v.offset + AutoSync.shared.offset
            + SongTiming.shared.offset(track?.id)
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
    private var quickestCall = 1.0

    func poll() {
        guard !polling else { return }
        polling = true
        playerQueue.async {
            let state = Player.state()
            DispatchQueue.main.async {
                self.polling = false
                self.apply(state)
            }
        }
    }

    private func apply(_ state: PlayerState?) {
        guard let state else {
            if isPlaying { isPlaying = false }
            return
        }
        if state.track.id != track?.id {
            trackChanged(state.track)
            trackStart = (state.measuredAt, state.position)
        }
        let measured = state.measuredAt
        // A reading from a slow call could be off by up to half of it (they range from 30 to 180 ms), so it's no
        // use for fine correction. The quickest recent call sets the bar.
        quickestCall = min(quickestCall * 1.01, state.callTime)
        let drift = state.position - position(at: measured)
        if state.playing != isPlaying || abs(drift) > 0.25 {
            // Seek, pause or track change: jump straight to the player's position.
            basePosition = state.position
            baseTime = measured
        } else if abs(drift) > 0.02 && state.callTime <= quickestCall * 2 + 0.01 {
            // Small drift used to be ignored up to 0.3 s, so lyrics could sit that far off for a whole song.
            // Ease a third of the way towards the player each poll: converges in a few seconds, and a
            // single noisy reading moves words by only a few milliseconds.
            basePosition += drift / 3
        }
        if state.playing != isPlaying { isPlaying = state.playing }
    }

    /// 1 right as a word starts, decaying to 0 — drives the edge glow in time with the vocals.
    func wordPulse(at time: Double) -> Double {
        guard let line = lyrics.last(where: { $0.start <= time }),
              let word = line.words.last(where: { $0.start <= time }) else { return 0 }
        return exp(-(time - word.start) * 5)
    }

    /// What the visuals hit on: the real kick drum when Cadence can hear the music, else each sung word.
    func kick(at time: Double, date: Date) -> Double {
        if Style.shared.v.audioReactive, let kick = AudioPulse.shared.kick(at: date) { return kick }
        return wordPulse(at: time)
    }

    /// Lyrics were searched for and there are none — the stage switches to its visual-only mode.
    var noLyrics: Bool { lyrics.isEmpty && status.hasPrefix("No synced") }

    func reloadLyrics() {
        guard let track else { return }
        cache[track.id] = nil
        untimedIDs.remove(track.id)
        LyricsStore.remove(track.id)
        loadLyrics(track)
    }

    private func trackChanged(_ track: Track) {
        self.track = track
        PresetMemory.shared.songChanged(track)
        loadLyrics(track)
        loadArtwork(track)
    }

    private func loadLyrics(_ track: Track, attempt: Int = 0) {
        untimed = false
        // Lyrics you timed yourself with tap-to-sync win over anything downloaded.
        if let tapped = SongTiming.shared.tapped(track.id) {
            lyrics = LRC.parse(tapped)
            status = ""
            return
        }
        if let cached = cache[track.id] {
            lyrics = cached
            untimed = untimedIDs.contains(track.id)
            status = cached.isEmpty ? "No synced lyrics for this song" : ""
            return
        }
        if let text = LyricsStore.load(track.id), case let saved = LRC.parse(text), !saved.isEmpty {
            cache[track.id] = saved
            lyrics = saved
            status = ""
            upgradeToWordTiming(track, text)
            return
        }
        // Ads and the gaps between songs come through with no title; there's nothing to search for.
        guard !track.title.trimmingCharacters(in: .whitespaces).isEmpty else {
            lyrics = []
            status = ""
            return
        }
        // A retry stays quiet: the song keeps showing what went wrong until there's something better.
        if attempt == 0 {
            lyrics = []
            status = "Searching lyrics…"
        }
        Task {
            let found: LRCLib.Found?
            do {
                found = try await LRCLib.lyrics(for: track)
            } catch {
                await MainActor.run {
                    Log.write("lyrics search failed for \(track.title): \((error as? LRCLib.Unavailable)?.reason ?? "\(error)")")
                    guard self.track?.id == track.id else { return }
                    self.status = "Couldn't reach the lyrics service"
                }
                // Not cached, so it can try again: every 30 s for 3 minutes while the song is playing.
                guard attempt < 6 else { return }
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                await MainActor.run {
                    guard self.track?.id == track.id, self.cache[track.id] == nil else { return }
                    self.loadLyrics(track, attempt: attempt + 1)
                }
                return
            }
            await MainActor.run {
                var lines: [LyricLine] = []
                var estimated = false
                switch found {
                case .timed(let lrc):
                    lines = LRC.parse(lrc)
                    LyricsStore.save(lrc, for: track.id)
                    self.upgradeToWordTiming(track, lrc)
                case .plain(let plain):
                    lines = LRC.parse(LRC.estimated(plain, duration: track.duration))
                    estimated = !lines.isEmpty
                    if estimated { self.untimedIDs.insert(track.id) }
                case nil:
                    break
                }
                self.cache[track.id] = lines
                Log.write("\(lines.count) lyric lines\(estimated ? " (untimed)" : "") for \(track.title), first sung at \(lines.first { !$0.words.isEmpty }?.start ?? 0)s")
                guard self.track?.id == track.id else { return }
                self.lyrics = lines
                self.untimed = estimated
                self.status = lines.isEmpty ? "No synced lyrics for this song" : ""
            }
        }
    }

    /// Lyrics go up straight away; real word timing, if NetEase has it, replaces them in the background.
    private func upgradeToWordTiming(_ track: Track, _ lrc: String) {
        guard Style.shared.v.lyricsBackup, !lrc.contains("<"), !LyricsStore.checked(track.id) else { return }
        Task {
            let found = await LRCLib.wordTimed(track)
            await MainActor.run {
                if found.asked { LyricsStore.markChecked(track.id) }
                guard let timed = found.lrc, SongTiming.shared.tapped(track.id) == nil else { return }
                let lines = LRC.parse(timed)
                LyricsStore.save(timed, for: track.id)
                self.cache[track.id] = lines
                Log.write("real word timing for \(track.title), \(lines.count) lines")
                if self.track?.id == track.id { self.lyrics = lines }
            }
        }
    }

    func isEstimated(_ id: String) -> Bool { untimedIDs.contains(id) }
    func forgetCached(_ id: String) { if track?.id != id { cache[id] = nil } }

    private let artworkQueue = DispatchQueue(label: "cadence.artwork", qos: .userInitiated)
    private let artworkSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 8
        config.timeoutIntervalForResource = 12
        return URLSession(configuration: config)
    }()
    private let artworkFolder: URL = {
        let url = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Cadence/Artwork", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    /// A failed download used to leave the last song's wallpaper up for good, so it now retries for about half a
    /// minute while the song is playing. Covers are kept on disk, so a song you've played needs no network at all.
    private func loadArtwork(_ track: Track, attempt: Int = 1) {
        guard let url = track.artworkURL else {
            playerQueue.async { [weak self] in
                guard let self else { return }
                if let data = Player.musicArtworkData(), let image = NSImage(data: data) {
                    artworkQueue.async { self.apply(artwork: image, for: track) }
                } else {
                    DispatchQueue.main.async { self.clearArtwork(for: track) }
                }
            }
            return
        }
        let file = artworkFolder.appendingPathComponent(url.lastPathComponent)
        if let saved = try? Data(contentsOf: file), let image = NSImage(data: saved) {
            artworkQueue.async { self.apply(artwork: image, for: track) }
            return
        }
        artworkSession.dataTask(with: url) { [weak self] data, response, error in
            guard let self else { return }
            if let data, (response as? HTTPURLResponse)?.statusCode == 200, let image = NSImage(data: data) {
                try? data.write(to: file, options: .atomic)
                artworkQueue.async { self.apply(artwork: image, for: track) }
                return
            }
            DispatchQueue.main.async {
                guard self.track?.id == track.id else { return }
                Log.write("artwork failed for \(track.title) (try \(attempt)): \(error?.localizedDescription ?? "bad response")")
                guard attempt < 5 else { return self.clearArtwork(for: track) }
                DispatchQueue.main.asyncAfter(deadline: .now() + pow(2, Double(attempt - 1))) {
                    guard self.track?.id == track.id else { return }
                    self.loadArtwork(track, attempt: attempt + 1)
                }
            }
        }.resume()
    }

    /// With no cover to show, the album-coloured backdrop is better than another song's picture.
    private func clearArtwork(for track: Track) {
        guard self.track?.id == track.id else { return }
        palette = Palette.fallback
        artwork = nil
        backdrop = nil
        wallpaper = nil
        duotone = nil
        cutout = nil
        duotoneCutout = nil
    }

    /// Runs off the main thread, one song at a time. The picture goes up first; cutting out the artist is slow, so
    /// it follows, and is skipped if the song has already changed again.
    private func apply(artwork image: NSImage, for track: Track) {
        guard DispatchQueue.main.sync(execute: { self.track?.id == track.id }) else { return }
        let palette = Palette.colors(from: image)
        let backdrop = Backdrop.blurred(image)
        let wallpaper = Backdrop.wallpaper(image)
        let duotone = Backdrop.duotone(image, palette: palette)
        DispatchQueue.main.async {
            guard self.track?.id == track.id else { return }
            self.palette = palette
            self.artwork = image
            self.backdrop = backdrop
            self.wallpaper = wallpaper
            self.duotone = duotone
            // The last song's artist mustn't stand on top of the new cover.
            self.cutout = nil
            self.duotoneCutout = nil
        }
        guard DispatchQueue.main.sync(execute: { self.track?.id == track.id }) else { return }
        let mask = wallpaper.flatMap(Backdrop.subjectMask)
        let cutout = mask.flatMap { mask in wallpaper.flatMap { Backdrop.cutout($0, mask: mask) } }
        let duotoneCutout = mask.flatMap { mask in duotone.flatMap { Backdrop.cutout($0, mask: mask) } }
        Log.write("artwork subject cut-out: \(cutout == nil ? "none" : "found")")
        DispatchQueue.main.async {
            guard self.track?.id == track.id else { return }
            self.cutout = cutout
            self.duotoneCutout = duotoneCutout
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

