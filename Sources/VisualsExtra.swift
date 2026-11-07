import AppKit
import SwiftUI

// MARK: - Extra visuals

/// Journeys, rooms, landscapes and sculptures: paper bird, freefall, light hall, TV wall, neon lattice, northern
/// lights, neon dunes, glow lagoon, canyon, helix, clockwork, glass swirl, gravity well and wood grain.

private func frac(_ x: Double) -> Double { x - floor(x) }

private func smooth(_ a: Double, _ b: Double, _ x: Double) -> Double {
    let t = min(max((x - a) / (b - a), 0), 1)
    return t * t * (3 - 2 * t)
}

extension VisualScene {
    private func backdrop(_ ctx: inout GraphicsContext, _ size: CGSize, _ colors: [UInt32]) {
        ctx.fill(Path(CGRect(origin: .zero, size: size)),
                 with: .linearGradient(Gradient(colors: colors.map { hexColor($0) }),
                                       startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
    }

    /// Beats so far: the count steps on every hit, so things can change on the beat.
    private var beatCount: Int { Int(floor(BeatClock.shared.travel(at: Date()))) }

    // MARK: Paper bird

    /// A folded paper bird gliding over low-poly hills at dusk, flapping harder on the beat.
    func paperBird(_ ctx: inout GraphicsContext, _ size: CGSize) {
        let w = size.width, h = size.height
        backdrop(&ctx, size, [0x2B3A6B, 0xC86B85, 0xF4B58A])
        ctx.blendMode = .screen
        soft(&ctx, CGPoint(x: w * 0.72, y: h * 0.5), h * 0.35, hexColor(0xFFE0B0, 0.6))
        ctx.blendMode = .normal
        // Hills in layers, nearer ones darker and faster.
        let layers: [(UInt32, Double, Double)] = [(0x8A6A9E, 0.55, 0.15), (0x5E4C86, 0.63, 0.3), (0x3A325E, 0.72, 0.55),
                                                  (0x211C3A, 0.84, 0.9)]
        for (k, layer) in layers.enumerated() {
            let step = w / 9
            let shift = frac(t * layer.2 * 0.05 * speed) * step
            var hill = Path()
            hill.move(to: CGPoint(x: -step, y: h))
            var x = -step - shift
            var i = Int(floor(t * layer.2 * 0.05 * speed))
            while x <= w + step * 2 {
                let peak = h * layer.1 - h * 0.12 * noise(i &+ k &* 101, 400)
                hill.addLine(to: CGPoint(x: x, y: peak))
                x += step
                i += 1
            }
            hill.addLine(to: CGPoint(x: w + step * 2, y: h))
            hill.closeSubpath()
            ctx.fill(hill, with: .color(hexColor(layer.0)))
        }
        // The bird: a body and two wings that fold up and down.
        let center = CGPoint(x: w * 0.42 + sin(t * 0.3) * w * 0.05, y: h * 0.38 + sin(t * 0.9) * h * 0.03)
        let span = min(w, h) * 0.16
        let flap = sin(t * (3 + 3 * min(kick, 1.2)) * speed)
        let tipY = center.y - flap * span * 0.55
        var far = Path(), near = Path(), body = Path()
        far.move(to: CGPoint(x: center.x - span * 0.25, y: center.y))
        far.addLine(to: CGPoint(x: center.x + span * 0.15, y: tipY - span * 0.1))
        far.addLine(to: CGPoint(x: center.x + span * 0.25, y: center.y))
        far.closeSubpath()
        near.move(to: CGPoint(x: center.x - span * 0.3, y: center.y + span * 0.02))
        near.addLine(to: CGPoint(x: center.x - span * 0.05, y: tipY + span * 0.05))
        near.addLine(to: CGPoint(x: center.x + span * 0.3, y: center.y + span * 0.02))
        near.closeSubpath()
        body.move(to: CGPoint(x: center.x - span * 0.6, y: center.y - span * 0.12))
        body.addLine(to: CGPoint(x: center.x - span * 0.2, y: center.y + span * 0.08))
        body.addLine(to: CGPoint(x: center.x + span * 0.5, y: center.y + span * 0.02))
        body.addLine(to: CGPoint(x: center.x + span * 0.7, y: center.y - span * 0.2))
        body.addLine(to: CGPoint(x: center.x + span * 0.35, y: center.y - span * 0.02))
        body.closeSubpath()
        ctx.fill(far, with: .color(hexColor(0xD9CFC4)))
        ctx.fill(body, with: .color(hexColor(0xF2ECE4)))
        ctx.fill(near, with: .color(hexColor(flap > 0 ? 0xFFFFFF : 0xE6DDD2)))
        ctx.stroke(body, with: .color(hexColor(0xBFB3A6, 0.6)), lineWidth: 1)
    }

    // MARK: Freefall

    /// Falling down a shaft between towers, their lit windows rushing up past you.
    func freefall(_ ctx: inout GraphicsContext, _ size: CGSize) {
        let w = size.width, h = size.height
        backdrop(&ctx, size, [0x070914, 0x0E1430, 0x070914])
        let center = CGPoint(x: w / 2, y: h / 2)
        ctx.blendMode = .screen
        soft(&ctx, center, min(w, h) * 0.25, hexColor(0xFF9A3C, 0.55 + 0.25 * kick))
        ctx.blendMode = .normal
        let travel = t * 1.2 * speed + 0.5 * BeatClock.shared.travel(at: Date())
        let phase = frac(travel)
        var lit = Path(), dark = Path()
        for k in stride(from: 26, through: 1, by: -1) {
            let z = Double(k) - phase
            let scale = 1 / (0.3 * z + 0.2)
            let half = min(w, h) * 0.22 * scale
            let next = min(w, h) * 0.22 / (0.3 * (z + 1) + 0.2)
            let depthRow = Int(floor(travel)) + k
            guard half < max(w, h) * 0.75 else { continue }  // the nearest slice would be giant blocks
            let windows = 7
            for side in 0..<4 {
                for j in 0..<windows {
                    let u = (Double(j) + 0.5) / Double(windows) * 2 - 1
                    let along = u * half * 0.9
                    let mid = (half + next) / 2
                    let size2 = max(1, (half - next) * 0.5)
                    let rect: CGRect
                    switch side {
                    case 0: rect = CGRect(x: center.x - mid - size2 / 2, y: center.y + along * 0.9 - size2 * 0.4, width: size2, height: size2 * 0.8)
                    case 1: rect = CGRect(x: center.x + mid - size2 / 2, y: center.y + along * 0.9 - size2 * 0.4, width: size2, height: size2 * 0.8)
                    case 2: rect = CGRect(x: center.x + along - size2 * 0.4, y: center.y - mid * 0.9 - size2 / 2, width: size2 * 0.8, height: size2)
                    default: rect = CGRect(x: center.x + along - size2 * 0.4, y: center.y + mid * 0.9 - size2 / 2, width: size2 * 0.8, height: size2)
                    }
                    if noise(depthRow &* 41 &+ side &* 9 &+ j, 410) > 0.55 { lit.addRect(rect) } else { dark.addRect(rect) }
                }
            }
        }
        ctx.fill(dark, with: .color(hexColor(0x1C2448)))
        ctx.fill(lit, with: .color(hexColor(0xFFD27A, 0.75 + 0.2 * min(kick, 1))))
    }

    // MARK: Light hall

    /// A long hall of glowing frames; each beat sends a pulse of light running down it.
    func lightHall(_ ctx: inout GraphicsContext, _ size: CGSize) {
        let w = size.width, h = size.height
        backdrop(&ctx, size, [0x050403, 0x0D0906, 0x050403])
        let center = CGPoint(x: w / 2, y: h * 0.5)
        let travel = t * 0.5 * speed
        let phase = frac(travel)
        let pulse = beatAge * 9  // how far down the hall the last beat's light has run
        for k in stride(from: 24, through: 1, by: -1) {
            let z = Double(k) - phase
            let scale = 1 / (0.35 * z + 0.25)
            let fw = min(w, h) * 0.5 * scale, fh = fw * 0.62
            let rect = CGRect(x: center.x - fw / 2, y: center.y - fh / 2, width: fw, height: fh)
            let shape = Path(roundedRect: rect, cornerRadius: fw * 0.04)
            let hit = exp(-pow(z - pulse, 2) * 0.6)
            let fade = min(1, (24 - z) / 6)
            ctx.stroke(shape, with: .color(hexColor(0xFFB45A, (0.12 + 0.3 * hit) * fade)), lineWidth: max(2, 22 * scale))
            ctx.stroke(shape, with: .color(hexColor(0xFFE2B0, (0.35 + 0.65 * hit) * fade)), lineWidth: max(0.8, 3 * scale))
        }
    }

    // MARK: TV wall

    /// A stack of old TVs. Each flicks between the cover and static, a few at a time on each beat.
    func tvWall(_ ctx: inout GraphicsContext, _ size: CGSize) {
        let w = size.width, h = size.height
        backdrop(&ctx, size, [0x0A0807, 0x14100D, 0x0A0807])
        let columns = 6, rows = 4
        let cellW = w / Double(columns), cellH = h / Double(rows)
        let beat = beatCount
        let cover = ctx.resolve(Image(nsImage: art))
        for r in 0..<rows {
            for c in 0..<columns {
                let i = r * columns + c
                let frame = CGRect(x: Double(c) * cellW + cellW * 0.06, y: Double(r) * cellH + cellH * 0.08,
                                   width: cellW * 0.88, height: cellH * 0.84)
                ctx.fill(Path(roundedRect: frame, cornerRadius: cellW * 0.06), with: .color(hexColor(0x2A2522)))
                let screen = frame.insetBy(dx: frame.width * 0.08, dy: frame.height * 0.1)
                let shape = Path(roundedRect: screen, cornerRadius: screen.width * 0.12)
                var tv = ctx
                tv.clip(to: shape)
                if noise(i &+ beat &* 37, 420) > 0.35 {
                    tv.draw(cover, in: screen)
                    tv.fill(shape, with: .color(hexColor(0x7FE0FF, 0.12)))
                } else {
                    var snow = Path()
                    let grain = max(2, screen.width / 40)
                    var y = screen.minY
                    var row = 0
                    while y < screen.maxY {
                        var x = screen.minX
                        var col = 0
                        while x < screen.maxX {
                            if noise(i &* 7919 &+ row &* 131 &+ col &+ Int(t * 24) &* 17, 421) > 0.5 {
                                snow.addRect(CGRect(x: x, y: y, width: grain, height: grain))
                            }
                            x += grain
                            col += 1
                        }
                        y += grain
                        row += 1
                    }
                    tv.fill(shape, with: .color(hexColor(0x202020)))
                    tv.fill(snow, with: .color(.white.opacity(0.7)))
                }
                // Scan lines and glass.
                var lines = Path()
                var y = screen.minY
                while y < screen.maxY { lines.addRect(CGRect(x: screen.minX, y: y, width: screen.width, height: 1)); y += 3 }
                tv.fill(lines, with: .color(.black.opacity(0.25)))
                tv.fill(shape, with: .radialGradient(Gradient(colors: [.white.opacity(0.08), .black.opacity(0.4)]),
                                                     center: CGPoint(x: screen.midX, y: screen.midY),
                                                     startRadius: 0, endRadius: screen.width * 0.7))
            }
        }
        ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.white.opacity(0.05 * min(kick, 1))))
    }

