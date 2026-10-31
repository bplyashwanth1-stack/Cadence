import AppKit
import SwiftUI

// MARK: - Reel lyrics

/// A lyric line set like a poster: words grouped into rows, each row scaled to the same width, the strongest word
/// biggest. Sizes are measured once per line, since measuring text every frame would be far too slow.
struct PosterLayout {
    struct Piece {
        let index: Int  // into the line's words
        let text: String
        let size: Double
        let width: Double
        let key: Bool
    }

    struct Row {
        let pieces: [Piece]
        let height: Double
    }

    let rows: [Row]
    let height: Double

    private static var cache: [String: PosterLayout] = [:]
    private static let quiet: Set<String> = [
        "a", "an", "the", "and", "or", "but", "to", "of", "in", "on", "at", "for", "with", "is", "am", "are", "was",
        "i", "i'm", "you", "me", "my", "your", "we", "it", "it's", "that", "this", "so", "be", "do", "oh", "ooh", "yeah",
    ]

    static func make(_ words: [String], family: String, weight: String, tracking: Double, width: Double,
                     maxHeight: Double) -> PosterLayout {
        let tag = "\(words.joined(separator: " "))|\(family)|\(weight)|\(tracking)|\(Int(width))|\(Int(maxHeight))"
        if let hit = cache[tag] { return hit }
        let font = nsFont(family, weight)
        func measure(_ text: String) -> Double {
            NSAttributedString(string: text, attributes: [.font: font]).size().width + tracking * Double(text.count)
        }
        let strongest = words.indices.max {
            score(words[$0]) < score(words[$1])
        }

        // Rows of up to about 14 letters, with the strongest word alone so it can go big.
        var groups: [[Int]] = []
        for i in words.indices {
            let letters = (groups.last ?? []).reduce(0) { $0 + words[$1].count + 1 } + words[i].count
            if groups.isEmpty || i == strongest || groups.last?.contains(where: { $0 == strongest }) == true || letters > 14 {
                groups.append([i])
            } else {
                groups[groups.count - 1].append(i)
            }
        }

        var rows: [Row] = []
        for group in groups {
            let joined = group.map { words[$0] }.joined(separator: " ")
            let wide = max(measure(joined), 1)
            var size = 100 * width / wide
            // A one-word row would otherwise fill the whole screen for a short word.
            size = min(size, maxHeight * 0.6)
            let pieces = group.map { i in
                Piece(index: i, text: words[i], size: size, width: measure(words[i]) * size / 100, key: i == strongest)
            }
            rows.append(Row(pieces: pieces, height: size * 1.08))
        }
        var total = rows.reduce(0) { $0 + $1.height }
        if total > maxHeight {
            let shrink = maxHeight / total
            rows = rows.map { row in
                Row(pieces: row.pieces.map {
                    Piece(index: $0.index, text: $0.text, size: $0.size * shrink, width: $0.width * shrink, key: $0.key)
                }, height: row.height * shrink)
            }
            total = maxHeight
        }
        let layout = PosterLayout(rows: rows, height: total)
        if cache.count > 400 { cache.removeAll() }
        cache[tag] = layout
        return layout
    }

    private static func score(_ word: String) -> Int {
        let plain = word.lowercased().filter { $0.isLetter || $0 == "'" }
        if quiet.contains(plain) { return 0 }
        return plain.count + (Burst.kind(for: word) != nil ? 8 : 0)
    }

    private static func nsFont(_ family: String, _ weight: String) -> NSFont {
        let weights: [String: NSFont.Weight] = ["light": .light, "regular": .regular, "medium": .medium,
                                                "semibold": .semibold, "bold": .bold, "heavy": .heavy, "black": .black]
        let fallback = NSFont.systemFont(ofSize: 100, weight: weights[weight] ?? .bold)
        guard !family.hasPrefix("System") else { return fallback }
        let descriptor = NSFontDescriptor(fontAttributes: [.family: family])
        return NSFont(descriptor: descriptor, size: 100) ?? fallback
    }
}

/// Lyrics as motion graphics: each line is a poster that builds word by word on the vocal, in one of several
/// reel styles, hits on the kick and zooms past the camera when the next line lands.
struct ReelLyricsStage: View {
    enum Look: CaseIterable { case slam, rise, echo, block, blackout, turn, neon }

