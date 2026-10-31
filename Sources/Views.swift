import AppKit
import SwiftUI

// MARK: - Easing

private func clamp(_ x: Double) -> Double { min(max(x, 0), 1) }

private func easeOutCubic(_ x: Double) -> Double { 1 - pow(1 - x, 3) }

/// Overshoots slightly then settles — the springy "pop" used in reels-style lyrics.
private func easeOutBack(_ x: Double) -> Double {
    let c1 = 1.70158, c3 = c1 + 1
    return 1 + c3 * pow(x - 1, 3) + c1 * pow(x - 1, 2)
}

// MARK: - Layout

/// Wraps words onto rows like text, so each word can animate independently.
struct FlowLayout: Layout {
    var alignment: String
    var spacing: CGFloat
    var lineSpacing: CGFloat

    private typealias Row = (indices: [Int], width: CGFloat, height: CGFloat)

    private func rows(_ maxWidth: CGFloat, _ subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var current: [Int] = []
        var width: CGFloat = 0, height: CGFloat = 0
        for (i, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(.unspecified)
            let needed = current.isEmpty ? size.width : width + spacing + size.width
            if needed > maxWidth && !current.isEmpty {
                rows.append((current, width, height))
                current = [i]; width = size.width; height = size.height
            } else {
                current.append(i); width = needed; height = max(height, size.height)
            }
        }
        if !current.isEmpty { rows.append((current, width, height)) }
        return rows
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        let r = rows(maxWidth, subviews)
        let height = r.reduce(0) { $0 + $1.height } + lineSpacing * CGFloat(max(r.count - 1, 0))
        let width = maxWidth.isFinite ? maxWidth : (r.map(\.width).max() ?? 0)
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(bounds.width, subviews) {
            var x: CGFloat
            switch alignment {
            case "leading": x = bounds.minX
            case "trailing": x = bounds.maxX - row.width
            default: x = bounds.minX + (bounds.width - row.width) / 2
            }
            for i in row.indices {
                let size = subviews[i].sizeThatFits(.unspecified)
                subviews[i].place(at: CGPoint(x: x, y: y + (row.height - size.height) / 2),
                                  proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + lineSpacing
        }
    }
}

// MARK: - Words and lines

struct WordView: View {
    let word: Word
    let index: Int
    let time: Double
    let active: Bool  // belongs to the line being sung
    var size: Double? = nil  // the word stack sizes each word itself
    var connects = true  // a following word sits to the right, so the comet trail runs on into the gap
    var line = 0  // lyric line the word belongs to, so Mix can pick an effect per line
    @Environment(\.isStage) private var isStage
    @ObservedObject private var style = Style.shared
    @ObservedObject private var player = NowPlaying.shared

    var body: some View {
        let s = style.v
        let size = self.size ?? (isStage ? s.stageFontSize * 0.5 : s.fontSize)
        let string = s.display(word.text)
        let base = Text(string).font(s.font(size: size)).tracking(s.tracking)
        let dim = AnyShapeStyle(Color.white.opacity(s.unsungOpacity))
        if !active {
            base.foregroundStyle(dim)
        } else {
            effect(base, string, s, size, dim)
        }
    }

    @ViewBuilder
    private func effect(_ base: Text, _ string: String, _ s: StyleValues, _ size: Double,
                        _ dim: AnyShapeStyle) -> some View {
        let progress = word.progress(at: time)
        let appear = clamp((time - word.start) / 0.35)  // fixed-length entrance, independent of word length
        let lit = s.highlight(player.palette, onStage: isStage)
        let glow = s.glowColor(player.palette, onStage: isStage)
        let radius = size * 0.3 * s.glow

        switch s.wordStyle(line: line, chorus: player.repeated.contains(line)) {
        case "reveal":
            // Unsung words are invisible; each one rises and un-blurs into place.
            let e = easeOutCubic(appear)
            base.foregroundStyle(lit)
                .opacity(appear)
                .offset(y: (1 - e) * size * 0.45)
                .blur(radius: (1 - appear) * 8)
                .shadow(color: glow.opacity(s.glow * appear), radius: radius)

        case "bounce":
            base.foregroundStyle(lit)
                .scaleEffect(appear > 0 ? 0.4 + 0.6 * easeOutBack(appear) : 0.4)
                .opacity(clamp(appear * 3))
                .shadow(color: glow.opacity(s.glow * appear), radius: radius)

        case "typewriter":
            // Full word reserves the space; letters appear one by one over the word's duration.
            let shown = Int((progress * Double(string.count)).rounded(.up))
            base.foregroundStyle(Color.clear)
                .overlay(alignment: .leading) {
                    Text(String(string.prefix(shown))).font(s.font(size: size)).tracking(s.tracking)
                        .foregroundStyle(lit)
                        .fixedSize()
                }
                .shadow(color: glow.opacity(progress > 0 ? s.glow : 0), radius: radius)

        case "bloom":
            // Word flashes in large and bright, then settles.
            let settle = easeOutCubic(appear)
            base.foregroundStyle(lit)
                .opacity(appear)
                .scaleEffect(1 + 0.25 * (1 - settle))
                .shadow(color: glow.opacity(appear > 0 ? min(1, s.glow + 0.4 * (1 - settle)) : 0),
                        radius: radius * (1 + 2 * (1 - settle)))

        case "wave":
            fill(base, lit, dim, glow, radius, s, progress)
                .offset(y: sin(time * 4 + Double(index) * 0.7) * size * 0.05)

        case "pop":
            let lift = sin(progress * .pi)
            base.foregroundStyle(progress > 0 ? lit : dim)
                .scaleEffect(1 + 0.12 * lift)
                .offset(y: -size * 0.12 * lift)
                .shadow(color: glow.opacity(progress > 0 ? s.glow : 0), radius: radius)

        case "fade":
            base.foregroundStyle(lit)
                .opacity(s.unsungOpacity + (1 - s.unsungOpacity) * progress)
                .shadow(color: glow.opacity(s.glow * progress), radius: radius)

        case "comet":
            // A comet streaks along under the line, lighting each word as it passes; its trail runs on into
            // the gap so the trails join the words up, then fades.
            let fade = clamp(1 - (time - word.end) / 1.4)
            base.foregroundStyle(progress > 0 ? lit : dim)
                .scaleEffect(appear > 0 ? 1 + 0.08 * (1 - easeOutCubic(appear)) : 1)
                .shadow(color: glow.opacity(progress > 0 ? s.glow : 0), radius: radius)
                .overlay {
                    if progress > 0 {
                        CometTrail(progress: progress, fade: fade, gap: connects ? size * 0.28 : 0,
                                   color: accent(s), size: size)
                    }
                }

        case "glitch":
            // Lands with a jittery red/cyan split, then settles clean.
            let shake = appear > 0 ? 1 - appear : 0
            let dx = size * 0.09 * shake
            let jx = noise(Int(time * 24) &+ index &* 97, 7) * 2 - 1
            let jy = noise(Int(time * 24) &+ index &* 97, 8) * 2 - 1
            ZStack {
                base.foregroundStyle(Color(red: 1, green: 0.1, blue: 0.35))
                    .offset(x: -dx + jx * dx, y: jy * dx * 0.5).opacity(shake)
                base.foregroundStyle(Color(red: 0.1, green: 0.95, blue: 1))
                    .offset(x: dx - jx * dx, y: -jy * dx * 0.5).opacity(shake)
                base.foregroundStyle(appear > 0 ? lit : dim)
                    .offset(x: jx * dx * 0.4)
            }
            .shadow(color: glow.opacity(appear > 0 ? s.glow : 0), radius: radius)

        case "neon":
            // Flickers on like a neon sign, then holds a hot layered glow.
            let pattern = [1, 0.1, 1, 0.3, 0.1, 1, 0.6, 1]
            let flicker = appear <= 0 ? 0 : appear >= 1 ? 1 : pattern[min(Int(appear * 8), 7)]
            let neon = accent(s)
            base.foregroundStyle(appear > 0 ? AnyShapeStyle(Color.white) : dim)
                .shadow(color: neon.opacity(flicker), radius: size * 0.06)
                .shadow(color: neon.opacity(flicker * 0.9), radius: size * 0.2)
                .shadow(color: neon.opacity(flicker * max(s.glow, 0.3)), radius: size * 0.5)
                .opacity(appear > 0 ? 0.35 + 0.65 * flicker : 1)

        case "slam":
            // Hits big and fast, with a shake on impact.
            let hit = clamp((time - word.start) / 0.16)
            let after = clamp((time - word.start - 0.16) / 0.35)
            let shake = hit >= 1 ? (1 - after) * sin(time * 90) * size * 0.035 : 0
            base.foregroundStyle(lit)
                .scaleEffect(1 + 1.6 * pow(1 - hit, 2))
                .blur(radius: (1 - hit) * 6)
                .opacity(hit > 0 ? 1 : 0)
                .offset(x: shake, y: shake * 0.6)
                .shadow(color: glow.opacity(hit > 0 ? s.glow : 0), radius: radius)

        case "scramble":
            // Random glyphs decode into the word, left to right.
            let chars = Array(string)
            let span = min(max(word.end - word.start, 0.2), 0.6)
            let resolved = Int(clamp((time - word.start) / span) * Double(chars.count))
            let glyphs = Array("ABCDEFGHJKLMNPQRSTUVWXYZ#$%&*@!?")
            let shown = time < word.start ? "" : String(chars.enumerated().map { i, c in
                i < resolved || !c.isLetter ? c : glyphs[Int(noise(Int(time * 20) &+ i &* 31 &+ index &* 7, 9) * Double(glyphs.count))]
            })
            base.foregroundStyle(Color.clear)
                .overlay(alignment: .leading) {
                    Text(shown).font(s.font(size: size)).tracking(s.tracking)
                        .foregroundStyle(lit)
                        .fixedSize()
                }
                .shadow(color: glow.opacity(appear > 0 ? s.glow : 0), radius: radius)

        case "flip":
            // Each word flips up into place like a split-flap board.
            base.foregroundStyle(lit)
                .rotation3DEffect(.degrees((1 - easeOutBack(appear)) * -90), axis: (x: 1, y: 0, z: 0),
                                  anchor: .bottom, perspective: 0.5)
                .opacity(clamp(appear * 2.5))
                .shadow(color: glow.opacity(s.glow * appear), radius: radius)

        case "cascade":
            // Letters drop in one after another.
            HStack(spacing: 0) {
                ForEach(Array(string.enumerated()), id: \.offset) { i, c in
                    let a = clamp((time - word.start - Double(i) * 0.035) / 0.32)
                    Text(String(c)).font(s.font(size: size)).tracking(s.tracking)
                        .foregroundStyle(lit)
                        .opacity(a)
                        .offset(y: (1 - easeOutBack(a)) * -size * 0.5)
                        .rotationEffect(.degrees((1 - a) * 20))
                }
            }
            .shadow(color: glow.opacity(appear > 0 ? s.glow : 0), radius: radius)

        case "float":
            let e = easeOutCubic(appear)
            base.foregroundStyle(lit)
                .opacity(appear)
                .offset(y: (1 - e) * size * 0.6 + sin(time * 1.6 + Double(index)) * size * 0.04)
                .shadow(color: glow.opacity(s.glow * appear), radius: radius)

        case "ink":
            // Soaks in from a wide, soft blot.
            let spread = clamp((time - word.start) / 0.6)
            base.foregroundStyle(lit)
                .blur(radius: (1 - easeOutCubic(spread)) * size * 0.16)
                .opacity(clamp(spread * 2))
                .scaleEffect(1.1 - 0.1 * easeOutCubic(spread))

        case "spin":
            base.foregroundStyle(lit)
                .rotation3DEffect(.degrees((1 - easeOutCubic(appear)) * 180), axis: (x: 0, y: 1, z: 0), perspective: 0.4)
                .opacity(clamp(appear * 2.5))
                .shadow(color: glow.opacity(s.glow * appear), radius: radius)

        case "swing":
            // Hangs from its top edge and swings to rest.
            let age = time - word.start
            base.foregroundStyle(lit)
                .rotationEffect(.degrees(age < 0 ? 0 : 24 * exp(-age * 4) * cos(age * 11)), anchor: .top)
                .opacity(clamp(appear * 3))
                .shadow(color: glow.opacity(s.glow * appear), radius: radius)

        case "rainbow":
            let shift = time * 0.25 + Double(index) * 0.08
            let hues = (0..<5).map { Color(hue: (shift + Double($0) * 0.13).truncatingRemainder(dividingBy: 1), saturation: 0.75, brightness: 1) }
            base.foregroundStyle(appear > 0 ? AnyShapeStyle(LinearGradient(colors: hues, startPoint: .leading, endPoint: .trailing)) : dim)
                .scaleEffect(1 + 0.06 * (appear > 0 ? 1 - appear : 0))
                .shadow(color: glow.opacity(appear > 0 ? s.glow * 0.6 : 0), radius: radius)

        case "stamp":
            let hit = clamp((time - word.start) / 0.13)
            base.foregroundStyle(lit)
                .scaleEffect(1 + 0.9 * pow(1 - hit, 2))
                .rotationEffect(.degrees((noise(index, 91) - 0.5) * 7 + (1 - hit) * 9))
                .opacity(hit > 0 ? 1 : 0)
                .shadow(color: glow.opacity(hit > 0 ? s.glow : 0), radius: radius)

        case "smoke":
            let gone = clamp((time - word.end - 0.5) / 1.6)
            base.foregroundStyle(lit)
                .opacity(appear * (1 - 0.85 * gone))
                .blur(radius: gone * size * 0.14 + (1 - appear) * 5)
                .offset(x: sin(gone * 5 + Double(index)) * size * 0.08 * gone, y: -gone * size * 0.7)

        case "jelly":
            let age = max(0, time - word.start)
            let wobble = exp(-age * 6) * sin(age * 22)
            base.foregroundStyle(lit)
                .scaleEffect(x: 1 + 0.3 * wobble, y: 1 - 0.3 * wobble)
                .opacity(clamp(appear * 4))
                .shadow(color: glow.opacity(s.glow * appear), radius: radius)

        case "ripple":
            HStack(spacing: 0) {
                ForEach(Array(string.enumerated()), id: \.offset) { i, c in
                    let age = time - word.start - Double(i) * 0.04
                    Text(String(c)).font(s.font(size: size)).tracking(s.tracking)
                        .foregroundStyle(lit)
                        .opacity(clamp(age / 0.12))
                        .offset(y: age < 0 ? 0 : -sin(min(age / 0.45, 1) * .pi) * size * 0.22)
                }
            }
            .shadow(color: glow.opacity(appear > 0 ? s.glow : 0), radius: radius)

        case "highlight":
            // A marker swipes behind the word as it's sung.
            let pad = size * 0.12
            base.foregroundStyle(progress > 0 ? AnyShapeStyle(s.usesWhite(onStage: isStage) ? Color.black : .white) : dim)
                .padding(.horizontal, pad)
                .background(alignment: .leading) {
                    GeometryReader { geo in
                        RoundedRectangle(cornerRadius: pad, style: .continuous)
                            .fill(lit)
                            .frame(width: geo.size.width * clamp(progress * 1.05))
                            .rotationEffect(.degrees(-1.5))
                    }
                }
                .padding(.horizontal, -pad)
                .shadow(color: glow.opacity(progress > 0 ? s.glow * 0.6 : 0), radius: radius)

        case "shine":
            // Karaoke fill, then a white sheen glides across the finished word.
            let sweep = clamp((time - word.end) / 0.6) * 1.6 - 0.3
            fill(base, lit, dim, glow, radius, s, progress)
                .overlay {
                    if sweep > -0.3 && sweep < 1.3 {
                        base.foregroundStyle(Color.white)
                            .mask(LinearGradient(stops: [.init(color: .clear, location: clamp(sweep - 0.25)),
                                                         .init(color: .white, location: clamp(sweep)),
                                                         .init(color: .clear, location: clamp(sweep + 0.25))],
                                                 startPoint: .leading, endPoint: .trailing))
                    }
                }

        default:
            fill(base, lit, dim, glow, radius, s, progress)
        }
    }

    /// A saturated album colour for effects that need a real hue even when the text is white.
    private func accent(_ s: StyleValues) -> Color {
        switch s.colorMode {
        case "white": return .white
        case "custom": return Color(hex: s.customHex)
        default: return Color(nsColor: player.palette[0])
        }
    }

    /// Colour sweeps through the word left-to-right as it's sung.
    private func fill(_ base: Text, _ lit: AnyShapeStyle, _ dim: AnyShapeStyle, _ glow: Color, _ radius: Double,
                      _ s: StyleValues, _ progress: Double) -> some View {
        let edge = clamp(progress * 1.1)
        let soft = clamp(progress * 1.1 - 0.1)
        let mask = LinearGradient(stops: [.init(color: .white, location: soft), .init(color: .clear, location: edge)],
                                  startPoint: .leading, endPoint: .trailing)
        return base.foregroundStyle(dim)
            .overlay { base.foregroundStyle(lit).mask(mask) }
            .shadow(color: glow.opacity(progress > 0 ? s.glow : 0), radius: radius)
    }
}

/// The glowing streak under a word for the comet effect: a trail up to the head, which burns white.
struct CometTrail: View {
    let progress: Double
    let fade: Double
    let gap: Double
    let color: Color
    let size: Double

    var body: some View {
        GeometryReader { geo in
            let head = (geo.size.width + gap) * progress
            let thick = max(2, size * 0.045)
            ZStack(alignment: .leading) {
                Capsule().fill(color.opacity(0.85))
                    .frame(width: max(head, thick), height: thick)
                    .opacity(progress < 1 ? 1 : fade)
                Capsule().fill(LinearGradient(colors: [.clear, .white], startPoint: .leading, endPoint: .trailing))
                    .frame(width: min(head, size * 1.2), height: thick)
                    .offset(x: max(head - size * 1.2, 0))
                    .opacity(progress < 1 ? 1 : 0)
                Circle().fill(Color.white)
                    .frame(width: thick * 2.6, height: thick * 2.6)
                    .shadow(color: .white, radius: thick * 2)
                    .shadow(color: color, radius: size * 0.3)
                    .offset(x: head - thick * 1.3)
                    .opacity(progress < 1 ? 1 : 0)
            }
            .frame(width: geo.size.width, height: geo.size.height + thick * 2, alignment: .bottomLeading)
            .shadow(color: color, radius: thick * 2)
        }
        .allowsHitTesting(false)
    }
}

struct LineView: View {
    let line: LyricLine
    let time: Double
    let isCurrent: Bool
    @Environment(\.isStage) private var isStage
    @ObservedObject private var style = Style.shared

    var body: some View {
        let s = style.v
        let size = isStage ? s.stageFontSize * 0.5 : s.fontSize
        Group {
            if line.words.isEmpty {
                Text("♪").font(s.font(size: size))
                    .foregroundStyle(Color.white.opacity(isCurrent ? 0.9 : s.unsungOpacity))
            } else {
                FlowLayout(alignment: s.alignment, spacing: size * 0.28, lineSpacing: size * 0.12) {
                    ForEach(Array(line.words.enumerated()), id: \.offset) { i, word in
                        WordView(word: word, index: i, time: time, active: isCurrent, line: line.id)
                    }
                }
            }
        }
        .scaleEffect(isCurrent ? 1 : 0.86, anchor: s.anchor)
        .opacity(isCurrent ? 1 : 0.8)
        .blur(radius: isCurrent || !s.blurInactive ? 0 : size * 0.04)
        .shadow(color: .black.opacity(s.textShadow ? 0.4 : 0), radius: size * 0.1, y: 1)
    }
}

// MARK: - Line transitions

struct Zoom: ViewModifier {
    let scale: Double
    let blur: Double
    let opacity: Double

    static let identity = Zoom(scale: 1, blur: 0, opacity: 1)

    func body(content: Content) -> some View {
        content.scaleEffect(scale).blur(radius: blur).opacity(opacity)
    }
}

struct Flip: ViewModifier {
    let angle: Double

    func body(content: Content) -> some View {
        content
            .rotation3DEffect(.degrees(angle), axis: (x: 1, y: 0, z: 0), perspective: 0.6)
            .opacity(1 - abs(angle) / 90)
    }
}

private func lineTransition(_ name: String) -> AnyTransition {
    switch name {
    case "fade":
        return .opacity
    case "scale":
        return .scale(scale: 0.7).combined(with: .opacity)
    case "blur":
        return .modifier(active: Zoom(scale: 1.08, blur: 14, opacity: 0), identity: .identity)
    case "zoom":
        return .asymmetric(insertion: .modifier(active: Zoom(scale: 0.6, blur: 10, opacity: 0), identity: .identity),
                           removal: .modifier(active: Zoom(scale: 1.4, blur: 16, opacity: 0), identity: .identity))
    case "flip":
        return .asymmetric(insertion: .modifier(active: Flip(angle: -85), identity: Flip(angle: 0)),
                           removal: .modifier(active: Flip(angle: 85), identity: Flip(angle: 0)))
    case "push":
        return .asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                           removal: .move(edge: .leading).combined(with: .opacity))
    case "drop":
        return .asymmetric(insertion: .move(edge: .top).combined(with: .opacity),
                           removal: .move(edge: .bottom).combined(with: .opacity))
    default:
        return .asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity),
                           removal: .move(edge: .top).combined(with: .opacity))
    }
}

