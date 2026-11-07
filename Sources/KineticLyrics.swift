import AppKit
import SwiftUI

// MARK: - Kinetic lyric styles

/// Motion-typography layouts for the line being sung. Each one takes the current word, the words of its line
/// and how long ago the word started, so seeking and scrubbing need no state.
enum KineticStyles {
    static let kinds: [(tag: String, name: String)] = [
        ("ring", "Ring — the line orbits the sung word"),
        ("stairs", "Stairs — words step down, joined by lines"),
        ("split", "Colour Split — the sung word in red and cyan layers"),
        ("scatter", "Scatter — words land around the screen, the sung one framed"),
        ("waveline", "Wave Line — a wavy underline that rides the music"),
        ("trail", "Trail — the sung word leaves echoes behind it"),
        ("circle", "Circle — a ring draws round the sung word"),
        ("hinge", "Hinge — big caps swinging in on a hinge"),
        ("sparkle", "Sparkle — words fall away, a star beside the sung one"),
        ("confetti", "Confetti — little stars round the line"),
        ("marquee", "Marquee — one giant word sliding past"),
        ("chips", "Chips — words in pills, the sung one filled"),
        ("giant", "Giant — the word so big it runs off the screen"),
        ("twist", "Twist — words flip over in 3D"),
        ("stamp", "Stamp — words thump down at angles"),
        ("thinbold", "Thin & Bold — the line thin, the sung word heavy"),
        ("card", "Card — the sung word on a card that bends to the beat"),
    ]

    static let tags = Set(kinds.map(\.tag))
}

private func clamp01(_ x: Double) -> Double { min(max(x, 0), 1) }
private func easeOut(_ x: Double) -> Double { 1 - pow(1 - clamp01(x), 3) }
private func easeOutBack(_ x: Double) -> Double {
    let x = clamp01(x), c1 = 1.70158, c3 = c1 + 1
    return 1 + c3 * pow(x - 1, 3) + c1 * pow(x - 1, 2)
}

/// A four-pointed star, for sparkles.
struct Sparkle: Shape {
    func path(in rect: CGRect) -> Path {
        Constellation.star(at: CGPoint(x: rect.midX, y: rect.midY), radius: min(rect.width, rect.height) / 2)
    }
}

/// A wavy line across its frame.
struct WaveShape: Shape {
    var phase: Double
    var amplitude: Double

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let steps = 60
        for i in 0...steps {
            let u = Double(i) / Double(steps)
            let y = rect.midY + sin(u * .pi * 4 + phase) * amplitude * sin(u * .pi)
            let point = CGPoint(x: rect.minX + u * rect.width, y: y)
            if i == 0 { p.move(to: point) } else { p.addLine(to: point) }
        }
        return p
    }
}

struct KineticLyricsView: View {
    let style: String
    let time: Double
    let look: VisualLook
    let kick: Double
    let base: Double
    @ObservedObject private var settings = Style.shared
    @ObservedObject private var player = NowPlaying.shared

    var body: some View {
        GeometryReader { geo in
            if let current = currentLine(player, time) {
                let words = player.words
                let i = current.index
                let moment = Moment(words: words, index: i, line: current.line, age: time - words[i].start,
                                    size: geo.size, t: Date().timeIntervalSinceReferenceDate)
                styled(moment)
                    .frame(width: geo.size.width, height: geo.size.height)
            }
        }
    }

    struct Moment {
        let words: [Word]
        let index: Int
        let line: Range<Int>
        let age: Double
        let size: CGSize
        let t: Double

        /// Up to `count` words of the line before the sung one.
        func before(_ count: Int) -> Range<Int> { max(line.lowerBound, index - count)..<index }
    }

    private var big: Double { base * look.mainScale }
    private var small: Double { base * look.otherScale }
    private var accent: Color { look.box ?? look.main }

    private func word(_ m: Moment, _ i: Int) -> String { settings.v.display(m.words[i].text) }

    /// Roughly how wide a word sets at `size`, so layouts can make room for long ones.
    private func width(_ string: String, _ size: Double) -> Double { Double(max(string.count, 2)) * size * 0.6 }

    private func text(_ string: String, _ size: Double, _ color: Color) -> some View {
        Text(string).font(look.font(size)).tracking(settings.v.tracking).foregroundStyle(color)
            .lineLimit(1).minimumScaleFactor(0.3).fixedSize(horizontal: true, vertical: false)
    }

