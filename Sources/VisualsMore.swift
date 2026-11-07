import AppKit
import SwiftUI

// MARK: - More visuals

/// Field scenes (contours, molten bands, terraces, silk, ink) are worked out per pixel at a low resolution and
/// smoothed up to the screen, which is what makes flowing bands affordable every frame. The rest are drawn.
enum PixelField {
    private static let space = CGColorSpaceCreateDeviceRGB()

    /// Pixels packed as R | G << 8 | B << 16.
    static func image(_ pixels: [UInt32], _ width: Int, _ height: Int) -> CGImage? {
        let data = pixels.withUnsafeBufferPointer { Data(buffer: $0) }
        guard let provider = CGDataProvider(data: data as CFData) else { return nil }
        let info = CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                       space: space, bitmapInfo: info, provider: provider, decode: nil, shouldInterpolate: true,
                       intent: .defaultIntent)
    }

    static func pack(_ r: Double, _ g: Double, _ b: Double) -> UInt32 {
        func c(_ v: Double) -> UInt32 { UInt32(max(0, min(255, v * 255))) }
        return c(r) | c(g) << 8 | c(b) << 16
    }

    static func rgb(_ hex: UInt32) -> (Double, Double, Double) {
        (Double((hex >> 16) & 0xFF) / 255, Double((hex >> 8) & 0xFF) / 255, Double(hex & 0xFF) / 255)
    }

    static func lerp(_ a: (Double, Double, Double), _ b: (Double, Double, Double), _ f: Double) -> (Double, Double, Double) {
        (a.0 + (b.0 - a.0) * f, a.1 + (b.1 - a.1) * f, a.2 + (b.2 - a.2) * f)
    }
}

private func smoothstep(_ a: Double, _ b: Double, _ x: Double) -> Double {
    let t = min(max((x - a) / (b - a), 0), 1)
    return t * t * (3 - 2 * t)
}

private func fract(_ x: Double) -> Double { x - floor(x) }

extension VisualScene {
    /// A flowing field: three interfering waves, each bent by the others. Row and column terms are worked out
    /// once per line, so each pixel costs three sines.
    func field(columns: Int, rows: Int, warp: Double, scale: Double = 3, _ pixel: (_ f: Double, _ x: Double, _ y: Double) -> UInt32) -> CGImage? {
        let aspect = Double(rows) / Double(columns)
        let s = t * 0.35 * speed
        var rowA = [Double](repeating: 0, count: rows), rowB = rowA
        for y in 0..<rows {
            let yy = Double(y) / Double(rows) * scale * aspect
            rowA[y] = sin(yy * 1.7 + s)
            rowB[y] = sin(yy * 0.9 - s * 0.7)
        }
        var colA = [Double](repeating: 0, count: columns), colB = colA
        for x in 0..<columns {
            let xx = Double(x) / Double(columns) * scale
            colA[x] = sin(xx * 1.3 - s * 0.8)
            colB[x] = sin(xx * 2.1 + s * 0.6)
        }
        var pixels = [UInt32](repeating: 0, count: columns * rows)
        for y in 0..<rows {
            let yy = Double(y) / Double(rows) * scale * aspect
            for x in 0..<columns {
                let xx = Double(x) / Double(columns) * scale
                let f = sin(xx * 2.2 + 1.6 * rowA[y] * warp + 0.8 * rowB[y])
                    + sin(yy * 2.6 + 1.4 * colA[x] * warp + s * 0.6)
                    + 0.5 * sin((xx + yy) * 3.1 + colB[x] + rowB[y])
                pixels[y * columns + x] = pixel(f, xx, yy)
            }
        }
        return PixelField.image(pixels, columns, rows)
    }

    func drawField(_ ctx: inout GraphicsContext, _ size: CGSize, _ image: CGImage?) {
        guard let image else { return }
        ctx.draw(Image(decorative: image, scale: 1), in: CGRect(origin: .zero, size: size))
    }

