import AppKit
import CoreImage
import SwiftUI

// MARK: - Visuals

/// Generated wallpapers, in the style of live-wallpaper lyric edits: a purple nebula with neon comets, a voxel
/// landscape with a river, the artwork as a spinning storm, a chrome sculpture, a globe of dots, a hill of glowing
/// strands with a ring on the beat, the artwork smeared into motion blur, and a warm glow. They hit on the bass.
enum Visuals {
    static let kinds: [(tag: String, name: String)] = [
        ("nebula", "Nebula — purple space with neon comets"),
        ("voxel", "Voxel Land — a block landscape with a river"),
        ("vortex", "Vortex — the artwork as a spinning storm"),
        ("chrome", "Chrome — a spiky metal sculpture on blue"),
        ("dotsphere", "Dot Globe — a sphere of dots turning in the dark"),
        ("hill", "Particle Hill — glowing strands, a ring on the beat"),
        ("smear", "Smear — the artwork in a long motion blur"),
        ("sunset", "Sunset Glow — a soft warm gradient"),
        ("contours", "Contours — black and white bands winding together"),
        ("molten", "Molten — seams of lava between dark crust"),
        ("terraces", "Terraces — a topographic map in steps of blue"),
        ("silk", "Silk — pale fabric folding in the light"),
        ("ink", "Ink — drops of ink merging on paper"),
        ("tunnel", "Tunnel — neon rings rushing past"),
        ("wiresea", "Wire Sea — a wireframe ocean to the horizon"),
        ("city", "Night City — flying low over a block city"),
        ("ringed", "Ringed Planet — a planet in a ring of dust"),
        ("shoal", "Shoal — a school of fish under shafts of light"),
        ("warp", "Warp — stars streaking to light speed"),
        ("paperbird", "Paper Bird — a folded paper bird over low hills"),
        ("freefall", "Freefall — dropping between lit towers"),
        ("lighthall", "Light Hall — a corridor of glowing frames"),
        ("tvwall", "TV Wall — old TVs flicking between the cover and static"),
        ("lattice", "Neon Lattice — flying through a neon grid"),
        ("northern", "Northern Lights — aurora over a dark field"),
        ("dunes", "Neon Dunes — dunes at dusk traced in neon"),
        ("lagoon", "Glow Lagoon — glowing water, rings on the beat"),
        ("canyon", "Canyon — layered rock in rust and sand"),
        ("helix", "Helix — a spiral of blocks"),
        ("clockwork", "Clockwork — a clock ticking on the beat, with butterflies"),
        ("glassswirl", "Glass Swirl — ribbons of glass spiralling in"),
        ("gravitywell", "Gravity Well — light spiralling into a well"),
        ("woodgrain", "Wood Grain — polished rings and knots"),
    ]

    static let tags = Set(kinds.map(\.tag))

    /// The main hue of each scene that's a single strong colour, so it can be turned to the album's.
    /// Scenes made from the artwork, or whose colours are the point (lava, wood, paper), are left alone.
    private static let baseHue: [String: Double] = [
        "nebula": 0.75, "tunnel": 0.72, "lattice": 0.8, "wiresea": 0.53, "warp": 0.6, "gravitywell": 0.6,
        "hill": 0.53, "lagoon": 0.47, "northern": 0.42, "dunes": 0.85, "helix": 0.88, "chrome": 0.63,
        "terraces": 0.58, "shoal": 0.56, "city": 0.7, "ringed": 0.08, "dotsphere": 0, "lighthall": 0.1,
    ]

    /// How far to turn a scene's colours so its main hue matches the album's. Grey covers leave it be.
    static func tint(_ kind: String, toward palette: [NSColor]) -> Angle {
        guard let base = baseHue[kind], let first = palette.first,
              let c = first.usingColorSpace(.deviceRGB), c.saturationComponent > 0.25 else { return .zero }
        var turn = c.hueComponent - base
        if turn > 0.5 { turn -= 1 }
        if turn < -0.5 { turn += 1 }
        return .degrees(turn * 360)
    }

    /// How Visual Mix cycles. Neighbouring screens start three apart, so two displays never match.
    private static let order = ["nebula", "voxel", "contours", "vortex", "chrome", "tunnel", "dotsphere", "molten",
                                "hill", "city", "smear", "silk", "shoal", "warp", "terraces", "ringed", "ink",
                                "wiresea", "sunset", "lattice", "paperbird", "northern", "helix", "freefall",
                                "glassswirl", "dunes", "lighthall", "canyon", "gravitywell", "tvwall", "lagoon",
                                "woodgrain", "clockwork"]

    /// The visual showing on screen `screen` at `date`, and how freshly it cut in (1 at the cut, more on a drop,
    /// decaying), or nil when the background isn't one of these.
    static func scene(_ chosen: String, time: Double, date: Date, screen: Int) -> (tag: String, cut: Double)? {
        if tags.contains(chosen) { return (chosen, 0) }
        guard chosen == "visualmix" else { return nil }
        let director = VisualDirector.shared
        director.update(date: date, time: time)
        return (order[(director.scene + screen * 3) % order.count], director.flash(at: date))
    }
}

