import AppKit
import SwiftUI

// MARK: - Worlds

/// Whole scenes for the cover to live in. Like the staged covers, they run at a steady pace of their own and show
/// the picture complete.
struct WorldScene: View {
    static let kinds: [(tag: String, name: String)] = [
        ("gallery", "Gallery — framed on a wall under a moving light"),
        ("billboard", "Billboard — above a city at night"),
        ("crt", "Old TV — on a glowing tube set"),
        ("galaxy", "Deep Space — among the stars, a moon in orbit"),
        ("ocean", "Ocean — over rolling waves"),
        ("mountains", "Mountains — ridges drifting past"),
        ("highway", "Highway — driving into the night"),
        ("neonwall", "Neon Wall — in neon tubes on brick"),
        ("aquarium", "Aquarium — with fish swimming past"),
        ("forest", "Forest — through misty trees"),
        ("coderain", "Code Rain — behind falling code"),
        ("newspaper", "Front Page — the day's headline"),
    ]

    let kind: String
    let art: NSImage
    let title: String
    let artist: String
    let size: CGSize
    let t: Double
    let motion: Double
    let palette: [NSColor]

    private var main: Color { Color(nsColor: palette[0]) }
    private var second: Color { Color(nsColor: palette[1 % palette.count]) }
    private var speed: Double { max(motion, 0.3) }

    var body: some View {
        Group {
            switch kind {
            case "gallery": gallery
            case "billboard": billboard
            case "crt": crt
            case "galaxy": galaxy
            case "ocean": ocean
            case "mountains": mountains
            case "highway": highway
            case "neonwall": neonWall
            case "aquarium": aquarium
            case "forest": forest
            case "coderain": codeRain
            default: newspaper
            }
        }
        .frame(width: size.width, height: size.height)
        .clipped()
    }

    private var side: Double { min(size.width, size.height) }

    private func wrap(_ v: Double, _ m: Double) -> Double {
        let r = v.truncatingRemainder(dividingBy: m)
        return r < 0 ? r + m : r
    }

    private var gallery: some View {
        let cover = side * 0.5
        let light = size.width * (0.5 + 0.34 * sin(t * 0.35 * speed))
        return ZStack {
            LinearGradient(colors: [Color(white: 0.16), Color(white: 0.09)], startPoint: .top, endPoint: .bottom)
            Rectangle().fill(Color(white: 0.05)).frame(height: size.height * 0.14)
                .frame(maxHeight: .infinity, alignment: .bottom)
            VStack(spacing: side * 0.03) {
                wholeCover(art, cover)
                    .padding(cover * 0.08)
                    .background(Color(white: 0.95))
                    .padding(cover * 0.03)
                    .background(LinearGradient(colors: [Color(red: 0.8, green: 0.62, blue: 0.3), Color(red: 0.42, green: 0.28, blue: 0.1)],
                                               startPoint: .topLeading, endPoint: .bottomTrailing))
                    .shadow(color: .black.opacity(0.6), radius: 22, y: 14)
                VStack(spacing: 2) {
                    Text(title).font(.system(size: 13, weight: .semibold, design: .serif))
                    Text(artist).font(.system(size: 11, design: .serif)).opacity(0.7)
                }
                .lineLimit(1)
                .foregroundStyle(Color(white: 0.1))
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(Color(white: 0.88))
            }
            .offset(y: -size.height * 0.03)
            RadialGradient(colors: [Color(red: 1, green: 0.93, blue: 0.75).opacity(0.3), .clear], center: .center,
                           startRadius: 0, endRadius: side * 0.62)
                .frame(width: side * 1.24, height: side * 1.24)
                .position(x: light, y: size.height * 0.42)
                .blendMode(.screen)
        }
    }

