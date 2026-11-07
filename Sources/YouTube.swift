import AppKit

// MARK: - YouTube (in Chrome, Safari, Arc, Brave, Edge or Vivaldi)

/// YouTube and YouTube Music play in a browser tab, which AppleScript can't ask for a "current track". Instead
/// Cadence runs a few lines of JavaScript in each YouTube tab: the video element gives the exact position and the
/// player gives the video's id, title and channel. Browsers only allow this once "Allow JavaScript from Apple
/// Events" is on (Chrome: View › Developer; Safari: Settings › Developer).
enum YouTube {
    struct Browser {
        let bundleID: String
        let name: String
        var safari: Bool { bundleID == "com.apple.Safari" }
        /// Where the browser keeps the switch that lets AppleScript run JavaScript.
        var setting: String {
            safari ? "Safari › Settings › Advanced › Show features for web developers, then Developer › Allow JavaScript from Apple Events"
                : "\(name)'s menu bar: View › Developer › Allow JavaScript from Apple Events"
        }
    }

    static let browsers = [
        Browser(bundleID: "com.google.Chrome", name: "Google Chrome"),
        Browser(bundleID: "com.google.Chrome.canary", name: "Chrome Canary"),
        Browser(bundleID: "company.thebrowser.Browser", name: "Arc"),
        Browser(bundleID: "com.brave.Browser", name: "Brave"),
        Browser(bundleID: "com.microsoft.edgemac", name: "Microsoft Edge"),
        Browser(bundleID: "com.vivaldi.Vivaldi", name: "Vivaldi"),
        Browser(bundleID: "com.apple.Safari", name: "Safari"),
    ]

    /// Browsers with YouTube open that refuse to run JavaScript for Cadence. Read on the main thread.
    private(set) static var blocked: [Browser] = []

    // Everything below runs on NowPlaying's player queue.

    /// One YouTube tab, as its JavaScript reported it.
    private struct Reading: Decodable {
        let id: String
        let t: Double  // position
        let d: Double  // length
        let play: Bool
        let now: Double  // when `t` was read, in ms since 1970
        let title: String
        let author: String
        let album: String
        let music: Bool  // on music.youtube.com
        let ad: Bool
        let cat: String  // YouTube's category for the video, when known
        let art: String
        let song: String  // the description's "Music" card, when it names exactly one song
        let singer: String
    }

    /// The tab a reading came from, so the play/pause and seek buttons reach it.
    private struct Tab {
        let browser: Browser
        let window: String
        let index: Int
        let id: String  // Chrome-family tabs keep an id when tabs move; Safari's don't have one
    }

    private static var scripts: [String: NSAppleScript] = [:]
    private static var permission: [String: OSStatus] = [:]
    private static var permissionChecked: [String: Date] = [:]
    private static var lastScan = Date.distantPast
    private static var cached: PlayerState?
    private static var tab: Tab?
    private static var lastTrack: Track?
    private static var blockedIDs: Set<String> = []
    /// YouTube tabs (video id, tab title) in browsers that won't run JavaScript: all that can be known without it.
    private static var unreadable: [(id: String, title: String, browser: Browser)] = []

    /// Track ids for a video Cadence can see but not read; lyrics wait for the browser setting.
    static let setupPrefix = "youtube-setup:"