/// When Visual Mix cuts, like a reel edited to the track: on the beat, once a bar (every other beat in the
/// chorus), hard on a drop, and on the first beat of a new section. Without the audio it cuts every two lines.
/// Every layer and screen asks the same director, and it acts once per date, so they all cut together.
final class VisualDirector {
    static let shared = VisualDirector()

    private(set) var scene = 0
    private var cutAt = Date.distantPast
    private var bigCut = false
    private var lastDate = Date.distantPast
    private var trackID: String?
    private var line = -1
    private var section = 0
    private var sectionDue = false
    private var lastBeatSeen = Date.distantPast
    private var beatsSinceCut = 0
    private var levels: [Float] = []  // ~3 s of loudness, sampled at 30 per second
    private var lastLevel = Date.distantPast

    func update(date: Date, time: Double) {
        guard date > lastDate else { return }
        lastDate = date
        let player = NowPlaying.shared
        let index = player.lyrics.lastIndex { $0.start <= time } ?? -1
        if player.track?.id != trackID {
            trackID = player.track?.id
            scene = 0
            cutAt = .distantPast
            levels = []
            beatsSinceCut = 0
            line = index
            section = max(index, 0) / 4
            sectionDue = false
        }
        let newLine = index != line
        line = index
        if max(index, 0) / 4 != section {
            section = max(index, 0) / 4
            sectionDue = true
        }
        let chorus = index >= 0 && player.repeated.contains(index)
        let since = date.timeIntervalSince(cutAt)

        guard Style.shared.v.audioReactive, let audio = AudioPulse.shared.snapshot() else {
            // No beat to hear: cut as every second line starts.
            if newLine && index > 0 && index % 2 == 0 { cut(date, big: false) }
            return
        }
        // Loudness history at a steady rate, whichever layer is asking.
        if date.timeIntervalSince(lastLevel) >= 1 / 30.0 {
            lastLevel = date
            levels.append(audio.level)
            if levels.count > 90 { levels.removeFirst(levels.count - 90) }
        }
        guard audio.lastBeat > lastBeatSeen else {
            // A long stretch with no beat (a quiet bridge) still moves on, slowly.
            if since > 9 { cut(date, big: false) }
            return
        }
        lastBeatSeen = audio.lastBeat
        beatsSinceCut += 1
        let before = levels.prefix(max(levels.count - 15, 0))
        let quietBefore = before.count > 30 && before.reduce(0, +) / Float(before.count) < 0.4
        if quietBefore && audio.level > 0.7 && since > 0.6 {
            cut(date, big: true)  // the drop
        } else if sectionDue && since > 0.8 {
            cut(date, big: false)
        } else if beatsSinceCut >= (chorus ? 2 : 4) && since > (chorus ? 0.7 : 1.4) {
            cut(date, big: false)
        }
    }

    private func cut(_ date: Date, big: Bool) {
        scene += 1
        cutAt = date
        bigCut = big
        beatsSinceCut = 0
        sectionDue = false
    }

    /// 1 right at a cut, decaying: the white flash and the punch-in. A drop hits harder and longer.
    func flash(at date: Date) -> Double {
        let since = date.timeIntervalSince(cutAt)
        guard since >= 0 else { return 0 }
        return bigCut ? 1.4 * exp(-since * 2.5) : exp(-since * 5)
    }
}

func hexColor(_ value: UInt32, _ opacity: Double = 1) -> Color {
    Color(red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255,
          blue: Double(value & 0xFF) / 255).opacity(opacity)
}

private func mix(_ a: UInt32, _ b: UInt32, _ f: Double) -> Color {
    func ch(_ v: UInt32, _ s: UInt32) -> Double { Double((v >> s) & 0xFF) / 255 }
    let f = min(max(f, 0), 1)
    return Color(red: ch(a, 16) + (ch(b, 16) - ch(a, 16)) * f,
                 green: ch(a, 8) + (ch(b, 8) - ch(a, 8)) * f,
                 blue: ch(a, 0) + (ch(b, 0) - ch(a, 0)) * f)
}

private func frac(_ x: Double) -> Double { x - floor(x) }

private func wrapped(_ v: Double, _ m: Double) -> Double {
    let r = v.truncatingRemainder(dividingBy: m)
    return r < 0 ? r + m : r
}

/// The artwork run through Core Image once per song: twirled for the vortex, smeared for the motion blur.
enum ArtFX {
    private static let context = CIContext(options: [.useSoftwareRenderer: false])
    private static var cache: [String: NSImage] = [:]
    private static var order: [String] = []

