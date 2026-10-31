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
        v.autoSync = c.autoSync
        v.lyricsBackup = c.lyricsBackup
        v.batterySaver = c.batterySaver
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
        Preset(name: "Fan Edit", symbol: "wand.and.stars", blurb: "The cover with big poster lyrics") { v in
            v.stageBackground = "motion"
            v.stageLayout = "reel"
            v.depthOverLyrics = true
            v.fontFamily = "Anton"
            v.fontWeight = "regular"
            v.uppercase = true
            v.keywordBursts = false
            v.motion = 0.9
            v.backgroundDarkness = 0.45
        },
        Preset(name: "Cinema Cut", symbol: "camera.aperture", blurb: "Wide caps, darker grade") { v in
            v.stageBackground = "motion"
            v.stageLayout = "reel"
            v.fontFamily = "Bebas Neue"
            v.fontWeight = "regular"
            v.uppercase = true
            v.tracking = 4
            v.colorMode = "white"
            v.edgeGlow = false
            v.keywordBursts = false
            v.particles = "dust"
            v.motion = 0.5
            v.backgroundDarkness = 0.62
        },
        Preset(name: "Poster Drop", symbol: "textformat.size", blurb: "Heavy poster type") { v in
            v.stageBackground = "motion"
            v.stageLayout = "reel"
            v.fontFamily = "Archivo Black"
            v.fontWeight = "regular"
            v.uppercase = true
            v.keywordBursts = false
            v.motion = 0.85
            v.backgroundDarkness = 0.55
        },
        Preset(name: "Sad Hours", symbol: "cloud.rain.fill", blurb: "Blue duotone, slow italic serif") { v in
            v.stageBackground = "duotone"
            v.stageLayout = "lines"
            v.linesShown = 2
            v.wordStyle = "reveal"
            v.transition = "fade"
            v.particles = "dust"
            v.edgeGlow = false
            v.fontFamily = "Playfair Display"
            v.fontWeight = "regular"
            v.italic = true
            v.colorMode = "custom"
            v.customHex = "#A9CCFF"
            v.motion = 0.25
            v.stageFontSize = 125
            v.backgroundDarkness = 0.65
        },
        Preset(name: "Golden Hour", symbol: "sun.max.fill", blurb: "Warm light leaks, soft bokeh, script") { v in
            v.stageBackground = "motion"
            v.stageLayout = "lines"
            v.linesShown = 2
            v.wordStyle = "shine"
            v.transition = "fade"
            v.particles = "bokeh"
            v.lightLeaks = true
            v.fontFamily = "Lobster"
            v.fontWeight = "regular"
            v.colorMode = "custom"
            v.customHex = "#FFD08A"
            v.motion = 0.35
            v.stageFontSize = 130
        },
        Preset(name: "Y2K", symbol: "sparkle", blurb: "Kaleidoscope, neon outline type, stars") { v in
            v.stageBackground = "kaleido"
            v.wordStyle = "neon"
            v.transition = "flip"
            v.particles = "stars"
            v.fontFamily = "Monoton"
            v.fontWeight = "regular"
            v.uppercase = true
            v.colorMode = "custom"
            v.customHex = "#D0AEFF"
            v.motion = 0.6
            v.stageFontSize = 130
            v.backgroundDarkness = 0.6
        },
        Preset(name: "Polaroid Days", symbol: "photo.fill", blurb: "Swinging polaroid, petals, handwriting") { v in
            v.stageBackground = "polaroid"
            v.stageLayout = "lines"
            v.linesShown = 2
            v.wordStyle = "float"
            v.transition = "fade"
            v.particles = "petals"
            v.lyricsBacking = "shade"
            v.fontFamily = "Caveat"
            v.fontWeight = "bold"
            v.motion = 0.6
            v.stageFontSize = 130
            v.backgroundDarkness = 0.4
        },
        Preset(name: "Mixtape", symbol: "recordingtape", blurb: "Cassette, VHS tape, typed words") { v in
            v.stageBackground = "cassette"
            v.stageLayout = "lines"
            v.linesShown = 2
            v.wordStyle = "typewriter"
            v.transition = "slide"
            v.vhs = true
            v.lyricsBacking = "shade"
            v.fontFamily = "Righteous"
            v.fontWeight = "regular"
            v.motion = 0.5
            v.stageFontSize = 115
            v.backgroundDarkness = 0.45
        },
        Preset(name: "Moonlit", symbol: "moon.fill", blurb: "Lake reflection, fireflies, ink") { v in
            v.stageBackground = "lake"
            v.stageLayout = "lines"
            v.linesShown = 2
            v.wordStyle = "ink"
            v.transition = "fade"
            v.particles = "fireflies"
            v.edgeGlow = false
            v.fontFamily = "Playfair Display"
            v.fontWeight = "regular"
            v.italic = true
            v.colorMode = "white"
            v.motion = 0.5
            v.stageFontSize = 120
            v.backgroundDarkness = 0.4
        },
        Preset(name: "Late Show", symbol: "popcorn.fill", blurb: "Cinema screen, subtitle band") { v in
            v.stageBackground = "cinema"
            v.stageLayout = "lines"
            v.linesShown = 1
            v.wordStyle = "fade"
            v.transition = "fade"
            v.lyricsBacking = "band"
            v.edgeGlow = false
            v.fontFamily = "Bebas Neue"
            v.fontWeight = "regular"
            v.uppercase = true
            v.tracking = 5
            v.colorMode = "white"
            v.stageFontSize = 115
            v.backgroundDarkness = 0.25
        },
        Preset(name: "Synthwave", symbol: "sunset.fill", blurb: "Neon grid, comets, VHS") { v in
            v.stageBackground = "retro"
            v.stageLayout = "lines"
            v.linesShown = 2
            v.wordStyle = "neon"
            v.transition = "zoom"
            v.particles = "comets"
            v.vhs = true
            v.fontFamily = "Unbounded"
            v.fontWeight = "bold"
            v.uppercase = true
            v.colorMode = "custom"
            v.customHex = "#3DE8FF"
            v.motion = 0.7
            v.stageFontSize = 95
            v.backgroundDarkness = 0.3
        },
        Preset(name: "Snow Globe", symbol: "snowflake", blurb: "Floating cover in falling snow") { v in
            v.stageBackground = "cover"
            v.stageLayout = "lines"
            v.linesShown = 2
            v.wordStyle = "float"
            v.transition = "blur"
            v.particles = "snow"
            v.fontFamily = "DM Serif Display"
            v.fontWeight = "regular"
            v.colorMode = "white"
            v.motion = 0.4
            v.stageFontSize = 125
        },
        Preset(name: "Monsoon", symbol: "cloud.heavyrain.fill", blurb: "Rain on the cover, words turn to smoke") { v in
            v.stageBackground = "motion"
            v.stageLayout = "lines"
            v.linesShown = 2
            v.wordStyle = "smoke"
            v.transition = "fade"
            v.particles = "rain"
            v.edgeGlow = false
            v.fontFamily = "Space Grotesk"
            v.fontWeight = "bold"
            v.colorMode = "custom"
            v.customHex = "#BFE0FF"
            v.motion = 0.3
            v.stageFontSize = 115
            v.backgroundDarkness = 0.68
        },
        Preset(name: "Sakura", symbol: "leaf.fill", blurb: "Pink duotone, drifting petals, swinging words") { v in
            v.stageBackground = "duotone"
            v.stageLayout = "lines"
            v.linesShown = 2
            v.wordStyle = "swing"
            v.transition = "fade"
            v.particles = "petals"
            v.lightLeaks = true
            v.fontFamily = "Pacifico"
            v.fontWeight = "regular"
            v.colorMode = "custom"
            v.customHex = "#FFC2DC"
            v.motion = 0.35
            v.stageFontSize = 120
        },
        Preset(name: "Festival", symbol: "fireworks", blurb: "Rising lanterns, rainbow words") { v in
            v.stageBackground = "vinyl"
            v.stageLayout = "lines"
            v.linesShown = 2
            v.wordStyle = "rainbow"
            v.transition = "zoom"
            v.particles = "lanterns"
            v.fontFamily = "Lobster"
            v.fontWeight = "regular"
            v.motion = 0.5
            v.stageFontSize = 130
            v.backgroundDarkness = 0.6
        },
        Preset(name: "Bubblegum", symbol: "bubbles.and.sparkles.fill", blurb: "Bubbles, jelly words, sugar pink") { v in
            v.stageBackground = "cover"
            v.stageLayout = "lines"
            v.linesShown = 2
            v.wordStyle = "jelly"
            v.transition = "scale"
            v.particles = "bubbles"
            v.fontFamily = "Bungee"
            v.fontWeight = "regular"
            v.colorMode = "custom"
            v.customHex = "#FF9AD5"
            v.motion = 0.5
            v.stageFontSize = 105
        },
        Preset(name: "Stadium", symbol: "light.beacon.max.fill", blurb: "Sweeping stage beams, stamped words") { v in
            v.stageBackground = "disc"
            v.wordStyle = "stamp"
            v.transition = "zoom"
            v.lightBeams = true
            v.fontFamily = "Archivo Black"
            v.fontWeight = "regular"
            v.uppercase = true
            v.motion = 0.6
            v.backgroundDarkness = 0.6
        },
        Preset(name: "Ripple", symbol: "water.waves", blurb: "Aurora flow, a wave through the letters") { v in
            v.stageBackground = "aurora"
            v.stageLayout = "lines"
            v.linesShown = 2
            v.wordStyle = "ripple"
            v.transition = "fade"
            v.particles = "bokeh"
            v.fontFamily = "Sora"
            v.fontWeight = "semibold"
            v.stageFontSize = 115
        },
    ]
}

