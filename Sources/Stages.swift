import AppKit
import SwiftUI

// MARK: - Staged covers

/// Backgrounds that give the whole cover a place to live: pinned up, in a tape, over water, on a cinema screen or
/// in front of a retro sunset. They move by themselves at a steady pace and never crop into the picture.

func wholeCover(_ art: NSImage, _ side: Double, corner: Double = 0) -> some View {
    Image(nsImage: art)
        .resizable()
        .interpolation(.medium)
        .aspectRatio(contentMode: .fit)
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
}

/// A polaroid on a string, swinging slowly, with the song title written underneath.
struct PolaroidScene: View {
    let art: NSImage
    let title: String
    let size: CGSize
    let t: Double
    let motion: Double

    var body: some View {
        let side = min(size.width, size.height) * 0.56
        let swing = sin(t * 0.7) * 5 * max(motion, 0.3)
        let top = size.height * 0.09
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                Rectangle().fill(Color.white.opacity(0.55)).frame(width: 2, height: top + 8)
                VStack(spacing: side * 0.04) {
                    wholeCover(art, side)
                    Text(title)
                        .font(.custom("Caveat", size: side * 0.095).weight(.bold))
                        .foregroundStyle(Color(white: 0.16))
                        .lineLimit(1)
                        .minimumScaleFactor(0.4)
                        .frame(width: side)
                }
                .padding(.horizontal, side * 0.05)
                .padding(.top, side * 0.05)
                .padding(.bottom, side * 0.08)
                .background(Color(white: 0.96))
                .shadow(color: .black.opacity(0.5), radius: 26, y: 14)
            }
            .rotationEffect(.degrees(swing), anchor: .top)
        }
        .frame(width: size.width, height: size.height, alignment: .top)
    }
}

/// A cassette with the cover on its label and both reels turning.
struct CassetteScene: View {
    let art: NSImage
    let title: String
    let size: CGSize
    let t: Double
    let motion: Double

