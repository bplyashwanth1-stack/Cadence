import AppKit
import CoreImage
import SwiftUI

/// A living backdrop: flowing mesh of album colours, the artwork blurred into it, vignette and film grain.
struct AuroraBackground: View {
    let date: Date
    @ObservedObject private var style = Style.shared
    @ObservedObject private var player = NowPlaying.shared

    var body: some View {
        let t = date.timeIntervalSinceReferenceDate
        let darkness = style.v.backgroundDarkness
        GeometryReader { geo in
            ZStack {
                Color.black
                mesh(t, darkness)
                if let art = player.backdrop {
                    // Pre-blurred once per song; only scaled and rotated here, which is cheap.
                    Image(nsImage: art)
                        .resizable()
                        .interpolation(.medium)
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .scaleEffect(1.5 + 0.08 * sin(t * 0.07))
                        .rotationEffect(.degrees(t * 1.5))
                        .opacity(0.3)
                }
                Color.black.opacity(0.2 + darkness * 0.4)
                RadialGradient(colors: [.clear, .black.opacity(0.65)], center: .center,
                               startRadius: geo.size.height * 0.25, endRadius: geo.size.width * 0.75)
                Image(nsImage: Grain.image)
                    .resizable(resizingMode: .tile)
                    .opacity(0.08)
                    .blendMode(.overlay)
            }
            .clipped()
        }
        .animation(.easeInOut(duration: 1.5), value: player.palette)
    }

    @ViewBuilder
    private func mesh(_ t: Double, _ darkness: Double) -> some View {
        let base = player.palette.map { $0 }
        let c = (0..<4).map { base[$0 % base.count] }
        // Mix bright and shaded versions of the album colours across the 3x3 mesh.
        let shade = { (color: NSColor, amount: Double) -> Color in
            Color(nsColor: color.blended(withFraction: min(0.95, amount * (0.55 + darkness * 0.45)), of: .black) ?? color)
        }
        let colors: [Color] = [
            shade(c[0], 0.9), shade(c[1], 0.6), shade(c[2], 0.95),
            shade(c[3], 0.5), shade(c[0], 0.25), shade(c[1], 0.7),
            shade(c[2], 0.95), shade(c[3], 0.6), shade(c[0], 0.9),
        ]
        if #available(macOS 15.0, *) {
            MeshGradient(width: 3, height: 3, points: points(t), colors: colors)
        } else {
            LinearGradient(colors: [colors[1], colors[4], colors[7]], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }

    /// Corners stay put, edge points slide along their edge, the centre wanders.
    private func points(_ t: Double) -> [SIMD2<Float>] {
        func wobble(_ phase: Double, _ speed: Double) -> Float { Float(sin(t * speed + phase) * 0.12) }
        return [
            [0, 0], [0.5 + wobble(0, 0.21), 0], [1, 0],
            [0, 0.5 + wobble(1.3, 0.17)], [0.5 + wobble(2.1, 0.23), 0.5 + wobble(3.7, 0.19)], [1, 0.5 + wobble(4.2, 0.15)],
            [0, 1], [0.5 + wobble(5.1, 0.2), 1], [1, 1],
        ]
    }
}

/// Shrinks and blurs the artwork once, so the backdrop never has to blur per frame.
enum Backdrop {
    private static let context = CIContext()

    static func blurred(_ image: NSImage) -> NSImage? {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let input = CIImage(cgImage: cg)
        let scale = 96 / max(input.extent.width, input.extent.height)
        let small = input.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let blurred = small.clampedToExtent()
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 10])
            .cropped(to: small.extent)
        guard let output = context.createCGImage(blurred, from: small.extent) else { return nil }
        return NSImage(cgImage: output, size: NSSize(width: output.width, height: output.height))
    }

    /// Sharp artwork capped at 1200 px with a little extra saturation, for the wallpaper backgrounds.
    static func wallpaper(_ image: NSImage) -> NSImage? {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        var input = CIImage(cgImage: cg)
        let scale = min(1, 1200 / max(input.extent.width, input.extent.height))
        input = input.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let output = input.applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 1.15])
        return render(output, extent: input.extent)
    }

    /// The artwork's light and shade remapped onto a dark and a bright album colour.
    static func duotone(_ image: NSImage, palette: [NSColor]) -> NSImage? {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        var input = CIImage(cgImage: cg)
        let scale = min(1, 1200 / max(input.extent.width, input.extent.height))
        input = input.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        func ci(_ color: NSColor) -> CIColor {
            let c = color.usingColorSpace(.sRGB) ?? color
            return CIColor(red: c.redComponent, green: c.greenComponent, blue: c.blueComponent)
        }
        let dark = palette[0].blended(withFraction: 0.82, of: .black) ?? palette[0]
        let light = palette[palette.count > 1 ? 1 : 0].blended(withFraction: 0.2, of: .white) ?? palette[0]
        let output = input
            .applyingFilter("CIColorControls", parameters: [kCIInputContrastKey: 1.25])
            .applyingFilter("CIFalseColor", parameters: ["inputColor0": ci(dark), "inputColor1": ci(light)])
        return render(output, extent: input.extent)
    }

    private static func render(_ image: CIImage, extent: CGRect) -> NSImage? {
        guard let output = context.createCGImage(image, from: extent) else { return nil }
        return NSImage(cgImage: output, size: NSSize(width: output.width, height: output.height))
    }
}

/// Fine monochrome noise, generated once and tiled.
enum Grain {
    static let image: NSImage = {
        let size = 256
        let noise = CIFilter(name: "CIRandomGenerator")!.outputImage!
            .cropped(to: CGRect(x: 0, y: 0, width: size, height: size))
        let mono = noise.applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0])
        let rep = NSCIImageRep(ciImage: mono)
        let image = NSImage(size: NSSize(width: size, height: size))
        image.addRepresentation(rep)
        return image
    }()
}