    private func glowing<V: View>(_ view: V, _ size: Double) -> some View {
        view.shadow(color: look.glow ?? .clear, radius: size * 0.18)
            .shadow(color: .black.opacity(0.25), radius: size * 0.05, y: size * 0.03)
    }

    @ViewBuilder
    private func styled(_ m: Moment) -> some View {
        switch style {
        case "ring": ring(m)
        case "stairs": stairs(m)
        case "split": split(m)
        case "scatter": scatter(m)
        case "waveline": waveLine(m)
        case "trail": trail(m)
        case "circle": circle(m)
        case "hinge": hinge(m)
        case "sparkle": sparkle(m)
        case "confetti": confetti(m)
        case "marquee": marquee(m)
        case "chips": chips(m)
        case "giant": giant(m)
        case "twist": twist(m)
        case "stamp": stamp(m)
        case "thinbold": thinBold(m)
        default: card(m)
        }
    }

    // MARK: Styles

    /// The sung word in the middle; the rest of the line orbits it on a tilted ring.
    private func ring(_ m: Moment) -> some View {
        let w = max(big * 4.4, width(word(m, m.index), big) * 1.5), h = max(big * 1.5, w * 0.34)
        let others = Array(m.line).filter { $0 != m.index }
        return ZStack {
            Ellipse().stroke(accent.opacity(0.35), lineWidth: 1.5).frame(width: w, height: h)
            ForEach(Array(others.enumerated()), id: \.element) { k, i in
                let a = Double(k) / Double(max(others.count, 1)) * 2 * .pi + m.t * 0.5
                text(word(m, i), small, look.other)
                    .opacity(i < m.index ? 1 : look.upcoming)
                    .scaleEffect(0.8 + 0.25 * (sin(a) + 1) / 2)
                    .offset(x: cos(a) * w / 2, y: sin(a) * h / 2)
            }
            glowing(text(word(m, m.index), big, look.main), big)
                .scaleEffect(0.7 + 0.3 * easeOutBack(m.age / 0.25) + 0.04 * kick)
        }
        .rotationEffect(.degrees(-8))
    }

    /// Words step down to the right, joined by bracket lines, the sung one underlined.
    private func stairs(_ m: Moment) -> some View {
        let shown = Array(m.before(3)) + [m.index]
        let step = CGSize(width: big * 0.6, height: big * 0.85)
        let start = CGSize(width: -step.width * Double(shown.count - 1) / 2, height: -step.height * Double(shown.count - 1) / 2)
        return ZStack {
            ForEach(Array(shown.enumerated()), id: \.element) { k, i in
                let current = i == m.index
                let x = start.width + step.width * Double(k), y = start.height + step.height * Double(k)
                text(word(m, i), current ? big : small * 1.4, current ? look.main : look.other)
                    .overlay(alignment: .bottom) {
                        if current {
                            Capsule().fill(accent).frame(height: max(2, big * 0.05))
                                .scaleEffect(x: easeOut(m.age / 0.3), anchor: .leading)
                                .offset(y: big * 0.12)
                        }
                    }
                    .offset(x: x, y: y)
                if k > 0 {
                    Path { p in
                        p.move(to: CGPoint(x: x - step.width * 0.1, y: y - step.height * 0.95))
                        p.addLine(to: CGPoint(x: x + step.width * 0.55, y: y - step.height * 0.95))
                        p.addLine(to: CGPoint(x: x + step.width * 0.55, y: y - step.height * 0.35))
                    }
                    .stroke(accent.opacity(0.5), lineWidth: 1.5)
                    .offset(x: m.size.width / 2, y: m.size.height / 2)
                    .frame(width: m.size.width, height: m.size.height)
                }
            }
        }
    }

    /// The sung word split into offset red and cyan layers that snap together.
    private func split(_ m: Moment) -> some View {
        let spread = big * 0.06 * (1 - easeOut(m.age / 0.35)) + big * 0.015 * kick
        let label = word(m, m.index)
        return VStack(spacing: big * 0.12) {
            text(m.before(4).map { word(m, $0) }.joined(separator: " "), small, look.other)
            ZStack {
                text(label, big, Color(red: 1, green: 0.2, blue: 0.3).opacity(0.8)).offset(x: -spread, y: spread * 0.3)
                text(label, big, Color(red: 0.2, green: 0.9, blue: 1).opacity(0.8)).offset(x: spread, y: -spread * 0.3)
                glowing(text(label, big, look.main), big)
            }
            .overlay(alignment: .topTrailing) {
                Sparkle().fill(accent).frame(width: big * 0.25, height: big * 0.25)
                    .rotationEffect(.degrees(m.t * 90)).offset(x: big * 0.3, y: -big * 0.2)
            }
        }
    }