struct LyricsView: View {
    let time: Double
    @Environment(\.isStage) private var isStage
    @ObservedObject private var style = Style.shared
    @ObservedObject private var player = NowPlaying.shared

    var body: some View {
        let s = style.v
        let lines = player.lyrics
        let index = lines.lastIndex { $0.start <= time } ?? -1
        VStack(alignment: s.horizontal, spacing: s.lineSpacing) {
            ForEach(visible(lines, index: index, shown: s.linesShown)) { line in
                LineView(line: line, time: time, isCurrent: line.id == index)
                    .transition(lineTransition(s.transition(line: line.id)))
            }
        }
        .modifier(LyricsBacking(kind: isStage ? s.lyricsBacking : "none", size: s.stageFontSize * 0.5))
        .frame(maxWidth: .infinity, alignment: s.frameAlignment)
        .animation(.spring(response: 0.55, dampingFraction: 1 - s.bounce * 0.55), value: index)
    }

    /// The current line plus neighbours: centred for 3+ lines, upcoming-only for 1–2.
    private func visible(_ lines: [LyricLine], index: Int, shown: Int) -> [LyricLine] {
        guard !lines.isEmpty else { return [] }
        let before = index >= 0 && shown >= 3 ? (shown - 1) / 2 : 0
        let from = max(0, max(index, 0) - before)
        let to = min(lines.count, from + shown)
        return Array(lines[from..<to])
    }
}

