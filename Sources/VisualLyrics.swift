import AppKit
import SwiftUI

// MARK: - Lyric looks for the visuals

/// Which screen a stage view is on (0 is the main one), and whether it's the live desktop wallpaper rather than
/// the lock screen.
private struct StageScreenKey: EnvironmentKey { static let defaultValue = 0 }
private struct WallpaperKey: EnvironmentKey { static let defaultValue = false }
private struct LyricLayoutKey: EnvironmentKey { static let defaultValue: String? = nil }
private struct LyricBaseKey: EnvironmentKey { static let defaultValue: Double? = nil }

extension EnvironmentValues {
    var stageScreen: Int {
        get { self[StageScreenKey.self] }
        set { self[StageScreenKey.self] = newValue }
    }

    var isWallpaper: Bool {
        get { self[WallpaperKey.self] }
        set { self[WallpaperKey.self] = newValue }
    }

    /// A lyric layout to use instead of the lock screen's (a second display, the floating desktop lyrics).
    var lyricLayout: String? {
        get { self[LyricLayoutKey.self] }
        set { self[LyricLayoutKey.self] = newValue }
    }

    /// The lyrics size to use instead of the lock screen's.
    var lyricBase: Double? {
        get { self[LyricBaseKey.self] }
        set { self[LyricBaseKey.self] = newValue }
    }
}

/// How the column, big word and extruded layouts draw: type, colours and where on screen.
struct VisualLook {
    var layout = "column"  // column, bigword, extrude, tape
    var family = "Poppins"
    var weight = "bold"
    var italic = false
    var main = Color.white  // the word being sung
    var other = Color.white.opacity(0.9)  // the rest of the line
    var box: Color?  // a box behind the word being sung
    var boxText = Color.white
    var glow: Color?
    var extrude: Color?  // 3D letters, in this colour
    var tape = hexColor(0xFFA463, 0.85)  // the strip behind the word in the tape layout
    var mainScale = 0.6  // × the lyrics size
    var otherScale = 0.3
    var upcoming = 0.45  // opacity of words not sung yet; 0 builds the line word by word
    var x = 0.2  // the column's left edge, or the big word's centre, across the screen
    var centered = false
    var showNext = true

    func font(_ size: Double) -> Font {
        StyleValues.font(family: family, size: size, weight: StyleValues.weight(weight), italic: italic)
    }