    /// The YouTube tab that's playing, else a paused one. Tabs are only looked through every second or two while
    /// nothing is playing, so an idle browser costs almost nothing.
    static func state() -> PlayerState? {
        // The tab being followed is read on its own: one quick call instead of a walk through every tab. Other tabs
        // are only looked through when it's paused (once a second) or gone.
        if let tab {
            let reading = read(tab)
            if let reading, reading.play || Date().timeIntervalSince(lastScan) < 1 {
                cached = state(from: reading)
                return cached
            }
            if reading == nil { lastScan = .distantPast }
        }
        let wait = cached == nil ? 2.0 : 1.0
        guard Date().timeIntervalSince(lastScan) >= wait else { return cached }
        lastScan = Date()
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        var paused: (Reading, Tab)?
        var found: (Reading, Tab)?
        unreadable = []
        for browser in browsers where running.contains(browser.bundleID) && allowed(browser) {
            for (reading, tab) in scan(browser) {
                if reading.play && !reading.ad { found = (reading, tab); break }
                // The tab Cadence was already following wins among paused ones.
                if paused == nil || "youtube:" + reading.id == lastTrack?.id { paused = (reading, tab) }
            }
            if found != nil { break }
        }
        guard let (reading, tab) = found ?? paused else {
            self.tab = nil
            // A YouTube tab that can't be read still beats showing an old, paused song: show the video's name and
            // what to switch on.
            cached = unreadable.first.map { video in
                let track = Track(id: setupPrefix + video.id, title: tidy(video.title), artist: "YouTube — needs one switch in \(video.browser.name)",
                                  album: "", duration: 0, artworkURL: URL(string: "https://i.ytimg.com/vi/\(video.id)/hqdefault.jpg"),
                                  video: true)
                return PlayerState(track: track, playing: false, position: 0, measuredAt: Date(), callTime: 0.01)
            }
            return cached
        }
        if self.tab?.id != tab.id || self.tab?.window != tab.window || self.tab?.index != tab.index {
            self.tab = tab
            tabScript = nil
        }
        cached = state(from: reading)
        return cached
    }

    private static var tabScript: NSAppleScript?

    /// The followed tab alone, with a script compiled once per tab. nil if the tab's gone or left the video.
    private static func read(_ tab: Tab) -> Reading? {
        let script = tabScript ?? {
            let source = "tell application id \"\(tab.browser.bundleID)\" to " + run(pageScript, in: reference(tab), tab.browser)
            let script = NSAppleScript(source: source)!
            script.compileAndReturnError(nil)
            tabScript = script
            return script
        }()
        var error: NSDictionary?
        let out = script.executeAndReturnError(&error).stringValue ?? ""
        return error == nil && !out.isEmpty ? try? JSONDecoder().decode(Reading.self, from: Data(out.utf8)) : nil
    }

    private static func reference(_ tab: Tab) -> String {
        func literal(_ s: String) -> String { Int(s) != nil ? s : quoted(s) }
        let window = "window id \(literal(tab.window))"
        return tab.browser.safari || tab.id.isEmpty ? "(tab \(tab.index) of \(window))" : "(tab id \(literal(tab.id)) of \(window))"
    }

    private static func state(from r: Reading) -> PlayerState? {
        let id = "youtube:" + r.id
        // During an ad the video element plays the ad: hold the song where it was instead of jumping to the ad.
        if r.ad {
            guard let track = lastTrack, track.id == id else { return nil }
            return PlayerState(track: track, playing: false, position: cached?.position ?? 0, measuredAt: Date(), callTime: 0.01)
        }
        // Vlogs, games and news have no lyrics; music, film and entertainment (where film songs often go) do.
        guard r.music || !r.song.isEmpty || ["", "Music", "Entertainment", "Film & Animation"].contains(r.cat) else { return nil }
        let track = lastTrack?.id == id ? lastTrack! : makeTrack(r)
        lastTrack = track
        // The page stamps the reading itself, so it's exact however long AppleScript took.
        return PlayerState(track: track, playing: r.play, position: r.t, measuredAt: Date(timeIntervalSince1970: r.now / 1000),
                           callTime: 0.005)
    }

    // MARK: Reading the tabs

