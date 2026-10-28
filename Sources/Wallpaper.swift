import AppKit
import SwiftUI

// MARK: - Wallpaper backgrounds

/// The song's artwork as a moving wallpaper, in the styles of lyric edits on reels: a slow Ken Burns drift that
/// kicks on every word, a floating cover, a duotone print, a spinning record and a mirrored kaleidoscope.
struct WallpaperBackground: View {
    let date: Date
    let time: Double
    /// Draws only the cut-out subject of the artwork, lined up exactly with the background, so it can sit on top
    /// of the lyrics and the words pass behind the artist.
    var foreground = false
    @ObservedObject private var style = Style.shared
    @ObservedObject private var player = NowPlaying.shared

    var body: some View {
        let s = style.v
        let t = date.timeIntervalSinceReferenceDate
        let kick = s.beatZoom ? player.kick(at: time, date: date) : 0
        let direction = direct(s.stageBackground, time)
        // Each new line punches in a little; a scene cut punches in hard.
        let pulse = min(1.4, kick + 0.35 * direction.line + direction.cut)
        if foreground {
            let cutout = direction.scene == "duotone" ? player.duotoneCutout : direction.scene == "motion" ? player.cutout : nil
            if s.depth, let cutout {
                GeometryReader { geo in
                    kenBurnsImage(intensified(s, direction.chorus), cutout, geo.size, t, pulse)
                        // Same shading the background gets from its darkening layer.
                        .colorMultiply(Color(white: 1 - (0.1 + s.backgroundDarkness * 0.65)))
                        .shadow(color: .black.opacity(0.45), radius: 24)
                }
                .clipped()
                .id(direction.scene)
                .transition(.opacity)
                .animation(.easeOut(duration: 0.35), value: direction.scene)
            }
        } else if let art = player.wallpaper ?? player.artwork {
            GeometryReader { geo in
                ZStack {
                    Color.black
                    scene(direction.scene, intensified(s, direction.chorus), art, geo.size, t, pulse)
                        .id(direction.scene)
                        .transition(.opacity)
                    Color.black.opacity(0.1 + s.backgroundDarkness * 0.65)
                    // White flash on a scene cut, like a hard edit.
                    Color.white.opacity(direction.cut * 0.35).blendMode(.plusLighter)
                    RadialGradient(colors: [.clear, .black.opacity(0.7)], center: .center,
                                   startRadius: geo.size.height * 0.3, endRadius: geo.size.width * 0.75)
                    Image(nsImage: Grain.image)
                        .resizable(resizingMode: .tile)
                        .opacity(0.09)
                        .blendMode(.overlay)
                }
                .clipped()
            }
            .animation(.easeInOut(duration: 1.5), value: player.artwork)
            .animation(.easeOut(duration: 0.35), value: direction.scene)
        } else {
            AuroraBackground(date: date)
        }
    }

    private static let autoScenes = ["motion", "cover", "disc", "kaleido", "duotone", "vinyl"]

    /// Which scene to show and how hard to hit. Auto changes scene every four lines and goes harder on the chorus.
    private func direct(_ chosen: String, _ time: Double) -> (scene: String, line: Double, cut: Double, chorus: Bool) {
        let lines = player.lyrics
        guard let index = lines.lastIndex(where: { $0.start <= time }) else {
            return (chosen == "auto" ? "motion" : chosen, 0, 0, false)
        }
        let line = exp(-(time - lines[index].start) * 5)
        let chorus = player.repeated.contains(index)
        guard chosen == "auto" else { return (chosen, line, 0, chorus) }
        let section = index / 4
        let cut = section > 0 ? exp(-(time - lines[section * 4].start) * 4) : 0
        return (Self.autoScenes[section % Self.autoScenes.count], line, cut, chorus)
    }

    /// The chorus gets more motion and the RGB split.
    private func intensified(_ s: StyleValues, _ chorus: Bool) -> StyleValues {
        guard chorus else { return s }
        var s = s
        s.motion = min(1, s.motion * 1.5 + 0.1)
        s.rgbSplit = true
        return s
    }

    @ViewBuilder
    private func scene(_ name: String, _ s: StyleValues, _ art: NSImage, _ size: CGSize, _ t: Double,
                       _ pulse: Double) -> some View {
        switch name {
        case "cover": cover(s, art, size, t, pulse)
        case "disc": disc(s, art, size, t, pulse)
        case "duotone": kenBurns(s, player.duotone ?? art, size, t, pulse)
        case "vinyl": vinyl(s, art, size, t, pulse)
        case "kaleido": kaleidoscope(s, art, size, t, pulse)
        default: kenBurns(s, art, size, t, pulse)
        }
    }

