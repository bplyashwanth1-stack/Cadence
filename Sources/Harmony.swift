import AppKit
import SwiftUI

// MARK: - Colour harmonies

/// Lyric colours built from one source colour (the album art's, or your own) by colour-wheel rules, so the
/// words always belong together and stay readable on a dark stage.
enum Harmony {
    static let modes: [(tag: String, name: String)] = [
        ("source", "Source match — the colour itself"),
        ("tonal", "Tonal — lighter and darker shades of it"),
        ("analogous", "Analogous — its neighbours on the colour wheel"),
        ("complementary", "Complementary — its opposite"),
        ("split", "Split complementary — either side of its opposite"),
        ("triadic", "Triadic — three evenly spaced colours"),
    ]

    struct Set {
        let highlight: Color  // the word being sung
        let text: Color  // the rest of the line
        let support: Color  // depth, outlines, extras
        let ink: Color  // text on a filled highlight
    }

    static func colors(_ source: NSColor, _ mode: String) -> Set {
        let c = source.usingColorSpace(.deviceRGB) ?? source
        let hue = c.hueComponent
        // Vivid enough to read as a colour, bright enough to read on dark backgrounds.
        let saturation = max(c.saturationComponent, 0.55)
        func color(_ shift: Double, _ s: Double = saturation, _ b: Double = 0.95) -> NSColor {
            NSColor(hue: (hue + shift).truncatingRemainder(dividingBy: 1) + (hue + shift < 0 ? 1 : 0),
                    saturation: min(s, 1), brightness: min(b, 1), alpha: 1)
        }
        let highlight = color(0, saturation, max(c.brightnessComponent, 0.85))
        let text: NSColor, support: NSColor
        switch mode {
        case "tonal": text = color(0, saturation * 0.35, 1); support = color(0, saturation, 0.55)
        case "analogous": text = color(1.0 / 12, saturation * 0.6); support = color(-1.0 / 12, saturation, 0.8)
        case "complementary": text = color(0.5, saturation * 0.55); support = color(0.5, saturation, 0.7)
        case "split": text = color(5.0 / 12, saturation * 0.6); support = color(7.0 / 12, saturation, 0.75)
        case "triadic": text = color(1.0 / 3, saturation * 0.6); support = color(2.0 / 3, saturation, 0.75)
        default: text = color(0, saturation * 0.25, 1); support = color(0, saturation, 0.6)
        }
        // Dark ink on light highlights, white on dark ones.
        let rgb = highlight.usingColorSpace(.deviceRGB) ?? highlight
        let luminance = 0.2126 * rgb.redComponent + 0.7152 * rgb.greenComponent + 0.0722 * rgb.blueComponent
        return Set(highlight: Color(nsColor: highlight), text: Color(nsColor: text), support: Color(nsColor: support),
                   ink: luminance > 0.6 ? Color(white: 0.08) : .white)
    }
}