    let lines: [LyricLine]
    let time: Double
    let kick: Double
    let chorus: Set<Int>
    let accent: Color
    let style: StyleValues
    let size: CGSize

    /// Edits show a few huge words at a time, so a line is cut into pages of 3 or 4 words that land one after another.
    private func page(_ line: LyricLine) -> (words: ArraySlice<Word>, number: Int) {
        let index = line.words.lastIndex { $0.start <= time } ?? 0
        let per = line.words.count <= 4 ? 4 : (line.words.count % 3 == 1 ? 4 : 3)
        let number = index / per
        let start = number * per
        return (line.words[start..<min(start + per, line.words.count)], number)
    }

    private func look(_ id: Int, _ number: Int) -> Look {
        let hard = chorus.contains(id)
        let seed = id &* 7 &+ number
        // A full blackout is the big moment, so only some chorus lines get one.
        if hard && noise(seed, 71) < 0.25 { return .blackout }
        let pool: [Look] = hard ? [.slam, .echo, .block, .neon] : [.rise, .slam, .rise, .block, .turn]
        return pool[Int(noise(seed, 72) * Double(pool.count))]
    }

    var body: some View {
        let sung = lines.filter { !$0.words.isEmpty }
        let current = sung.last { $0.start <= time }
        let held = current.map { time - ($0.words.last?.end ?? $0.end) } ?? 0
        ZStack {
            if let current, held < 1.2 {
                let shown = page(current)
                let chosen = look(current.id, shown.number)
                let intro = time - (shown.words.first?.start ?? current.start)
                if chosen == .blackout {
                    Color.black.opacity(0.82 * min(intro / 0.08, 1))
                        .frame(width: size.width * 1.2, height: size.height * 1.2)
                }
                poster(Array(shown.words), line: current.id, page: shown.number, look: chosen, leaving: max(0, held - 0.9) / 0.3)
            }
        }
        .frame(width: size.width, height: size.height)
        .drawingGroup()
    }

    @ViewBuilder
    private func poster(_ words: [Word], line: Int, page: Int, look: Look, leaving: Double) -> some View {
        let seed = line &* 11 &+ page
        let width = size.width * (0.68 + 0.2 * noise(seed, 73))
        let shown = words.map { style.display($0.text) }
        let layout = PosterLayout.make(shown, family: style.fontFamily, weight: style.fontWeight, tracking: style.tracking,
                                       width: width, maxHeight: size.height * 0.7)
        let age = time - (words.first?.start ?? 0)
        // The whole poster keeps creeping towards you, and kicks with the bass.
        let drift = 1 + 0.018 * min(age, 6) + 0.035 * kick
        VStack(spacing: 0) {
            ForEach(layout.rows.indices, id: \.self) { r in
                HStack(spacing: (layout.rows[r].pieces.first?.size ?? 0) * 0.24) {
                    ForEach(layout.rows[r].pieces, id: \.index) { piece in
                        word(piece, words[piece.index], seed: seed &+ piece.index, look: look)
                    }
                }
                .frame(height: layout.rows[r].height)
            }
        }
        .scaleEffect(drift * (1 + 0.8 * leaving))
        .rotationEffect(.degrees((noise(seed, 74) - 0.5) * 3.5))
        .offset(x: (noise(seed, 76) - 0.5) * 16 * kick, y: (noise(seed, 77) - 0.5) * 16 * kick)
        .opacity(1 - leaving)
    }

    @ViewBuilder
    private func word(_ piece: PosterLayout.Piece, _ word: Word, seed: Int, look: Look) -> some View {
        let age = time - word.start
        if age < -0.02 {
            label(piece, style.textShadow).hidden()
        } else {
            switch look {
            case .slam: slam(piece, age, seed)
            case .rise: rise(piece, age)
            case .echo: echo(piece, age, seed)
            case .block: block(piece, age, word)
            case .blackout: slam(piece, age, seed)
            case .turn: turn(piece, age)
            case .neon: neon(piece, age)
            }
        }
    }

    private func easeOut(_ x: Double) -> Double { 1 - pow(1 - min(max(x, 0), 1), 4) }