    var body: some View {
        let width = min(size.width * 0.62, size.height * 0.95)
        let height = width * 0.64
        let body = RoundedRectangle(cornerRadius: width * 0.03, style: .continuous)
        let spin = t * 60 * max(motion, 0.25)
        ZStack {
            body.fill(LinearGradient(colors: [Color(white: 0.2), Color(white: 0.08)], startPoint: .top, endPoint: .bottom))
                .overlay(body.strokeBorder(Color.white.opacity(0.14), lineWidth: 2))
            VStack(spacing: height * 0.035) {
                HStack(spacing: width * 0.03) {
                    wholeCover(art, height * 0.5, corner: 4)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(title)
                            .font(.custom("Caveat", size: height * 0.12).weight(.bold))
                            .foregroundStyle(Color(white: 0.12))
                            .lineLimit(2)
                            .minimumScaleFactor(0.4)
                        ForEach(0..<2, id: \.self) { _ in
                            Rectangle().fill(Color(white: 0.45)).frame(height: 1.5)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(height * 0.03)
                .background(Color(red: 0.95, green: 0.93, blue: 0.86))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                ZStack {
                    Capsule().fill(Color.black.opacity(0.8))
                    HStack(spacing: width * 0.26) {
                        reel(height * 0.22, spin)
                        reel(height * 0.22, spin * 0.8)
                    }
                }
                .frame(width: width * 0.6, height: height * 0.27)
            }
            .padding(height * 0.05)
        }
        .frame(width: width, height: height)
        .shadow(color: .black.opacity(0.55), radius: 30, y: 16)
        .rotation3DEffect(.degrees(sin(t * 0.4) * 7 * motion), axis: (x: 0, y: 1, z: 0), perspective: 0.5)
        .rotation3DEffect(.degrees(cos(t * 0.3) * 4 * motion), axis: (x: 1, y: 0, z: 0), perspective: 0.5)
        .frame(width: size.width, height: size.height)
    }

    private func reel(_ d: Double, _ angle: Double) -> some View {
        ZStack {
            Circle().fill(Color(white: 0.92))
            ForEach(0..<6, id: \.self) { i in
                Capsule().fill(Color(white: 0.2))
                    .frame(width: d * 0.1, height: d * 0.28)
                    .offset(y: -d * 0.3)
                    .rotationEffect(.degrees(Double(i) * 60))
            }
            Circle().fill(Color(white: 0.2)).frame(width: d * 0.26, height: d * 0.26)
        }
        .frame(width: d, height: d)
        .rotationEffect(.degrees(angle))
    }
}

/// The cover over dark water, its reflection trembling, with slow ripples crossing the surface.
struct LakeScene: View {
    let art: NSImage
    let size: CGSize
    let t: Double
    let motion: Double

    var body: some View {
        let side = min(size.width, size.height) * 0.46
        let shore = size.height * 0.58
        ZStack {
            wholeCover(art, side, corner: side * 0.02)
                .shadow(color: .black.opacity(0.4), radius: 20)
                .position(x: size.width / 2, y: shore - side / 2 - 8)
            wholeCover(art, side, corner: side * 0.02)
                .scaleEffect(x: 1, y: -1)
                .mask(LinearGradient(colors: [.white.opacity(0.55), .clear], startPoint: .top, endPoint: .bottom)
                    .frame(width: side, height: side))
                .offset(x: sin(t * 1.1) * 7 * max(motion, 0.3))
                .position(x: size.width / 2, y: shore + side / 2 + 8)
            Canvas { ctx, size in
                ctx.fill(Path(CGRect(x: 0, y: shore, width: size.width, height: 1)), with: .color(.white.opacity(0.14)))
                for i in 0..<44 {
                    let r1 = noise(i, 81), r2 = noise(i, 82), r3 = noise(i, 83)
                    let depth = r2 * r2
                    let y = shore + 12 + depth * (size.height - shore - 12)
                    let length = 40 + depth * 240
                    let travel = (r1 * (size.width + length) + t * (12 + r3 * 26)).truncatingRemainder(dividingBy: size.width + length)
                    let rect = CGRect(x: travel - length, y: y, width: length, height: 1 + depth * 2.5)
                    ctx.fill(Path(ellipseIn: rect), with: .color(.white.opacity(0.1 + 0.16 * r3)))
                }
            }
        }
        .frame(width: size.width, height: size.height)
    }
}

/// A dark cinema: the cover on the screen, a projector beam through drifting dust, heads in the front row.
struct CinemaScene: View {
    let art: NSImage
    let size: CGSize
    let t: Double
    let palette: [NSColor]

    var body: some View {
        let height = size.height * 0.62
        let width = min(size.width * 0.74, height * 1.78)
        let top = size.height * 0.08
        ZStack {
            Color(white: 0.03)
            ZStack {
                Image(nsImage: art).resizable().aspectRatio(contentMode: .fill)
                    .frame(width: width, height: height).clipped().blur(radius: 26).opacity(0.75)
                wholeCover(art, height * 0.94)
            }
            .frame(width: width, height: height)
            .clipped()
            .shadow(color: Color(nsColor: palette[0]).opacity(0.5), radius: 50)
            .position(x: size.width / 2, y: top + height / 2)
            Canvas { ctx, size in
                let source = CGPoint(x: size.width / 2, y: size.height * 1.02)
                let left = size.width / 2 - width / 2, right = size.width / 2 + width / 2
                var beam = Path()
                beam.addLines([source, CGPoint(x: left, y: top + height), CGPoint(x: right, y: top + height)])
                beam.closeSubpath()
                ctx.fill(beam, with: .linearGradient(Gradient(colors: [.white.opacity(0.22), .white.opacity(0.03)]),
                                                     startPoint: source, endPoint: CGPoint(x: size.width / 2, y: top + height)))
                for i in 0..<70 {
                    let r1 = noise(i, 84), r2 = noise(i, 85), r3 = noise(i, 86)
                    let y = (r2 * size.height - t * (6 + r3 * 12)).truncatingRemainder(dividingBy: size.height)
                    let py = y < 0 ? y + size.height : y
                    let spread = max(0, (source.y - py) / (source.y - top - height))
                    let x = size.width / 2 + (r1 - 0.5) * width * min(spread, 1) + sin(t * 0.3 + r3 * 9) * 12
                    ctx.fill(Path(ellipseIn: CGRect(x: x, y: py, width: 2, height: 2)), with: .color(.white.opacity(0.4)))
                }
                // Heads in two rows.
                for row in 0..<2 {
                    let radius = size.height * (row == 0 ? 0.055 : 0.075)
                    let y = size.height * (row == 0 ? 0.93 : 1.0)
                    var x = row == 0 ? -radius : -radius * 2.2
                    var i = 0
                    while x < size.width + radius {
                        let r = radius * (0.9 + 0.2 * noise(i &+ row &* 50, 87))
                        ctx.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2.8)),
                                 with: .color(Color(white: row == 0 ? 0.05 : 0.015)))
                        x += radius * 2.6
                        i += 1
                    }
                }
            }
        }
        .frame(width: size.width, height: size.height)
    }
}

/// A retro sunset with a neon grid rolling towards you, the cover floating on the horizon.
struct RetroGridScene: View {
    let art: NSImage
    let size: CGSize
    let t: Double
    let motion: Double
    let palette: [NSColor]

