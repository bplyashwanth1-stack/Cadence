import AppKit
import SwiftUI

// MARK: - Keyword bursts

/// A one-off screen effect set off by a sung word: "fire" throws up embers, "rain" brings rain, "love" floats hearts.
enum Burst {
    case fire, love, rain, stars, money, cold, flash

    private static let groups: [(Burst, [String])] = [
        (.fire, ["fire", "fires", "burn", "burning", "burned", "burnt", "flame", "flames", "blaze", "inferno", "lit",
                 "heat", "hot", "aag", "आग", "jal", "जल", "jalna", "जलना"]),
        (.love, ["love", "loved", "lover", "loving", "heart", "hearts", "kiss", "dil", "दिल", "pyaar", "pyar", "प्यार",
                 "ishq", "इश्क", "इश्क़", "mohabbat", "मोहब्बत", "jaan", "जान"]),
        (.rain, ["rain", "raining", "rainy", "cry", "crying", "cried", "tears", "tear", "drown", "drowning", "storm",
                 "baarish", "barish", "बारिश", "aansu", "आँसू", "आंसू"]),
        (.stars, ["star", "stars", "starlight", "galaxy", "shine", "shining", "sky", "heaven", "dream", "dreams",
                  "magic", "taare", "tare", "तारे", "sitare", "सितारे", "chand", "चाँद", "चांद", "aasman", "आसमान"]),
        (.money, ["money", "cash", "rich", "dollar", "dollars", "bands", "paisa", "पैसा"]),
        (.cold, ["cold", "ice", "frozen", "freeze", "snow", "winter", "thand", "ठंड"]),
        (.flash, ["lightning", "thunder", "electric", "shock", "flash", "explode", "boom", "bang", "bijli", "बिजली"]),
    ]

    private static let map: [String: Burst] = {
        var map: [String: Burst] = [:]
        for (kind, words) in groups {
            for word in words where map[word] == nil { map[word] = kind }
        }
        return map
    }()

    static func kind(for word: String) -> Burst? {
        let key = word.lowercased()
            .replacingOccurrences(of: "’", with: "'")
            .trimmingCharacters(in: CharacterSet.punctuationCharacters.union(.symbols).union(.whitespaces))
        return map[key] ?? map[Romanizer.latin(key)]
    }
}

struct KeywordBursts: View {
    let time: Double
    let palette: [NSColor]
    @ObservedObject private var player = NowPlaying.shared

    static let life = 2.6

    var body: some View {
        if let burst = player.bursts.last(where: { $0.start <= time }), time - burst.start < Self.life {
            BurstCanvas(kind: burst.kind, age: time - burst.start, seed: burst.index, palette: palette)
        }
    }
}

private struct BurstCanvas: View {
    let kind: Burst
    let age: Double
    let seed: Int
    let palette: [NSColor]

    var body: some View {
        // Snaps in, holds, then fades over the last 0.8 s.
        let envelope = min(1, age / 0.12) * min(1, max(0, (KeywordBursts.life - age) / 0.8))
        Canvas { ctx, size in
            ctx.opacity = envelope
            switch kind {
            case .fire: fire(ctx, size)
            case .love: symbols(ctx, size, "heart.fill", [.pink, Color(red: 1, green: 0.2, blue: 0.4), .red],
                                count: 24, rising: true)
            case .money: symbols(ctx, size, "dollarsign", [Color(red: 0.3, green: 0.95, blue: 0.5), .green],
                                 count: 30, rising: false)
            case .cold: symbols(ctx, size, "snowflake", [.white, Color(red: 0.75, green: 0.9, blue: 1)],
                                count: 50, rising: false)
            case .stars: sparkles(ctx, size)
            case .rain: rain(ctx, size)
            case .flash: flash(ctx, size)
            }
        }
        .allowsHitTesting(false)
    }

    private func r(_ i: Int, _ salt: Int) -> Double { noise(seed &* 131 &+ i, salt) }

    /// Symbols floating up from the bottom (hearts) or tumbling down from the top (money, snow).
    private func symbols(_ ctx: GraphicsContext, _ size: CGSize, _ name: String, _ colors: [Color], count: Int,
                         rising: Bool) {
        let images = colors.map { color -> GraphicsContext.ResolvedImage in
            var image = ctx.resolve(Image(systemName: name))
            image.shading = .color(color)
            return image
        }
        for i in 0..<count {
            let local = age - r(i, 1) * 0.6
            guard local > 0 else { continue }
            let speed = size.height * (0.28 + r(i, 2) * 0.3)
            let travel = local * speed
            let x = size.width * (0.05 + 0.9 * r(i, 3)) + sin(local * 2.5 + r(i, 4) * 6) * 36
            let y = rising ? size.height * 1.05 - travel : -40 + travel
            let side = 22 + r(i, 5) * 46
            let image = images[i % images.count]
            var c = ctx
            c.opacity *= min(1, local / 0.2) * (0.6 + 0.4 * r(i, 6))
            c.translateBy(x: x, y: y)
            c.rotate(by: .degrees(sin(local * 2 + r(i, 7) * 6) * 25))
            c.scaleBy(x: min(1, local / 0.25), y: min(1, local / 0.25))
            c.draw(image, in: CGRect(x: -side / 2, y: -side / 2, width: side, height: side))
        }
    }