    // MARK: Neon lattice

    /// Flying through a 3D grid of neon beams.
    func neonLattice(_ ctx: inout GraphicsContext, _ size: CGSize) {
        let w = size.width, h = size.height
        backdrop(&ctx, size, [0x05020C, 0x0C0420, 0x05020C])
        let travel = t * 0.9 * speed + 0.4 * BeatClock.shared.travel(at: Date())
        let phase = frac(travel)
        let roll = sin(t * 0.15) * 0.25
        func project(_ x: Double, _ y: Double, _ z: Double) -> CGPoint? {
            guard z > 0.15 else { return nil }
            let rx = x * cos(roll) - y * sin(roll), ry = x * sin(roll) + y * cos(roll)
            return CGPoint(x: w / 2 + rx / z * w * 0.35, y: h / 2 + ry / z * w * 0.35)
        }
        let span = [-2.0, -1.0, 0.0, 1.0, 2.0]
        var cyan = Path(), pink = Path()
        for k in 0..<14 {
            let z = Double(k) + 1 - phase
            for a in span {
                if let p = project(-2, a, z), let q = project(2, a, z) { cyan.move(to: p); cyan.addLine(to: q) }
                if let p = project(a, -2, z), let q = project(a, 2, z) { pink.move(to: p); pink.addLine(to: q) }
            }
        }
        for a in span {
            for b in span where abs(a) == 2 || abs(b) == 2 {
                if let p = project(a, b, 0.4), let q = project(a, b, 14) { cyan.move(to: p); cyan.addLine(to: q) }
            }
        }
        ctx.blendMode = .screen
        let glow = 0.5 + 0.5 * min(kick, 1)
        ctx.stroke(cyan, with: .color(hexColor(0x3BE8FF, 0.18 * glow)), lineWidth: 6)
        ctx.stroke(pink, with: .color(hexColor(0xFF3BD0, 0.18 * glow)), lineWidth: 6)
        ctx.stroke(cyan, with: .color(hexColor(0x9CF5FF, 0.85)), lineWidth: 1.4)
        ctx.stroke(pink, with: .color(hexColor(0xFF9CEA, 0.85)), lineWidth: 1.4)
    }

