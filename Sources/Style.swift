import AppKit
import CoreText
import SwiftUI

// MARK: - Style settings

/// Every customisation lives here; persisted as one JSON blob so defaults are declared once.
struct StyleValues: Codable, Equatable {
    // Font
    var fontFamily = "Unbounded"
    var fontWeight = "bold"
    var italic = false
    var uppercase = false
    var tracking = 0.0
    var lineSpacing = 14.0
    var alignment = "center"
    var textShadow = true

    // Color
    var colorMode = "album"  // album, white, custom
    var customHex = "#FF5FA2"
    var unsungOpacity = 0.3
    var glow = 0.5

    // Animation
    var wordStyle = "mix"  // mix, or one of StyleValues.wordEffects
    var transition = "mix"  // mix, zoom, flip, slide, push, drop, blur, scale, fade
    var bounce = 0.35
    var blurInactive = true
    var linesShown = 3

    // Lock screen
    var showOnLockScreen = true
    var stageLayout = "stack"  // stack (one word at a time, Verci-style), lines, reel (poster motion graphics), constellation, fisheye, fisheyevisual, column, bigword, extrude, matched (the look that goes with the visual)
    var stageFontSize = 150.0
    var stageIcons = true
    var stageDrift = true
    var stageBackground = "auto"  // auto, motion, mono, cover, disc, duotone, vinyl, kaleido, polaroid, cassette, lake, cinema, retro, the WorldScene kinds, aurora, album, gradient, custom, black
    var audioReactive = true
    var depth = true  // the artist cut out of the artwork stands in front of the clock
    var depthOverLyrics = false  // …and in front of the lyrics too (can hide the word being sung)
    var keywordBursts = true
    var romanize = false  // Hindi, Urdu, etc. shown in English letters
    var titleCard = true  // song title slams in when a new song starts
    var autoSync = true  // correct lyric timing from the audio
    var lyricsBackup = true  // ask NetEase when LRCLIB has nothing
    var youtube = true  // follow YouTube / YouTube Music playing in a browser
    var matchOutput = true  // hold lyrics back by your headphones' delay
    var learnTiming = true  // learn each song's line and word timing from the audio
    var batterySaver = true  // lighter visuals when unplugged
    var backgroundDarkness = 0.55
    var motion = 0.6
    var beatZoom = true
    var rgbSplit = false
    var particles = "none"  // none, bokeh, stars, embers, dust, snow, rain, petals, fireflies, lanterns, comets, bubbles
    var lightLeaks = false
    var lightBeams = false  // stage spotlights sweeping from above
    var vhs = false  // scan lines and a rolling tracking band
    var lyricsBacking = "none"  // none, shade, glass, band, paper, terminal, bubble, sign
    var stackStyle = "effect"  // effect (the chosen word effect), box (highlighter)
    var stageHex = "#14141A"
    var edgeGlow = true
    var edgeStyle = "race"  // race (two streaks circling), rim (a steady light all the way round)
    var edgeColor = "album"  // album, white, custom
    var edgeHex = "#FFFFFF"
    var edgeThickness = 70.0
    var edgeBrightness = 0.85
    var edgeBeat = true  // moves with the music; off holds it still
    var edgeDesktop = false  // also light the screen edge on the desktop while music plays
    var stageFooter = true
    var stageClock = true
    var keepAwake = true

    // Desktop
    var showOnDesktop = false
    var lyricColors = "look"  // look (each style's own), album, custom
    var lyricHex = "#FF5A4F"
    var harmony = "source"  // source, tonal, analogous, complementary, split, triadic
    var secondLayout = "same"  // the lyric layout on other displays, or the same as the main one
    var desktopLayout = "lines"  // the floating desktop lyrics: lines, or any lyric layout
    var syncLyrics = false  // edited lyrics live in iCloud Drive
    var translate = false  // a translated line under lyrics in another language
    var shuffleLooks = false  // each new song picks a favourite look
    var tintVisuals = true  // the generated visuals take on the album's colour
    var liveWallpaper = false  // the whole stage as the desktop wallpaper, on every screen, while music plays
    var fontSize = 34.0
    var width = 760.0
    var background = "none"  // none, blur, glass, dim
    var backgroundOpacity = 0.6
    var showHeader = false
    var clickThrough = true

    // Sync
    var offset = 0.0
}

final class Style: ObservableObject {
    static let shared = Style()

    @Published var v: StyleValues {
        didSet { UserDefaults.standard.set(try? JSONEncoder().encode(v), forKey: "style") }
    }