    /// Words land at scattered spots; the sung one gets a drawn frame and a sparkle.
    private func scatter(_ m: Moment) -> some View {
        let area = CGSize(width: m.size.width * 0.55, height: m.size.height * 0.45)
        return ZStack {
            ForEach(Array(m.before(4)) + [m.index], id: \.self) { i in
                let current = i == m.index
                let slot = Double(i - m.before(4).lowerBound)
                let angle = slot / 4 * 2 * .pi + noise(m.line.lowerBound, 91) * 2 * .pi
                let rx = max(area.width / 2, width(word(m, m.index), big) * 0.75), ry = max(area.height / 2, big * 1.1)
                let x = current ? 0 : cos(angle) * rx
                let y = current ? 0 : sin(angle) * ry
                Group {
                    if current {
                        glowing(text(word(m, i), big, look.main), big)
                            .padding(.horizontal, big * 0.18)
                            .padding(.vertical, big * 0.04)
                            .overlay(Rectangle().trim(from: 0, to: easeOut(m.age / 0.3)).stroke(accent, lineWidth: max(2, big * 0.04)))
                            .overlay(alignment: .topTrailing) {
                                Sparkle().fill(accent).frame(width: big * 0.2, height: big * 0.2).offset(x: big * 0.1, y: -big * 0.1)
                            }
                            .scaleEffect(0.85 + 0.15 * easeOutBack(m.age / 0.25))
                    } else {
                        text(word(m, i), small * 1.2, look.other)
                    }
                }
                .offset(x: x, y: y)
            }
        }
    }

    /// The line above, the sung word big, a wavy line underneath riding the beat.
    private func waveLine(_ m: Moment) -> some View {
        VStack(spacing: big * 0.12) {
            text(m.before(4).map { word(m, $0) }.joined(separator: " "), small, look.other)
            glowing(text(word(m, m.index), big, look.main), big)
                .offset(y: (1 - easeOut(m.age / 0.25)) * big * 0.3)
                .opacity(easeOut(m.age / 0.15))
            ZStack {
                WaveShape(phase: m.t * 3, amplitude: big * (0.06 + 0.12 * kick)).stroke(accent, lineWidth: max(2, big * 0.035))
                WaveShape(phase: m.t * 3 + 1, amplitude: big * (0.04 + 0.08 * kick)).stroke(accent.opacity(0.35), lineWidth: max(1, big * 0.02))
            }
            .frame(width: big * 4.5, height: big * 0.4)
        }
    }

    /// The sung word with faded copies trailing off to the right that pull in behind it.
    private func trail(_ m: Moment) -> some View {
        let label = word(m, m.index)
        let pull = 1 - easeOut(m.age / 0.5)
        return VStack(spacing: big * 0.1) {
            text(m.before(4).map { word(m, $0) }.joined(separator: " "), small, look.other)
            ZStack {
                ForEach(1..<5, id: \.self) { k in
                    text(label, big, accent.opacity(0.28 - Double(k) * 0.05))
                        .offset(x: Double(k) * big * 0.12 * (0.3 + pull), y: -Double(k) * big * 0.03 * (0.3 + pull))
                }
                glowing(text(label, big, look.main), big)
            }
        }
    }

    /// A circle draws itself round the sung word, with a soft glow inside it.
    private func circle(_ m: Moment) -> some View {
        let d = max(big * 2.6, width(word(m, m.index), big) * 1.15)
        let tall = min(d, big * 2.6)
        return ZStack {
            Ellipse().fill(RadialGradient(colors: [accent.opacity(0.25), .clear], center: .center, startRadius: 0, endRadius: d / 2))
                .frame(width: d, height: tall)
            Ellipse().trim(from: 0, to: easeOut(m.age / 0.45)).stroke(accent, lineWidth: max(2, big * 0.035))
                .frame(width: d, height: tall)
            Ellipse().stroke(accent.opacity(0.3), lineWidth: 1).frame(width: d * 1.06, height: tall * 1.08)
            glowing(text(word(m, m.index), big, look.main), big)
            text(m.before(3).map { word(m, $0) }.joined(separator: " "), small, look.other)
                .offset(x: -d * 0.25, y: -tall * 0.62)
        }
    }