    func gridSize(_ size: CGSize, _ columns: Int = 300) -> (Int, Int) {
        // A coarser grid on battery saver: about a third of the work, still smooth once scaled up.
        let columns = Power.shared.saving ? columns * 6 / 10 : columns
        return (columns, max(2, Int(Double(columns) * size.height / max(size.width, 1))))
    }

    // MARK: Contours

    /// Black and white bands winding through each other, with a colour fringe where they cross.
    func contours(_ ctx: inout GraphicsContext, _ size: CGSize) {
        let (c, r) = gridSize(size, 420)
        let warp = 1 + 0.5 * min(kick, 1.2)
        let frequency = 7.5 + 1.2 * band(4, of: 32)
        let edge = 0.3
        let image = field(columns: c, rows: r, warp: warp, scale: 3.6) { f, _, _ in
            let red = smoothstep(-edge, edge, sin((f + 0.035) * frequency + t * 0.5))
            let green = smoothstep(-edge, edge, sin(f * frequency + t * 0.5))
            let blue = smoothstep(-edge, edge, sin((f - 0.035) * frequency + t * 0.5))
            return PixelField.pack(0.04 + 0.9 * red, 0.04 + 0.9 * green, 0.06 + 0.9 * blue)
        }
        drawField(&ctx, size, image)
    }

    // MARK: Molten

    /// Bands of lava: dark crust between glowing orange and yellow seams.
    func molten(_ ctx: inout GraphicsContext, _ size: CGSize) {
        let (c, r) = gridSize(size, 380)
        let warp = 1 + 0.6 * min(kick, 1.2)
        let crust = PixelField.rgb(0x1C0400), ember = PixelField.rgb(0xD83A06), gold = PixelField.rgb(0xFFC94A)
        let heat = 0.8 + 0.4 * kick
        let image = field(columns: c, rows: r, warp: warp, scale: 3.4) { f, _, _ in
            let seam = smoothstep(0.55, 0.85, sin(f * 5.5 + t * 0.4))
            let glow = (0.5 + 0.5 * sin(f * 0.9 + 1)) * heat
            let hot = PixelField.lerp(ember, gold, min(glow, 1))
            let color = PixelField.lerp(crust, hot, seam)
            return PixelField.pack(color.0, color.1, color.2)
        }
        drawField(&ctx, size, image)
    }

    // MARK: Terraces

    /// A topographic map: the field cut into flat steps of blue, each edged with a fine dark line.
    func terraces(_ ctx: inout GraphicsContext, _ size: CGSize) {
        let (c, r) = gridSize(size)
        let steps: [(Double, Double, Double)] = [0x061A3D, 0x0B2E66, 0x154C93, 0x2470B8, 0x4A97D6, 0x7DBDEA, 0xB4DDF5, 0xE6F4FC]
            .map(PixelField.rgb)
        let lift = 0.25 * min(kick, 1.2)
        let image = field(columns: c, rows: r, warp: 0.9) { f, _, _ in
            let level = (f + 2.5) / 5 * 8 + lift
            let index = min(7, max(0, Int(level)))
            let line = fract(level) < 0.1 ? 0.62 : 1
            let color = steps[index]
            return PixelField.pack(color.0 * line, color.1 * line, color.2 * line)
        }
        drawField(&ctx, size, image)
    }

    // MARK: Silk

    /// Pale silk folding over itself, lit from the top left so each ripple has a light and a dark side.
    func silk(_ ctx: inout GraphicsContext, _ size: CGSize) {
        let (c, r) = gridSize(size, 260)
        let ivory = PixelField.rgb(0xF4EDE2), blush = PixelField.rgb(0xE9C8D2), lilac = PixelField.rgb(0xC6C3EC)
        var previous = 0.0
        let warp = 1.1 + 0.4 * min(kick, 1.2)
        let image = field(columns: c, rows: r, warp: warp) { f, xx, _ in
            let v = 0.5 + 0.5 * sin(f * 3 + t * 0.25)
            let slope = xx == 0 ? 0 : v - previous
            previous = v
            let tint = 0.5 + 0.5 * sin(f * 0.6 + 2)
            let base = PixelField.lerp(PixelField.lerp(ivory, blush, tint), lilac, max(0, 1 - tint * 2) * 0.6)
            let light = min(1.1, max(0.78, 0.95 + slope * 4 + 0.06 * v))
            return PixelField.pack(base.0 * light, base.1 * light, base.2 * light)
        }
        drawField(&ctx, size, image)
    }