    // MARK: Northern lights

    /// Curtains of aurora rippling over a dark field under the stars, brightening with the music.
    func northernLights(_ ctx: inout GraphicsContext, _ size: CGSize) {
        let w = size.width, h = size.height
        backdrop(&ctx, size, [0x02040E, 0x061A2A, 0x0A2A30])
        var stars = Path()
        for i in 0..<260 {
            let r = 0.4 + 0.8 * noise(i, 430)
            stars.addEllipse(in: CGRect(x: noise(i, 431) * w, y: noise(i, 432) * h * 0.7, width: r * 2, height: r * 2))
        }
        ctx.fill(stars, with: .color(.white.opacity(0.55)))
        ctx.blendMode = .screen
        let curtains: [(UInt32, Double, Double)] = [(0x3DFFB0, 0.32, 0), (0x2EE6D6, 0.26, 1.7), (0x9A6BFF, 0.2, 3.1)]
        for (k, curtain) in curtains.enumerated() {
            let base = h * curtain.1
            let height = h * (0.3 + 0.12 * band(k * 6, of: 32))
            var top = [CGPoint]()
            var x = -10.0
            while x <= w + 10 {
                let y = base + sin(x / w * 5 + t * 0.3 * speed + curtain.2) * h * 0.06 + sin(x / w * 13 - t * 0.5) * h * 0.02
                top.append(CGPoint(x: x, y: y))
                x += w / 60
            }
            var sheet = Path()
            sheet.addLines(top)
            for p in top.reversed() { sheet.addLine(to: CGPoint(x: p.x, y: p.y + height)) }
            sheet.closeSubpath()
            let alpha = 0.35 + 0.25 * min(kick, 1)
            ctx.fill(sheet, with: .linearGradient(Gradient(colors: [hexColor(curtain.0, 0), hexColor(curtain.0, alpha), hexColor(curtain.0, 0)]),
                                                 startPoint: CGPoint(x: 0, y: base - h * 0.08),
                                                 endPoint: CGPoint(x: 0, y: base + height)))
            var rays = Path()
            for (j, p) in top.enumerated() where j % 2 == 0 {
                rays.move(to: p)
                rays.addLine(to: CGPoint(x: p.x, y: p.y + height * (0.5 + 0.5 * noise(j &+ k &* 100, 433))))
            }
            ctx.stroke(rays, with: .color(hexColor(curtain.0, 0.12)), lineWidth: w / 90)
        }
        ctx.blendMode = .normal
        var field = Path()
        field.move(to: CGPoint(x: 0, y: h))
        var x = 0.0
        while x <= w {
            field.addLine(to: CGPoint(x: x, y: h * 0.86 + sin(x / w * 7) * h * 0.02 - noise(Int(x), 434) * 4))
            x += 6
        }
        field.addLine(to: CGPoint(x: w, y: h))
        field.closeSubpath()
        ctx.fill(field, with: .color(hexColor(0x020608)))
    }