    private func text(_ piece: PosterLayout.Piece) -> Text {
        Text(piece.text).font(style.font(size: piece.size)).tracking(style.tracking)
    }

    private func label(_ piece: PosterLayout.Piece, _ shadow: Bool) -> some View {
        text(piece)
            .fixedSize()
            .foregroundStyle(piece.key ? accent : Color.white)
            .shadow(color: .black.opacity(shadow ? 0.55 : 0), radius: piece.size * 0.06, y: piece.size * 0.02)
    }

    /// Falls from huge and lands with a jolt.
    private func slam(_ piece: PosterLayout.Piece, _ age: Double, _ seed: Int) -> some View {
        let land = easeOut(age / 0.13)
        return label(piece, true)
            .scaleEffect(2.4 - 1.4 * land)
            .rotationEffect(.degrees((noise(seed, 78) - 0.5) * 14 * (1 - land)))
            .opacity(min(age / 0.04, 1))
    }

    /// Rises into place, whole, fading in on the way.
    private func rise(_ piece: PosterLayout.Piece, _ age: Double) -> some View {
        let up = easeOut(age / 0.26)
        return label(piece, true)
            .offset(y: piece.size * 0.45 * (1 - up))
            .opacity(min(age / 0.14, 1))
    }

    /// Slams in with copies of itself flying out above and below, then the copies fade.
    private func echo(_ piece: PosterLayout.Piece, _ age: Double, _ seed: Int) -> some View {
        let spread = easeOut(age / 0.3)
        let fade = max(0, 1 - age / 0.7)
        return ZStack {
            ForEach([-2, -1, 1, 2], id: \.self) { step in
                text(piece)
                    .fixedSize()
                    .foregroundStyle(Color.white.opacity(0.3 / Double(abs(step)) * fade))
                    .offset(y: Double(step) * piece.size * 0.85 * spread)
            }
            slam(piece, age, seed)
        }
    }

    /// Swings round in 3D to face you.
    private func turn(_ piece: PosterLayout.Piece, _ age: Double) -> some View {
        label(piece, true)
            .rotation3DEffect(.degrees(80 * (1 - easeOut(age / 0.3))), axis: (x: 0, y: 1, z: 0), perspective: 0.5)
            .opacity(min(age / 0.1, 1))
    }

    /// Glows in like a sign warming up, without flickering.
    private func neon(_ piece: PosterLayout.Piece, _ age: Double) -> some View {
        let on = easeOut(age / 0.25)
        return text(piece)
            .fixedSize()
            .foregroundStyle(Color.white)
            .shadow(color: accent.opacity(on), radius: piece.size * 0.05)
            .shadow(color: accent.opacity(on * 0.8), radius: piece.size * 0.18)
            .opacity(on)
    }

    /// A colour bar shoots across and the word appears cut out of it.
    private func block(_ piece: PosterLayout.Piece, _ age: Double, _ word: Word) -> some View {
        let sweep = easeOut(age / 0.2)
        let held = age < 0.5 || piece.key
        return text(piece)
            .fixedSize()
            .foregroundStyle(held ? Color.black : Color.white)
            .padding(.horizontal, piece.size * 0.1)
            .background(alignment: .leading) {
                if held {
                    Rectangle().fill(piece.key ? accent : Color.white)
                        .frame(width: max(0, (piece.width + piece.size * 0.2) * sweep))
                }
            }
            .opacity(min(age / 0.05, 1))
    }
}

/// The lock-screen layer: hooks the stage up to what's playing.
struct ReelLyricsView: View {
    let time: Double
    let date: Date
    @ObservedObject private var style = Style.shared
    @ObservedObject private var player = NowPlaying.shared

    var body: some View {
        GeometryReader { geo in
            let c = player.palette[0].usingColorSpace(.deviceRGB) ?? player.palette[0]
            let album = Color(nsColor: NSColor(hue: c.hueComponent, saturation: max(c.saturationComponent, 0.7),
                                               brightness: 1, alpha: 1))
            ReelLyricsStage(lines: player.lyrics, time: time, kick: player.kick(at: time, date: date),
                            chorus: player.repeated, accent: style.v.colorMode == "custom" ? Color(hex: style.v.customHex) : album,
                            style: style.v, size: geo.size)
        }
    }
}