    static func twirl(_ art: NSImage) -> NSImage? {
        processed(art, "twirl") { image, side in
            let saturated = image.applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 1.35,
                                                                                 kCIInputContrastKey: 1.1])
            return saturated.clampedToExtent().applyingFilter("CITwirlDistortion", parameters: [
                kCIInputCenterKey: CIVector(x: side / 2, y: side / 2),
                kCIInputRadiusKey: side / 2,
                kCIInputAngleKey: 7.5,
            ])
        }
    }

    static func smear(_ art: NSImage) -> NSImage? {
        processed(art, "smear") { image, _ in
            image.applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 1.5, kCIInputBrightnessKey: 0.04])
                .clampedToExtent()
                .applyingFilter("CIMotionBlur", parameters: [kCIInputRadiusKey: 70, kCIInputAngleKey: 0])
        }
    }

    private static func processed(_ art: NSImage, _ kind: String, _ make: (CIImage, Double) -> CIImage) -> NSImage? {
        let key = "\(kind)-\(ObjectIdentifier(art).hashValue)"
        if let hit = cache[key] { return hit }
        guard let cg = art.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        // Square, 900 px: enough for a full screen once it's spinning or blurred.
        let side = 900.0
        var image = CIImage(cgImage: cg)
        let scale = side / min(image.extent.width, image.extent.height)
        image = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        image = image.transformed(by: CGAffineTransform(translationX: -(image.extent.width - side) / 2 - image.extent.minX,
                                                        y: -(image.extent.height - side) / 2 - image.extent.minY))
        let frame = CGRect(x: 0, y: 0, width: side, height: side)
        let output = make(image.cropped(to: frame), side).cropped(to: frame)
        guard let result = context.createCGImage(output, from: frame) else { return nil }
        let made = NSImage(cgImage: result, size: NSSize(width: side, height: side))
        cache[key] = made
        order.append(key)
        if order.count > 6 { cache[order.removeFirst()] = nil }
        return made
    }
}

struct VisualScene: View {
    let kind: String
    let art: NSImage
    let size: CGSize
    let t: Double
    let motion: Double
    /// 0…1.4: the bass hit, plus a punch on each new line.
    let kick: Double
    /// Seconds since the last beat (or sung word, when Cadence can't hear the music).
    let beatAge: Double
    let bands: [Float]

    var speed: Double { 0.4 + motion }

    var body: some View {
        Group {
            switch kind {
            case "nebula": Canvas { ctx, size in nebula(&ctx, size) }
            case "voxel": Canvas { ctx, size in voxel(&ctx, size) }
            case "vortex": vortex
            case "chrome": Canvas { ctx, size in chrome(&ctx, size) }
            case "dotsphere": Canvas { ctx, size in dotSphere(&ctx, size) }
            case "hill": Canvas { ctx, size in hill(&ctx, size) }
            case "smear": smear
            case "contours": Canvas { ctx, size in contours(&ctx, size) }
            case "molten": Canvas { ctx, size in molten(&ctx, size) }
            case "terraces": Canvas { ctx, size in terraces(&ctx, size) }
            case "silk": Canvas { ctx, size in silk(&ctx, size) }
            case "ink": Canvas { ctx, size in ink(&ctx, size) }
            case "tunnel": Canvas { ctx, size in tunnel(&ctx, size) }
            case "wiresea": Canvas { ctx, size in wireSea(&ctx, size) }
            case "city": Canvas { ctx, size in city(&ctx, size) }
            case "ringed": Canvas { ctx, size in ringed(&ctx, size) }
            case "shoal": Canvas { ctx, size in school(&ctx, size) }
            case "warp": Canvas { ctx, size in warp(&ctx, size) }
            case "paperbird": Canvas { ctx, size in paperBird(&ctx, size) }
            case "freefall": Canvas { ctx, size in freefall(&ctx, size) }
            case "lighthall": Canvas { ctx, size in lightHall(&ctx, size) }
            case "tvwall": Canvas { ctx, size in tvWall(&ctx, size) }
            case "lattice": Canvas { ctx, size in neonLattice(&ctx, size) }
            case "northern": Canvas { ctx, size in northernLights(&ctx, size) }
            case "dunes": Canvas { ctx, size in neonDunes(&ctx, size) }
            case "lagoon": Canvas { ctx, size in glowLagoon(&ctx, size) }
            case "canyon": Canvas { ctx, size in canyon(&ctx, size) }
            case "helix": Canvas { ctx, size in helix(&ctx, size) }
            case "clockwork": Canvas { ctx, size in clockwork(&ctx, size) }
            case "glassswirl": Canvas { ctx, size in glassSwirl(&ctx, size) }
            case "gravitywell": Canvas { ctx, size in gravityWell(&ctx, size) }
            case "woodgrain": Canvas { ctx, size in woodGrain(&ctx, size) }
            default: Canvas { ctx, size in sunset(&ctx, size) }
            }
        }
        .frame(width: size.width, height: size.height)
        .clipped()
    }

    /// Spectrum band `i` of `count`, 0…1, or a gentle made-up one when the music can't be heard.
    func band(_ i: Int, of count: Int) -> Double {
        guard !bands.isEmpty else { return 0.3 + 0.25 * sin(t * 2.1 + Double(i) * 0.7) * kick }
        let index = min(bands.count - 1, max(0, i * bands.count / max(count, 1)))
        return Double(bands[index])
    }