    // MARK: Neon dunes

    /// Rolling dunes at dusk, each crest traced in neon that flares on the beat.
    func neonDunes(_ ctx: inout GraphicsContext, _ size: CGSize) {
        let w = size.width, h = size.height
        backdrop(&ctx, size, [0x1A0A3A, 0x5A1A6A, 0xE0508A])
        ctx.blendMode = .screen
        soft(&ctx, CGPoint(x: w * 0.5, y: h * 0.48), h * 0.22, hexColor(0xFFB070, 0.8))
        ctx.blendMode = .normal
        let rims: [UInt32] = [0xFF4FD8, 0x3BE8FF, 0xFF8A3C, 0xB06BFF, 0x3BE8FF]
        for k in 0..<5 {
            let base = h * (0.55 + 0.1 * Double(k))
            let drift = t * (0.02 + 0.03 * Double(k)) * speed
            var crest = [CGPoint]()
            var x = -10.0
            while x <= w + 10 {
                let u = x / w
                let y = base - h * 0.07 * (sin(u * (3 + Double(k)) + drift * 6 + Double(k)) * 0.6 + sin(u * 7.3 - drift * 4) * 0.4)
                crest.append(CGPoint(x: x, y: y))
                x += w / 80
            }
            var dune = Path()
            dune.addLines(crest)
            dune.addLine(to: CGPoint(x: w + 10, y: h))
            dune.addLine(to: CGPoint(x: -10, y: h))
            dune.closeSubpath()
            ctx.fill(dune, with: .linearGradient(Gradient(colors: [hexColor(0x1A0B2E), hexColor(0x07030F)]),
                                                 startPoint: CGPoint(x: 0, y: base - h * 0.1), endPoint: CGPoint(x: 0, y: h)))
            var line = Path()
            line.addLines(crest)
            let flare = 0.5 + 0.5 * min(kick, 1)
            ctx.stroke(line, with: .color(hexColor(rims[k], 0.25 * flare)), lineWidth: 8)
            ctx.stroke(line, with: .color(hexColor(rims[k], 0.95)), lineWidth: 1.8)
        }
    }

