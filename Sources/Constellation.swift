import SwiftUI

// MARK: - Constellation layout

/// Sung words become stars joined up into a constellation. The word being sung is large, then shrinks into a small
/// label beside its star as the next one lights up. Everything is worked out from the playback time, so seeking and
/// scrubbing need no state.
enum Constellation {
    /// Words per sky before it clears, however long the lines are.
    static let maxWords = 14
    private static let linesPerSky = 2

    /// The words sharing a sky with word `index`: two lyric lines, split up if they run long.
    static func page(around index: Int, wordLines: [Int], wordCount: Int) -> Range<Int> {
        guard index >= 0, index < wordCount, wordLines.count >= wordCount else { return 0..<0 }
        let group = { (i: Int) in wordLines[i] / linesPerSky }
        var first = index
        while first > 0 && group(first - 1) == group(index) { first -= 1 }
        var end = index + 1
        while end < wordCount && group(end) == group(index) { end += 1 }
        let start = first + (index - first) / maxWords * maxWords
        return start..<min(end, start + maxWords)
    }

    /// Scattered positions in 0...1 for `count` stars: one per cell of a grid, in shuffled order, so they spread
    /// across the sky without landing on top of each other, and the lines between them cross like a real chart.
    static func points(count: Int, seed: Int) -> [CGPoint] {
        guard count > 0 else { return [] }
        let columns = max(2, Int(ceil((Double(count) * 1.8).squareRoot())))
        let rows = max(2, Int(ceil(Double(count) * 1.25 / Double(columns))))
        var cells = Array(0..<(columns * rows))
        for i in stride(from: cells.count - 1, to: 0, by: -1) {
            cells.swapAt(i, Int(noise(seed &+ i, 61) * Double(i + 1)))
        }
        return (0..<count).map { i in
            let cell = cells[i]
            let jitterX = (noise(seed &+ i, 62) - 0.5) * 0.6
            let jitterY = (noise(seed &+ i, 63) - 0.5) * 0.6
            return CGPoint(x: (Double(cell % columns) + 0.5 + jitterX) / Double(columns),
                           y: (Double(cell / columns) + 0.5 + jitterY) / Double(rows))
        }
    }

    /// A four-pointed sparkle.
    static func star(at center: CGPoint, radius: Double) -> Path {
        var path = Path()
        let waist = radius * 0.2
        for i in 0..<8 {
            let angle = Double(i) * .pi / 4 - .pi / 2
            let r = i.isMultiple(of: 2) ? radius : waist
            let point = CGPoint(x: center.x + cos(angle) * r, y: center.y + sin(angle) * r)
            if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }
}

private func clamp01(_ x: Double) -> Double { min(max(x, 0), 1) }
private func easeOut(_ x: Double) -> Double { 1 - pow(1 - clamp01(x), 3) }

struct ConstellationView: View {
    let time: Double
    let date: Date
    @ObservedObject private var style = Style.shared
    @ObservedObject private var player = NowPlaying.shared