    /// The sung word in big caps swinging down on a hinge; the words before it stack small at its corner.
    private func hinge(_ m: Moment) -> some View {
        let swing = easeOutBack(m.age / 0.35)
        return ZStack(alignment: .topTrailing) {
            glowing(text(word(m, m.index).uppercased(), big * 1.1, look.main), big)
                .rotationEffect(.degrees(-6 + (1 - swing) * 70), anchor: .topLeading)
            VStack(alignment: .trailing, spacing: 0) {
                ForEach(Array(m.before(2)), id: \.self) { i in text(word(m, i).uppercased(), small * 0.9, look.other) }
            }
            .rotationEffect(.degrees(-6))
            .offset(x: big * 1.1, y: -big * 1.0)
        }
    }

    /// Words fall away down a diagonal, the sung one with a spinning star beside it.
    private func sparkle(_ m: Moment) -> some View {
        let shown = Array(m.before(3)) + [m.index]
        return ZStack {
            ForEach(Array(shown.enumerated()), id: \.element) { k, i in
                let current = i == m.index
                let offset = Double(k - shown.count + 1)
                text(word(m, i), current ? big : small * 1.2, current ? look.main : look.other)
                    .opacity(current ? 1 : 0.5 + 0.15 * Double(k))
                    .offset(x: offset * big * 0.8, y: offset * big * 0.6)
            }
            Sparkle().fill(accent)
                .frame(width: big * 0.6, height: big * 0.6)
                .scaleEffect(easeOutBack(m.age / 0.3) * (1 + 0.15 * kick))
                .rotationEffect(.degrees(m.age * 120))
                .offset(x: width(word(m, m.index), big) * 0.5 + big * 0.5, y: big * 0.6)
        }
    }

    /// The line stacked and centred, the sung word underlined, little stars twinkling round it.
    private func confetti(_ m: Moment) -> some View {
        ZStack {
            VStack(spacing: big * 0.05) {
                ForEach(Array(m.before(3)), id: \.self) { i in text(word(m, i), small * 1.2, look.other) }
                glowing(text(word(m, m.index), big, look.main), big)
                    .scaleEffect(0.8 + 0.2 * easeOutBack(m.age / 0.25))
                Capsule().fill(accent).frame(width: big * 1.6, height: max(2, big * 0.04))
                    .scaleEffect(x: easeOut(m.age / 0.3))
            }
            ForEach(0..<9, id: \.self) { k in
                let seed = m.index &* 13 &+ k
                Sparkle().fill(accent.opacity(0.85))
                    .frame(width: big * (0.12 + 0.1 * noise(seed, 93)), height: big * (0.12 + 0.1 * noise(seed, 93)))
                    .scaleEffect(0.6 + 0.4 * abs(sin(m.t * 3 + Double(k))))
                    .offset(x: (noise(seed, 94) - 0.5) * big * 4, y: (noise(seed, 95) - 0.5) * big * 3)
            }
        }
    }

    /// One giant word with a solid shadow, sliding across the screen over the time it's sung.
    private func marquee(_ m: Moment) -> some View {
        let w = m.words[m.index]
        let span = max(w.end - w.start, 0.4)
        let slide = clamp01(m.age / (span + 0.6))
        let size = base * 1.9
        let label = word(m, m.index)
        return ZStack {
            text(label, size, look.extrude ?? accent.opacity(0.45)).offset(x: size * 0.03, y: size * 0.04)
            text(label, size, look.main)
        }
        .offset(x: (0.25 - 0.5 * slide) * m.size.width)
    }

    /// Words in pills: earlier ones pale and small, stacked up and to the right; the sung one filled, with an arrow.
    private func chips(_ m: Moment) -> some View {
        let before = Array(m.before(2))
        return VStack(alignment: .leading, spacing: big * 0.12) {
            ForEach(Array(before.enumerated()), id: \.element) { k, i in
                text(word(m, i), small * 1.1, accent.opacity(0.7))
                    .padding(.horizontal, small * 0.6).padding(.vertical, small * 0.2)
                    .background(Capsule().fill(accent.opacity(0.14)))
                    .offset(x: big * 0.5 * Double(before.count - k))
            }
            HStack(spacing: big * 0.15) {
                Image(systemName: "arrow.up.right.circle.fill").font(.system(size: big * 0.35)).foregroundStyle(accent)
                text(word(m, m.index), big * 0.8, look.box == nil ? .white : look.boxText)
                    .padding(.horizontal, big * 0.35).padding(.vertical, big * 0.1)
                    .background(Capsule().fill(accent))
                    .overlay(Capsule().stroke(accent.opacity(0.5), lineWidth: 2).padding(-big * 0.06))
            }
            .scaleEffect(0.8 + 0.2 * easeOutBack(m.age / 0.25), anchor: .leading)
        }
    }