    private var billboard: some View {
        let height = size.height * 0.42
        let width = height * 2.1
        return ZStack {
            LinearGradient(colors: [Color(red: 0.03, green: 0.03, blue: 0.13), second.opacity(0.6)], startPoint: .top, endPoint: .bottom)
            Canvas { ctx, size in
                for layer in 0..<2 {
                    var x = -20.0
                    var i = layer &* 40
                    while x < size.width {
                        let w = 70 + noise(i, 101) * 90
                        let h = size.height * (0.25 + 0.4 * noise(i, 102)) * (layer == 0 ? 1.15 : 0.8)
                        let top = size.height * 0.92 - h
                        ctx.fill(Path(CGRect(x: x, y: top, width: w, height: h)), with: .color(Color(white: layer == 0 ? 0.07 : 0.03)))
                        var y = top + 10
                        var row = 0
                        while y < size.height * 0.9 {
                            var wx = x + 8
                            var col = 0
                            while wx < x + w - 10 {
                                if noise(i &* 31 &+ row &* 7 &+ col, 103) > 0.62 {
                                    ctx.fill(Path(CGRect(x: wx, y: y, width: 6, height: 8)),
                                             with: .color(Color(red: 1, green: 0.85, blue: 0.5).opacity(0.55)))
                                }
                                wx += 13
                                col += 1
                            }
                            y += 16
                            row += 1
                        }
                        x += w + 4
                        i += 1
                    }
                }
                ctx.fill(Path(CGRect(x: 0, y: size.height * 0.92, width: size.width, height: size.height * 0.08)), with: .color(Color(white: 0.02)))
                for i in 0..<14 {
                    let right = i % 2 == 0
                    let run = wrap(noise(i, 104) * size.width + t * (90 + noise(i, 105) * 110) * (right ? 1 : -1), size.width + 80) - 40
                    let color = right ? Color(red: 1, green: 0.2, blue: 0.2) : Color(red: 1, green: 0.95, blue: 0.75)
                    ctx.fill(Path(CGRect(x: run, y: size.height * (right ? 0.945 : 0.965), width: 26, height: 2.5)), with: .color(color.opacity(0.9)))
                }
            }
            HStack(spacing: height * 0.08) {
                wholeCover(art, height * 0.82)
                VStack(alignment: .leading, spacing: 6) {
                    Text(title).font(.system(size: height * 0.13, weight: .heavy, design: .rounded)).lineLimit(2).minimumScaleFactor(0.4)
                    Text(artist).font(.system(size: height * 0.07, weight: .medium, design: .rounded)).opacity(0.8).lineLimit(1)
                }
                .foregroundStyle(Color.white)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(height * 0.08)
            .frame(width: width, height: height)
            .background(LinearGradient(colors: [main.opacity(0.9), Color(white: 0.06)], startPoint: .leading, endPoint: .trailing))
            .overlay(Rectangle().strokeBorder(Color(white: 0.3), lineWidth: 5))
            .shadow(color: main.opacity(0.7), radius: 40)
            .position(x: size.width / 2, y: size.height * 0.33)
            HStack(spacing: width * 0.6) {
                Rectangle().fill(Color(white: 0.1)).frame(width: 12, height: size.height * 0.4)
                Rectangle().fill(Color(white: 0.1)).frame(width: 12, height: size.height * 0.4)
            }
            .position(x: size.width / 2, y: size.height * 0.74)
        }
    }

    private var crt: some View {
        let height = size.height * 0.64
        let width = height * 1.34
        return ZStack {
            LinearGradient(colors: [Color(red: 0.08, green: 0.05, blue: 0.04), Color(red: 0.02, green: 0.02, blue: 0.03)], startPoint: .top, endPoint: .bottom)
            Rectangle().fill(Color(red: 0.16, green: 0.09, blue: 0.05)).frame(height: size.height * 0.16)
                .frame(maxHeight: .infinity, alignment: .bottom)
            Ellipse().fill(RadialGradient(colors: [main.opacity(0.35), .clear], center: .center, startRadius: 0, endRadius: width * 0.8))
                .frame(width: width * 1.8, height: height * 1.5)
                .position(x: size.width / 2, y: size.height * 0.46)
            VStack(spacing: 0) {
                ZStack {
                    Rectangle().stroke(Color(white: 0.55), lineWidth: 3).frame(width: 2, height: height * 0.3)
                        .rotationEffect(.degrees(-26), anchor: .bottom).offset(x: -height * 0.07)
                    Rectangle().stroke(Color(white: 0.55), lineWidth: 3).frame(width: 2, height: height * 0.3)
                        .rotationEffect(.degrees(30), anchor: .bottom).offset(x: height * 0.07)
                }
                .frame(height: height * 0.26, alignment: .bottom)
                HStack(spacing: height * 0.05) {
                    ZStack {
                        Color.black
                        wholeCover(art, height * 0.72)
                        Canvas { ctx, size in
                            var lines = Path()
                            var y = 0.0
                            while y < size.height { lines.addRect(CGRect(x: 0, y: y, width: size.width, height: 1)); y += 3 }
                            ctx.fill(lines, with: .color(.black.opacity(0.28)))
                            let band = wrap(t * 40, size.height + 50) - 25
                            ctx.fill(Path(CGRect(x: 0, y: band, width: size.width, height: 26)), with: .color(.white.opacity(0.05)))
                        }
                    }
                    .frame(width: width * 0.76, height: height * 0.78)
                    .clipShape(RoundedRectangle(cornerRadius: height * 0.06, style: .continuous))
                    VStack(spacing: height * 0.05) {
                        ForEach(0..<2, id: \.self) { i in
                            Circle().fill(Color(white: 0.75)).frame(width: height * 0.08, height: height * 0.08)
                                .overlay(Rectangle().fill(Color(white: 0.2)).frame(width: 2, height: height * 0.04).offset(y: -height * 0.015))
                                .rotationEffect(.degrees(Double(i) * 70 + 20))
                        }
                        ForEach(0..<4, id: \.self) { _ in
                            Rectangle().fill(Color.black.opacity(0.5)).frame(width: height * 0.1, height: 3)
                        }
                    }
                }
                .padding(height * 0.05)
                .background(RoundedRectangle(cornerRadius: height * 0.05, style: .continuous)
                    .fill(LinearGradient(colors: [Color(red: 0.4, green: 0.25, blue: 0.13), Color(red: 0.22, green: 0.13, blue: 0.07)],
                                         startPoint: .top, endPoint: .bottom)))
            }
            .shadow(color: .black.opacity(0.6), radius: 24, y: 12)
            .position(x: size.width / 2, y: size.height * 0.5)
        }
    }

    private var galaxy: some View {
        let cover = side * 0.46
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let angle = t * 0.4 * speed
        let orbitX = cos(angle) * cover * 1.25, orbitY = sin(angle) * cover * 0.32
        return ZStack {
            Color(red: 0.01, green: 0.01, blue: 0.05)
            Canvas { ctx, size in
                for (color, x, y, radius) in [(main, 0.2 + 0.05 * sin(t * 0.05), 0.3, 0.7), (second, 0.8, 0.7 + 0.05 * cos(t * 0.04), 0.65)] {
                    let c = CGPoint(x: size.width * x, y: size.height * y), r = size.width * radius
                    ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
                             with: .radialGradient(Gradient(colors: [color.opacity(0.32), color.opacity(0)]), center: c, startRadius: 0, endRadius: r))
                }
                for i in 0..<220 {
                    let depth = 0.3 + 0.7 * noise(i, 106)
                    let x = wrap(noise(i, 107) * size.width - t * 5 * depth, size.width), y = noise(i, 108) * size.height
                    let r = depth * 1.5
                    ctx.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)), with: .color(.white.opacity(0.3 + 0.6 * depth)))
                }
                var ring = Path(ellipseIn: CGRect(x: center.x - cover * 1.25, y: center.y - cover * 0.32, width: cover * 2.5, height: cover * 0.64))
                ring = ring.applying(.identity)
                ctx.stroke(ring, with: .color(.white.opacity(0.28)), lineWidth: 1.2)
            }
            moon(cover).position(x: center.x + orbitX, y: center.y + orbitY).zIndex(orbitY < 0 ? 0 : 2)
            wholeCover(art, cover, corner: cover * 0.02)
                .shadow(color: main.opacity(0.8), radius: 36)
                .rotation3DEffect(.degrees(sin(t * 0.3) * 10 * motion), axis: (x: 0.2, y: 1, z: 0), perspective: 0.5)
                .zIndex(1)
        }
    }

    private func moon(_ cover: Double) -> some View {
        Circle()
            .fill(RadialGradient(colors: [Color(white: 0.95), second, Color(white: 0.08)], center: UnitPoint(x: 0.3, y: 0.3),
                                 startRadius: 0, endRadius: cover * 0.11))
            .frame(width: cover * 0.2, height: cover * 0.2)
    }

    private var ocean: some View {
        let cover = side * 0.44
        return ZStack {
            LinearGradient(colors: [Color(red: 0.08, green: 0.05, blue: 0.2), main, Color(red: 1, green: 0.72, blue: 0.45)],
                           startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.66))
            wholeCover(art, cover, corner: cover * 0.02)
                .shadow(color: .black.opacity(0.4), radius: 24, y: 10)
                .offset(y: sin(t * 0.7 * speed) * 10)
                .position(x: size.width / 2, y: size.height * 0.34)
            Canvas { ctx, size in
                for layer in 0..<5 {
                    let f = Double(layer) / 4
                    let top = size.height * (0.6 + 0.08 * Double(layer))
                    var wave = Path()
                    wave.move(to: CGPoint(x: 0, y: size.height))
                    var x = 0.0
                    while x <= size.width + 20 {
                        let p = x * (0.006 + 0.002 * f)
                        let y = top + sin(p + t * (0.5 + 0.35 * f) * speed + Double(layer) * 1.4) * (9 + 14 * f)
                            + sin(p * 2.3 - t * 0.4 * speed + Double(layer)) * (4 + 6 * f)
                        wave.addLine(to: CGPoint(x: x, y: y))
                        x += 18
                    }
                    wave.addLine(to: CGPoint(x: size.width, y: size.height))
                    wave.closeSubpath()
                    ctx.fill(wave, with: .color(Color(red: 0.02 + 0.08 * (1 - f), green: 0.12 + 0.2 * (1 - f), blue: 0.25 + 0.3 * (1 - f))))
                }
            }
        }
    }

    private func ridge(_ x: Double, _ layer: Int) -> Double {
        let a = Double(layer) * 3.7
        return sin(x * 0.004 + a) * 0.5 + sin(x * 0.011 + a * 2) * 0.28 + sin(x * 0.027 + a * 3) * 0.12
    }

    private var mountains: some View {
        let cover = side * 0.4
        return ZStack {
            LinearGradient(colors: [second.opacity(0.9), main, Color(red: 1, green: 0.8, blue: 0.55)], startPoint: .top, endPoint: .bottom)
            wholeCover(art, cover, corner: cover * 0.02)
                .shadow(color: Color(red: 1, green: 0.85, blue: 0.6), radius: 40)
                .position(x: size.width / 2, y: size.height * 0.36)
            Canvas { ctx, size in
                for layer in 0..<5 {
                    let f = Double(layer) / 4
                    let base = size.height * (0.58 + 0.095 * Double(layer))
                    let shift = t * (5 + 34 * f) * speed
                    var path = Path()
                    path.move(to: CGPoint(x: 0, y: size.height))
                    var x = 0.0
                    while x <= size.width + 16 {
                        path.addLine(to: CGPoint(x: x, y: base - ridge(x + shift, layer) * size.height * (0.09 - 0.03 * f)))
                        x += 14
                    }
                    path.addLine(to: CGPoint(x: size.width, y: size.height))
                    path.closeSubpath()
                    ctx.fill(path, with: .color(Color(white: 0.34 - 0.3 * f).opacity(0.96)))
                }
            }
        }
    }

    private var highway: some View {
        let cover = side * 0.34
        let horizon = size.height * 0.5
        return ZStack {
            LinearGradient(colors: [Color(red: 0.02, green: 0.02, blue: 0.1), second.opacity(0.5), main.opacity(0.75)], startPoint: .top,
                           endPoint: UnitPoint(x: 0.5, y: 0.5))
            Canvas { ctx, size in
                let middle = size.width / 2
                ctx.fill(Path(CGRect(x: 0, y: horizon, width: size.width, height: size.height - horizon)), with: .color(Color(white: 0.02)))
                var road = Path()
                road.addLines([CGPoint(x: middle - 24, y: horizon), CGPoint(x: middle + 24, y: horizon),
                               CGPoint(x: middle + size.width * 0.62, y: size.height), CGPoint(x: middle - size.width * 0.62, y: size.height)])
                road.closeSubpath()
                ctx.fill(road, with: .color(Color(white: 0.09)))
                let run = t * 0.9 * speed
                for i in 0..<14 {
                    let z = wrap(Double(i) / 14 + run, 1), s = z * z
                    let y = horizon + (size.height - horizon) * s
                    let w = 2 + 12 * s, h = 2 + 58 * s
                    ctx.fill(Path(CGRect(x: middle - w / 2, y: y, width: w, height: h)), with: .color(Color(red: 1, green: 0.85, blue: 0.4).opacity(0.3 + 0.7 * z)))
                }
                for i in 0..<8 {
                    let z = wrap(Double(i) / 8 + run * 0.7, 1), s = z * z
                    let y = horizon + (size.height - horizon) * s
                    for side in [-1.0, 1.0] {
                        let x = middle + side * (28 + size.width * 0.74 * s)
                        let pole = 8 + 230 * s
                        ctx.fill(Path(CGRect(x: x - 1, y: y - pole, width: 1 + 3 * s, height: pole)), with: .color(Color(white: 0.2)))
                        let r = 2 + 44 * s
                        let top = CGPoint(x: x, y: y - pole)
                        let warm = Color(red: 1, green: 0.78, blue: 0.45)
                        ctx.fill(Path(ellipseIn: CGRect(x: top.x - r, y: top.y - r, width: r * 2, height: r * 2)),
                                 with: .radialGradient(Gradient(colors: [warm.opacity(0.85), warm.opacity(0)]), center: top, startRadius: 0, endRadius: r))
                    }
                }
            }
            wholeCover(art, cover, corner: cover * 0.02)
                .shadow(color: main, radius: 34)
                .position(x: size.width / 2, y: horizon - cover * 0.58)
        }
    }

    private var neonWall: some View {
        let cover = side * 0.5
        let tube = Color(red: 1, green: 0.2, blue: 0.62), cool = Color(red: 0.2, green: 0.95, blue: 1)
        let shape = RoundedRectangle(cornerRadius: cover * 0.05, style: .continuous)
        return ZStack {
            Canvas { ctx, size in
                ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(red: 0.08, green: 0.04, blue: 0.05)))
                let bw = 62.0, bh = 25.0
                var mortar = Path()
                var row = 0
                var y = 0.0
                while y < size.height {
                    mortar.addRect(CGRect(x: 0, y: y, width: size.width, height: 2))
                    var x = row % 2 == 0 ? 0.0 : -bw / 2
                    while x < size.width { mortar.addRect(CGRect(x: x, y: y, width: 2, height: bh)); x += bw }
                    y += bh
                    row += 1
                }
                ctx.fill(mortar, with: .color(.black.opacity(0.55)))
            }
            Ellipse().fill(RadialGradient(colors: [tube.opacity(0.32), .clear], center: .center, startRadius: 0, endRadius: side * 0.62))
                .frame(width: side * 1.5, height: side * 1.2)
            VStack(spacing: side * 0.035) {
                Text("NOW PLAYING")
                    .font(.custom("Monoton", size: side * 0.05))
                    .foregroundStyle(Color.white)
                    .shadow(color: cool, radius: 4).shadow(color: cool, radius: 16)
                wholeCover(art, cover, corner: cover * 0.05)
                    .overlay(shape.stroke(Color.white, lineWidth: 3))
                    .shadow(color: tube, radius: 6).shadow(color: tube, radius: 22).shadow(color: tube, radius: 46)
            }
        }
    }

    private var aquarium: some View {
        let cover = side * 0.42
        return ZStack {
            LinearGradient(colors: [Color(red: 0.08, green: 0.55, blue: 0.72), Color(red: 0.02, green: 0.13, blue: 0.3)], startPoint: .top, endPoint: .bottom)
            wholeCover(art, cover, corner: cover * 0.03)
                .shadow(color: .black.opacity(0.4), radius: 22, y: 10)
                .offset(y: sin(t * 0.5) * 8)
            Canvas { ctx, size in
                for i in 0..<4 {
                    let x = size.width * (0.14 + 0.24 * Double(i)) + sin(t * 0.3 + Double(i)) * 60
                    var ray = Path()
                    ray.addLines([CGPoint(x: x - 30, y: 0), CGPoint(x: x + 30, y: 0), CGPoint(x: x + 150, y: size.height), CGPoint(x: x - 90, y: size.height)])
                    ray.closeSubpath()
                    ctx.fill(ray, with: .linearGradient(Gradient(colors: [.white.opacity(0.13), .white.opacity(0)]), startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
                }
                for i in 0..<18 {
                    let r1 = noise(i, 109), r2 = noise(i, 110), r3 = noise(i, 111)
                    let right = i % 2 == 0
                    let length = 22 + r3 * 44
                    let run = wrap(r1 * (size.width + 200) + t * (24 + r3 * 40) * speed * (right ? 1 : -1), size.width + 200) - 100
                    let y = size.height * (0.1 + 0.8 * r2) + sin(t * 0.8 + r1 * 9) * 12
                    let color = Color(hue: (0.02 + r3 * 0.16 + (i % 3 == 0 ? 0.5 : 0)).truncatingRemainder(dividingBy: 1), saturation: 0.8, brightness: 1)
                    var c = ctx
                    c.translateBy(x: run, y: y)
                    if !right { c.scaleBy(x: -1, y: 1) }
                    let wag = sin(t * 8 + r1 * 20) * length * 0.1
                    var tail = Path()
                    tail.addLines([CGPoint(x: -length * 0.42, y: 0), CGPoint(x: -length * 0.8, y: -length * 0.26 + wag), CGPoint(x: -length * 0.8, y: length * 0.26 + wag)])
                    tail.closeSubpath()
                    c.fill(tail, with: .color(color.opacity(0.9)))
                    c.fill(Path(ellipseIn: CGRect(x: -length / 2, y: -length * 0.25, width: length, height: length * 0.5)), with: .color(color))
                    c.fill(Path(ellipseIn: CGRect(x: length * 0.24, y: -length * 0.09, width: length * 0.08, height: length * 0.08)), with: .color(.black))
                }
                for i in 0..<24 {
                    let radius = 2 + noise(i, 112) * 6
                    let y = wrap(noise(i, 113) * size.height - t * (30 + noise(i, 114) * 40), size.height)
                    let x = noise(i, 115) * size.width + sin(t + Double(i)) * 8
                    ctx.stroke(Path(ellipseIn: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)), with: .color(.white.opacity(0.4)), lineWidth: 1)
                }
                var sand = Path()
                sand.move(to: CGPoint(x: 0, y: size.height))
                var x = 0.0
                while x <= size.width + 20 {
                    sand.addLine(to: CGPoint(x: x, y: size.height * 0.93 + sin(x * 0.012) * 10))
                    x += 20
                }
                sand.addLine(to: CGPoint(x: size.width, y: size.height))
                sand.closeSubpath()
                ctx.fill(sand, with: .color(Color(red: 0.72, green: 0.6, blue: 0.38).opacity(0.8)))
            }
        }
    }

    private var forest: some View {
        let cover = side * 0.38
        return ZStack {
            LinearGradient(colors: [Color(red: 0.03, green: 0.08, blue: 0.12), second.opacity(0.45), Color(red: 0.55, green: 0.7, blue: 0.68)],
                           startPoint: .top, endPoint: .bottom)
            wholeCover(art, cover, corner: cover * 0.02)
                .shadow(color: Color(red: 0.8, green: 1, blue: 0.9).opacity(0.7), radius: 34)
                .position(x: size.width / 2, y: size.height * 0.31)
            Canvas { ctx, size in
                for layer in 0..<4 {
                    let f = Double(layer) / 3
                    let width = 34 + 58 * f
                    let height = size.height * (0.15 + 0.16 * f)
                    let gap = width * 1.1
                    let shift = wrap(t * (2 + 14 * f) * speed, gap)
                    var x = -gap * 2 - shift
                    var i = 0
                    var trees = Path()
                    while x < size.width + gap {
                        let tall = height * (0.8 + 0.4 * noise(i &+ layer &* 37, 116))
                        let foot = size.height * (0.78 + 0.07 * Double(layer))
                        for tier in 0..<3 {
                            let top = foot - tall + tall * Double(tier) * 0.2
                            let spread = width * (0.42 + 0.2 * Double(tier))
                            trees.addLines([CGPoint(x: x, y: top), CGPoint(x: x + spread, y: top + tall * 0.42), CGPoint(x: x - spread, y: top + tall * 0.42)])
                            trees.closeSubpath()
                        }
                        trees.addRect(CGRect(x: x - width * 0.05, y: foot - tall * 0.2, width: width * 0.1, height: tall * 0.3))
                        x += gap
                        i += 1
                    }
                    ctx.fill(trees, with: .color(Color(red: 0.03, green: 0.12 - 0.08 * f, blue: 0.1 - 0.06 * f).opacity(0.65 + 0.35 * f)))
                    let mist = wrap(t * (8 + 8 * f), size.width + 500) - 250
                    ctx.fill(Path(ellipseIn: CGRect(x: mist - 300, y: size.height * (0.66 + 0.06 * f), width: 900, height: 110)),
                             with: .radialGradient(Gradient(colors: [.white.opacity(0.12), .white.opacity(0)]),
                                                   center: CGPoint(x: mist + 150, y: size.height * (0.66 + 0.06 * f) + 55), startRadius: 0, endRadius: 450))
                }
                ctx.fill(Path(CGRect(x: 0, y: size.height * 0.83, width: size.width, height: size.height * 0.17)), with: .color(Color(red: 0.01, green: 0.03, blue: 0.03)))
            }
        }
    }

    private var codeRain: some View {
        let cover = side * 0.46
        let green = Color(red: 0.24, green: 1, blue: 0.52)
        return ZStack {
            Color.black
            Canvas { ctx, size in
                let glyphs = ["0", "1", "ア", "カ", "サ", "ナ", "ハ", "マ", "ヤ", "ラ", "7", "Z"]
                let bright = glyphs.map { ctx.resolve(Text($0).font(.system(size: 17, weight: .bold, design: .monospaced)).foregroundColor(.white)) }
                let dim = glyphs.map { ctx.resolve(Text($0).font(.system(size: 17, design: .monospaced)).foregroundColor(green)) }
                let columns = Int(size.width / 24)
                for col in 0..<columns {
                    let trail = 8 + Int(noise(col, 117) * 10)
                    let head = wrap(noise(col, 118) * size.height * 2 + t * (70 + noise(col, 119) * 120), size.height * 1.6)
                    for i in 0..<trail {
                        let y = head - Double(i) * 21
                        guard y > -20, y < size.height + 20 else { continue }
                        let index = Int(noise(col &* 31 &+ i, 120) * Double(glyphs.count))
                        var c = ctx
                        c.opacity = i == 0 ? 1 : (1 - Double(i) / Double(trail)) * 0.75
                        c.draw(i == 0 ? bright[index] : dim[index], at: CGPoint(x: Double(col) * 24 + 12, y: y))
                    }
                }
            }
            wholeCover(art, cover, corner: 4)
                .overlay(Rectangle().strokeBorder(green, lineWidth: 2))
                .shadow(color: green.opacity(0.7), radius: 30)
        }
    }

    private var newspaper: some View {
        let width = min(size.width * 0.72, size.height * 1.3)
        let cover = size.height * 0.42
        let ink = Color(white: 0.09)
        return ZStack {
            Color(white: 0.1)
            VStack(spacing: size.height * 0.016) {
                Text("THE DAILY CADENCE")
                    .font(.custom("Abril Fatface", size: size.height * 0.066))
                    .foregroundStyle(ink)
                Rectangle().fill(ink).frame(height: 3)
                Text(title.uppercased())
                    .font(.custom("Abril Fatface", size: size.height * 0.052))
                    .foregroundStyle(ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.4)
                HStack(alignment: .top, spacing: size.height * 0.03) {
                    column(ink)
                    VStack(spacing: 6) {
                        wholeCover(art, cover)
                            .saturation(0.25)
                        Text(artist).font(.system(size: 12, weight: .medium, design: .serif)).italic().foregroundStyle(ink).lineLimit(1)
                    }
                    column(ink)
                }
            }
            .padding(size.height * 0.03)
            .frame(width: width)
            .background(Color(red: 0.92, green: 0.89, blue: 0.81))
            .shadow(color: .black.opacity(0.6), radius: 24, y: 10)
            .rotationEffect(.degrees(sin(t * 0.25) * 1.8 * motion))
        }
    }

    private func column(_ ink: Color) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(0..<16, id: \.self) { i in
                Rectangle().fill(ink.opacity(0.55)).frame(height: 2.5)
                    .padding(.trailing, i % 5 == 4 ? 30 : 0)
            }
        }
        .frame(maxWidth: .infinity)
    }
}