    // MARK: Glow lagoon

    /// Dark water full of drifting glowing plankton; every beat drops a ring of light into it.
    func glowLagoon(_ ctx: inout GraphicsContext, _ size: CGSize) {
        let w = size.width, h = size.height
        backdrop(&ctx, size, [0x01060C, 0x03141E, 0x062430])
        ctx.blendMode = .screen
        soft(&ctx, CGPoint(x: w * 0.7, y: h * 0.15), h * 0.12, hexColor(0xDFF6FF, 0.5))
        var glow = [Path](repeating: Path(), count: 3)
        for i in 0..<700 {
            let x = frac(noise(i, 440) + t * 0.004 * (noise(i, 441) - 0.5) * speed) * w
            let y = h * (0.3 + 0.7 * noise(i, 442)) + sin(t * 0.6 + Double(i)) * 4
            let twinkle = 0.5 + 0.5 * sin(t * (1 + 2 * noise(i, 443)) + Double(i))
            let r = 0.8 + 1.8 * twinkle
            glow[min(2, Int(twinkle * 3))].addEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
        }
        for i in 0..<3 { ctx.fill(glow[i], with: .color(hexColor(0x3BFFE0, 0.3 + 0.25 * Double(i)))) }
        // The last few beats' rings, spreading out.
        for beat in BeatClock.shared.recent(at: Date()) where beat.age < 2.5 {
            let center = CGPoint(x: w * (0.2 + 0.6 * noise(beat.index, 444)), y: h * (0.5 + 0.35 * noise(beat.index, 445)))
            let radius = 20 + beat.age * w * 0.12
            let rect = CGRect(x: center.x - radius, y: center.y - radius * 0.3, width: radius * 2, height: radius * 0.6)
            let alpha = 1 - beat.age / 2.5
            ctx.stroke(Path(ellipseIn: rect), with: .color(hexColor(0x3BFFE0, 0.2 * alpha)), lineWidth: 10)
            ctx.stroke(Path(ellipseIn: rect), with: .color(hexColor(0xB8FFF2, 0.8 * alpha)), lineWidth: 1.5)
        }
    }