    /// Saved settings are laid over the defaults, so settings added in a newer build don't wipe the rest.
    private init() {
        if let data = UserDefaults.standard.data(forKey: "style"),
           let saved = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let values = StyleValues.overDefaults(saved) {
            var values = values.withoutRetiredBackground()
            // Edge light became a setting of its own, on by default; presets used to switch it off.
            if !UserDefaults.standard.bool(forKey: "edgeLightOwnSetting") {
                values.edgeGlow = true
                UserDefaults.standard.set(true, forKey: "edgeLightOwnSetting")
            }
            v = values
        } else {
            v = StyleValues()
        }
    }
}

extension StyleValues {
    /// Saved settings laid over the defaults, so settings newer than the save still decode.
    static func overDefaults(_ saved: [String: Any]) -> StyleValues? {
        guard let defaults = try? JSONSerialization.jsonObject(with: JSONEncoder().encode(StyleValues())) as? [String: Any],
              let merged = try? JSONSerialization.data(withJSONObject: defaults.merging(saved) { $1 }) else { return nil }
        return try? JSONDecoder().decode(StyleValues.self, from: merged)
    }

    /// Backgrounds made from the artwork itself (see Wallpaper.swift).
    /// A lyric word as shown: in English letters when romanizing, and in caps when asked.
    func display(_ text: String) -> String {
        let shown = romanize ? Romanizer.latin(text) : text
        return uppercase ? shown.uppercased() : shown
    }

    /// Every word effect, as (tag, label) — shared by Settings and the menu bar.
    static let wordEffects: [(String, String)] = [
        ("comet", "Comet — a comet streaks through the words"),
        ("float", "Float — words drift up and keep bobbing"),
        ("ink", "Ink — words bleed in like ink on paper"),
        ("spin", "Spin — words turn round to face you"),
        ("swing", "Swing — words swing down from above"),
        ("rainbow", "Rainbow — colour flows through the words"),
        ("stamp", "Stamp — words thump down at an angle"),
        ("smoke", "Smoke — words rise away as smoke once sung"),
        ("jelly", "Jelly — words wobble in"),
        ("ripple", "Ripple — a wave runs through the letters"),
        ("neon", "Neon — flickers on and glows"),
        ("glitch", "Glitch — RGB-split jitter"),
        ("slam", "Slam — words hit with a shake"),
        ("scramble", "Scramble — letters decode"),
        ("cascade", "Cascade — letters drop in"),
        ("flip", "Flip — words flip up"),
        ("highlight", "Highlighter — marker swipes behind"),
        ("shine", "Shine — fill, then a sheen"),
        ("reveal", "Reveal — words rise in as sung"),
        ("bounce", "Bounce — words spring in"),
        ("bloom", "Bloom — words flash in and settle"),
        ("typewriter", "Typewriter — letter by letter"),
        ("fill", "Karaoke fill — colour sweeps through"),
        ("wave", "Wave — karaoke fill that floats"),
        ("pop", "Pop — words hop when sung"),
        ("fade", "Fade — words brighten"),
    ]

    /// What Mix rotates through, line by line: smooth ones for verses, hard-hitting ones for the chorus.
    /// Extra time ahead of the word, beyond the usual lead: slow entrances have to start sooner to land with the
    /// voice, and quick hits or colour sweeps later, since they read straight away.
    static func lead(_ style: String) -> Double {
        switch style {
        case "ink": return 0.14
        case "reveal", "float", "cascade", "ripple", "bloom", "flip", "spin": return 0.06
        case "slam", "stamp", "glitch", "jelly", "bounce", "pop", "swing": return -0.06
        case "fill", "wave", "shine", "highlight", "typewriter", "comet", "fade", "rainbow": return -0.1
        default: return 0
        }
    }

    private static let verseMix = ["reveal", "comet", "cascade", "highlight", "flip", "scramble", "shine", "bloom",
                                   "float", "ink", "swing", "ripple"]
    private static let chorusMix = ["slam", "neon", "glitch", "bounce", "stamp", "jelly", "rainbow"]
    private static let transitionMix = ["zoom", "flip", "slide", "push", "drop", "blur"]

    /// The word effect for a given lyric line, resolving Mix.
    func wordStyle(line: Int, chorus: Bool) -> String {
        guard wordStyle == "mix" else { return wordStyle }
        let pool = chorus ? Self.chorusMix : Self.verseMix
        return pool[Int(noise(line, 31) * Double(pool.count))]
    }

    func transition(line: Int) -> String {
        guard transition == "mix" else { return transition }
        return Self.transitionMix[Int(noise(line, 32) * Double(Self.transitionMix.count))]
    }

    /// Lyric layouts drawn by VisualLyricsView (the visual looks and the kinetic styles).
    static let visualLayouts: Set<String> = Set(["column", "bigword", "extrude", "tape", "matched"]).union(KineticStyles.tags)