    private func fill(_ art: NSImage, _ size: CGSize) -> some View {
        Image(nsImage: art)
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fill)
            .frame(width: size.width, height: size.height)
    }

    /// Pre-blurred artwork, slowly turning — the bed under the cover and the record.
    private func blurredFill(_ art: NSImage, _ size: CGSize, _ t: Double) -> some View {
        fill(player.backdrop ?? art, size)
            .scaleEffect(1.5 + 0.08 * sin(t * 0.07))
            .rotationEffect(.degrees(t * 1.5))
    }

    /// Full-screen artwork that zooms, pans and tilts slowly, and punches in on every sung word.
    @ViewBuilder
    private func kenBurns(_ s: StyleValues, _ art: NSImage, _ size: CGSize, _ t: Double, _ pulse: Double) -> some View {
        let m = s.motion
        let image = kenBurnsImage(s, art, size, t, pulse)
        if s.rgbSplit {
            // Red, green and blue copies pulled apart on the beat and added back together.
            let split = (1.5 + 18 * pulse) * max(m, 0.3)
            ZStack {
                Color.black
                image.colorMultiply(Color(red: 1, green: 0, blue: 0)).offset(x: -split).blendMode(.plusLighter)
                image.colorMultiply(Color(red: 0, green: 1, blue: 0)).blendMode(.plusLighter)
                image.colorMultiply(Color(red: 0, green: 0, blue: 1)).offset(x: split).blendMode(.plusLighter)
            }
            .compositingGroup()
        } else {
            image
        }
    }

    private func kenBurnsImage(_ s: StyleValues, _ art: NSImage, _ size: CGSize, _ t: Double, _ pulse: Double) -> some View {
        let m = s.motion
        let zoom: Double = 1.12 + 0.14 * m * (0.5 + 0.5 * sin(t * 0.08)) + 0.07 * m * pulse
        let tilt: Double = sin(t * 0.05) * 2.5 * m
        let dx: Double = sin(t * 0.061) * size.width * 0.035 * m
        let dy: Double = cos(t * 0.047) * size.height * 0.035 * m
        return fill(art, size)
            .brightness(0.06 * pulse)
            .scaleEffect(zoom)
            .rotationEffect(.degrees(tilt))
            .offset(x: dx, y: dy)
    }

    /// The sharp cover floating in 3D over its own blurred colours.
    private func cover(_ s: StyleValues, _ art: NSImage, _ size: CGSize, _ t: Double, _ pulse: Double) -> some View {
        let m = s.motion
        let side = min(size.width, size.height) * 0.56
        let shape = RoundedRectangle(cornerRadius: side * 0.035, style: .continuous)
        return ZStack {
            blurredFill(art, size, t)
            Image(nsImage: art)
                .resizable()
                .interpolation(.high)
                .aspectRatio(1, contentMode: .fill)
                .frame(width: side, height: side)
                .clipShape(shape)
                .overlay(shape.strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
                .shadow(color: .black.opacity(0.6), radius: 50, y: 24)
                .scaleEffect(1 + 0.035 * m * pulse)
                .rotation3DEffect(.degrees(sin(t * 0.4) * 12 * m), axis: (x: 0, y: 1, z: 0), perspective: 0.5)
                .rotation3DEffect(.degrees(cos(t * 0.31) * 8 * m), axis: (x: 1, y: 0, z: 0), perspective: 0.5)
        }
    }

    /// The artwork as a spinning disc in the middle of the screen, ringed by a spectrum that moves with the music.
    private func disc(_ s: StyleValues, _ art: NSImage, _ size: CGSize, _ t: Double, _ pulse: Double) -> some View {
        let d = min(size.width, size.height) * 0.56
        let face = ZStack {
            Image(nsImage: art)
                .resizable()
                .interpolation(.high)
                .aspectRatio(1, contentMode: .fill)
                .frame(width: d, height: d)
            // Rainbow sheen of a CD's surface.
            AngularGradient(colors: ([.red, .yellow, .green, .cyan, .blue, .purple, .red] as [Color]).map { $0.opacity(0.22) },
                            center: .center)
                .blendMode(.overlay)
            ForEach(0..<6, id: \.self) { i in
                Circle().stroke(Color.black.opacity(0.12), lineWidth: 1).padding(d * (0.08 + Double(i) * 0.06))
            }
            Circle().fill(Color.black.opacity(0.85)).frame(width: d * 0.16, height: d * 0.16)
            Circle().stroke(Color.white.opacity(0.35), lineWidth: 2).frame(width: d * 0.16, height: d * 0.16)
            Circle().fill(Color.black).frame(width: d * 0.05, height: d * 0.05)
        }
        .frame(width: d, height: d)
        .clipShape(Circle())
        .rotationEffect(.degrees(t * 45 * max(s.motion, 0.2)))
        .drawingGroup()
        return ZStack {
            blurredFill(art, size, t).scaleEffect(1 + 0.06 * pulse)
            SpectrumRing(diameter: d, t: t, pulse: pulse, palette: player.palette)
            face
                .overlay(Circle().stroke(Color.white.opacity(0.18), lineWidth: 1.5))
                .shadow(color: .black.opacity(0.6), radius: 40, y: 16)
                .scaleEffect(1 + 0.045 * pulse)
        }
    }

    /// A record with the artwork as its label, spinning at the side of the screen.
    private func vinyl(_ s: StyleValues, _ art: NSImage, _ size: CGSize, _ t: Double, _ pulse: Double) -> some View {
        let d = size.height * 1.05
        let record = ZStack {
            Circle().fill(Color(white: 0.05))
            ForEach(0..<16, id: \.self) { i in
                Circle().stroke(Color.white.opacity(i % 3 == 0 ? 0.06 : 0.03), lineWidth: 1)
                    .padding(d * (0.04 + Double(i) * 0.021))
            }
            Image(nsImage: art)
                .resizable()
                .interpolation(.high)
                .aspectRatio(1, contentMode: .fill)
                .frame(width: d * 0.38, height: d * 0.38)
                .clipShape(Circle())
            Circle().fill(Color.black).frame(width: d * 0.025, height: d * 0.025)
        }
        .frame(width: d, height: d)
        .rotationEffect(.degrees(t * 40 * max(s.motion, 0.15)))
        .drawingGroup()
        // Light catching the grooves stays still while the record turns underneath it.
        .overlay {
            Circle().fill(AngularGradient(colors: [.clear, .white.opacity(0.1), .clear, .clear, .white.opacity(0.1), .clear],
                                          center: .center, angle: .degrees(-30)))
        }
        return ZStack {
            blurredFill(art, size, t)
            record
                .scaleEffect(1 + 0.02 * pulse)
                .shadow(color: .black.opacity(0.7), radius: 60, x: -20)
                .position(x: size.width * 0.82, y: size.height * 0.55)
        }
    }

    /// The artwork mirrored four ways into a seamless pattern that turns and breathes.
    private func kaleidoscope(_ s: StyleValues, _ art: NSImage, _ size: CGSize, _ t: Double, _ pulse: Double) -> some View {
        let m = s.motion
        let tile = hypot(size.width, size.height) / 2  // 2×2 tiles cover the screen at any rotation
        func piece(_ x: CGFloat, _ y: CGFloat) -> some View {
            Image(nsImage: art)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fill)
                .frame(width: tile, height: tile)
                .clipped()
                .scaleEffect(x: x, y: y)
        }
        return VStack(spacing: 0) {
            HStack(spacing: 0) { piece(1, 1); piece(-1, 1) }
            HStack(spacing: 0) { piece(1, -1); piece(-1, -1) }
        }
        .scaleEffect(1.08 + 0.2 * m * (0.5 + 0.5 * sin(t * 0.07)) + 0.08 * m * pulse)
        .rotationEffect(.degrees(t * 5 * m))
        .frame(width: size.width, height: size.height)
    }
}