    /// The look each visual comes with, as in the edits it's modelled on.
    static let matched: [String: VisualLook] = [
        "nebula": VisualLook(main: .white, other: .white.opacity(0.92), box: hexColor(0x9C88F4, 0.92), x: 0.24),
        "voxel": VisualLook(weight: "medium", main: hexColor(0xF2879A, 0.95), other: hexColor(0xF2879A, 0.78),
                            mainScale: 0.5, otherScale: 0.3, upcoming: 0.55, x: 0.2),
        "vortex": VisualLook(main: .white, other: .white.opacity(0.85), mainScale: 0.36, otherScale: 0.26,
                             upcoming: 0.6, x: 0.17),
        "chrome": VisualLook(layout: "bigword", main: hexColor(0xE6ECFF), glow: hexColor(0x5B7CFF),
                             mainScale: 1.0, x: 0.34, showNext: false),
        "dotsphere": VisualLook(family: "Futura", main: hexColor(0xFF4B1F), other: hexColor(0xEBC23B),
                                mainScale: 0.5, otherScale: 0.34, upcoming: 0, x: 0.2),
        "hill": VisualLook(main: .white, other: .white.opacity(0.92), box: Color.white.opacity(0.94),
                           boxText: hexColor(0x101418), mainScale: 0.62, otherScale: 0.34, upcoming: 1, x: 0.17),
        "smear": VisualLook(layout: "bigword", family: "Futura", weight: "medium", main: hexColor(0xFF3D1F),
                            other: hexColor(0xFF3D1F, 0.85), mainScale: 1.25, otherScale: 0.3, x: 0.5),
        "sunset": VisualLook(layout: "extrude", weight: "black", main: .white, other: .white,
                             extrude: hexColor(0x8E2A66), mainScale: 0.62, otherScale: 0.38, upcoming: 0.5,
                             centered: true),
        "contours": VisualLook(layout: "tape", weight: "black", main: hexColor(0xF0380F), other: hexColor(0xF2C14E),
                               mainScale: 0.75, otherScale: 0.3, x: 0.5),
        "molten": VisualLook(main: hexColor(0xFFE2A8), other: .white.opacity(0.9), box: hexColor(0x1A0500, 0.9),
                             boxText: hexColor(0xFFC94A), x: 0.2),
        "terraces": VisualLook(main: .white, other: .white.opacity(0.92), box: hexColor(0x061A3D, 0.92), x: 0.2),
        "silk": VisualLook(layout: "tape", weight: "black", main: hexColor(0xE8340C), other: hexColor(0xE0A93A),
                           tape: hexColor(0xFFB98A, 0.8), mainScale: 0.75, otherScale: 0.3, x: 0.5),
        "ink": VisualLook(layout: "bigword", family: "Futura", weight: "medium", main: hexColor(0xE0302A),
                          other: hexColor(0x0B0D14, 0.8), mainScale: 1.1, otherScale: 0.3, x: 0.5),
        "tunnel": VisualLook(layout: "bigword", main: .white, glow: hexColor(0x3BE8FF), mainScale: 1.0, x: 0.5,
                             showNext: false),
        "wiresea": VisualLook(main: hexColor(0x5FF3FF), other: .white.opacity(0.85), glow: hexColor(0x1B7CFF),
                              mainScale: 0.55, otherScale: 0.3, x: 0.2),
        "city": VisualLook(main: .white, other: .white.opacity(0.9), box: hexColor(0xFFD27A, 0.95),
                           boxText: hexColor(0x141A33), x: 0.2),
        "ringed": VisualLook(main: hexColor(0xFFD9A0), other: .white.opacity(0.85), glow: hexColor(0xFFB070),
                             mainScale: 0.55, otherScale: 0.3, x: 0.16),
        "shoal": VisualLook(main: .white, other: .white.opacity(0.92), box: Color.white.opacity(0.94),
                            boxText: hexColor(0x063353), x: 0.18),
        "warp": VisualLook(layout: "bigword", main: .white, glow: hexColor(0x7FB4FF), mainScale: 1.1, x: 0.5,
                           showNext: false),
        "paperbird": VisualLook(main: .white, other: .white.opacity(0.9), box: hexColor(0x211C3A, 0.85), x: 0.62),
        "freefall": VisualLook(layout: "bigword", main: hexColor(0xFFD27A), glow: hexColor(0xFF9A3C), mainScale: 1.0,
                               x: 0.5, showNext: false),
        "lighthall": VisualLook(layout: "bigword", main: hexColor(0xFFE2B0), glow: hexColor(0xFFB45A), mainScale: 1.0,
                                x: 0.5, showNext: false),
        "tvwall": VisualLook(layout: "tape", weight: "black", main: hexColor(0x101010), other: .white,
                             tape: hexColor(0xFFE14A, 0.95), mainScale: 0.75, otherScale: 0.3, x: 0.5),
        "lattice": VisualLook(main: hexColor(0x9CF5FF), other: .white.opacity(0.85), glow: hexColor(0xFF3BD0),
                              mainScale: 0.55, otherScale: 0.3, x: 0.2),
        "northern": VisualLook(main: .white, other: .white.opacity(0.88), glow: hexColor(0x3DFFB0), mainScale: 0.55,
                               otherScale: 0.3, x: 0.2),
        "dunes": VisualLook(layout: "extrude", weight: "black", main: .white, other: .white,
                            extrude: hexColor(0xB0306A), mainScale: 0.6, otherScale: 0.36, upcoming: 0.5, centered: true),
        "lagoon": VisualLook(main: hexColor(0xB8FFF2), other: .white.opacity(0.85), glow: hexColor(0x3BFFE0),
                             mainScale: 0.55, otherScale: 0.3, x: 0.2),
        "canyon": VisualLook(main: .white, other: .white.opacity(0.92), box: hexColor(0x5A2614, 0.9), x: 0.2),
        "helix": VisualLook(layout: "bigword", main: .white, glow: hexColor(0xC04FFF), mainScale: 0.9, x: 0.28,
                            showNext: false),
        "clockwork": VisualLook(layout: "tape", weight: "black", main: hexColor(0xD8402A), other: hexColor(0x2E2A26),
                                tape: hexColor(0xF2D7A8, 0.9), mainScale: 0.7, otherScale: 0.3, x: 0.5),
        "glassswirl": VisualLook(main: .white, other: .white.opacity(0.9), box: hexColor(0x1A2A5A, 0.85), x: 0.2),
        "gravitywell": VisualLook(layout: "bigword", main: .white, glow: hexColor(0x6AA8FF), mainScale: 1.0, x: 0.5,
                                  showNext: false),
        "woodgrain": VisualLook(layout: "tape", weight: "black", main: hexColor(0xFFF3DE), other: hexColor(0xFFF3DE, 0.85),
                                tape: hexColor(0x2A170A, 0.85), mainScale: 0.75, otherScale: 0.3, x: 0.5),
    ]