    /// Sparkles popping up all over the screen and twinkling.
    private func sparkles(_ ctx: GraphicsContext, _ size: CGSize) {
        var white = ctx.resolve(Image(systemName: "sparkle"))
        white.shading = .color(.white)
        var gold = ctx.resolve(Image(systemName: "sparkle"))
        gold.shading = .color(Color(red: 1, green: 0.88, blue: 0.55))
        for i in 0..<36 {
            let local = age - r(i, 1) * 0.9
            guard local > 0 else { continue }
            let pop = min(1, local / 0.3)
            let twinkle = 0.55 + 0.45 * sin(local * 9 + r(i, 2) * 10)
            let side = (18 + r(i, 3) * 40) * pop * (0.8 + 0.2 * twinkle)
            let image = i % 3 == 0 ? gold : white
            var c = ctx
            c.opacity *= twinkle
            c.translateBy(x: size.width * r(i, 4), y: size.height * r(i, 5))
            c.rotate(by: .degrees(local * 40))
            c.draw(image, in: CGRect(x: -side / 2, y: -side / 2, width: side, height: side))
        }
    }

    /// A storm of slanted streaks with a cold tint.
    private func rain(_ ctx: GraphicsContext, _ size: CGSize) {
        ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(red: 0.3, green: 0.5, blue: 0.9).opacity(0.1)))
        for i in 0..<160 {
            let speed = size.height * (1.4 + r(i, 1) * 0.8)
            let length = 30 + r(i, 2) * 50
            let y = (r(i, 3) * size.height + age * speed).truncatingRemainder(dividingBy: size.height + length) - length
            let x = r(i, 4) * (size.width + 200) - 100 + y * 0.18
            var streak = Path()
            streak.move(to: CGPoint(x: x, y: y))
            streak.addLine(to: CGPoint(x: x + length * 0.18, y: y + length))
            ctx.stroke(streak, with: .color(.white.opacity(0.18 + 0.25 * r(i, 5))), lineWidth: 1.5)
        }
    }

    /// Embers shooting up with a hot glow rising from the bottom edge.
    private func fire(_ ctx: GraphicsContext, _ size: CGSize) {
        let hot = Color(nsColor: palette[0].blended(withFraction: 0.6, of: .orange) ?? .orange)
        let flicker = 0.8 + 0.2 * sin(age * 23)
        ctx.fill(Path(CGRect(x: 0, y: size.height * 0.45, width: size.width, height: size.height * 0.55)),
                 with: .linearGradient(Gradient(colors: [.clear, hot.opacity(0.25 * flicker), Color.orange.opacity(0.5 * flicker)]),
                                       startPoint: CGPoint(x: 0, y: size.height * 0.45),
                                       endPoint: CGPoint(x: 0, y: size.height)))
        for i in 0..<140 {
            let local = age - r(i, 1) * 0.5
            guard local > 0 else { continue }
            let speed = size.height * (0.35 + r(i, 2) * 0.6)
            let y = size.height + 10 - local * speed
            let x = size.width * r(i, 3) + sin(local * (3 + r(i, 4) * 3) + r(i, 5) * 9) * 40
            let radius = 1.5 + r(i, 6) * 3
            let glow = radius * 4
            let a = (0.6 + 0.4 * sin(local * 17 + r(i, 7) * 20)) * max(0, min(1, y / size.height * 1.4))
            ctx.fill(Path(ellipseIn: CGRect(x: x - glow, y: y - glow, width: glow * 2, height: glow * 2)),
                     with: .radialGradient(Gradient(colors: [hot.opacity(a * 0.6), hot.opacity(0)]),
                                           center: CGPoint(x: x, y: y), startRadius: 0, endRadius: glow))
            ctx.fill(Path(ellipseIn: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)),
                     with: .color(Color(red: 1, green: 0.9, blue: 0.7).opacity(a)))
        }
    }

    /// A white flash with a jagged lightning bolt that flickers out.
    private func flash(_ ctx: GraphicsContext, _ size: CGSize) {
        ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.white.opacity(0.55 * exp(-age * 7))))
        guard age < 0.45, Int(age * 30) % 3 != 2 else { return }
        var bolt = Path()
        var point = CGPoint(x: size.width * (0.2 + 0.6 * r(0, 1)), y: -10)
        bolt.move(to: point)
        var step = 0
        while point.y < size.height * 0.85 {
            step += 1
            point = CGPoint(x: point.x + (r(step, 2) - 0.5) * 140, y: point.y + 40 + r(step, 3) * 60)
            bolt.addLine(to: point)
        }
        ctx.stroke(bolt, with: .color(Color(red: 0.6, green: 0.8, blue: 1).opacity(0.3)),
                   style: StrokeStyle(lineWidth: 22, lineCap: .round, lineJoin: .round))
        ctx.stroke(bolt, with: .color(.white), style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
    }
}
