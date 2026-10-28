import AppKit
import SwiftUI

// MARK: - Presets

/// A whole look in one click: background, lyric animation, font, particles and extras together.
struct Preset {
    let name: String
    let symbol: String
    let blurb: String
    let tweak: (inout StyleValues) -> Void

    /// The preset's look on top of the defaults, keeping the settings that aren't about looks.
    func values(keeping current: StyleValues) -> StyleValues {
        var v = StyleValues()
        tweak(&v)
        return v.keepingSystemSettings(from: current)
    }
}

extension StyleValues {
    /// Copies over everything a preset shouldn't touch: where lyrics show, sync, the desktop window, permissions.
    func keepingSystemSettings(from c: StyleValues) -> StyleValues {
        var v = self
        v.showOnLockScreen = c.showOnLockScreen
        v.stageClock = c.stageClock
        v.stageFooter = c.stageFooter
        v.keepAwake = c.keepAwake
        v.audioReactive = c.audioReactive
        v.romanize = c.romanize
        v.titleCard = c.titleCard
        v.showOnDesktop = c.showOnDesktop
        v.fontSize = c.fontSize
        v.width = c.width
        v.background = c.background
        v.backgroundOpacity = c.backgroundOpacity
        v.showHeader = c.showHeader
        v.clickThrough = c.clickThrough
        v.offset = c.offset
        return v
    }
}

enum Presets {
    /// Looks borrowed from lyric edits on reels.
    static let builtIn: [Preset] = [
        Preset(name: "Reel Edit", symbol: "scissors", blurb: "Cuts on the beat, a new effect every line") { _ in },
        Preset(name: "Night Drive", symbol: "moon.stars.fill", blurb: "Spinning vinyl, neon words, stars") { v in
            v.stageBackground = "vinyl"
            v.wordStyle = "neon"
            v.transition = "fade"
            v.particles = "stars"
            v.lightLeaks = true
            v.fontFamily = "Righteous"
            v.fontWeight = "regular"
            v.backgroundDarkness = 0.62
            v.motion = 0.45
        },
        Preset(name: "Hype", symbol: "flame.fill", blurb: "Kaleidoscope, words slam in, embers") { v in
            v.stageBackground = "kaleido"
            v.wordStyle = "slam"
            v.transition = "zoom"
            v.rgbSplit = true
            v.particles = "embers"
            v.motion = 1
            v.fontFamily = "Anton"
            v.fontWeight = "regular"
            v.uppercase = true
            v.stageFontSize = 185
            v.backgroundDarkness = 0.5
        },
        Preset(name: "Chill", symbol: "cloud.fill", blurb: "Floating cover, soft reveal, bokeh") { v in
            v.stageBackground = "cover"
            v.stageLayout = "lines"
            v.linesShown = 3
            v.wordStyle = "reveal"
            v.transition = "blur"
            v.particles = "bokeh"
            v.lyricsBacking = "shade"
            v.fontFamily = "DM Serif Display"
            v.fontWeight = "regular"
            v.motion = 0.35
            v.stageFontSize = 130
        },
        Preset(name: "Love Letter", symbol: "heart.fill", blurb: "Pink duotone, letters cascade in, script") { v in
            v.stageBackground = "duotone"
            v.stageLayout = "lines"
            v.linesShown = 2
            v.wordStyle = "cascade"
            v.transition = "fade"
            v.particles = "bokeh"
            v.lightLeaks = true
            v.fontFamily = "Pacifico"
            v.fontWeight = "regular"
            v.colorMode = "custom"
            v.customHex = "#FF8CC6"
            v.motion = 0.4
            v.stageFontSize = 135
        },
        Preset(name: "Glitchcore", symbol: "waveform.path.ecg", blurb: "RGB split, glitching words, mint") { v in
            v.stageBackground = "motion"
            v.rgbSplit = true
            v.wordStyle = "glitch"
            v.transition = "flip"
            v.particles = "dust"
            v.fontFamily = "Space Grotesk"
            v.fontWeight = "bold"
            v.uppercase = true
            v.tracking = 2
            v.colorMode = "custom"
            v.customHex = "#7CFFCB"
            v.motion = 0.9
        },
        Preset(name: "Movie Subs", symbol: "film.fill", blurb: "Cinematic band, one line, wide caps") { v in
            v.stageBackground = "motion"
            v.stageLayout = "lines"
            v.linesShown = 1
            v.wordStyle = "reveal"
            v.transition = "fade"
            v.lyricsBacking = "band"
            v.particles = "dust"
            v.edgeGlow = false
            v.fontFamily = "Bebas Neue"
            v.fontWeight = "regular"
            v.uppercase = true
            v.tracking = 6
            v.colorMode = "white"
            v.backgroundDarkness = 0.7
            v.motion = 0.3
            v.stageFontSize = 140
        },
        Preset(name: "Galaxy", symbol: "sparkles", blurb: "Spinning disc, comet through the words") { v in
            v.stageBackground = "disc"
            v.stageLayout = "lines"
            v.linesShown = 2
            v.wordStyle = "comet"
            v.transition = "zoom"
            v.particles = "stars"
            v.lyricsBacking = "glass"
            v.fontFamily = "Sora"
            v.fontWeight = "semibold"
            v.stageFontSize = 120
        },
        Preset(name: "Highlighter", symbol: "highlighter", blurb: "Clean word stack with the marker box") { v in
            v.stageBackground = "motion"
            v.stackStyle = "box"
            v.particles = "none"
            v.keywordBursts = false
            v.edgeGlow = false
            v.fontFamily = "Archivo Black"
            v.fontWeight = "regular"
            v.motion = 0.4
        },
    ]
}