    /// The look for this screen right now: matched to the visual on it, or built from the user's own settings.
    static func resolve(_ s: StyleValues, layout: String, time: Double, date: Date, screen: Int,
                        palette: [NSColor]) -> VisualLook {
        var look: VisualLook
        if layout == "matched" {
            if let scene = Visuals.scene(s.stageBackground, time: time, date: date, screen: screen), let made = matched[scene.tag] {
                look = made
            } else {
                look = VisualLook.from(s, layout: "column", palette: palette)
            }
        } else {
            look = VisualLook.from(s, layout: layout, palette: palette)
        }
        look.harmonize(s, palette)
        if s.myFont {
            look.family = s.fontFamily
            look.weight = s.fontWeight
            look.italic = s.italic
        }
        return look
    }

    /// Recolours the look from the album art or your own colour, in the chosen harmony, unless the colours are
    /// left to the look itself.
    mutating func harmonize(_ s: StyleValues, _ palette: [NSColor]) {
        guard s.lyricColors != "look" else { return }
        let source = s.lyricColors == "custom" ? NSColor(Color(hex: s.lyricHex)) : palette[0]
        let set = Harmony.colors(source, s.harmony)
        main = set.highlight
        other = set.text
        glow = set.highlight.opacity(0.6)
        if box != nil {
            box = set.highlight
            boxText = set.ink
            main = set.ink
        }
        tape = set.highlight.opacity(0.85)
        if extrude != nil { extrude = set.support }
    }

    static func from(_ s: StyleValues, layout: String, palette: [NSColor]) -> VisualLook {
        var look = VisualLook(layout: layout, family: s.fontFamily, weight: s.fontWeight, italic: s.italic)
        let accent: Color
        switch s.colorMode {
        case "white": accent = .white
        case "custom": accent = Color(hex: s.customHex)
        default:
            let c = palette[0].usingColorSpace(.deviceRGB) ?? palette[0]
            accent = Color(nsColor: NSColor(hue: c.hueComponent, saturation: max(c.saturationComponent, 0.7),
                                            brightness: 0.85, alpha: 1))
        }
        look.other = .white.opacity(0.88)
        if s.stackStyle == "box" && layout == "column" {
            look.main = .white
            look.box = accent
            look.boxText = s.colorMode == "white" ? .black : .white
        } else {
            look.main = s.colorMode == "white" ? .white : accent
        }
        if s.glow > 0.05 { look.glow = s.glowColor(palette, onStage: true).opacity(s.glow) }
        switch layout {
        case "bigword":
            look.mainScale = 1.1
            look.x = s.alignment == "leading" ? 0.32 : s.alignment == "trailing" ? 0.68 : 0.5
        case "tape":
            look.main = s.colorMode == "white" ? .white : accent
            look.other = s.colorMode == "white" ? .white.opacity(0.8) : accent.opacity(0.7)
            look.tape = s.colorMode == "white" ? .black.opacity(0.6) : accent.opacity(0.35)
            look.mainScale = 0.75
            look.x = 0.5
        case "extrude":
            look.main = .white
            look.extrude = s.colorMode == "white" ? Color(white: 0.35) : accent.opacity(0.9)
            look.centered = true
            look.mainScale = 0.62
            look.otherScale = 0.38
        default:
            look.centered = s.alignment == "center"
            look.x = s.alignment == "trailing" ? 0.55 : 0.2
        }
        return look
    }
}