    // MARK: Canyon

    /// Layered rock: bands of rust, sand and cream bent by the field, drifting slowly upward.
    func canyon(_ ctx: inout GraphicsContext, _ size: CGSize) {
        let (c, r) = gridSize(size, 320)
        let palette: [(Double, Double, Double)] = [0x5A2614, 0x9C4A22, 0xC8743A, 0xE3B27A, 0xF2DDB8, 0xB06A3A, 0x7A3418]
            .map(PixelField.rgb)
        let drift = t * 0.05 * speed
        let image = field(columns: c, rows: r, warp: 0.7 + 0.3 * min(kick, 1.2), scale: 3) { f, _, yy in
            let v = yy * 2.2 + f * 0.35 + drift
            let layer = v * 4
            let index = Int(floor(layer)) % palette.count
            let color = palette[(index + palette.count) % palette.count]
            let grain = 0.92 + 0.08 * sin(layer * 40)
            let edge = frac(layer) < 0.06 ? 0.75 : 1
            return PixelField.pack(color.0 * grain * edge, color.1 * grain * edge, color.2 * grain * edge)
        }
        drawField(&ctx, size, image)
    }

    // MARK: Helix

    /// A spiral of blocks turning in the dark, each one swelling with its slice of the spectrum.
    func helix(_ ctx: inout GraphicsContext, _ size: CGSize) {
        let w = size.width, h = size.height
        backdrop(&ctx, size, [0x07040F, 0x120A24, 0x07040F])
        let count = 84
        let radius = min(w, h) * 0.26
        var blocks: [(z: Double, rect: CGRect, i: Int)] = []
        for i in 0..<count {
            let u = Double(i) / Double(count)
            let a = u * 6 * .pi + t * 0.6 * speed
            let x = cos(a) * radius, z = sin(a)
            let y = (u - 0.5) * h * 0.85
            let s = min(w, h) * 0.04 * (1 + 0.25 * z) * (1 + 0.6 * band(i % 32, of: 32) * min(kick + 0.3, 1.2))
            blocks.append((z, CGRect(x: w / 2 + x - s / 2, y: h / 2 + y - s / 2, width: s, height: s), i))
        }
        blocks.sort { $0.z < $1.z }
        let colors: [UInt32] = [0xFF8A3C, 0xFF4F7A, 0xC04FFF, 0x5C7CFF]
        for block in blocks {
            let shade = 0.45 + 0.55 * (block.z + 1) / 2
            let color = colors[block.i * colors.count / count]
            let face = block.rect
            let depth = face.width * 0.35
            var side = Path()
            side.move(to: CGPoint(x: face.maxX, y: face.minY))
            side.addLine(to: CGPoint(x: face.maxX + depth, y: face.minY - depth))
            side.addLine(to: CGPoint(x: face.maxX + depth, y: face.maxY - depth))
            side.addLine(to: CGPoint(x: face.maxX, y: face.maxY))
            side.closeSubpath()
            var top = Path()
            top.move(to: CGPoint(x: face.minX, y: face.minY))
            top.addLine(to: CGPoint(x: face.minX + depth, y: face.minY - depth))
            top.addLine(to: CGPoint(x: face.maxX + depth, y: face.minY - depth))
            top.addLine(to: CGPoint(x: face.maxX, y: face.minY))
            top.closeSubpath()
            ctx.fill(Path(face), with: .color(hexColor(color, shade)))
            ctx.fill(side, with: .color(hexColor(color, shade * 0.6)))
            ctx.fill(top, with: .color(hexColor(color, min(1, shade * 1.25))))
        }
    }

    // MARK: Clockwork