    var body: some View {
        let s = style.v
        let words = player.words
        let lines = player.wordLines
        let index = words.lastIndex { $0.start <= time } ?? -1
        let t = date.timeIntervalSinceReferenceDate
        let kick = s.beatZoom ? player.kick(at: time, date: date) : 0

        Canvas { context, size in
            let page = Constellation.page(around: index, wordLines: lines, wordCount: words.count)
            guard !page.isEmpty else { return }
            // The last sky fades out as the new one starts drawing.
            if page.lowerBound > 0 {
                let leaving = 1 - (time - words[page.lowerBound].start) / 0.5
                if leaving > 0 {
                    let last = Constellation.page(around: page.lowerBound - 1, wordLines: lines, wordCount: words.count)
                    draw(last, words, index: page.lowerBound - 1, nextStart: words[page.lowerBound].start, opacity: leaving,
                         kick: 0, t: t, s, context, size)
                }
            }
            // Clear the sky during a long instrumental gap rather than leave a stale verse up.
            let untilNext = index + 1 < words.count ? words[index + 1].start - time : .infinity
            let quiet = untilNext > 1.5 ? clamp01((time - words[index].end - 3) / 0.6) : 0
            let nextStart = index + 1 < words.count ? words[index + 1].start : .infinity
            draw(page, words, index: index, nextStart: nextStart, opacity: 1 - quiet, kick: kick, t: t, s, context, size)
        }
        .drawingGroup()
        .shadow(color: .black.opacity(0.45), radius: 8, y: 2)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func draw(_ page: Range<Int>, _ words: [Word], index: Int, nextStart: Double, opacity: Double, kick: Double,
                      t: Double, _ s: StyleValues, _ context: GraphicsContext, _ size: CGSize) {
        guard opacity > 0 else { return }
        var context = context
        context.opacity = opacity
        let color = s.glowColor(player.palette, onStage: true)
        let bigSize = s.stageFontSize * 0.46
        let smallScale = max(0.34, 19 / max(bigSize, 1))
        let inset = size.height * 0.1
        let field = CGRect(x: inset, y: inset, width: max(size.width - inset * 2, 1), height: max(size.height - inset * 2, 1))
        let seed = page.lowerBound
        let points = Constellation.points(count: page.count, seed: seed).enumerated().map { i, p -> CGPoint in
            let drift = s.stageDrift ? 7.0 : 0
            let phase = noise(seed &+ i, 64) * .pi * 2
            return CGPoint(x: field.minX + p.x * field.width + sin(t * 0.32 + phase) * drift,
                           y: field.minY + p.y * field.height + cos(t * 0.27 + phase) * drift)
        }
        let shown = page.lowerBound...min(index, page.upperBound - 1)

        // Lines first, so stars and words sit on top. Each draws out from the star before it as its word starts.
        for i in shown where i > page.lowerBound {
            let reach = easeOut((time - words[i].start) / 0.3)
            let target = points[i - page.lowerBound]
            var links = [points[i - page.lowerBound - 1]]
            // A few extra links turn the chain into a web.
            if i - 2 >= page.lowerBound && noise(seed &+ i, 65) < 0.4 { links.append(points[i - page.lowerBound - 2]) }
            for from in links {
                var line = Path()
                line.move(to: from)
                line.addLine(to: CGPoint(x: from.x + (target.x - from.x) * reach, y: from.y + (target.y - from.y) * reach))
                context.stroke(line, with: .color(color.opacity(0.5)), lineWidth: 1.25)
            }
        }

        for i in shown {
            let point = points[i - page.lowerBound]
            let appear = easeOut((time - words[i].start) / 0.25)
            // 1 while being sung, falling to 0 once the next word has taken over.
            let next = i + 1 < page.upperBound ? words[i + 1].start : (i == index ? nextStart : words[i].end)
            let focus = 1 - easeOut((time - next) / 0.35)

            let twinkle = 0.85 + 0.15 * sin(t * 2.4 + Double(i))
            let radius = (6 + 13 * focus * (1 + 0.35 * kick)) * twinkle * appear
            context.fill(Constellation.star(at: point, radius: radius), with: .color(color))

            let font = s.font(size: bigSize)
            var text = context.resolve(Text(s.display(words[i].text)).font(font))
            text.shading = .color(color.opacity(0.62 + 0.38 * focus))
            let measured = text.measure(in: CGSize(width: size.width, height: size.height))
            let scale = (smallScale + (1 - smallScale) * focus) * (0.8 + 0.2 * appear)
            let width = measured.width * scale, height = measured.height * scale
            // Beside the star, kept fully on screen.
            let side = noise(seed &+ i, 66) < 0.5 ? -1.0 : 1.0
            let x = min(max(point.x + side * (width / 2 + 12), width / 2), size.width - width / 2)
            let y = min(max(point.y - height * 0.6 - 6, height / 2), size.height - height / 2)

            var layer = context
            layer.opacity = opacity * appear
            layer.translateBy(x: x, y: y)
            layer.scaleBy(x: scale, y: scale)
            layer.draw(text, at: .zero, anchor: .center)
        }
    }
}