extension Presets {
    /// Every preset in menu order — built-in first, then the user's — as (name, symbol, values).
    static func all(keeping current: StyleValues) -> [(name: String, symbol: String, values: StyleValues)] {
        builtIn.map { ($0.name, $0.symbol, $0.values(keeping: current)) }
            + PresetStore.shared.custom.map { ($0.name, "star.fill", $0.values(keeping: current)) }
    }

    /// Switches to the preset after the current one (or the first, if the current look isn't a preset) and
    /// flashes its name — for the ✨ button on the lock screen, where there's no menu bar.
    static func next() {
        let style = Style.shared
        let list = all(keeping: style.v)
        let current = list.firstIndex { $0.values == style.v }
        let pick = list[current.map { ($0 + 1) % list.count } ?? 0]
        style.v = pick.values
        PresetToast.shared.show(pick.name, pick.symbol)
    }
}

/// The name of a preset just switched to, shown briefly on the lock screen.
final class PresetToast: ObservableObject {
    static let shared = PresetToast()
    @Published private(set) var name = ""
    @Published private(set) var symbol = "sparkles"
    @Published private(set) var shownAt = Date.distantPast

    func show(_ name: String, _ symbol: String) {
        self.name = name
        self.symbol = symbol
        shownAt = Date()
    }
}

struct PresetToastView: View {
    let date: Date
    @ObservedObject private var toast = PresetToast.shared

    var body: some View {
        let age = date.timeIntervalSince(toast.shownAt)
        if age >= 0 && age < 1.8 {
            let appear = min(age / 0.2, 1)
            let fade = min(max((1.8 - age) / 0.4, 0), 1)
            HStack(spacing: 10) {
                Image(systemName: toast.symbol)
                Text(toast.name)
            }
            .font(.system(size: 22, weight: .bold, design: .rounded))
            .foregroundStyle(Color.white)
            .padding(.horizontal, 22)
            .padding(.vertical, 12)
            .background(Capsule().fill(Color.black.opacity(0.55)))
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.25), lineWidth: 1))
            .scaleEffect(0.8 + 0.2 * appear)
            .opacity(appear * fade)
        }
    }
}

struct CustomPreset: Codable, Identifiable {
    var id: String { name }
    let name: String
    let values: StyleValues

    func values(keeping current: StyleValues) -> StyleValues { values.keepingSystemSettings(from: current) }
}

/// Looks the user saved, kept in UserDefaults.
final class PresetStore: ObservableObject {
    static let shared = PresetStore()

    @Published private(set) var custom: [CustomPreset] {
        didSet { UserDefaults.standard.set(try? JSONEncoder().encode(custom), forKey: "presets") }
    }

    private init() {
        let data = UserDefaults.standard.data(forKey: "presets")
        custom = data.flatMap { try? JSONDecoder().decode([CustomPreset].self, from: $0) } ?? []
    }

    func save(_ name: String, _ values: StyleValues) {
        let name = name.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        custom.removeAll { $0.name == name }
        custom.append(CustomPreset(name: name, values: values))
    }

    func delete(_ name: String) {
        custom.removeAll { $0.name == name }
    }
}

/// Grid of preset cards for the Settings window, plus saving and deleting your own.
struct PresetPicker: View {
    @ObservedObject private var style = Style.shared
    @ObservedObject private var store = PresetStore.shared
    @State private var newName = ""

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
            ForEach(Presets.builtIn, id: \.name) { preset in
                card(preset.name, preset.symbol, preset.blurb, preset.values(keeping: style.v))
            }
            ForEach(store.custom) { preset in
                card(preset.name, "star.fill", "Your look", preset.values(keeping: style.v))
                    .overlay(alignment: .topTrailing) {
                        Button { store.delete(preset.name) } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .padding(6)
                        .help("Delete this preset")
                    }
            }
        }
        .padding(.vertical, 4)
        HStack {
            TextField("Name", text: $newName, prompt: Text("Save the current look as…"))
                .onSubmit(save)
            Button("Save", action: save).disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    private func save() {
        store.save(newName, style.v)
        newName = ""
    }

    private func card(_ name: String, _ symbol: String, _ blurb: String, _ values: StyleValues) -> some View {
        let selected = style.v == values
        return Button { style.v = values } label: {
            VStack(alignment: .leading, spacing: 4) {
                Image(systemName: symbol).font(.title3)
                Text(name).font(.headline)
                Text(blurb).font(.caption).foregroundStyle(.secondary).lineLimit(2, reservesSpace: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 10)
                .fill(selected ? Color.accentColor.opacity(0.22) : Color.primary.opacity(0.05)))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(selected ? Color.accentColor : .clear, lineWidth: 2))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