/// Bars radiating from the disc: the live spectrum when Cadence can hear the music, otherwise a beat-driven shimmer.
struct SpectrumRing: View {
    let diameter: Double
    let t: Double
    let pulse: Double
    let palette: [NSColor]

    var body: some View {
        let bands = AudioPulse.shared.snapshot()?.bands
        Canvas { ctx, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let count = 120
            let inner = diameter / 2 + 10
            for i in 0..<count {
                // Mirrored left/right so bass sits at the top and bottom and the ring is symmetric.
                let half = i < count / 2 ? i : count - 1 - i
                let value: Double
                if let bands {
                    value = Double(bands[min(half * bands.count / (count / 2), bands.count - 1)])
                } else {
                    value = (0.15 + 0.55 * pulse) * (0.5 + 0.5 * sin(t * 3 + Double(half) * 0.45 + noise(half, 21) * 6))
                }
                let length = 6 + value * diameter * 0.28
                let angle = Double(i) / Double(count) * 2 * .pi - .pi / 2
                let dir = CGPoint(x: cos(angle), y: sin(angle))
                var bar = Path()
                bar.move(to: CGPoint(x: center.x + dir.x * inner, y: center.y + dir.y * inner))
                bar.addLine(to: CGPoint(x: center.x + dir.x * (inner + length), y: center.y + dir.y * (inner + length)))
                let color = Color(nsColor: palette[half * palette.count / (count / 2 + 1)])
                    .opacity(0.55 + 0.45 * value)
                ctx.stroke(bar, with: .color(color), style: StrokeStyle(lineWidth: 4, lineCap: .round))
            }
        }
        .shadow(color: Color(nsColor: palette[0]).opacity(0.8), radius: 14)
        .allowsHitTesting(false)
    }
}