extension Presets {
    /// Every preset in menu order — favourites, then built-in, then the user's — as (name, symbol, values).
    static func all(keeping current: StyleValues) -> [(name: String, symbol: String, values: StyleValues)] {
        let list = builtIn.map { ($0.name, $0.symbol, $0.values(keeping: current)) }
            + PresetStore.shared.custom.map { ($0.name, "star.fill", $0.values(keeping: current)) }
        let favourites = PresetMemory.shared.favourites
        return list.filter { favourites.contains($0.0) } + list.filter { !favourites.contains($0.0) }
    }

    /// The name of the preset the current look matches, if any.
    static func current() -> String? {
        all(keeping: Style.shared.v).first { $0.values == Style.shared.v }?.name
    }

    /// Steps through the presets (from the first or last, if the current look isn't a preset) and flashes the
    /// name — for the lock screen, where there's no menu bar. With favourites set, it stays among those.
    static func step(_ by: Int) {
        let favourites = PresetMemory.shared.favourites
        let everything = all(keeping: Style.shared.v)
        let chosen = everything.filter { favourites.contains($0.name) }
        let list = chosen.isEmpty ? everything : chosen
        let current = list.firstIndex { $0.values == Style.shared.v }
        let index = current.map { ($0 + by + list.count) % list.count } ?? (by > 0 ? 0 : list.count - 1)
        pick(list[index].name, list[index].symbol, list[index].values)
    }

