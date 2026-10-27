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
    @Environment(\.isStage) private var isStage
    @ObservedObject private var style = Style.shared
    @ObservedObject private var player = NowPlaying.shared

    var body: some View {
        let s = style.v
        let size = isStage ? s.stageFontSize * 0.5 : s.fontSize
        let string = s.uppercase ? word.text.uppercased() : word.text
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

        switch s.wordStyle {
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

        default:
            fill(base, lit, dim, glow, radius, s, progress)
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
                        WordView(word: word, index: i, time: time, active: isCurrent)
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
    @ObservedObject private var style = Style.shared
    @ObservedObject private var player = NowPlaying.shared

    var body: some View {
        let s = style.v
        let lines = player.lyrics
        let index = lines.lastIndex { $0.start <= time } ?? -1
        VStack(alignment: s.horizontal, spacing: s.lineSpacing) {
            ForEach(visible(lines, index: index, shown: s.linesShown)) { line in
                LineView(line: line, time: time, isCurrent: line.id == index)
                    .transition(lineTransition(s.transition))
            }
        }
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

/// Lumn-style rim light whose brightness kicks on every sung word.
struct EdgeGlow: View {
    let time: Double
    let date: Date
    @ObservedObject private var player = NowPlaying.shared

    var body: some View {
        let colors = player.palette.map { Color(nsColor: $0) }
        let pulse = player.wordPulse(at: time)
        // Soft edges come from gradient fades rather than a blur, which is far cheaper per frame.
        Rectangle()
            .fill(AngularGradient(colors: colors + colors + [colors[0]], center: .center,
                                  angle: .degrees(date.timeIntervalSinceReferenceDate * 24)))
            .mask(EdgeFade(thickness: 70))
            .opacity(0.45 + 0.55 * pulse)
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

struct StageView: View {
    @ObservedObject private var style = Style.shared
    @ObservedObject private var player = NowPlaying.shared

    var body: some View {
        let s = style.v
        let visible = player.stageVisible(s)
        TimelineView(.animation(paused: !visible)) { context in
            let time = player.position(at: context.date) + s.offset
            ZStack {
                StageBackground(date: context.date)
                if s.edgeGlow { EdgeGlow(time: time, date: context.date) }
                VStack(alignment: s.horizontal, spacing: 0) {
                    if s.stageClock { StageClock(date: context.date).frame(maxWidth: .infinity) }
                    Spacer(minLength: 0)
                    if player.lyrics.isEmpty {
                        Text(player.status)
                            .font(s.font(size: s.stageFontSize * 0.3))
                            .foregroundStyle(Color.white.opacity(0.6))
                            .frame(maxWidth: .infinity, alignment: s.frameAlignment)
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
                    LyricsView(time: player.position(at: context.date) + s.offset)
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