// MARK: - Overlays (particles and light leaks over any background)

struct StageEffects: View {
    let date: Date
    let time: Double
    @ObservedObject private var style = Style.shared
    @ObservedObject private var player = NowPlaying.shared

    var body: some View {
        let s = style.v
        let t = date.timeIntervalSinceReferenceDate
        let pulse = player.kick(at: time, date: date)
        ZStack {
            if s.lightLeaks { LightLeaks(t: t, pulse: pulse, palette: player.palette) }
            if s.particles != "none" { Particles(kind: s.particles, t: t, pulse: pulse, palette: player.palette) }
            if s.keywordBursts { KeywordBursts(time: time, palette: player.palette) }
        }
        .allowsHitTesting(false)
    }
}

/// Soft blooms of album colour and warm film light drifting around the edges, like light leaking into a camera.
struct LightLeaks: View {
    let t: Double
    let pulse: Double
    let palette: [NSColor]

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let boost = 1 + 0.5 * pulse
            ZStack {
                leak(Color(nsColor: palette[0]), w * (0.5 + 0.6 * cos(t * 0.11)), h * (0.5 + 0.65 * sin(t * 0.13)),
                     w * 0.45, 0.3 * boost)
                leak(Color(nsColor: palette[1 % palette.count]), w * (0.5 + 0.62 * sin(t * 0.07 + 2)),
                     h * (0.5 + 0.6 * cos(t * 0.09 + 1)), w * 0.4, 0.26 * boost)
                leak(Color(red: 1, green: 0.55, blue: 0.25), w * (0.5 + 0.7 * cos(t * 0.05 + 4)), h * -0.05,
                     w * 0.35, (0.16 + 0.1 * sin(t * 0.3)) * boost)
            }
            .blendMode(.screen)
        }
    }

    private func leak(_ color: Color, _ x: Double, _ y: Double, _ radius: Double, _ opacity: Double) -> some View {
        Circle()
            .fill(RadialGradient(colors: [color.opacity(opacity), color.opacity(opacity * 0.4), .clear],
                                 center: .center, startRadius: 0, endRadius: radius))
            .frame(width: radius * 2, height: radius * 2)
            .position(x: x, y: y)
    }
}

/// Bokeh, twinkling stars, rising embers or drifting dust, all drawn in one Canvas pass.
struct Particles: View {
    let kind: String
    let t: Double
    let pulse: Double
    let palette: [NSColor]

    private func wrap(_ v: Double, _ m: Double) -> Double {
        let r = v.truncatingRemainder(dividingBy: m)
        return r < 0 ? r + m : r
    }