    /// The word blown up past the edges of the screen, with a star in the corner.
    private func giant(_ m: Moment) -> some View {
        ZStack(alignment: .topTrailing) {
            Text(word(m, m.index)).font(look.font(base * 2.6)).foregroundStyle(look.main)
                .fixedSize()
                .scaleEffect(1.15 - 0.15 * easeOut(m.age / 0.3) + 0.03 * kick)
                .frame(width: m.size.width, height: m.size.height)
                .clipped()
            Sparkle().fill(accent).frame(width: base * 0.5, height: base * 0.5)
                .rotationEffect(.degrees(m.t * 40)).padding(base * 0.3)
        }
    }

    /// Words flip over in 3D: the new one turns down into place as the last one turns away above it.
    private func twist(_ m: Moment) -> some View {
        let turn = easeOut(m.age / 0.4)
        return VStack(spacing: big * 0.15) {
            if m.index > m.line.lowerBound {
                text(word(m, m.index - 1), big * 0.7, look.other)
                    .rotation3DEffect(.degrees(-50 * turn), axis: (x: 1, y: 0.3, z: 0), perspective: 0.5)
                    .opacity(1 - 0.5 * turn)
            }
            ZStack {
                text(word(m, m.index), big, look.extrude ?? accent.opacity(0.4)).offset(x: big * 0.03, y: big * 0.05)
                glowing(text(word(m, m.index), big, look.main), big)
            }
            .rotation3DEffect(.degrees((1 - turn) * 90), axis: (x: 1, y: -0.2, z: 0), anchor: .top, perspective: 0.5)
        }
    }

    /// Words thump down one after another at angles, climbing across the screen.
    private func stamp(_ m: Moment) -> some View {
        let shown = Array(m.before(3)) + [m.index]
        return ZStack {
            ForEach(Array(shown.enumerated()), id: \.element) { k, i in
                let current = i == m.index
                let offset = Double(k - shown.count + 1)
                let hit = current ? clamp01(m.age / 0.16) : 1
                let back = width(word(m, m.index), big) * 0.55 + big * 1.1 * (-offset - 0.3)
                text(word(m, i), current ? big : small * 1.1, current ? look.main : look.other)
                    .rotationEffect(.degrees((noise(i, 96) - 0.5) * 24))
                    .scaleEffect(current ? 2.2 - 1.2 * hit : 1)
                    .opacity(current ? hit : 0.6)
                    .offset(x: current ? 0 : -back, y: -offset * big * 0.65)
            }
        }
        .offset(x: big * 0.8)
    }

    /// The words before in a thin weight, the sung word underneath in heavy, gliding in from the side.
    private func thinBold(_ m: Moment) -> some View {
        VStack(spacing: 0) {
            Text(m.before(4).map { word(m, $0) }.joined(separator: " "))
                .font(StyleValues.font(family: look.family, size: big * 0.7, weight: .light, italic: look.italic))
                .foregroundStyle(look.other).lineLimit(1).minimumScaleFactor(0.3)
            Text(word(m, m.index))
                .font(StyleValues.font(family: look.family, size: big * 1.05, weight: .black, italic: look.italic))
                .foregroundStyle(look.main).lineLimit(1).minimumScaleFactor(0.3)
                .offset(x: (1 - easeOut(m.age / 0.35)) * big * 1.2)
                .opacity(easeOut(m.age / 0.2))
        }
        .frame(maxWidth: m.size.width * 0.85)
    }

    /// The sung word on a filled card that leans and bends with the beat.
    private func card(_ m: Moment) -> some View {
        let lean = sin(m.t * 2) * 4 + kick * 6
        return text(word(m, m.index), big, look.box == nil ? .white : look.boxText)
            .padding(.horizontal, big * 0.6)
            .padding(.vertical, big * 0.35)
            .background(RoundedRectangle(cornerRadius: big * 0.05).fill(accent))
            .scaleEffect(x: 1 + 0.04 * kick, y: 1 - 0.03 * kick)
            .rotation3DEffect(.degrees(lean), axis: (x: 0.2, y: 1, z: 0), perspective: 0.6)
            .scaleEffect(0.85 + 0.15 * easeOutBack(m.age / 0.25))
    }
}