private func clamp01(_ x: Double) -> Double { min(max(x, 0), 1) }

/// Picks the layout for the look on this screen.
struct VisualLyricsView: View {
    let time: Double
    let date: Date
    @Environment(\.stageScreen) private var screen
    @Environment(\.lyricLayout) private var layoutOverride
    @Environment(\.lyricBase) private var baseOverride
    @ObservedObject private var style = Style.shared
    @ObservedObject private var player = NowPlaying.shared

    var body: some View {
        let s = style.v
        let layout = layoutOverride ?? s.stageLayout
        let look = VisualLook.resolve(s, layout: layout, time: time, date: date, screen: screen, palette: player.palette)
        let kick = s.beatZoom ? min(player.kick(at: time, date: date), 1.2) : 0
        let base = baseOverride ?? s.stageFontSize
        Group {
            if look.layout == "bigword" {
                BigWordView(time: time, look: look, kick: kick, base: base)
            } else if look.layout == "tape" {
                TapeWordView(time: time, look: look, kick: kick, base: base)
            } else if KineticStyles.tags.contains(look.layout) {
                KineticLyricsView(style: look.layout, time: time, look: look, kick: kick, base: base)
            } else {
                ColumnLyricsView(time: time, look: look, kick: kick, base: base)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// The word being sung and where its line starts and ends, or nil in a long instrumental gap.
func currentLine(_ player: NowPlaying, _ time: Double) -> (index: Int, line: Range<Int>)? {
    let words = player.words, lines = player.wordLines
    guard let index = words.lastIndex(where: { $0.start <= time }), lines.count == words.count else { return nil }
    let untilNext = index + 1 < words.count ? words[index + 1].start - time : .infinity
    if time - words[index].end > 3 && untilNext > 1.5 { return nil }
    var first = index
    while first > 0 && lines[first - 1] == lines[index] { first -= 1 }
    var end = index + 1
    while end < words.count && lines[end] == lines[index] { end += 1 }
    return (index, first..<end)
}

// MARK: Column

/// The line being sung, one word per row: sung words full, the current word large (boxed in some looks), the
/// rest of the line waiting dimmer below. Rows slide up as the line moves on.
struct ColumnLyricsView: View {
    let time: Double
    let look: VisualLook
    let kick: Double
    var base = Style.shared.v.stageFontSize
    @ObservedObject private var style = Style.shared
    @ObservedObject private var player = NowPlaying.shared

    private static let maxRows = 7

    var body: some View {
        let s = style.v
        let size = base
        let current = currentLine(player, time)
        let index = current?.index ?? -1
        GeometryReader { geo in
            VStack(alignment: look.centered ? .center : .leading, spacing: size * 0.02) {
                if let current {
                    let line = current.line
                    let from = max(line.lowerBound, min(current.index - 3, line.upperBound - Self.maxRows))
                    let to = min(line.upperBound, from + Self.maxRows)
                    ForEach(from..<to, id: \.self) { i in
                        row(i, index: current.index, s: s, size: size)
                            .transition(.asymmetric(
                                insertion: .modifier(active: Zoom(scale: 0.9, blur: 10, opacity: 0), identity: .identity)
                                    .combined(with: .offset(y: size * 0.3)),
                                removal: .modifier(active: Zoom(scale: 0.95, blur: 14, opacity: 0), identity: .identity)
                                    .combined(with: .offset(y: -size * 0.35))))
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: look.centered ? .center : .leading)
            .padding(.leading, look.centered ? 0 : max(0, geo.size.width * look.x - 90))
        }
        .drawingGroup()
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: index)
    }

    @ViewBuilder
    private func row(_ i: Int, index: Int, s: StyleValues, size: Double) -> some View {
        let word = player.words[i]
        let isCurrent = i == index
        let full = size * look.mainScale
        // Every row is set at the large size and scaled down, so a word growing into the current one animates.
        let k = isCurrent ? 1 + 0.05 * kick : look.otherScale / look.mainScale
        let text = Text(s.display(word.text)).font(look.font(full)).tracking(s.tracking)
        let anchor: UnitPoint = look.centered ? .center : .leading
        letters(text, isCurrent: isCurrent, size: full, wipe: clamp01((time - word.start) / 0.14))
            .fixedSize()
            .opacity(i <= index ? 1 : look.upcoming)
            .scaleEffect(k, anchor: anchor)
            .frame(height: full * 1.25 * k, alignment: look.centered ? .center : .leading)
            .offset(x: look.centered ? 0 : (noise(i, 71) - 0.3) * size * 0.16 * k)
    }

    @ViewBuilder
    private func letters(_ text: Text, isCurrent: Bool, size: Double, wipe: Double) -> some View {
        let color = isCurrent ? look.main : look.other
        if isCurrent, let box = look.box {
            text.foregroundStyle(look.boxText)
                .padding(.horizontal, size * 0.13)
                .padding(.vertical, size * 0.02)
                .background(alignment: .leading) {
                    RoundedRectangle(cornerRadius: size * 0.07, style: .continuous)
                        .fill(box)
                        .scaleEffect(x: wipe, anchor: .leading)
                }
                .shadow(color: (look.glow ?? box).opacity(0.5), radius: size * 0.2)
        } else if let depth = look.extrude {
            ZStack {
                ForEach(1..<9, id: \.self) { j in
                    text.foregroundStyle(depth.opacity(1 - Double(j) * 0.06))
                        .offset(x: Double(j) * size * 0.007, y: Double(j) * size * 0.012)
                }
                text.foregroundStyle(color)
            }
            .padding(.horizontal, size * 0.13)
            .shadow(color: .black.opacity(0.3), radius: size * 0.15, y: size * 0.06)
        } else {
            text.foregroundStyle(color)
                .padding(.horizontal, size * 0.13)
                .shadow(color: isCurrent ? (look.glow ?? .clear) : .clear, radius: size * 0.25)
                .shadow(color: .black.opacity(0.25), radius: size * 0.06, y: size * 0.02)
        }
    }
}

// MARK: Big word

/// One huge word at a time. It streaks in sideways out of a motion blur, the last one breaks up into pixels as it
/// goes, and the next word waits small underneath.
struct BigWordView: View {
    let time: Double
    let look: VisualLook
    let kick: Double
    var base = Style.shared.v.stageFontSize
    @ObservedObject private var style = Style.shared
    @ObservedObject private var player = NowPlaying.shared

    var body: some View {
        let s = style.v
        let words = player.words
        let size = base * look.mainScale
        GeometryReader { geo in
            if let current = currentLine(player, time) {
                let i = current.index
                let word = words[i]
                let age = time - word.start
                let p = clamp01(age / 0.18)
                let e = 1 - pow(1 - p, 3)
                let maxWidth = geo.size.width * (look.x == 0.5 ? 0.86 : 0.5)
                ZStack {
                    if i > 0, age < 0.24 {
                        PixelWord(text: s.display(words[i - 1].text), look: look, size: size, progress: age / 0.24,
                                  maxWidth: maxWidth)
                    }
                    VStack(spacing: base * 0.04) {
                        Text(s.display(word.text))
                            .font(look.font(size))
                            .tracking(s.tracking)
                            .foregroundStyle(look.main)
                            .lineLimit(1)
                            .minimumScaleFactor(0.25)
                            .frame(maxWidth: maxWidth)
                            .shadow(color: look.glow ?? .clear, radius: size * 0.18)
                            .shadow(color: .black.opacity(0.25), radius: size * 0.05, y: size * 0.02)
                            .scaleEffect(x: 1 + (1 - e) * 1.3, y: 1 - (1 - e) * 0.15)
                            .blur(radius: (1 - e) * 22)
                            .offset(x: (1 - e) * size * 0.7)
                            .opacity(0.25 + 0.75 * e)
                            .scaleEffect(1 + 0.05 * kick)
                        if look.showNext, i + 1 < current.line.upperBound {
                            Text(s.display(words[i + 1].text))
                                .font(look.font(base * look.otherScale))
                                .foregroundStyle(look.other)
                                .lineLimit(1)
                                .opacity(0.85)
                        }
                    }
                }
                .position(x: geo.size.width * look.x, y: geo.size.height * 0.5)
            }
        }
    }
}

/// A word drawn at a fraction of its resolution and blown up without smoothing, coarser as `progress` goes 0…1.
private struct PixelWord: View {
    let text: String
    let look: VisualLook
    let size: Double
    let progress: Double
    let maxWidth: Double

    var body: some View {
        let block = [3.0, 6, 11, 18, 28][min(4, Int(progress * 5))]
        if let image = Pixelator.image(text, look: look, size: size, block: block) {
            Image(nsImage: image)
                .interpolation(.none)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: min(image.size.width, maxWidth))
                .opacity(1 - progress)
        }
    }
}

@MainActor
enum Pixelator {
    private static var cache: [String: NSImage] = [:]

    static func image(_ text: String, look: VisualLook, size: Double, block: Double) -> NSImage? {
        let key = "\(text)|\(look.family)|\(look.weight)|\(Int(size))|\(block)|\(look.main.description)"
        if let hit = cache[key] { return hit }
        let renderer = ImageRenderer(content: Text(text).font(look.font(size)).foregroundStyle(look.main)
            .lineLimit(1).fixedSize().padding(size * 0.05))
        renderer.scale = 1 / block
        guard let image = renderer.nsImage else { return nil }
        if cache.count > 150 { cache.removeAll() }
        cache[key] = image
        return image
    }
}

// MARK: Tape

/// The word being sung slapped onto a tilted strip of tape, with the words before it in the line riding small
/// and tilted above, and a couple of flick marks off the corner on each new word.
struct TapeWordView: View {
    let time: Double
    let look: VisualLook
    let kick: Double
    var base = Style.shared.v.stageFontSize
    @ObservedObject private var style = Style.shared
    @ObservedObject private var player = NowPlaying.shared

    var body: some View {
        let s = style.v
        let words = player.words
        GeometryReader { geo in
            if let current = currentLine(player, time) {
                let i = current.index
                let word = words[i]
                let age = time - word.start
                let size = base * look.mainScale
                let tilt = (noise(i, 81) - 0.5) * 10
                let stick = clamp01(age / 0.16)
                let pop = 1 + 0.25 * (1 - stick) * (1 - stick) + 0.04 * kick
                let before = (max(current.line.lowerBound, i - 3)..<i).map { s.display(words[$0].text) }.joined(separator: " ")
                VStack(spacing: size * 0.08) {
                    if !before.isEmpty {
                        Text(before)
                            .font(look.font(base * look.otherScale))
                            .foregroundStyle(look.other)
                            .lineLimit(1)
                            .minimumScaleFactor(0.4)
                            .rotationEffect(.degrees(-tilt * 0.6))
                            .offset(x: -size * 0.3)
                    }
                    Text(s.display(word.text))
                        .font(look.font(size))
                        .tracking(s.tracking)
                        .foregroundStyle(look.main)
                        .lineLimit(1)
                        .minimumScaleFactor(0.3)
                        .shadow(color: .black.opacity(0.2), radius: size * 0.04, y: size * 0.03)
                        .padding(.horizontal, size * 0.35)
                        .padding(.vertical, size * 0.06)
                        .background {
                            RoundedRectangle(cornerRadius: size * 0.06)
                                .fill(look.tape)
                                .scaleEffect(x: stick, anchor: .leading)
                                .shadow(color: .black.opacity(0.18), radius: size * 0.08, y: size * 0.06)
                        }
                        .overlay(alignment: .topTrailing) {
                            // Flick marks off the corner, just as the word lands.
                            HStack(spacing: size * 0.08) {
                                Capsule().frame(width: size * 0.04, height: size * 0.2).rotationEffect(.degrees(30))
                                Capsule().frame(width: size * 0.04, height: size * 0.16).rotationEffect(.degrees(40))
                            }
                            .foregroundStyle(look.tape)
                            .opacity(max(0, 1 - age / 0.5))
                            .offset(x: size * 0.2, y: -size * 0.25)
                        }
                        .frame(maxWidth: geo.size.width * 0.8)
                        .rotationEffect(.degrees(tilt))
                        .scaleEffect(pop)
                }
                .position(x: geo.size.width * look.x, y: geo.size.height * 0.5)
            }
        }
    }
}