// MARK: - Lock screen (full-screen stage)

struct StageBackground: View {
    let date: Date
    let time: Double
    @ObservedObject private var style = Style.shared
    @ObservedObject private var player = NowPlaying.shared

    var body: some View {
        let s = style.v
        let colors = player.palette.map {
            Color(nsColor: $0.blended(withFraction: s.backgroundDarkness, of: .black) ?? $0)
        }
        Group {
            switch s.stageBackground {
            case "aurora":
                AuroraBackground(date: date)
            case let name where StyleValues.wallpapers.contains(name):
                WallpaperBackground(date: date, time: time)
            case "gradient":
                // Slowly rotating two-colour gradient.
                let angle = date.timeIntervalSinceReferenceDate * 0.15
                let start = UnitPoint(x: 0.5 + 0.5 * cos(angle), y: 0.5 + 0.5 * sin(angle))
                let end = UnitPoint(x: 1 - start.x, y: 1 - start.y)
                LinearGradient(colors: colors, startPoint: start, endPoint: end)
            case "custom":
                Color(hex: s.stageHex)
            case "black":
                Color.black
            default:
                colors[0]
            }
        }
        .animation(.easeInOut(duration: 1.2), value: player.palette)
    }
}

/// Lumn-style rim light: two streaks of album colour racing around the screen edge at a steady brightness.
/// The beat pushes them along rather than flashing them.
struct EdgeGlow: View {
    let time: Double
    let date: Date
    @ObservedObject private var player = NowPlaying.shared