    /// Every lyric layout, as (tag, label), for Settings and the menu bar.
    static let layouts: [(String, String)] = [
        ("stack", "Word stack"), ("lines", "Lines"), ("reel", "Reel — poster motion graphics"),
        ("constellation", "Constellation — words joined like stars"), ("fisheye", "Fisheye — a word stack under a glass lens"),
        ("fisheyevisual", "Fisheye Visual — the lens, with icons"), ("matched", "Matched — the look that goes with each visual"),
        ("column", "Column — the line in a column, sung word boxed"), ("bigword", "Big Word — one huge word, streaking in"),
        ("extrude", "Extruded — 3D letters, centred"), ("tape", "Tape — the word on a strip of tape"),
    ] + KineticStyles.kinds.map { ($0.tag, $0.name) }

    static let wallpapers: Set<String> = ["auto", "motion", "mono", "cover", "disc", "duotone", "vinyl", "kaleido",
                                          "polaroid", "cassette", "lake", "cinema", "retro",
                                          "gallery", "billboard", "crt", "galaxy", "ocean", "mountains", "highway", "neonwall", "aquarium", "forest", "coderain", "newspaper",
                                          "nebula", "voxel", "vortex", "chrome", "dotsphere", "hill", "smear", "sunset", "visualmix",
                                          "contours", "molten", "terraces", "silk", "ink", "tunnel", "wiresea", "city", "ringed", "shoal", "warp",
                                          "paperbird", "freefall", "lighthall", "tvwall", "lattice", "northern", "dunes", "lagoon", "canyon", "helix", "clockwork", "glassswirl", "gravitywell", "woodgrain"]

    /// Backgrounds that no longer exist, for settings and saved presets from older builds.
    func withoutRetiredBackground() -> StyleValues {
        var v = self
        if ["beatmix", "pixels", "pillars", "tunnel", "slices", "photos"].contains(v.stageBackground) {
            v.stageBackground = "motion"
        }
        return v
    }

    static func weight(_ name: String) -> Font.Weight {
        switch name {
        case "light": return .light
        case "regular": return .regular
        case "medium": return .medium
        case "semibold": return .semibold
        case "heavy": return .heavy
        case "black": return .black
        default: return .bold
        }
    }

    static func font(family: String, size: Double, weight: Font.Weight, italic: Bool) -> Font {
        let font: Font
        switch family {
        case "System": font = .system(size: size, weight: weight)
        case "System Rounded": font = .system(size: size, weight: weight, design: .rounded)
        case "System Serif": font = .system(size: size, weight: weight, design: .serif)
        case "System Mono": font = .system(size: size, weight: weight, design: .monospaced)
        case "System Expanded": font = .system(size: size, weight: weight).width(.expanded)
        case "System Condensed": font = .system(size: size, weight: weight).width(.condensed)
        case "System Compressed": font = .system(size: size, weight: weight).width(.compressed)
        default: font = .custom(family, size: size).weight(weight)
        }
        return italic ? font.italic() : font
    }

    func font(size: Double) -> Font {
        Self.font(family: fontFamily, size: size, weight: Self.weight(fontWeight), italic: italic)
    }

    var horizontal: HorizontalAlignment {
        alignment == "leading" ? .leading : alignment == "trailing" ? .trailing : .center
    }

    var frameAlignment: Alignment {
        alignment == "leading" ? .leading : alignment == "trailing" ? .trailing : .center
    }

    var anchor: UnitPoint {
        alignment == "leading" ? .leading : alignment == "trailing" ? .trailing : .center
    }

    /// On a full-screen album-coloured background the album gradient would vanish, so use white there.
    func usesWhite(onStage: Bool) -> Bool {
        colorMode == "white"
            || (onStage && colorMode == "album"
                && (["aurora", "album", "gradient"].contains(stageBackground) || Self.wallpapers.contains(stageBackground)))
    }

    func highlight(_ palette: [NSColor], onStage: Bool) -> AnyShapeStyle {
        if usesWhite(onStage: onStage) { return AnyShapeStyle(Color.white) }
        if colorMode == "custom" { return AnyShapeStyle(Color(hex: customHex)) }
        let colors = palette.map { Color(nsColor: $0.blended(withFraction: 0.2, of: .white) ?? $0) }
        return AnyShapeStyle(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing))
    }

    /// The two colours of the edge light.
    func edgeColors(_ palette: [NSColor]) -> (Color, Color) {
        switch edgeColor {
        case "white": return (.white, .white)
        case "custom": return (Color(hex: edgeHex), Color(hex: edgeHex))
        default: return (Color(nsColor: palette[0]), Color(nsColor: palette[1 % palette.count]))
        }
    }

    func glowColor(_ palette: [NSColor], onStage: Bool) -> Color {
        if usesWhite(onStage: onStage) { return .white }
        if colorMode == "custom" { return Color(hex: customHex) }
        return Color(nsColor: palette[0])
    }
}