    func soft(_ ctx: inout GraphicsContext, _ center: CGPoint, _ radius: Double, _ color: Color) {
        ctx.fill(Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)),
                 with: .radialGradient(Gradient(colors: [color, color.opacity(0.35), color.opacity(0)]),
                                       center: center, startRadius: 0, endRadius: radius))
    }

    // MARK: Nebula

    private func nebula(_ ctx: inout GraphicsContext, _ size: CGSize) {
        let w = size.width, h = size.height, big = max(w, h)
        ctx.fill(Path(CGRect(origin: .zero, size: size)),
                 with: .linearGradient(Gradient(colors: [hexColor(0x07021A), hexColor(0x170838), hexColor(0x060114)]),
                                       startPoint: .zero, endPoint: CGPoint(x: w, y: h)))
        ctx.blendMode = .screen
        let clouds: [(UInt32, Double)] = [(0x7A3BFF, 0.55), (0xB04DFF, 0.45), (0x4B2BD8, 0.5), (0xE070FF, 0.28),
                                          (0x5E1FB0, 0.6), (0x9B5CFF, 0.4), (0x3A1A9E, 0.5), (0xC77DFF, 0.3)]
        for (i, cloud) in clouds.enumerated() {
            let x = w * (0.1 + 0.8 * noise(i, 201)) + sin(t * 0.05 * speed + Double(i)) * w * 0.07
            let y = h * (0.05 + 0.9 * noise(i, 202)) + cos(t * 0.04 * speed + Double(i) * 1.7) * h * 0.07
            soft(&ctx, CGPoint(x: x, y: y), big * (0.2 + 0.24 * noise(i, 203)) * (1 + 0.06 * kick), hexColor(cloud.0, cloud.1))
        }
        // Wisps: soft blobs stretched into streaks, slowly turning.
        for i in 0..<7 {
            var layer = ctx
            layer.translateBy(x: w * (0.15 + 0.7 * noise(i, 204)), y: h * (0.1 + 0.8 * noise(i, 205)))
            layer.rotate(by: .radians(noise(i, 206) * .pi + sin(t * 0.03 + Double(i)) * 0.2))
            layer.scaleBy(x: 1, y: 0.18 + 0.15 * noise(i, 207))
            soft(&layer, .zero, big * (0.12 + 0.12 * noise(i, 208)), hexColor(i % 2 == 0 ? 0xD9A6FF : 0x8F6BFF, 0.35))
        }
        ctx.blendMode = .normal

        // Star dust: fine speckle everywhere, plus brighter stars that twinkle, drifting slowly sideways.
        for bucket in 0..<4 {
            var path = Path()
            for i in stride(from: bucket, to: 1400, by: 4) {
                let x = wrapped(noise(i, 210) * w + t * (3 + 9 * noise(i, 212)) * speed, w)
                let y = noise(i, 211) * h
                let r = i % 9 == 0 ? 1.1 + 1.2 * noise(i, 213) : 0.5 + 0.5 * noise(i, 213)
                path.addEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
            }
            let twinkle = 0.35 + 0.25 * sin(t * (1.3 + Double(bucket) * 0.7) + Double(bucket))
            ctx.fill(path, with: .color(.white.opacity(twinkle + 0.1 * kick)))
        }

        // Drifting rocks.
        for i in 0..<12 {
            let x = wrapped(noise(i, 220) * w * 1.2 - t * (6 + 10 * noise(i, 221)) * speed, w * 1.2) - w * 0.1
            let y = h * (0.2 + 0.7 * noise(i, 222)) + sin(t * 0.3 + Double(i)) * 8
            let r = 4 + 9 * noise(i, 223)
            var rock = Path()
            for k in 0..<7 {
                let a = Double(k) / 7 * 2 * .pi + t * 0.2 * (noise(i, 224) - 0.5)
                let rr = r * (0.7 + 0.5 * noise(i &* 7 &+ k, 225))
                let p = CGPoint(x: x + cos(a) * rr, y: y + sin(a) * rr)
                if k == 0 { rock.move(to: p) } else { rock.addLine(to: p) }
            }
            rock.closeSubpath()
            ctx.fill(rock, with: .color(hexColor(0x6F6A9E, 0.75)))
        }

        // Neon comets streaking up and to the right, leaving long glowing tails.
        let comets: [UInt32] = [0xFF6AD5, 0x8CFF5A, 0x6AE8FF]
        for (k, color) in comets.enumerated() {
            let angle = [-0.55, -0.3, -0.42][k]
            let direction = CGVector(dx: cos(angle), dy: sin(angle))
            let period = 6.5 + Double(k) * 1.3
            let u = frac((t * speed + Double(k) * 2.4) / period)
            let fade = min(1, u * 6) * min(1, (1 - u) * 5)
            guard fade > 0 else { continue }
            let start = CGPoint(x: w * [-0.05, 0.05, -0.15][k], y: h * [1.05, 0.98, 0.7][k])
            let travel = big * 1.1 * (1 - pow(1 - u, 2))
            let head = CGPoint(x: start.x + direction.dx * travel, y: start.y + direction.dy * travel)
            let tailLength = big * 0.5
            let tail = CGPoint(x: head.x - direction.dx * tailLength, y: head.y - direction.dy * tailLength)
            var line = Path()
            line.move(to: tail)
            line.addLine(to: head)
            let width = 4.5 * (1 + 0.6 * kick)
            for (spread, alpha) in [(6.0, 0.08), (3.0, 0.18), (1.0, 0.95)] {
                ctx.stroke(line, with: .linearGradient(Gradient(colors: [hexColor(color, 0), hexColor(color, alpha * fade)]),
                                                       startPoint: tail, endPoint: head),
                           style: StrokeStyle(lineWidth: width * spread, lineCap: .round))
            }
            soft(&ctx, head, 18 * (1 + kick), Color.white.opacity(0.8 * fade))
            // Sparks shed behind the head.
            for s in 0..<6 {
                let back = Double(s) * 22 + frac(t * 3 + Double(s) * 0.17) * 22
                let p = CGPoint(x: head.x - direction.dx * back + (noise(s &+ k &* 10, 226) - 0.5) * 18,
                                y: head.y - direction.dy * back + (noise(s &+ k &* 10, 227) - 0.5) * 18)
                ctx.fill(Path(ellipseIn: CGRect(x: p.x - 1.5, y: p.y - 1.5, width: 3, height: 3)),
                         with: .color(hexColor(color, 0.8 * fade)))
            }
        }
    }

    // MARK: Voxel land

    private func voxel(_ ctx: inout GraphicsContext, _ size: CGSize) {
        let w = size.width, h = size.height
        ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(hexColor(0x8EDFD8)))
        let base = w / 46  // a near block's width
        let flow = t * 1.6 * speed
        let lift = 1 + 0.3 * min(kick, 1.2)
        let topColors: [Color] = (0..<10).map { mix(0x0B7F8C, 0xE4FBF6, pow(Double($0) / 9, 0.8)) }
        let sideColors: [Color] = (0..<10).map { mix(0x04414A, 0x4FA7A6, Double($0) / 9) }
        let river = hexColor(0xF2D33E), riverLight = hexColor(0xFFE97A), riverSide = hexColor(0xA88B12)

        // Rows from the far edge (top) to the near edge (bottom), so nearer blocks cover farther ones.
        var y = -base * 1.5
        var z = 0
        while y < h + base * 2 {
            let depth = min(1, y / h)
            let scale = 0.42 + 0.58 * max(depth, 0)
            let cell = base * scale
            let rowZ = Double(z) - flow
            let riverX = 0.5 + 0.2 * sin(rowZ * 0.07) + 0.09 * sin(rowZ * 0.023 + 1.3)
            var tops = [Path](repeating: Path(), count: 10)
            var sides = [Path](repeating: Path(), count: 10)
            var riverTop = Path(), riverShine = Path(), riverSides = Path()
            let count = Int(w / cell) + 2
            let offset = (w - Double(count) * cell) / 2
            for c in 0..<count {
                let x = offset + Double(c) * cell
                let u = x / w
                let gx = (x - w / 2) / base
                var height = 0.5 + 0.28 * sin(gx * 0.17 + rowZ * 0.09 + t * 0.15)
                    + 0.2 * sin(gx * 0.06 - rowZ * 0.13) + 0.12 * sin((gx + rowZ) * 0.31)
                height += 0.35 * band(c * 32 / max(count, 1), of: 32) * depth
                let inRiver = abs(u - riverX) < 0.035 + 0.01 * sin(rowZ * 0.2)
                if inRiver { height = 0.15 + 0.05 * sin(t * 2 + gx) }
                let rise = max(height, 0.05) * cell * 1.8 * lift
                // Tops inset a hair, so the darker sides show between them and every block reads on its own.
                let gap = max(0.8, cell * 0.06)
                let top = CGRect(x: x + gap / 2, y: y - rise + gap / 2, width: cell - gap, height: cell * 0.62 - gap)
                let side = CGRect(x: x, y: y - rise, width: cell + 0.5, height: rise + cell * 0.82)
                if inRiver {
                    if noise(c &+ z &* 131 &+ Int(t * 4), 230) > 0.8 { riverShine.addRect(top) } else { riverTop.addRect(top) }
                    riverSides.addRect(side)
                } else {
                    let shade = min(9, max(0, Int(height * 9.5)))
                    tops[shade].addRect(top)
                    sides[shade].addRect(side)
                }
            }
            for i in 0..<10 where !sides[i].isEmpty { ctx.fill(sides[i], with: .color(sideColors[i])) }
            ctx.fill(riverSides, with: .color(riverSide))
            for i in 0..<10 where !tops[i].isEmpty { ctx.fill(tops[i], with: .color(topColors[i])) }
            ctx.fill(riverTop, with: .color(river))
            ctx.fill(riverShine, with: .color(riverLight))
            y += cell * 0.62
            z += 1
        }
        // Haze over the distance and pink mist drifting across.
        ctx.fill(Path(CGRect(x: 0, y: 0, width: w, height: h * 0.45)),
                 with: .linearGradient(Gradient(colors: [hexColor(0xBFF2EC, 0.55), hexColor(0xBFF2EC, 0)]),
                                       startPoint: .zero, endPoint: CGPoint(x: 0, y: h * 0.45)))
        ctx.blendMode = .screen
        for i in 0..<3 {
            let x = w * (0.3 + 0.5 * noise(i, 231)) + sin(t * 0.2 + Double(i) * 2) * w * 0.15
            let y2 = h * (0.25 + 0.4 * noise(i, 232)) + cos(t * 0.17 + Double(i)) * h * 0.1
            soft(&ctx, CGPoint(x: x, y: y2), w * 0.12 * (1 + 0.3 * kick), hexColor(0xFF9CC2, 0.35))
        }
    }

    // MARK: Vortex

    private var vortex: some View {
        let cover = (size.width * size.width + size.height * size.height).squareRoot() * 1.18
        let side = min(size.width, size.height)
        return ZStack {
            Color.black
            if let twirled = ArtFX.twirl(art) {
                Image(nsImage: twirled)
                    .resizable()
                    .frame(width: cover, height: cover)
                    .rotationEffect(.radians(-t * 0.35 * speed))
                    .scaleEffect(1 + 0.06 * kick)
                Image(nsImage: twirled)
                    .resizable()
                    .frame(width: cover, height: cover)
                    .rotationEffect(.radians(-t * 0.6 * speed + 1.3))
                    .scaleEffect(0.7)
                    .opacity(0.45)
                    .blendMode(.screen)
                    .mask(RadialGradient(colors: [.white, .clear], center: .center, startRadius: 0, endRadius: side * 0.55))
            }
            // The eye of the storm glows on the beat.
            RadialGradient(colors: [hexColor(0xFF7A2E, 0.55 + 0.3 * kick), .clear], center: .center,
                           startRadius: 0, endRadius: side * 0.35)
                .blendMode(.screen)
            // A small ring of beads circling the eye.
            Canvas { ctx, size in
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let r = side * 0.045 * (1 + 0.2 * kick)
                for i in 0..<9 {
                    let a = Double(i) / 9 * 2 * .pi + t * 1.4
                    let p = CGPoint(x: center.x + cos(a) * r, y: center.y + sin(a) * r)
                    let dot = r * 0.32
                    ctx.fill(Path(ellipseIn: CGRect(x: p.x - dot, y: p.y - dot, width: dot * 2, height: dot * 2)),
                             with: .color(.black.opacity(0.85)))
                }
            }
        }
    }

    // MARK: Chrome

    private func chrome(_ ctx: inout GraphicsContext, _ size: CGSize) {
        let w = size.width, h = size.height
        let center = CGPoint(x: w * 0.66, y: h * 0.47)
        ctx.fill(Path(CGRect(origin: .zero, size: size)),
                 with: .radialGradient(Gradient(colors: [hexColor(0x1F45E8), hexColor(0x0B1F95), hexColor(0x030A3C)]),
                                       center: center, startRadius: 0, endRadius: max(w, h) * 0.8))
        let r = min(w, h) * 0.16 * (1 + 0.08 * kick)
        ctx.blendMode = .screen
        soft(&ctx, center, r * 3.2, hexColor(0x5C7CFF, 0.5 + 0.25 * kick))
        ctx.blendMode = .normal

        let yaw = t * 0.4 * speed, pitch = 0.35 * sin(t * 0.23)
        func rotate(_ v: (Double, Double, Double)) -> (Double, Double, Double) {
            let x1 = v.0 * cos(yaw) + v.2 * sin(yaw), z1 = -v.0 * sin(yaw) + v.2 * cos(yaw)
            let y2 = v.1 * cos(pitch) - z1 * sin(pitch), z2 = v.1 * sin(pitch) + z1 * cos(pitch)
            return (x1, y2, z2)
        }
        func point(_ v: (Double, Double, Double), _ length: Double) -> CGPoint {
            let persp = 1 + v.2 * 0.18
            return CGPoint(x: center.x + v.0 * length * persp, y: center.y + v.1 * length * persp)
        }
        // Spikes along a Fibonacci sphere and a few rounded lumps, drawn back to front.
        enum Part { case spike(Int), lump(Int) }
        var parts: [(z: Double, dir: (Double, Double, Double), part: Part)] = []
        let spikes = 22
        for i in 0..<spikes {
            let yy = 1 - 2 * (Double(i) + 0.5) / Double(spikes)
            let ring = (1 - yy * yy).squareRoot()
            let a = Double(i) * 2.399963
            let d = rotate((ring * cos(a), yy, ring * sin(a)))
            parts.append((d.2, d, .spike(i)))
        }
        for i in 0..<11 {
            let a = Double(i) * 0.9 + 0.3, b = noise(i, 240) * 2 - 1
            let ring = (1 - b * b).squareRoot()
            let d = rotate((ring * cos(a), b, ring * sin(a)))
            parts.append((d.2, d, .lump(i)))
        }
        parts.sort { $0.z < $1.z }
        let dark = hexColor(0x050A38), mid = hexColor(0x3352E0), light = hexColor(0xF2F6FF)
        var drewCore = false
        for item in parts {
            if !drewCore && item.z > -0.1 {
                drewCore = true
                let core = CGRect(x: center.x - r * 0.7, y: center.y - r * 0.7, width: r * 1.4, height: r * 1.4)
                ctx.fill(Path(ellipseIn: core), with: .radialGradient(
                    Gradient(colors: [light, mid, dark]), center: CGPoint(x: center.x - r * 0.25, y: center.y - r * 0.3),
                    startRadius: 0, endRadius: r * 0.9))
            }
            let d = item.dir
            let lit = 0.5 + 0.5 * max(-1, min(1, -0.5 * d.0 - 0.6 * d.1 + 0.6 * d.2))
            switch item.part {
            case .spike(let i):
                let length = r * (0.75 + 0.9 * noise(i, 241)) * (1 + 0.45 * min(kick, 1.2) * noise(i, 242))
                let baseCenter = point(d, r * 0.55)
                let tip = point(d, r * 0.55 + length)
                let dx = tip.x - baseCenter.x, dy = tip.y - baseCenter.y
                let len = max((dx * dx + dy * dy).squareRoot(), 0.001)
                let half = r * 0.22
                let px = -dy / len * half, py = dx / len * half
                var spike = Path()
                spike.move(to: CGPoint(x: baseCenter.x + px, y: baseCenter.y + py))
                spike.addLine(to: tip)
                spike.addLine(to: CGPoint(x: baseCenter.x - px, y: baseCenter.y - py))
                spike.closeSubpath()
                ctx.fill(spike, with: .linearGradient(
                    Gradient(colors: [dark, mid.opacity(0.9), light.opacity(0.4 + 0.6 * lit), mid, dark]),
                    startPoint: CGPoint(x: baseCenter.x + px, y: baseCenter.y + py),
                    endPoint: CGPoint(x: baseCenter.x - px, y: baseCenter.y - py)))
            case .lump(let i):
                let c = point(d, r * 0.62)
                let lr = r * (0.3 + 0.18 * noise(i, 243)) * (1 + 0.1 * d.2)
                ctx.fill(Path(ellipseIn: CGRect(x: c.x - lr, y: c.y - lr, width: lr * 2, height: lr * 2)),
                         with: .radialGradient(Gradient(colors: [light.opacity(0.5 + 0.5 * lit), mid, dark]),
                                               center: CGPoint(x: c.x - lr * 0.35, y: c.y - lr * 0.4),
                                               startRadius: 0, endRadius: lr * 1.1))
            }
        }
        // Glints.
        ctx.blendMode = .screen
        for i in 0..<5 {
            let a = t * 0.8 + Double(i) * 1.26
            let p = CGPoint(x: center.x + cos(a) * r * 0.7, y: center.y + sin(a * 1.3) * r * 0.6)
            soft(&ctx, p, r * 0.12 * (1 + kick), Color.white.opacity(0.7))
        }
    }

    // MARK: Dot globe

    private func dotSphere(_ ctx: inout GraphicsContext, _ size: CGSize) {
        let w = size.width, h = size.height
        ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.black))
        let center = CGPoint(x: w * 0.64, y: h * 0.52)
        let radius = h * 0.38 * (1 + 0.04 * kick)
        let spin = t * 0.25 * speed, tilt = 0.32
        let dent = (x: 0.0, y: -0.82, z: 0.57)  // a dimple near the top, like a pressed ball
        var buckets = [Path](repeating: Path(), count: 8)
        let rows = 78
        for row in 0..<rows {
            let lat = (Double(row) + 0.5) / Double(rows) * .pi - .pi / 2
            let ring = cos(lat)
            let count = max(6, Int(ring * 160))
            let swell = 1 + 0.05 * band(row * 32 / rows, of: 32)
            for k in 0..<count {
                let lon = Double(k) / Double(count) * 2 * .pi + spin
                var x = ring * sin(lon), y = sin(lat), z = ring * cos(lon)
                let y2 = y * cos(tilt) - z * sin(tilt)
                z = y * sin(tilt) + z * cos(tilt)
                y = y2
                guard z > -0.05 else { continue }
                let toDent = (x - dent.x) * (x - dent.x) + (y - dent.y) * (y - dent.y) + (z - dent.z) * (z - dent.z)
                let pressed = exp(-toDent * 40)
                let r = radius * swell * (1 - 0.08 * pressed)
                x *= r; y *= r
                let light = (0.3 + 0.7 * max(0, -0.3 * x / r - 0.4 * y / r + 0.87 * z)) * (1 - 0.92 * pressed)
                let bucket = min(7, Int(light * 8))
                let dot = (0.7 + 1.8 * light) * radius / 380
                buckets[bucket].addEllipse(in: CGRect(x: center.x + x - dot, y: center.y + y - dot, width: dot * 2, height: dot * 2))
            }
        }
        for i in 0..<8 where !buckets[i].isEmpty {
            ctx.fill(buckets[i], with: .color(Color(white: 0.95).opacity(0.18 + 0.82 * Double(i) / 7)))
        }
    }

    // MARK: Particle hill

    private func hill(_ ctx: inout GraphicsContext, _ size: CGSize) {
        let w = size.width, h = size.height
        ctx.fill(Path(CGRect(origin: .zero, size: size)),
                 with: .linearGradient(Gradient(colors: [hexColor(0x03050C), hexColor(0x081422), hexColor(0x0C1F33)]),
                                       startPoint: .zero, endPoint: CGPoint(x: 0, y: h)))
        let groundY = h * 0.66
        let ringCenter = CGPoint(x: w * 0.5, y: groundY - h * 0.02)

        // A glowing ring that goes out from the mound on every beat, behind the near strands.
        func ring(_ radius: Double, _ alpha: Double) {
            let rect = CGRect(x: ringCenter.x - radius, y: ringCenter.y - radius * 0.42, width: radius * 2, height: radius * 0.84)
            let scale = max(0.6, radius / (size.width * 0.13))
            for (width, a) in [(90.0, 0.07), (54.0, 0.14), (30.0, 0.3), (14.0, 0.6), (5.0, 1.0)] {
                ctx.stroke(Path(ellipseIn: rect), with: .color(hexColor(0x3BE8FF, a * alpha)), lineWidth: width * scale)
            }
        }
        ctx.blendMode = .screen
        ring(w * 0.13 * (1 + 0.08 * kick), 0.85)
        let age = beatAge
        if age < 1.4 { ring(w * (0.13 + age * 0.35), max(0, 1 - age / 1.4)) }

        // Strands rising from the mound, coloured by height, swaying a little.
        var buckets = [Path](repeating: Path(), count: 8)
        let rows = 46, columns = 110
        for row in 0..<rows {
            let zf = Double(row) / Double(rows - 1)  // 0 far, 1 near
            let persp = 0.55 + 0.6 * zf
            let baseY = h * 0.38 + zf * h * 0.5
            for c in 0..<columns {
                let jitter = noise(c &+ row &* 997, 250)
                let xf = (Double(c) + jitter) / Double(columns) * 2 - 1
                let dz = (zf - 0.45) / 0.38, dx = xf / 0.6
                let mound = exp(-(dx * dx + dz * dz) * 1.4)
                let audio = band(c * 32 / columns, of: 32)
                let tall = (0.04 + mound * (0.75 + 0.45 * audio)) * (0.55 + 0.45 * noise(c &+ row &* 31, 251))
                let x = w / 2 + xf * w * 0.62 * persp
                let length = tall * h * 0.42 * persp * (1 + 0.15 * kick)
                let sway = sin(t * 1.3 + Double(c) * 0.4 + Double(row) * 0.2) * 3 * tall
                var strand = Path()
                strand.move(to: CGPoint(x: x, y: baseY))
                strand.addLine(to: CGPoint(x: x + sway, y: baseY - length))
                buckets[min(7, Int(tall * 9))].addPath(strand)
            }
        }
        ctx.blendMode = .normal
        for i in 0..<8 where !buckets[i].isEmpty {
            ctx.stroke(buckets[i], with: .color(mix(0x123A5E, 0x9CEBF7, Double(i) / 7).opacity(0.55 + 0.05 * Double(i))),
                       lineWidth: 1.6)
        }
        // Pink light on the summit, drifting.
        ctx.blendMode = .screen
        let glow = CGPoint(x: w * (0.5 + 0.08 * sin(t * 0.3)), y: h * (0.42 + 0.03 * cos(t * 0.4)))
        soft(&ctx, glow, w * 0.14 * (1 + 0.2 * kick), hexColor(0xFF8CC0, 0.6))
        soft(&ctx, ringCenter, w * 0.1, hexColor(0x3BE8FF, 0.25 + 0.2 * kick))
    }

    // MARK: Smear

    private var smear: some View {
        let w = size.width, h = size.height
        return ZStack {
            Color(nsColor: .black)
            if let smeared = ArtFX.smear(art) {
                Image(nsImage: smeared)
                    .resizable()
                    .frame(width: w * 1.8, height: h * 1.15)
                    .offset(x: sin(t * 0.22 * speed) * w * 0.3, y: sin(t * 0.13) * h * 0.04)
                    .scaleEffect(1 + 0.05 * kick)
                Image(nsImage: smeared)
                    .resizable()
                    .frame(width: w * 2.4, height: h * 0.5)
                    .offset(x: -sin(t * 0.3 * speed + 1) * w * 0.4, y: h * 0.06 * sin(t * 0.2))
                    .blendMode(.screen)
                    .opacity(0.55)
                    .mask(LinearGradient(colors: [.clear, .white, .clear], startPoint: .top, endPoint: .bottom))
            }
        }
    }

    // MARK: Sunset glow

    private func sunset(_ ctx: inout GraphicsContext, _ size: CGSize) {
        let w = size.width, h = size.height, big = max(w, h)
        ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(hexColor(0x3A1366)))
        ctx.blendMode = .screen
        let blobs: [(UInt32, Double, Double)] = [(0xFF7A3D, 0.15, 0.25), (0xFF3D8B, 0.55, 0.45), (0x8E3DFF, 0.85, 0.3),
                                                 (0x3D5BFF, 0.8, 0.85), (0xFF9F45, 0.25, 0.8), (0xE83DFF, 0.45, 0.1)]
        for (i, blob) in blobs.enumerated() {
            let x = w * blob.1 + sin(t * 0.07 * speed + Double(i) * 1.9) * w * 0.12
            let y = h * blob.2 + cos(t * 0.06 * speed + Double(i) * 1.3) * h * 0.12
            soft(&ctx, CGPoint(x: x, y: y), big * 0.42 * (1 + 0.05 * kick), hexColor(blob.0, 0.85))
        }
    }
}