    var body: some View {
        let first = Color(nsColor: player.palette[0])
        let second = Color(nsColor: player.palette[1 % player.palette.count])
        let _ = BeatClock.shared.update(date: date, time: time)
        let spin = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 9000) * 40
            + BeatClock.shared.travel(at: date) * 14
        // Soft edges come from gradient fades rather than a blur, which is far cheaper per frame.
        Rectangle()
            .fill(AngularGradient(stops: [
                .init(color: first.opacity(0), location: 0),
                .init(color: first, location: 0.26),
                .init(color: first.opacity(0), location: 0.31),
                .init(color: second.opacity(0), location: 0.5),
                .init(color: second, location: 0.76),
                .init(color: second.opacity(0), location: 0.81),
            ], center: .center, angle: .degrees(spin)))
            .mask(EdgeFade(thickness: 70))
            .opacity(0.85)
    }
}

/// Opaque at the screen edges, fading to clear inward.
struct EdgeFade: View {
    let thickness: CGFloat

    var body: some View {
        let fade = [Color.white, Color.white.opacity(0.3), Color.clear]
        ZStack {
            VStack {
                LinearGradient(colors: fade, startPoint: .top, endPoint: .bottom).frame(height: thickness)
                Spacer()
                LinearGradient(colors: fade, startPoint: .bottom, endPoint: .top).frame(height: thickness)
            }
            HStack {
                LinearGradient(colors: fade, startPoint: .leading, endPoint: .trailing).frame(width: thickness)
                Spacer()
                LinearGradient(colors: fade, startPoint: .trailing, endPoint: .leading).frame(width: thickness)
            }
        }
    }
}