extension Color {
    init(hex: String) {
        let value = UInt64(hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) ?? 0xFFFFFF
        self.init(red: Double((value >> 16) & 0xFF) / 255,
                  green: Double((value >> 8) & 0xFF) / 255,
                  blue: Double(value & 0xFF) / 255)
    }

    var hex: String {
        let c = NSColor(self).usingColorSpace(.sRGB) ?? .white
        return String(format: "#%02X%02X%02X", Int(c.redComponent * 255), Int(c.greenComponent * 255),
                      Int(c.blueComponent * 255))
    }
}

/// True inside the full-screen lock-screen view, so shared views can size and colour themselves for it.
private struct StageKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var isStage: Bool {
        get { self[StageKey.self] }
        set { self[StageKey.self] = newValue }
    }
}

/// Turns Indian-script lyrics ("पारो") into plain English letters ("paro"). Cached, since words are redrawn every
/// frame. Urdu and Arabic are left alone: they don't write most vowels, so the result is unreadable ("tm hw").
enum Romanizer {
    private static var cache: [String: String] = [:]

    static func latin(_ text: String) -> String {
        guard text.unicodeScalars.contains(where: { (0x0900...0x0DFF).contains($0.value) }) else { return text }
        if let hit = cache[text] { return hit }
        let latin = text.split(separator: " ", omittingEmptySubsequences: false).map(word).joined(separator: " ")
        cache[text] = latin
        return latin
    }

    /// Any Indian script in the letters people actually type: macOS's converter writes the academic system,
    /// where "c" is "ch" and "ś"/"ṣ" are "sh" ("premapicci" → "premapichchi", "raksasive" → "rakshasive").
    static func casual(_ text: String) -> String {
        guard var latin = text.applyingTransform(.toLatin, reverse: false) else { return text }
        latin = latin.replacingOccurrences(of: "ch", with: "chh")  // aspirated c, before plain c becomes "ch"
            .replacingOccurrences(of: "c", with: "ch")
            .replacingOccurrences(of: "ś", with: "sh")
            .replacingOccurrences(of: "ṣ", with: "sh")
            .replacingOccurrences(of: "r̥", with: "ru")
            .replacingOccurrences(of: "m̐", with: "n")  // chandrabindu: चाँद is "chand"
        return latin.applyingTransform(.stripDiacritics, reverse: false) ?? latin
    }

    /// Hindi drops the vowel a consonant would carry at the end of a word — दिल is "dil", not "dila".
    private static func word(_ token: Substring) -> String {
        var latin = casual(String(token))
        let letters = token.unicodeScalars.filter { !CharacterSet.punctuationCharacters.contains($0) }
        let nukta: UInt32 = 0x093C
        let last = letters.last { $0.value != nukta }?.value ?? 0
        let endsInConsonant = (0x0915...0x0939).contains(last) || (0x0958...0x095F).contains(last)
        if endsInConsonant, let a = latin.lastIndex(of: "a"), latin[latin.index(after: a)...].allSatisfy({ !$0.isLetter }) {
            latin.remove(at: a)
        }
        return latin
    }
}

// MARK: - Fonts

enum Fonts {
    static let system = ["System", "System Rounded", "System Serif", "System Mono",
                         "System Expanded", "System Condensed", "System Compressed"]

    /// Fonts shipped inside Cadence.app/Contents/Resources/Fonts, registered for this process.
    static let bundled: [String] = {
        guard let dir = Bundle.main.resourceURL?.appendingPathComponent("Fonts"),
              let urls = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
        else { return [] }
        var families = Set<String>()
        for url in urls where ["ttf", "otf"].contains(url.pathExtension.lowercased()) {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor] ?? []
            for d in descriptors {
                if let family = CTFontDescriptorCopyAttribute(d, kCTFontFamilyNameAttribute) as? String {
                    families.insert(family)
                }
            }
        }
        return families.sorted()
    }()

    /// Stylish fonts that ship with macOS.
    static let stylishSystem: [String] = {
        let installed = Set(NSFontManager.shared.availableFontFamilies)
        return ["Avenir Next", "Futura", "Helvetica Neue", "Didot", "Bodoni 72", "Baskerville", "Hoefler Text",
                "Gill Sans", "Optima", "Rockwell", "Copperplate", "American Typewriter", "Marker Felt",
                "Noteworthy", "Chalkduster", "Bradley Hand", "Snell Roundhand", "SignPainter", "Zapfino",
                "Phosphate", "Impact", "Trattatello", "Luminari"].filter(installed.contains)
    }()

    static var featured: [String] { system + bundled + stylishSystem }

    static var all: [String] { NSFontManager.shared.availableFontFamilies.sorted() }
}