    var body: some View {
        let horizon = size.height * 0.62
        let side = min(size.width, size.height) * 0.42
        let main = Color(nsColor: palette[0])
        let second = Color(nsColor: palette[1 % palette.count])
        ZStack {
            LinearGradient(colors: [Color(red: 0.03, green: 0.01, blue: 0.12), second.opacity(0.75), main],
                           startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.62))
            Circle()
                .fill(LinearGradient(colors: [Color(red: 1, green: 0.85, blue: 0.4), Color(red: 1, green: 0.25, blue: 0.5)],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: side * 1.7, height: side * 1.7)
                .position(x: size.width / 2, y: horizon - side * 0.35)
            Canvas { ctx, size in
                ctx.fill(Path(CGRect(x: 0, y: horizon, width: size.width, height: size.height - horizon)),
                         with: .color(Color(red: 0.03, green: 0.01, blue: 0.1)))
                let line = GraphicsContext.Shading.color(Color(red: 0.2, green: 0.95, blue: 1).opacity(0.75))
                var grid = Path()
                let middle = size.width / 2
                for i in -14...14 {
                    grid.move(to: CGPoint(x: middle + Double(i) * 34, y: horizon))
                    grid.addLine(to: CGPoint(x: middle + Double(i) * size.width * 0.42, y: size.height))
                }
                let step = (t * 0.6 * max(motion, 0.3)).truncatingRemainder(dividingBy: 1)
                for i in 0..<16 {
                    let z = (Double(i) + 1 - step) / 16
                    let y = horizon + (size.height - horizon) * z * z
                    grid.addRect(CGRect(x: 0, y: y, width: size.width, height: 1))
                }
                ctx.stroke(grid, with: line, lineWidth: 1.2)
                ctx.fill(Path(CGRect(x: 0, y: horizon - 1, width: size.width, height: 3)),
                         with: .color(Color(red: 0.2, green: 0.95, blue: 1)))
            }
            wholeCover(art, side, corner: side * 0.02)
                .shadow(color: main, radius: 34)
                .offset(y: sin(t * 0.6) * 9 * motion)
                .position(x: size.width / 2, y: horizon - side * 0.42)
        }
        .frame(width: size.width, height: size.height)
    }
}

// MARK: - Overlays

/// Stage spotlights sweeping slowly from above, at a steady brightness.
struct LightBeams: View {
    let t: Double
    let travel: Double
    let palette: [NSColor]

    var body: some View {
        Canvas { ctx, size in
            for i in 0..<4 {
                let color = i == 3 ? Color.white : Color(nsColor: palette[i % palette.count])
                let root = CGPoint(x: size.width * (0.14 + 0.24 * Double(i)), y: -30)
                let p = t.truncatingRemainder(dividingBy: 9000) * 0.42 + travel * 0.1 + Double(i) * 1.7
                let angle = sin(p) * 0.62
                let reach = size.height * 1.5
                let spread = 0.1
                func point(_ a: Double) -> CGPoint {
                    CGPoint(x: root.x + sin(a) * reach, y: root.y + cos(a) * reach)
                }
                var beam = Path()
                beam.addLines([root, point(angle - spread), point(angle + spread)])
                beam.closeSubpath()
                ctx.fill(beam, with: .linearGradient(Gradient(colors: [color.opacity(0.34), color.opacity(0)]),
                                                     startPoint: root, endPoint: point(angle)))
            }
        }
        .blendMode(.screen)
    }
}

/// Worn tape: fine scan lines, faint colour fringing at the edges and a tracking band rolling down the picture.
struct VHSOverlay: View {
    let t: Double

    var body: some View {
        Canvas { ctx, size in
            var lines = Path()
            var y = 0.0
            while y < size.height {
                lines.addRect(CGRect(x: 0, y: y, width: size.width, height: 1))
                y += 4
            }
            ctx.fill(lines, with: .color(.black.opacity(0.22)))
            let band = (t.truncatingRemainder(dividingBy: 1000) * 34).truncatingRemainder(dividingBy: size.height + 120) - 60
            ctx.fill(Path(CGRect(x: 0, y: band, width: size.width, height: 60)),
                     with: .linearGradient(Gradient(colors: [.white.opacity(0), .white.opacity(0.09), .white.opacity(0)]),
                                           startPoint: CGPoint(x: 0, y: band), endPoint: CGPoint(x: 0, y: band + 60)))
            ctx.fill(Path(CGRect(x: 0, y: 0, width: 5, height: size.height)), with: .color(.red.opacity(0.1)))
            ctx.fill(Path(CGRect(x: size.width - 5, y: 0, width: 5, height: size.height)), with: .color(.cyan.opacity(0.1)))
        }
    }
}