/// Big lock-screen clock in the lyrics font, with the date above it.
struct StageClock: View {
    let date: Date
    @ObservedObject private var style = Style.shared

    var body: some View {
        let s = style.v
        VStack(spacing: 2) {
            Text(date, format: .dateTime.weekday(.wide).day().month(.wide))
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .textCase(.uppercase)
                .tracking(3)
                .foregroundStyle(Color.white.opacity(0.7))
            Text(date, format: .dateTime.hour(.defaultDigits(amPM: .omitted)).minute())
                .font(StyleValues.font(family: s.fontFamily, size: 92, weight: .bold, italic: s.italic))
                .monospacedDigit()
                .foregroundStyle(Color.white.opacity(0.92))
                .shadow(color: .black.opacity(0.3), radius: 12, y: 4)
        }
    }
}

/// The lock screen is layered views — background, lyrics, and the cut-out artist — so the full-screen
/// background, which moves slowly, redraws at 30 fps while the lyrics run at 60 (20 and 30 on battery saver).
/// The background and cut-out layers snap to the same clock so the cut-out stays exactly on its background.
private func backdropDate(_ date: Date) -> Date {
    let fps = Power.shared.backdropFPS
    return Date(timeIntervalSinceReferenceDate: (date.timeIntervalSinceReferenceDate * fps).rounded(.down) / fps)
}