    static func pick(_ name: String, _ symbol: String, _ values: StyleValues) {
        Style.shared.v = values
        PresetToast.shared.show(name, symbol)
    }
}

/// Favourite presets, and which preset to use for a particular song or artist.
final class PresetMemory: ObservableObject {
    static let shared = PresetMemory()

    @Published private(set) var favourites: Set<String> {
        didSet { UserDefaults.standard.set(Array(favourites), forKey: "favouritePresets") }
    }
    @Published private(set) var rules: [String: String] {  // "song:<id>" or "artist:<name>" → preset name
        didSet { UserDefaults.standard.set(rules, forKey: "presetRules") }
    }
    private var usual: StyleValues?  // the look to go back to after a song with its own preset
    private var applied: StyleValues?

    private init() {
        favourites = Set(UserDefaults.standard.stringArray(forKey: "favouritePresets") ?? [])
        rules = UserDefaults.standard.dictionary(forKey: "presetRules") as? [String: String] ?? [:]
    }

    func toggleFavourite(_ name: String) {
        if favourites.contains(name) { favourites.remove(name) } else { favourites.insert(name) }
    }

    private func songKey(_ track: Track) -> String { "song:" + track.id }

    private func artistKey(_ track: Track) -> String {
        let first = track.artist.components(separatedBy: CharacterSet(charactersIn: ",&")).first ?? track.artist
        return "artist:" + first.trimmingCharacters(in: .whitespaces).lowercased()
    }

    /// The song's own preset wins over the artist's.
    func rule(for track: Track) -> String? { rules[songKey(track)] ?? rules[artistKey(track)] }

    func isPinned(_ track: Track?, artist: Bool) -> Bool {
        guard let track else { return false }
        return rules[artist ? artistKey(track) : songKey(track)] != nil
    }

    /// Pins the current preset to the song or artist, or unpins it.
    func togglePin(_ track: Track?, artist: Bool) {
        guard let track else { return }
        let key = artist ? artistKey(track) : songKey(track)
        if rules[key] != nil {
            rules[key] = nil
        } else if let name = Presets.current() {
            rules[key] = name
            // This look now belongs to the pin, so the next ordinary song goes back to the usual one.
            if usual == nil { usual = Style.shared.v }
            applied = Style.shared.v
        }
    }

    func songChanged(_ track: Track) {
        let style = Style.shared
        // Picking a different look by hand during a pinned song makes that the usual look from now on.
        if let applied, style.v != applied {
            usual = nil
            self.applied = nil
        }
        if let name = rule(for: track),
           let preset = Presets.all(keeping: style.v).first(where: { $0.name == name }) {
            if usual == nil { usual = style.v }
            if preset.values != style.v { style.v = preset.values }
            applied = preset.values
        } else if let usual {
            style.v = usual.keepingSystemSettings(from: style.v)
            self.usual = nil
            applied = nil
        }
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
        custom = (data.flatMap { try? JSONDecoder().decode([CustomPreset].self, from: $0) } ?? [])
            .map { CustomPreset(name: $0.name, values: $0.values.withoutRetiredBackground()) }
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
    @ObservedObject private var memory = PresetMemory.shared
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
        let favourite = memory.favourites.contains(name)
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
        .overlay(alignment: .bottomTrailing) {
            Button { memory.toggleFavourite(name) } label: {
                Image(systemName: favourite ? "heart.fill" : "heart").foregroundStyle(favourite ? Color.pink : .secondary)
            }
            .buttonStyle(.plain)
            .padding(8)
            .help("Favourite")
        }
    }
}