    // MARK: Ink

    /// Drops of ink on paper, merging and splitting; they swell on the bass and carry a thin red rim.
    func ink(_ ctx: inout GraphicsContext, _ size: CGSize) {
        let (c, r) = gridSize(size, 280)
        let aspect = Double(r) / Double(c)
        let blobs: [(x: Double, y: Double, r2: Double)] = (0..<12).map { i in
            let x = 0.5 + 0.34 * sin(t * (0.13 + 0.05 * noise(i, 300)) * speed + Double(i) * 1.9)
            let y = (0.5 + 0.32 * cos(t * (0.11 + 0.05 * noise(i, 301)) * speed + Double(i) * 2.7)) * aspect
            let radius = (0.025 + 0.035 * noise(i, 302)) * (1 + 0.3 * min(kick, 1.2) * noise(i, 303))
            return (x, y, radius * radius)
        }
        let paper = PixelField.rgb(0xF1ECE2), ink = PixelField.rgb(0x0B0D14), rim = PixelField.rgb(0xE0302A)
        var pixels = [UInt32](repeating: 0, count: c * r)
        for y in 0..<r {
            let py = Double(y) / Double(c)
            for x in 0..<c {
                let px = Double(x) / Double(c)
                var sum = 0.0
                for b in blobs {
                    let dx = px - b.x, dy = py - b.y
                    sum += b.r2 / (dx * dx + dy * dy + 0.0004)
                }
                let inside = smoothstep(0.95, 1.08, sum)
                let edge = smoothstep(0.7, 0.95, sum) * (1 - inside)
                let color = PixelField.lerp(PixelField.lerp(paper, rim, edge * 0.85), ink, inside)
                pixels[y * c + x] = PixelField.pack(color.0, color.1, color.2)
            }
        }
        drawField(&ctx, size, PixelField.image(pixels, c, r))
    }

    // MARK: Tunnel