struct StageBackdrop: View {
    @ObservedObject private var style = Style.shared
    @ObservedObject private var power = Power.shared
    @ObservedObject private var player = NowPlaying.shared

    var body: some View {
        let s = style.v
        let visible = player.stageVisible(s)
        TimelineView(.animation(minimumInterval: 1 / power.backdropFPS, paused: !visible)) { context in
            let date = backdropDate(context.date)
            let time = player.lyricTime(at: date)
            ZStack {
                StageBackground(date: date, time: time)
                StageEffects(date: date, time: time)
                if s.edgeGlow { EdgeGlow(time: time, date: date) }
                // The clock lives here, under the cut-out artist; the lyrics layer keeps an invisible copy for layout.
                if s.stageClock {
                    StageClock(date: date)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .padding(.horizontal, 90)
                        .padding(.top, 44)
                }
            }
        }
        .environment(\.isStage, true)
        .opacity(visible ? 1 : 0)
        .animation(.easeInOut(duration: 0.6), value: visible)
    }
}

/// The artist cut out of the artwork. There are two of these layers, under and over the lyrics; the clock is
/// drawn in the backdrop, so either way the artist stands in front of the clock, like the iPhone lock screen.
struct StageDepth: View {
    let overLyrics: Bool
    @ObservedObject private var style = Style.shared
    @ObservedObject private var power = Power.shared
    @ObservedObject private var player = NowPlaying.shared