    var body: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height
            let t = self.t.truncatingRemainder(dividingBy: 100_000)
            let count = ["bokeh": 22, "stars": 90, "embers": 60][kind] ?? 120
            for i in 0..<count {
                let r1 = noise(i, 11), r2 = noise(i, 12), r3 = noise(i, 13), r4 = noise(i, 14)
                let color = Color(nsColor: palette[i % palette.count])
                switch kind {
                case "bokeh":
                    let radius = 30 + r3 * 110
                    let y = wrap(r2 * (h + 2 * radius) - t * (8 + r4 * 18), h + 2 * radius) - radius
                    let x = r1 * w + sin(t * 0.2 + r3 * 6) * 40
                    let a = (0.08 + 0.16 * r4) * (1 + 0.7 * pulse)
                    ctx.fill(Path(ellipseIn: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)),
                             with: .radialGradient(Gradient(colors: [color.opacity(a), color.opacity(a * 0.7), color.opacity(0)]),
                                                   center: CGPoint(x: x, y: y), startRadius: 0, endRadius: radius))
                case "stars":
                    let twinkle = 0.5 + 0.5 * sin(t * (1 + r4 * 3) + r3 * 20)
                    let radius = 0.8 + r3 * 2
                    let x = wrap(r1 * w + t * (2 + r4 * 5), w), y = r2 * h
                    let a = twinkle * (0.45 + 0.4 * pulse)
                    ctx.fill(Path(ellipseIn: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)),
                             with: .color(.white.opacity(a)))
                    if r3 > 0.86 {
                        // The brightest few get a four-point flare.
                        let flare = radius * 7 * twinkle
                        ctx.fill(Path(CGRect(x: x - flare, y: y - 0.5, width: flare * 2, height: 1)), with: .color(.white.opacity(a * 0.7)))
                        ctx.fill(Path(CGRect(x: x - 0.5, y: y - flare, width: 1, height: flare * 2)), with: .color(.white.opacity(a * 0.7)))
                    }
                case "embers":
                    let y = wrap(r2 * (h + 40) - t * (30 + r4 * 60), h + 40) - 20
                    let x = r1 * w + sin(t * (0.8 + r3) + r4 * 9) * 30
                    let radius = 1.2 + r3 * 2.4
                    let flicker = 0.6 + 0.4 * sin(t * (6 + r4 * 8) + r1 * 30)
                    let fire = Color(nsColor: palette[0].blended(withFraction: 0.5, of: .orange) ?? palette[0])
                    let a = flicker * (0.5 + 0.4 * pulse) * min(1, y / h * 1.6)  // fade out as they rise
                    let glow = radius * 4
                    ctx.fill(Path(ellipseIn: CGRect(x: x - glow, y: y - glow, width: glow * 2, height: glow * 2)),
                             with: .radialGradient(Gradient(colors: [fire.opacity(a * 0.5), fire.opacity(0)]),
                                                   center: CGPoint(x: x, y: y), startRadius: 0, endRadius: glow))
                    ctx.fill(Path(ellipseIn: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)),
                             with: .color(.white.opacity(a)))
                default:  // dust
                    let x = wrap(r1 * w + t * (6 + r4 * 10), w)
                    let y = wrap(r2 * h + t * (3 + r3 * 6) + sin(t * 0.5 + r4 * 7) * 10, h)
                    let radius = 0.6 + r3 * 1.2
                    ctx.fill(Path(ellipseIn: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)),
                             with: .color(.white.opacity(0.12 + 0.3 * r4)))
                }
            }
        }
    }
}

// MARK: - Lyrics backing

/// Something behind the lyrics so they stay readable over a busy wallpaper.
struct LyricsBacking: ViewModifier {
    let kind: String
    let size: Double

    func body(content: Content) -> some View {
        switch kind {
        case "shade":
            // A soft dark pool behind the words.
            content.background {
                EllipticalGradient(colors: [.black.opacity(0.65), .black.opacity(0.35), .clear],
                                   center: .center, startRadiusFraction: 0, endRadiusFraction: 0.5)
                    .padding(.horizontal, -size * 1.5)
                    .padding(.vertical, -size * 1.1)
            }
        case "glass":
            let shape = RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
            content
                .padding(.horizontal, size * 0.4)
                .padding(.vertical, size * 0.28)
                .background {
                    shape.fill(Color.black.opacity(0.38))
                        .overlay(shape.fill(LinearGradient(colors: [.white.opacity(0.14), .white.opacity(0.03)],
                                                           startPoint: .topLeading, endPoint: .bottomTrailing)))
                        .overlay(shape.strokeBorder(LinearGradient(colors: [.white.opacity(0.4), .white.opacity(0.06)],
                                                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                                                    lineWidth: 1.5))
                        .shadow(color: .black.opacity(0.35), radius: size * 0.3, y: size * 0.1)
                }
        case "band":
            // Cinematic strip across the whole screen.
            content
                .padding(.vertical, size * 0.3)
                .background {
                    Rectangle().fill(Color.black.opacity(0.5))
                        .overlay(alignment: .top) { Rectangle().fill(Color.white.opacity(0.25)).frame(height: 1) }
                        .overlay(alignment: .bottom) { Rectangle().fill(Color.white.opacity(0.25)).frame(height: 1) }
                        .padding(.horizontal, -3000)
                }
        default:
            content
        }
    }
}
