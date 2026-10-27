import AppKit
import CoreText
import SwiftUI

// MARK: - Style settings

/// Every customisation lives here; persisted as one JSON blob so defaults are declared once.
struct StyleValues: Codable, Equatable {
    // Font
    var fontFamily = "Unbounded"
    var fontWeight = "bold"
    var italic = false
    var uppercase = false
    var tracking = 0.0
    var lineSpacing = 14.0
    var alignment = "center"
    var textShadow = true

    // Color
    var colorMode = "album"  // album, white, custom
    var customHex = "#FF5FA2"
    var unsungOpacity = 0.3
    var glow = 0.5

    // Animation
    var wordStyle = "reveal"  // fill, reveal, bounce, typewriter, bloom, wave, pop, fade
    var transition = "zoom"  // slide, zoom, flip, push, drop, blur, scale, fade
    var bounce = 0.35
    var blurInactive = true
    var linesShown = 3

    // Lock screen
    var showOnLockScreen = true
    var stageLayout = "stack"  // stack (one word at a time, Verci-style), lines
    var stageFontSize = 150.0
    var stageIcons = true
    var stageDrift = true
    var stageBackground = "aurora"  // aurora, album, gradient, custom, black
    var backgroundDarkness = 0.55
    var stageHex = "#14141A"
    var edgeGlow = true
    var stageFooter = true
    var stageClock = true
    var keepAwake = true

    // Desktop
    var showOnDesktop = false
    var fontSize = 34.0
    var width = 760.0
    var background = "none"  // none, blur, glass, dim
    var backgroundOpacity = 0.6
    var showHeader = false
    var clickThrough = true

    // Sync
    var offset = 0.0
}

final class Style: ObservableObject {
    static let shared = Style()

    @Published var v: StyleValues {
        didSet { UserDefaults.standard.set(try? JSONEncoder().encode(v), forKey: "style") }
    }

    private init() {
        if let data = UserDefaults.standard.data(forKey: "style"),
           let saved = try? JSONDecoder().decode(StyleValues.self, from: data) {
            v = saved
        } else {
            v = StyleValues()
        }
    }
}

extension StyleValues {
    static func weight(_ name: String) -> Font.Weight {
        switch name {
        case "light": return .light
        case "regular": return .regular
        case "medium": return .medium
        case "semibold": return .semibold
        case "heavy": return .heavy
        case "black": return .black
        default: return .bold
        }
    }

    static func font(family: String, size: Double, weight: Font.Weight, italic: Bool) -> Font {
        let font: Font
        switch family {
        case "System": font = .system(size: size, weight: weight)
        case "System Rounded": font = .system(size: size, weight: weight, design: .rounded)
        case "System Serif": font = .system(size: size, weight: weight, design: .serif)
        case "System Mono": font = .system(size: size, weight: weight, design: .monospaced)
        case "System Expanded": font = .system(size: size, weight: weight).width(.expanded)
        case "System Condensed": font = .system(size: size, weight: weight).width(.condensed)
        case "System Compressed": font = .system(size: size, weight: weight).width(.compressed)
        default: font = .custom(family, size: size).weight(weight)
        }
        return italic ? font.italic() : font
    }

    func font(size: Double) -> Font {
        Self.font(family: fontFamily, size: size, weight: Self.weight(fontWeight), italic: italic)
    }

    var horizontal: HorizontalAlignment {
        alignment == "leading" ? .leading : alignment == "trailing" ? .trailing : .center
    }

    var frameAlignment: Alignment {
        alignment == "leading" ? .leading : alignment == "trailing" ? .trailing : .center
    }

    var anchor: UnitPoint {
        alignment == "leading" ? .leading : alignment == "trailing" ? .trailing : .center
    }

    /// On a full-screen album-coloured background the album gradient would vanish, so use white there.
    private func usesWhite(onStage: Bool) -> Bool {
        colorMode == "white"
            || (onStage && colorMode == "album" && ["aurora", "album", "gradient"].contains(stageBackground))
    }

    func highlight(_ palette: [NSColor], onStage: Bool) -> AnyShapeStyle {
        if usesWhite(onStage: onStage) { return AnyShapeStyle(Color.white) }
        if colorMode == "custom" { return AnyShapeStyle(Color(hex: customHex)) }
        let colors = palette.map { Color(nsColor: $0.blended(withFraction: 0.2, of: .white) ?? $0) }
        return AnyShapeStyle(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing))
    }

    func glowColor(_ palette: [NSColor], onStage: Bool) -> Color {
        if usesWhite(onStage: onStage) { return .white }
        if colorMode == "custom" { return Color(hex: customHex) }
        return Color(nsColor: palette[0])
    }
}

extension Color {
    init(hex: String) {
        let value = UInt64(hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) ?? 0xFFFFFF
        self.init(red: Double((value >> 16) & 0xFF) / 255,
                  green: Double((value >> 8) & 0xFF) / 255,
                  blue: Double(value & 0xFF) / 255)
    }

    var hex: String {
        let c = NSColor(self).usingColorSpace(.sRGB) ?? .white
        return String(format: "#%02X%02X%02X", Int(c.redComponent * 255), Int(c.greenComponent * 255),
                      Int(c.blueComponent * 255))
    }
}

/// True inside the full-screen lock-screen view, so shared views can size and colour themselves for it.
private struct StageKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var isStage: Bool {
        get { self[StageKey.self] }
        set { self[StageKey.self] = newValue }
    }
}

// MARK: - Fonts

enum Fonts {
    static let system = ["System", "System Rounded", "System Serif", "System Mono",
                         "System Expanded", "System Condensed", "System Compressed"]

    /// Fonts shipped inside Cadence.app/Contents/Resources/Fonts, registered for this process.
    static let bundled: [String] = {
        guard let dir = Bundle.main.resourceURL?.appendingPathComponent("Fonts"),
              let urls = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
        else { return [] }
        var families = Set<String>()
        for url in urls where ["ttf", "otf"].contains(url.pathExtension.lowercased()) {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor] ?? []
            for d in descriptors {
                if let family = CTFontDescriptorCopyAttribute(d, kCTFontFamilyNameAttribute) as? String {
                    families.insert(family)
                }
            }
        }
        return families.sorted()
    }()

    /// Stylish fonts that ship with macOS.
    static let stylishSystem: [String] = {
        let installed = Set(NSFontManager.shared.availableFontFamilies)
        return ["Avenir Next", "Futura", "Helvetica Neue", "Didot", "Bodoni 72", "Baskerville", "Hoefler Text",
                "Gill Sans", "Optima", "Rockwell", "Copperplate", "American Typewriter", "Marker Felt",
                "Noteworthy", "Chalkduster", "Bradley Hand", "Snell Roundhand", "SignPainter", "Zapfino",
                "Phosphate", "Impact", "Trattatello", "Luminari"].filter(installed.contains)
    }()

    static var featured: [String] { system + bundled + stylishSystem }

    static var all: [String] { NSFontManager.shared.availableFontFamilies.sorted() }
}