    /// Rings rushing past out of the dark, twisting as they go, their outline pushed out by the spectrum.
    func tunnel(_ ctx: inout GraphicsContext, _ size: CGSize) {
        let w = size.width, h = size.height, big = max(w, h)
        ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(hexColor(0x03030A)))
        let center = CGPoint(x: w / 2 + sin(t * 0.3) * w * 0.05, y: h / 2 + cos(t * 0.23) * h * 0.05)
        ctx.blendMode = .screen
        soft(&ctx, center, big * 0.12, hexColor(0x8A5CFF, 0.5 + 0.3 * kick))
        let travel = t * 1.1 * speed + 0.6 * BeatClock.shared.travel(at: Date())
        let phase = fract(travel)
        let rings = 44
        let colors: [UInt32] = [0x3BE8FF, 0x8A5CFF, 0xFF4FD8, 0x5C7CFF]
        for k in stride(from: rings, through: 1, by: -1) {
            let z = Double(k) - phase
            let scale = 1 / (0.35 * z + 0.15)
            let radius = big * 0.42 * scale
            guard radius > 3 else { continue }
            let twist = z * 0.18 + t * 0.15
            let index = Int(floor(travel)) + k
            var ring = Path()
            let points = 40
            for j in 0...points {
                let a = Double(j % points) / Double(points) * 2 * .pi + twist
                let bump = 1 + 0.18 * band(j % points * 32 / points, of: 32) * (0.4 + kick)
                let p = CGPoint(x: center.x + cos(a) * radius * bump, y: center.y + sin(a) * radius * bump * 0.8)
                if j == 0 { ring.move(to: p) } else { ring.addLine(to: p) }
            }
            let fade = min(1, (Double(rings) - z) / 10) * min(1, z / 1.2)
            let color = colors[((index % colors.count) + colors.count) % colors.count]
            ctx.stroke(ring, with: .color(hexColor(color, 0.22 * fade)), lineWidth: max(1.5, 18 * scale))
            ctx.stroke(ring, with: .color(hexColor(color, 0.95 * fade)), lineWidth: max(1, 4 * scale))
        }
    }

    // MARK: Wireframe sea

    /// A wire mesh of rolling waves running to the horizon, lifted by the spectrum.
    func wireSea(_ ctx: inout GraphicsContext, _ size: CGSize) {
        let w = size.width, h = size.height
        ctx.fill(Path(CGRect(origin: .zero, size: size)),
                 with: .linearGradient(Gradient(colors: [hexColor(0x02040C), hexColor(0x061632), hexColor(0x02040C)]),
                                       startPoint: .zero, endPoint: CGPoint(x: 0, y: h)))
        let horizon = h * 0.42
        ctx.blendMode = .screen
        soft(&ctx, CGPoint(x: w / 2, y: horizon), w * 0.35, hexColor(0x1B7CFF, 0.35 + 0.2 * kick))
        let rows = 36, columns = 64
        let flow = t * 0.8 * speed
        func project(_ c: Int, _ r: Int) -> CGPoint {
            let depth = 1 + Double(r) * 0.32
            let worldZ = Double(r) * 0.32 + flow
            let x = (Double(c) / Double(columns - 1) * 2 - 1) * 9
            var y = 0.35 * sin(x * 0.7 + worldZ * 0.9) + 0.25 * sin(x * 1.3 - worldZ * 1.4 + t)
            y += 0.9 * band(c * 32 / columns, of: 32) * (0.4 + kick) * exp(-Double(r) * 0.08)
            return CGPoint(x: w / 2 + x / depth * w * 0.32, y: horizon + (1.6 - y) / depth * h * 0.32)
        }
        for r in stride(from: rows - 1, through: 0, by: -1) {
            var line = Path()
            for c in 0..<columns {
                let p = project(c, r)
                if c == 0 { line.move(to: p) } else { line.addLine(to: p) }
            }
            let near = 1 - Double(r) / Double(rows)
            ctx.stroke(line, with: .color(hexColor(0x5FF3FF, 0.15 + 0.7 * near)), lineWidth: 0.6 + 1.6 * near)
        }
        var columnsPath = Path()
        for c in stride(from: 0, to: columns, by: 2) {
            for r in 0..<rows {
                let p = project(c, r)
                if r == 0 { columnsPath.move(to: p) } else { columnsPath.addLine(to: p) }
            }
        }
        ctx.stroke(columnsPath, with: .color(hexColor(0x3BA8FF, 0.35)), lineWidth: 0.7)
    }

    // MARK: Voxel city

    /// Flying low over a city of blocks at night. Lit windows, and towers that grow with the music.
    func city(_ ctx: inout GraphicsContext, _ size: CGSize) {
        let w = size.width, h = size.height
        ctx.fill(Path(CGRect(origin: .zero, size: size)),
                 with: .linearGradient(Gradient(colors: [hexColor(0x070A1C), hexColor(0x1A1440), hexColor(0x3A1C4E)]),
                                       startPoint: .zero, endPoint: CGPoint(x: 0, y: h)))
        let base = w / 34
        let flow = t * 2.2 * speed
        let front = hexColor(0x141A33), side = hexColor(0x0C1024), road = hexColor(0x07080F)
        let roofs: [Color] = [hexColor(0x2B3570), hexColor(0x3B2F7A), hexColor(0x5A2E7A), hexColor(0x1F5C8A)]
        var y = -base
        var z = 0
        while y < h + base * 3 {
            let depth = max(0, min(1, y / h))
            let scale = 0.38 + 0.62 * depth
            let cell = base * scale
            let rowZ = Int(floor(Double(z) - flow))
            let count = Int(w / cell) + 2
            let offset = (w - Double(count) * cell) / 2
            var fronts = Path(), roofsPaths = [Path](repeating: Path(), count: roofs.count)
            var windows = Path(), roads = Path(), lights = Path()
            for c in 0..<count {
                let x = offset + Double(c) * cell
                let gc = c - count / 2
                let isRoad = ((gc % 5) + 5) % 5 == 0 || ((rowZ % 6) + 6) % 6 == 0
                let top = CGRect(x: x, y: y, width: cell, height: cell * 0.6)
                if isRoad {
                    roads.addRect(top)
                    if noise(c &+ rowZ &* 977, 310) > 0.93 {
                        lights.addEllipse(in: CGRect(x: x + cell * 0.4, y: y + cell * 0.2, width: cell * 0.2, height: cell * 0.2))
                    }
                    continue
                }
                let tall = pow(noise(gc &* 31 &+ rowZ &* 7919, 311), 3)
                let audio = band((c * 32 / max(count, 1)), of: 32)
                let height = cell * (0.4 + 7 * tall) * (1 + 0.35 * audio * min(kick + 0.3, 1.2))
                let roof = CGRect(x: x + 1, y: y - height, width: cell - 2, height: cell * 0.6)
                let face = CGRect(x: x + 1, y: roof.maxY, width: cell - 2, height: height)
                fronts.addRect(face)
                roofsPaths[Int(noise(gc, 312) * Double(roofs.count))].addRect(roof)
                // Windows in a grid on the front, some lit.
                let rowsOfWindows = Int(height / (cell * 0.35))
                if rowsOfWindows > 0 && cell > 8 {
                    for wy in 0..<min(rowsOfWindows, 14) where noise(gc &* 13 &+ wy &+ rowZ &* 101, 313) > 0.55 {
                        let wyPos = face.minY + Double(wy) * cell * 0.35 + cell * 0.1
                        windows.addRect(CGRect(x: x + cell * 0.25, y: wyPos, width: cell * 0.18, height: cell * 0.14))
                        windows.addRect(CGRect(x: x + cell * 0.58, y: wyPos, width: cell * 0.18, height: cell * 0.14))
                    }
                }
            }
            ctx.fill(roads, with: .color(road))
            ctx.fill(lights, with: .color(hexColor(0xFF5A5A, 0.9)))
            ctx.fill(fronts, with: .color(front))
            ctx.stroke(fronts, with: .color(side), lineWidth: 1)
            ctx.fill(windows, with: .color(hexColor(0xFFD27A, 0.55 + 0.35 * min(kick, 1))))
            for i in roofs.indices { ctx.fill(roofsPaths[i], with: .color(roofs[i])) }
            y += cell * 0.6
            z += 1
        }
        // Haze over the skyline.
        ctx.fill(Path(CGRect(x: 0, y: 0, width: w, height: h * 0.4)),
                 with: .linearGradient(Gradient(colors: [hexColor(0x3A1C4E, 0.8), hexColor(0x3A1C4E, 0)]),
                                       startPoint: .zero, endPoint: CGPoint(x: 0, y: h * 0.4)))
    }

    // MARK: Ringed planet

    /// A planet in a wide ring of glittering dust, the dust passing behind and in front of it.
    func ringed(_ ctx: inout GraphicsContext, _ size: CGSize) {
        let w = size.width, h = size.height
        ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(hexColor(0x04030A)))
        var stars = Path()
        for i in 0..<300 {
            let r = 0.4 + 0.9 * noise(i, 320)
            stars.addEllipse(in: CGRect(x: noise(i, 321) * w, y: noise(i, 322) * h, width: r * 2, height: r * 2))
        }
        ctx.fill(stars, with: .color(.white.opacity(0.6)))
        let center = CGPoint(x: w * 0.5, y: h * 0.5)
        let radius = min(w, h) * 0.17
        let tilt = 0.36, roll = -0.22
        var back = [Path](repeating: Path(), count: 4), frontP = [Path](repeating: Path(), count: 4)
        for i in 0..<2600 {
            let ringR = radius * (1.45 + 1.25 * pow(noise(i, 323), 0.8))
            let speedI = 0.25 / pow(ringR / radius, 1.5)
            let a = noise(i, 324) * 2 * .pi + t * speedI * speed
            let x = cos(a) * ringR, zz = sin(a) * ringR
            let y = zz * sin(tilt), depth = zz * cos(tilt)
            let px = center.x + x * cos(roll) - y * sin(roll)
            let py = center.y + x * sin(roll) + y * cos(roll)
            let dot = (0.5 + 1.3 * noise(i, 325)) * (1 + 0.6 * min(kick, 1.2) * band(i % 32, of: 32))
            let bucket = min(3, Int(noise(i, 326) * 4))
            let rect = CGRect(x: px - dot, y: py - dot, width: dot * 2, height: dot * 2)
            if depth < 0 { back[bucket].addEllipse(in: rect) } else { frontP[bucket].addEllipse(in: rect) }
        }
        let dust: [Color] = [hexColor(0xF5E6C8, 0.55), hexColor(0xE8C38A, 0.7), hexColor(0xFFFFFF, 0.8), hexColor(0xC9A0FF, 0.6)]
        for i in 0..<4 { ctx.fill(back[i], with: .color(dust[i])) }
        let planet = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
        var body = ctx
        body.clip(to: Path(ellipseIn: planet))
        body.fill(Path(planet), with: .linearGradient(
            Gradient(colors: [hexColor(0xE8B987), hexColor(0xC27A4A), hexColor(0xF0D2A8), hexColor(0xA65A3A), hexColor(0xDDA878)]),
            startPoint: CGPoint(x: planet.minX, y: planet.minY + radius * 0.3), endPoint: CGPoint(x: planet.maxX, y: planet.maxY - radius * 0.3)))
        body.fill(Path(planet), with: .radialGradient(Gradient(colors: [.clear, .black.opacity(0.85)]),
                                                     center: CGPoint(x: center.x - radius * 0.4, y: center.y - radius * 0.4),
                                                     startRadius: radius * 0.3, endRadius: radius * 1.9))
        for i in 0..<4 { ctx.fill(frontP[i], with: .color(dust[i])) }
        ctx.blendMode = .screen
        soft(&ctx, center, radius * 1.6, hexColor(0xFFB070, 0.12 + 0.15 * kick))
    }

    // MARK: Fish school

    /// A shoal of small fish circling in blue water under shafts of light, bursting outward on the beat.
    func school(_ ctx: inout GraphicsContext, _ size: CGSize) {
        let w = size.width, h = size.height
        ctx.fill(Path(CGRect(origin: .zero, size: size)),
                 with: .linearGradient(Gradient(colors: [hexColor(0x0E5A8A), hexColor(0x063353), hexColor(0x020E1C)]),
                                       startPoint: .zero, endPoint: CGPoint(x: 0, y: h)))
        ctx.blendMode = .screen
        for i in 0..<6 {
            let x = w * (0.1 + 0.8 * noise(i, 330)) + sin(t * 0.2 + Double(i)) * w * 0.04
            var ray = Path()
            ray.move(to: CGPoint(x: x - w * 0.015, y: 0))
            ray.addLine(to: CGPoint(x: x + w * 0.015, y: 0))
            ray.addLine(to: CGPoint(x: x + w * 0.09, y: h))
            ray.addLine(to: CGPoint(x: x - w * 0.03, y: h))
            ray.closeSubpath()
            let alpha = 0.06 + 0.05 * sin(t * 0.7 + Double(i) * 2)
            ctx.fill(ray, with: .linearGradient(Gradient(colors: [hexColor(0xBFF4FF, alpha), hexColor(0xBFF4FF, 0)]),
                                                startPoint: CGPoint(x: x, y: 0), endPoint: CGPoint(x: x, y: h * 0.9)))
        }
        ctx.blendMode = .normal
        let center = CGPoint(x: w / 2 + sin(t * 0.21 * speed) * w * 0.16, y: h * 0.52 + sin(t * 0.33 * speed) * h * 0.1)
        let spread = min(w, h) * 0.42 * (1 + 0.18 * min(kick, 1.2))
        var shades = [Path](repeating: Path(), count: 4)
        for i in 0..<750 {
            let r = spread * (0.2 + 0.8 * noise(i, 331).squareRoot())
            let direction = noise(i, 332) < 0.85 ? 1.0 : -1.0
            let a = noise(i, 333) * 2 * .pi + t * (0.5 + 0.5 * noise(i, 334)) * direction * speed
            let lift = (noise(i, 335) - 0.5) * spread * 0.35
            let p = CGPoint(x: center.x + cos(a) * r, y: center.y + sin(a) * r * 0.45 + lift)
            var hx = -sin(a) * direction, hy = cos(a) * 0.45 * direction
            let len = max((hx * hx + hy * hy).squareRoot(), 0.001)
            hx /= len; hy /= len
            let length = 8 + 5 * noise(i, 336), width: Double = 2
            var fish = Path()
            fish.move(to: CGPoint(x: p.x + hx * length, y: p.y + hy * length))
            fish.addLine(to: CGPoint(x: p.x - hy * width, y: p.y + hx * width))
            fish.addLine(to: CGPoint(x: p.x - hx * length * 0.8, y: p.y - hy * length * 0.8))
            fish.addLine(to: CGPoint(x: p.x + hy * width, y: p.y - hx * width))
            fish.closeSubpath()
            shades[min(3, Int((0.5 + 0.5 * sin(a)) * 4))].addPath(fish)
        }
        for i in 0..<4 {
            ctx.fill(shades[i], with: .color(hexColor(0xD8F2FF, 0.35 + 0.18 * Double(i))))
        }
    }

    // MARK: Warp

    /// Stars stretching into streaks as if jumping to light speed, faster on every hit.
    func warp(_ ctx: inout GraphicsContext, _ size: CGSize) {
        let w = size.width, h = size.height, big = max(w, h)
        ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(hexColor(0x02030A)))
        let center = CGPoint(x: w / 2, y: h / 2)
        ctx.blendMode = .screen
        soft(&ctx, center, big * 0.1, hexColor(0x9CC8FF, 0.4 + 0.3 * kick))
        let travel = t * 0.35 * speed + 0.25 * BeatClock.shared.travel(at: Date())
        var white = Path(), blue = Path()
        for i in 0..<520 {
            let angle = noise(i, 340) * 2 * .pi
            let z = fract(noise(i, 341) - travel * (0.6 + 0.8 * noise(i, 342)))
            let r0 = big * 0.02 / max(z, 0.02)
            let r1 = r0 * (1 + (0.15 + 0.45 * min(kick, 1.2)) * (1 - z) * 2)
            guard r0 < big else { continue }
            var streak = Path()
            streak.move(to: CGPoint(x: center.x + cos(angle) * r0, y: center.y + sin(angle) * r0))
            streak.addLine(to: CGPoint(x: center.x + cos(angle) * r1, y: center.y + sin(angle) * r1))
            if i % 3 == 0 { blue.addPath(streak) } else { white.addPath(streak) }
        }
        ctx.stroke(white, with: .color(.white.opacity(0.85)), lineWidth: 1.4)
        ctx.stroke(blue, with: .color(hexColor(0x7FB4FF, 0.9)), lineWidth: 1.8)
    }
}