    var body: some View {
        let s = style.v
        let visible = player.stageVisible(s) && s.depth && s.depthOverLyrics == overLyrics
            && StyleValues.wallpapers.contains(s.stageBackground)
        TimelineView(.animation(minimumInterval: 1 / power.backdropFPS, paused: !visible)) { context in
            let date = backdropDate(context.date)
            if visible {
                WallpaperBackground(date: date, time: player.lyricTime(at: date), foreground: true)
            }
        }
        .allowsHitTesting(false)
        .opacity(visible ? 1 : 0)
        .animation(.easeInOut(duration: 0.6), value: visible)
    }
}

struct StageView: View {
    @ObservedObject private var style = Style.shared
    @ObservedObject private var power = Power.shared
    @ObservedObject private var player = NowPlaying.shared

    var body: some View {
        let s = style.v
        let visible = player.stageVisible(s)
        // 60 fps: at ProMotion's 120 the lyrics cost twice as much for no visible gain.
        TimelineView(.animation(minimumInterval: 1 / power.lyricsFPS, paused: !visible)) { context in
            let time = player.lyricTime(at: context.date)
            ZStack {
                VStack(alignment: s.horizontal, spacing: 0) {
                    if s.stageClock { StageClock(date: context.date).frame(maxWidth: .infinity).hidden() }
                    Spacer(minLength: 0)
                    if TitleCard.showing(player, at: context.date) {
                        TitleCard(date: context.date, time: time)
                    } else if player.noLyrics {
                        NoLyricsView(date: context.date)
                    } else if player.lyrics.isEmpty {
                        Text(player.status)
                            .font(s.font(size: s.stageFontSize * 0.3))
                            .foregroundStyle(Color.white.opacity(0.6))
                            .frame(maxWidth: .infinity, alignment: s.frameAlignment)
                    } else if s.stageLayout == "reel" {
                        ReelLyricsView(time: time, date: context.date)
                    } else if s.stageLayout == "stack" {
                        WordStackView(time: time, date: context.date)
                    } else {
                        LyricsView(time: time)
                    }
                    Spacer(minLength: 0)
                    // Room for the now-playing bar, which lives in its own clickable window.
                    if s.stageFooter { Color.clear.frame(height: 110) }
                }
                .padding(.horizontal, 90)
                .padding(.top, 44)
                .padding(.bottom, 40)
                if player.untimed {
                    Text("Timing estimated · Tap to Sync fixes it")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .tracking(2)
                        .foregroundStyle(Color.white.opacity(0.5))
                        .frame(maxHeight: .infinity, alignment: .bottom)
                        .padding(.bottom, 140)
                }
                // Which preset the ✨ button just switched to, above the now-playing bar.
                PresetToastView(date: context.date)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 170)
            }
        }
        .environment(\.isStage, true)
        .opacity(visible ? 1 : 0)
        .animation(.easeInOut(duration: 0.6), value: visible)
    }
}