    /// A clock face telling the real time, its second hand ticking on the beat, with butterflies fluttering round.
    func clockwork(_ ctx: inout GraphicsContext, _ size: CGSize) {
        let w = size.width, h = size.height
        backdrop(&ctx, size, [0xEDE6DA, 0xE2D8C8, 0xCFC2AE])
        let center = CGPoint(x: w / 2, y: h / 2)
        let r = min(w, h) * 0.3
        ctx.fill(Path(ellipseIn: CGRect(x: center.x - r * 1.08, y: center.y - r * 1.08, width: r * 2.16, height: r * 2.16)),
                 with: .color(hexColor(0x2E2A26)))
        ctx.fill(Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)),
                 with: .radialGradient(Gradient(colors: [hexColor(0xFBF7EF), hexColor(0xE9E0D0)]), center: center,
                                       startRadius: 0, endRadius: r))
        var ticks = Path()
        for i in 0..<60 {
            let a = Double(i) / 60 * 2 * .pi
            let inner = i % 5 == 0 ? r * 0.84 : r * 0.92
            ticks.move(to: CGPoint(x: center.x + sin(a) * inner, y: center.y - cos(a) * inner))
            ticks.addLine(to: CGPoint(x: center.x + sin(a) * r * 0.97, y: center.y - cos(a) * r * 0.97))
        }
        ctx.stroke(ticks, with: .color(hexColor(0x2E2A26)), lineWidth: 2)
        let now = Calendar.current.dateComponents([.hour, .minute, .second], from: Date())
        let minute = Double(now.minute ?? 0), hour = Double((now.hour ?? 0) % 12) + minute / 60
        func hand(_ turns: Double, _ length: Double, _ width: Double, _ color: Color) {
            var p = Path()
            let a = turns * 2 * .pi
            p.move(to: CGPoint(x: center.x - sin(a) * length * 0.15, y: center.y + cos(a) * length * 0.15))
            p.addLine(to: CGPoint(x: center.x + sin(a) * length, y: center.y - cos(a) * length))
            ctx.stroke(p, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round))
        }
        hand(hour / 12, r * 0.5, 7, hexColor(0x2E2A26))
        hand(minute / 60, r * 0.75, 4.5, hexColor(0x2E2A26))
        hand(Double(beatCount % 60) / 60, r * 0.85, 1.6, hexColor(0xD8402A))
        ctx.fill(Path(ellipseIn: CGRect(x: center.x - 6, y: center.y - 6, width: 12, height: 12)), with: .color(hexColor(0xD8402A)))
        // Butterflies.
        let wings: [UInt32] = [0x2F7BFF, 0xFF8A2A, 0x3FC6B8, 0xFF5A8A, 0x7A5CFF]
        for i in 0..<5 {
            let x = w / 2 + sin(t * (0.3 + 0.07 * Double(i)) * speed + Double(i) * 1.3) * w * 0.38
            let y = h / 2 + sin(t * (0.41 + 0.05 * Double(i)) * speed + Double(i) * 2.1) * h * 0.35
            let s = min(w, h) * 0.055
            let open = abs(sin(t * (8 + 6 * min(kick, 1)) + Double(i)))
            for side in [-1.0, 1.0] {
                let upper = CGRect(x: x + (side < 0 ? -s * open : 0), y: y - s * 0.9, width: s * open, height: s)
                let lower = CGRect(x: x + (side < 0 ? -s * 0.7 * open : 0), y: y, width: s * 0.7 * open, height: s * 0.7)
                ctx.fill(Path(ellipseIn: upper), with: .color(hexColor(wings[i], 0.9)))
                ctx.fill(Path(ellipseIn: lower), with: .color(hexColor(wings[i], 0.75)))
            }
            ctx.fill(Path(CGRect(x: x - 1, y: y - s * 0.8, width: 2, height: s * 1.4)), with: .color(hexColor(0x221E1A)))
        }
    }

    // MARK: Glass swirl

    /// Ribbons of tinted glass spiralling into the middle, catching white highlights on their edges.
    func glassSwirl(_ ctx: inout GraphicsContext, _ size: CGSize) {
        let (c, r) = gridSize(size, 300)
        let scale = 3.0
        let cx = scale / 2, cy = scale * Double(r) / Double(c) / 2
        let blue = PixelField.rgb(0x9FD4FF), rose = PixelField.rgb(0xF4B8D8), deep = PixelField.rgb(0x1A2A5A)
        let spin = t * 0.4 * speed
        let image = field(columns: c, rows: r, warp: 0.6 + 0.4 * min(kick, 1.2), scale: scale) { f, xx, yy in
            let dx = xx - cx, dy = yy - cy
            let radius = max((dx * dx + dy * dy).squareRoot(), 0.001)
            let angle = atan2(dy, dx)
            let v = sin(angle * 3 + log(radius) * 5 - spin + f * 0.4)
            let tint = PixelField.lerp(blue, rose, 0.5 + 0.5 * sin(angle + f))
            let body = PixelField.lerp(deep, tint, 0.55 + 0.45 * v)
            let highlight = smooth(0.85, 0.98, v)
            let color = PixelField.lerp(body, (1, 1, 1), highlight)
            return PixelField.pack(color.0, color.1, color.2)
        }
        drawField(&ctx, size, image)
    }

    // MARK: Gravity well

    /// Particles spiralling down into a well of light, faster as they fall, over a funnel of rings.
    func gravityWell(_ ctx: inout GraphicsContext, _ size: CGSize) {
        let w = size.width, h = size.height
        backdrop(&ctx, size, [0x02030A, 0x070C1E, 0x02030A])
        let center = CGPoint(x: w / 2, y: h / 2)
        let big = max(w, h) * 0.46
        var rings = Path()
        for k in 1...9 {
            let rr = big * pow(Double(k) / 9, 1.6)
            rings.addEllipse(in: CGRect(x: center.x - rr, y: center.y - rr * 0.45, width: rr * 2, height: rr * 0.9))
        }
        ctx.stroke(rings, with: .color(hexColor(0x5C7CFF, 0.18)), lineWidth: 1)
        ctx.blendMode = .screen
        var dots = [Path](repeating: Path(), count: 4)
        for i in 0..<1600 {
            let life = frac(noise(i, 450) - t * 0.06 * speed * (1 + 0.5 * min(kick, 1)))
            let rr = big * pow(life, 1.4) + 4
            let a = noise(i, 451) * 2 * .pi + 1.8 / (life + 0.08)
            let p = CGPoint(x: center.x + cos(a) * rr, y: center.y + sin(a) * rr * 0.45)
            let s = 0.6 + 1.6 * (1 - life)
            dots[min(3, Int((1 - life) * 4))].addEllipse(in: CGRect(x: p.x - s, y: p.y - s, width: s * 2, height: s * 2))
        }
        let colors: [UInt32] = [0x3B5CFF, 0x6AA8FF, 0xBFE0FF, 0xFFFFFF]
        for i in 0..<4 { ctx.fill(dots[i], with: .color(hexColor(colors[i], 0.55 + 0.12 * Double(i)))) }
        soft(&ctx, center, big * 0.22 * (1 + 0.3 * kick), hexColor(0xCFE4FF, 0.7))
    }

    // MARK: Wood grain

    /// Polished wood: rings and knots in honey and walnut, with fine fibres, the grain shifting slowly.
    func woodGrain(_ ctx: inout GraphicsContext, _ size: CGSize) {
        let (c, r) = gridSize(size, 340)
        let dark = PixelField.rgb(0x4A2A14), honey = PixelField.rgb(0xC8873E), light = PixelField.rgb(0xE8B878)
        let image = field(columns: c, rows: r, warp: 0.8 + 0.3 * min(kick, 1.2), scale: 2.6) { f, xx, yy in
            let ring = 0.5 + 0.5 * sin(f * 9 + t * 0.2)
            let fibre = 0.035 * sin(f * 55) + 0.02 * sin(xx * 9 + yy * 4)
            let base = PixelField.lerp(honey, light, smooth(0.2, 0.9, ring))
            let color = PixelField.lerp(base, dark, smooth(0.75, 1, 1 - ring) * 0.85)
            let k = 0.92 + fibre
            return PixelField.pack(color.0 * k, color.1 * k, color.2 * k)
        }
        drawField(&ctx, size, image)
    }
}