    private static let pageScript = #"""
        (function(){try{
        var v=document.querySelector('video.html5-main-video')||document.querySelector('video');
        if(!v||!(v.duration>0)||!isFinite(v.duration))return '';
        var p=document.getElementById('movie_player');
        var d={};try{d=p.getVideoData()||{}}catch(e){}
        var r={};try{r=p.getPlayerResponse()||{}}catch(e){}
        var m=navigator.mediaSession&&navigator.mediaSession.metadata;
        var id=d.video_id||new URLSearchParams(location.search).get('v')||'';
        if(!id)return '';
        var mf=r.microformat&&r.microformat.playerMicroformatRenderer;
        var o={id:id,t:v.currentTime,d:v.duration,play:!v.paused&&!v.ended,now:Date.now(),
        title:d.title||(m&&m.title)||document.title.replace(' - YouTube Music','').replace(' - YouTube',''),
        author:d.author||(m&&m.artist)||'',album:(m&&m.album)||'',music:location.host.indexOf('music.')==0,
        ad:!!document.querySelector('.ad-showing,.ad-interrupting'),
        cat:(r.videoDetails&&r.videoDetails.videoId==id&&mf&&mf.category)||'',
        art:(m&&m.artwork&&m.artwork.length)?m.artwork[m.artwork.length-1].src:'',song:'',singer:''};
        var f=document.querySelector('ytd-watch-flexy');
        if(f&&f.getAttribute('video-id')==id){var seen={},n=0;
        [].forEach.call(f.querySelectorAll('ytd-horizontal-card-list-renderer'),function(s){
        if((s.innerText||'').trim().indexOf('Music')!=0)return;
        [].forEach.call(s.querySelectorAll('yt-video-attribute-view-model'),function(a){
        var L=[].filter.call(a.querySelectorAll('*'),function(e){return !e.children.length&&e.textContent.trim()}).map(function(e){return e.textContent.trim()});
        if(L.length>1&&!seen[L[0]+'|'+L[1]]){seen[L[0]+'|'+L[1]]=1;n++;o.song=L[0];o.singer=L[1]}})});
        if(n!=1){o.song='';o.singer=''}}
        return JSON.stringify(o)}catch(e){return ''}})()
        """#

    /// JavaScript as an AppleScript string literal.
    private static func quoted(_ js: String) -> String {
        "\"" + js.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "") + "\""
    }

    /// Runs `js` in a tab: Chrome-family browsers call it `execute`, Safari `do JavaScript`.
    private static func run(_ js: String, in tab: String, _ browser: Browser) -> String {
        browser.safari ? "do JavaScript \(quoted(js)) in \(tab)" : "execute \(tab) javascript \(quoted(js))"
    }

    /// Every YouTube watch tab in one browser, in one AppleScript call: a URL list per window, and JavaScript only
    /// in YouTube tabs.
    private static func scan(_ browser: Browser) -> [(Reading, Tab)] {
        let script = scripts[browser.bundleID] ?? {
            let source = """
                tell application id "\(browser.bundleID)"
                    set out to {}
                    set s to character id 31
                    repeat with w in windows
                        set us to URL of tabs of w
                        repeat with i from 1 to count of us
                            set u to (item i of us) as text
                            if u contains "youtube.com/watch" or u contains "music.youtube.com/" then
                                set r to \(run(pageScript, in: "(tab i of w)", browser))
                                if r is not missing value and r is not "" then set end of out to ((id of w) as text) & s & (i as text) & s & \(browser.safari ? "\"\"" : "((id of tab i of w) as text)") & s & r
                            end if
                        end repeat
                    end repeat
                    set AppleScript's text item delimiters to character id 30
                    return out as text
                end tell
                """
            let script = NSAppleScript(source: source)!
            scripts[browser.bundleID] = script
            return script
        }()
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        if let error {
            let message = error[NSAppleScript.errorMessage] as? String ?? error.description
            if message.contains("JavaScript from Apple Events") || message.contains("JavaScript through AppleScript") {
                setBlocked(browser, true)
                unreadable += titles(browser)
            } else {
                Log.write("YouTube in \(browser.name): \(message)")
            }
            return []
        }
        setBlocked(browser, false)
        guard let out = result.stringValue, !out.isEmpty else { return [] }
        return out.components(separatedBy: "\u{1E}").compactMap { entry in
            let f = entry.components(separatedBy: "\u{1F}")
            guard f.count >= 4, let index = Int(f[1]),
                  let reading = try? JSONDecoder().decode(Reading.self, from: Data(f[3...].joined(separator: "\u{1F}").utf8))
            else { return nil }
            return (reading, Tab(browser: browser, window: f[0], index: index, id: f[2]))
        }
    }

    /// The YouTube tabs of a browser that won't run JavaScript, by URL and tab title alone.
    private static func titles(_ browser: Browser) -> [(id: String, title: String, browser: Browser)] {
        let source = """
            tell application id "\(browser.bundleID)"
                set out to {}
                repeat with w in windows
                    repeat with t in tabs of w
                        set u to (URL of t) as text
                        if u contains "youtube.com/watch" or u contains "music.youtube.com/watch" then set end of out to u & (character id 31) & ((\(browser.safari ? "name" : "title") of t) as text)
                    end repeat
                end repeat
                set AppleScript's text item delimiters to character id 30
                return out as text
            end tell
            """
        var error: NSDictionary?
        guard let out = NSAppleScript(source: source)?.executeAndReturnError(&error).stringValue, !out.isEmpty else { return [] }
        return out.components(separatedBy: "\u{1E}").compactMap { entry in
            let f = entry.components(separatedBy: "\u{1F}")
            guard f.count == 2, let id = URLComponents(string: f[0])?.queryItems?.first(where: { $0.name == "v" })?.value else { return nil }
            let title = f[1].replacingOccurrences(of: " - YouTube Music", with: "").replacingOccurrences(of: " - YouTube", with: "")
                .replacing(#/^\(\d+\)\s*/#, with: "")  // "(3) " unread-notification count
            return (id, title, browser)
        }
    }

    /// Asks once per launch to control the browser (macOS shows its consent prompt); a refusal is checked again
    /// every half minute without asking, in case it's been allowed in System Settings since.
    private static func allowed(_ browser: Browser) -> Bool {
        let id = browser.bundleID
        if let status = permission[id], status == noErr { return true }
        if let last = permissionChecked[id], Date().timeIntervalSince(last) < 30 { return false }
        let ask = permission[id] == nil
        permissionChecked[id] = Date()
        var target = AEAddressDesc()
        let created = id.withCString { AECreateDesc(DescType(typeApplicationBundleID), $0, id.utf8.count, &target) }
        guard created == noErr else { return false }
        let status = AEDeterminePermissionToAutomateTarget(&target, AEEventClass(typeWildCard), AEEventID(typeWildCard), ask)
        AEDisposeDesc(&target)
        if permission[id] != status { Log.write("permission for \(id): \(status)") }
        permission[id] = status
        return status == noErr
    }

    private static func setBlocked(_ browser: Browser, _ isBlocked: Bool) {
        guard blockedIDs.contains(browser.bundleID) != isBlocked else { return }
        if isBlocked { blockedIDs.insert(browser.bundleID) } else { blockedIDs.remove(browser.bundleID) }
        let list = browsers.filter { blockedIDs.contains($0.bundleID) }
        Log.write(isBlocked ? "YouTube: \(browser.name) won't run JavaScript from Apple Events" : "YouTube: \(browser.name) allowed")
        DispatchQueue.main.async {
            blocked = list
            if isBlocked { NotificationCenter.default.post(name: .youTubeBlocked, object: browser.name) }
        }
    }

    // MARK: Controls

    /// "playpause", "next track" or "previous track", in the tab the song is playing in.
    static func command(_ verb: String) {
        let js: String
        switch verb {
        case "next track":
            js = "if(p&&p.nextVideo)p.nextVideo();else{var b=document.querySelector('.ytp-next-button,.next-button');if(b)b.click()}"
        case "previous track":
            js = "if(v.currentTime>3||!(p&&p.previousVideo))v.currentTime=0;else p.previousVideo()"
        default:
            js = "if(p&&p.getPlayerState){if(p.getPlayerState()==1)p.pauseVideo();else p.playVideo()}else if(v.paused)v.play();else v.pause()"
        }
        send(js)
    }

    static func seek(to seconds: Double) {
        let s = String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), seconds)
        send("if(p&&p.seekTo)p.seekTo(\(s),true);else v.currentTime=\(s)")
        cached = nil
    }

    private static func send(_ body: String) {
        guard let tab, let id = lastTrack?.id.dropFirst("youtube:".count) else { return }
        // The tab could have moved; only act if it still shows the same video.
        let js = "(function(){var v=document.querySelector('video.html5-main-video')||document.querySelector('video');"
            + "var p=document.getElementById('movie_player');try{var d=p.getVideoData();if(d&&d.video_id&&d.video_id!='\(id)')return}catch(e){}"
            + "if(!v)return;\(body)})()"
        let source = "tell application id \"\(tab.browser.bundleID)\" to \(run(js, in: reference(tab), tab.browser))"
        var error: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let error { Log.write("YouTube command failed: \(error)") }
    }

    // MARK: Turning a video into a song

    private static func makeTrack(_ r: Reading) -> Track {
        let channel = artistName(fromChannel: r.author)
        var readings: [(title: String, artist: String)] = []
        if r.music {
            // YouTube Music gives the song's own title and artist.
            readings.append((tidy(r.title), channel))
        }
        if !r.song.isEmpty { readings.append((tidy(r.song), r.singer)) }
        readings += guesses(title: r.title, channel: channel)
        var seen = Set<String>()
        readings = readings.filter { !$0.title.isEmpty && seen.insert(($0.title + "|" + $0.artist).lowercased()).inserted }
        let first = readings.first ?? (r.title, channel)
        let hints = ([r.author, r.singer] + segments(of: r.title)).joined(separator: " ")
        let (art, fallback) = artwork(r)
        func track(_ reading: (title: String, artist: String)) -> Track {
            Track(id: "youtube:" + r.id, title: reading.title, artist: reading.artist, album: r.album, duration: r.d,
                  artworkURL: art, artworkFallback: fallback, video: true, hints: hints)
        }
        var main = track(first)
        main.alternates = readings.dropFirst().prefix(3).map(track)
        Log.write("YouTube: \"\(r.title)\" by \(r.author) → \(readings.map { "\($0.title) / \($0.artist)" }.joined(separator: "; "))")
        return main
    }

    /// Album art on YouTube Music (square, any size asked for), else the video's widest thumbnail, falling back to
    /// the one every video has.
    private static func artwork(_ r: Reading) -> (URL?, URL?) {
        let fallback = URL(string: "https://i.ytimg.com/vi/\(r.id)/hqdefault.jpg")
        if r.art.contains("googleusercontent.com") {
            let big = r.art.replacingOccurrences(of: #"=w\d+-h\d+"#, with: "=w1200-h1200", options: .regularExpression)
            return (URL(string: big), fallback)
        }
        return (URL(string: "https://i.ytimg.com/vi/\(r.id)/maxresdefault.jpg"), fallback)
    }

    /// "Ed Sheeran", from "EdSheeranVEVO", "Ed Sheeran - Topic" or "Ed Sheeran Official".
    static func artistName(fromChannel channel: String) -> String {
        var name = channel.trimmingCharacters(in: .whitespaces)
        for suffix in [" - Topic", "VEVO", " Official", " Music", " Official Channel"] where name.hasSuffix(suffix) {
            name = String(name.dropLast(suffix.count)).trimmingCharacters(in: .whitespaces)
        }
        return name
    }

    /// The parts of a title split by "|": Indian film songs list the film, the stars and the singers this way.
    private static func segments(of title: String) -> [String] {
        title.components(separatedBy: CharacterSet(charactersIn: "|｜")).map { tidy($0) }.filter { !$0.isEmpty }
    }

    /// Every likely (song, artist) reading of a video title, most likely first.
    static func guesses(title: String, channel: String) -> [(title: String, artist: String)] {
        let parts = segments(of: title)
        guard let main = parts.first else { return [] }
        // Korean and some Western videos: Artist 'Song' MV.
        if let m = main.firstMatch(of: #/^(.+?)\s*['‘"“](.+?)['’"”]/#) {
            return [(tidy(String(m.2)), tidy(String(m.1))), (main, channel)]
        }
        let dash = main.firstMatch(of: #/\s[-–—~]\s/#)
        guard let dash else {
            // "Song | Film | Singer": try the song with the channel, then with each name after it.
            return [(main, channel)] + parts.dropFirst().prefix(3).map { (main, $0) }
        }
        let left = tidy(String(main[..<dash.range.lowerBound])), right = tidy(String(main[dash.range.upperBound...]))
        let rightFirst = (right, left), leftFirst = (left, right)
        // The channel usually names the artist, which says which side is the song.
        let ch = key(channel)
        if !ch.isEmpty, key(right).contains(ch) || ch.contains(key(right)), !key(right).isEmpty {
            return [leftFirst, rightFirst, (left, channel)]
        }
        // "Artist - Song" is the usual way round; "Song - Film" is common for Indian songs.
        return [rightFirst, leftFirst, (left, channel), (right, channel)]
    }

    /// A title without its packaging: brackets, "Official Video", "Full Video Song:", hashtags and featured artists.
    static func tidy(_ text: String) -> String {
        var t = text.replacingOccurrences(of: "#", with: "")
        t = t.replacing(#/\[[^\]]*\]|【[^】]*】|\([^)]*\)|（[^）]*）/#, with: " ")
        t = t.replacing(#/(?i)^\s*(full\s+)?(video|audio|song|lyrical|lyrics?|lyric(al)?\s+video|official\s+(music\s+)?video)\s*[:：]\s*/#, with: "")
        t = t.replacing(#/(?i)\b(official\s+(music\s+|lyric(al)?\s+)?(video|audio|visuali[sz]er)|full\s+video\s+song|full\s+video|video\s+song|full\s+song|audio\s+song|lyric(al)?\s+video|with\s+lyrics|lyrics|4k|hd|hq|mv|m\/v)\b/#, with: " ")
        if let feat = t.firstMatch(of: #/(?i)\s(ft\.?|feat\.?|featuring)\s/#) { t = String(t[..<feat.range.lowerBound]) }
        t = t.replacing(#/\s+/#, with: " ")
        return t.trimmingCharacters(in: CharacterSet(charactersIn: " -–—~:|,."))
    }

    private static func key(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil).filter { $0.isLetter || $0.isNumber }
    }

    // MARK: Artwork

    /// The fallback thumbnail is 4:3 with black bars above and below the 16:9 picture; this cuts them off.
    static func withoutLetterbox(_ image: NSImage) -> NSImage {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return image }
        let w = Double(cg.width), h = Double(cg.height)
        guard abs(w / h - 4.0 / 3.0) < 0.05 else { return image }
        let inner = w * 9 / 16
        guard let cropped = cg.cropping(to: CGRect(x: 0, y: ((h - inner) / 2).rounded(), width: w, height: inner.rounded())) else {
            return image
        }
        return NSImage(cgImage: cropped, size: NSSize(width: cropped.width, height: cropped.height))
    }
}

extension Notification.Name {
    /// A browser with YouTube open won't run JavaScript for Cadence; the object is its name.
    static let youTubeBlocked = Notification.Name("cadence.youTubeBlocked")
}