// MARK: - Desktop overlay

struct VisualEffect: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

struct OverlayBackground: View {
    @ObservedObject private var style = Style.shared

    var body: some View {
        let s = style.v
        let shape = RoundedRectangle(cornerRadius: 28, style: .continuous)
        switch s.background {
        case "blur":
            VisualEffect().clipShape(shape).opacity(s.backgroundOpacity)
        case "glass":
            if #available(macOS 26.0, *) {
                shape.fill(Color.black.opacity(0.15 * s.backgroundOpacity)).glassEffect(.regular, in: shape)
            } else {
                VisualEffect().clipShape(shape).opacity(s.backgroundOpacity)
            }
        case "dim":
            shape.fill(Color.black.opacity(s.backgroundOpacity))
        default:
            Color.clear
        }
    }
}

struct OverlayView: View {
    @ObservedObject private var style = Style.shared
    @ObservedObject private var player = NowPlaying.shared

    var body: some View {
        let s = style.v
        let visible = s.showOnDesktop && player.isPlaying && !player.locked && !player.previewing
        TimelineView(.animation(paused: !visible)) { context in
            VStack(alignment: s.horizontal, spacing: 14) {
                if s.showHeader, let track = player.track {
                    Text("\(track.title) · \(track.artist)")
                        .font(.system(size: max(12, s.fontSize * 0.38), weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.6))
                        .lineLimit(1)
                }
                if player.lyrics.isEmpty {
                    Text(player.status)
                        .font(.system(size: max(13, s.fontSize * 0.45), weight: .medium, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.5))
                } else {
                    LyricsView(time: player.lyricTime(at: context.date))
                }
            }
            .padding(.horizontal, 30)
            .padding(.vertical, 22)
            .frame(width: s.width, alignment: s.frameAlignment)
            .background(OverlayBackground())
        }
        .opacity(visible ? 1 : 0)
        .animation(.easeInOut(duration: 0.5), value: visible)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
