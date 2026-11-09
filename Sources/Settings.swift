import AppKit
import SwiftUI

struct FontGallery: View {
    @Binding var selection: String
    let weight: String
    let italic: Bool

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 10)], spacing: 10) {
            ForEach(Fonts.featured, id: \.self) { name in
                let selected = selection == name
                Button { selection = name } label: {
                    VStack(spacing: 4) {
                        Text("Aa").font(StyleValues.font(family: name, size: 28, weight: StyleValues.weight(weight),
                                                         italic: italic))
                            .frame(height: 40)
                        Text(name).font(.caption).lineLimit(1).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 10)
                        .fill(selected ? Color.accentColor.opacity(0.22) : Color.primary.opacity(0.05)))
                    .overlay(RoundedRectangle(cornerRadius: 10)
                        .stroke(selected ? Color.accentColor : Color.clear, lineWidth: 2))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
    }
}

struct SettingsView: View {
    let preview: () -> Void
    let resetPosition: () -> Void
    @ObservedObject private var style = Style.shared
    @ObservedObject private var player = NowPlaying.shared
    @ObservedObject private var timing = SongTiming.shared
    @AppStorage(UpdateChecker.defaultsKey) private var checkForUpdates = true

    var body: some View {
        // Four tabs, so each page stays short.
        TabView {
            Form {
                nowPlaying
                Section("Presets") {
                    Toggle("Shuffle: each new song gets a different favourite look", isOn: $style.v.shuffleLooks)
                    PresetPicker()
                }
                lockScreen
            }
            .formStyle(.grouped)
            .tabItem { Label("Look", systemImage: "paintpalette") }

            Form {
                font
                text
                color
                animation
            }
            .formStyle(.grouped)
            .tabItem { Label("Lyrics", systemImage: "textformat") }

            Form {
                desktop
            Section("YouTube") {
                Toggle("Follow YouTube and YouTube Music in the browser", isOn: $style.v.youtube)
                if style.v.youtube {
                    Text("Works in Chrome, Safari, Arc, Brave, Edge and Vivaldi. Spotify and Music come first when they're playing.")
                        .font(.caption).foregroundStyle(.secondary)
                    ForEach(YouTube.blocked, id: \.bundleID) { browser in
                        Text("⚠️ \(browser.name) needs one switch turned on — \(browser.setting).")
                            .font(.caption)
                    }
                }
            }

            }
            .formStyle(.grouped)
            .tabItem { Label("Desktop", systemImage: "menubar.dock.rectangle") }

            Form {
                nowPlaying
            Section("Sync") {
                if let id = player.track?.id {
                    slider("This song", Binding(get: { timing.offset(id) }, set: { timing.set($0, for: id) }),
                           -3...3) { String(format: "%+.2f s", $0) }
                    HStack {
                        Button("Tap to sync this song…") {
                            DistributedNotificationCenter.default().post(name: .init("local.cadence.tapsync"), object: nil)
                        }
                        if timing.tappedIDs.contains(id) {
                            Button("Remove my tapped timing") {
                                timing.removeTapped(id)
                                player.reloadLyrics()
                            }
                        }
                    }
                }
                slider("All songs", $style.v.offset, -3...3) { String(format: "%+.1f s", $0) }
                Toggle("Auto-fix timing from the audio", isOn: $style.v.autoSync)
                Toggle("Match my headphones' delay", isOn: $style.v.matchOutput)
                Toggle("Learn each song's timing as it plays", isOn: $style.v.learnTiming)
                Toggle("Also search NetEase when LRCLIB has nothing (unofficial)", isOn: $style.v.lyricsBackup)
                if style.v.autoSync && AutoSync.shared.offset != 0 {
                    LabeledContent("Auto correction") { Text(String(format: "%+.1f s", AutoSync.shared.offset)) }
                }
                Button("Search lyrics again") { player.reloadLyrics() }
            }

                Section("Your lyrics") {
                    Toggle("Keep my edited lyrics in iCloud Drive (shared with my other Macs)", isOn: $style.v.syncLyrics)
                    Toggle("Show a translation under lyrics in another language", isOn: $style.v.translate)
                }
                Section {
                    Button("Reset all settings") { style.v = StyleValues() }
                }
            }
            .formStyle(.grouped)
            .tabItem { Label("Timing", systemImage: "timer") }
        }
        .frame(width: 560, height: 760)
    }

    private var nowPlaying: some View {
        Section {
            LabeledContent("Now playing") {
                Text(player.track.map { "\($0.title) — \($0.artist)" } ?? "Nothing").lineLimit(1)
            }
            if !player.status.isEmpty {
                LabeledContent("Lyrics") { Text(player.status) }
            }
        }
    }

    private var lockScreen: some View {
        Section("Lock screen") {
            Toggle("Show lyrics on lock screen", isOn: $style.v.showOnLockScreen)
            Picker("Layout", selection: $style.v.stageLayout) {
                ForEach(StyleValues.layouts, id: \.0) { Text($0.1).tag($0.0) }
            }
            let original = Presets.defaultLayout(for: style.v)
            if style.v.stageLayout != original.layout {
                Button("Back to the default style (\(original.preset ?? "Cadence's original"))") {
                    style.v.stageLayout = original.layout
                }
            }
            Picker("Other displays", selection: $style.v.secondLayout) {
                Text("Same as this one").tag("same")
                Divider()
                ForEach(StyleValues.layouts.filter { $0.0 != "matched" }, id: \.0) { Text($0.1).tag($0.0) }
            }
            .help("The lyric style on your other screens, when the live wallpaper is on")
            if StyleValues.visualLayouts.contains(style.v.stageLayout) {
                Picker("Lyric colours", selection: $style.v.lyricColors) {
                    Text("The style's own").tag("look")
                    Text("From the album art").tag("album")
                    Text("My colour").tag("custom")
                }
                if style.v.lyricColors == "custom" {
                    ColorPicker("Lyric colour", selection: Binding(
                        get: { Color(hex: style.v.lyricHex) },
                        set: { style.v.lyricHex = $0.hex }
                    ), supportsOpacity: false)
                }
                if style.v.lyricColors != "look" {
                    Picker("Harmony", selection: $style.v.harmony) {
                        ForEach(Harmony.modes, id: \.tag) { Text($0.name).tag($0.tag) }
                    }
                }
            }
            if style.v.stageLayout == "matched" {
                Text("Each visual brings its own lyric look; other backgrounds use a column.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if style.v.stageLayout == "column" {
                Picker("Word being sung", selection: $style.v.stackStyle) {
                    Text("Large, in the lyric colour").tag("effect")
                    Text("In a box").tag("box")
                }
            }
            if style.v.stageLayout == "stack" {
                Picker("Word being sung", selection: $style.v.stackStyle) {
                    Text("Word effect (from Animation below)").tag("effect")
                    Text("Highlighter box").tag("box")
                }
                Toggle("Icons beside words", isOn: $style.v.stageIcons)
                Toggle("3D drift", isOn: $style.v.stageDrift)
            }
            if style.v.stageLayout == "constellation" {
                Toggle("Stars drift", isOn: $style.v.stageDrift)
            }
            Picker("Background", selection: $style.v.stageBackground) {
                Text("Auto — cuts between scenes, harder on the chorus").tag("auto")
                Text("Motion wallpaper — artwork drifts and kicks").tag("motion")
                Text("Black & white — the artwork in high-contrast mono").tag("mono")
                Text("Floating cover — artwork tilting in 3D").tag("cover")
                Text("Disc — spinning disc with a visualizer ring").tag("disc")
                Text("Duotone — artwork in two album colors").tag("duotone")
                Text("Vinyl — spinning record").tag("vinyl")
                Text("Kaleidoscope — mirrored artwork").tag("kaleido")
                Text("Polaroid — the cover swinging on a string").tag("polaroid")
                Text("Cassette — the cover on a turning tape").tag("cassette")
                Text("Moonlit Lake — the cover over rippling water").tag("lake")
                Text("Cinema — the cover on the big screen").tag("cinema")
                Text("Retro Grid — the cover on a neon sunset").tag("retro")
                ForEach(WorldScene.kinds, id: \.tag) { Text($0.name).tag($0.tag) }
                Divider()
                Text("Visual Mix — cuts between the visuals, a different one per screen").tag("visualmix")
                ForEach(Visuals.kinds, id: \.tag) { Text($0.name).tag($0.tag) }
                Divider()
                Text("Aurora — flowing album colors and artwork").tag("aurora")
                Text("Album color").tag("album")
                Text("Album gradient").tag("gradient")
                Text("Custom color").tag("custom")
                Text("Black").tag("black")
            }
            if style.v.stageBackground == "custom" {
                ColorPicker("Background color", selection: Binding(
                    get: { Color(hex: style.v.stageHex) },
                    set: { style.v.stageHex = $0.hex }
                ), supportsOpacity: false)
            }
            if ["aurora", "album", "gradient"].contains(style.v.stageBackground)
                || StyleValues.wallpapers.contains(style.v.stageBackground) {
                slider("Background darkness", $style.v.backgroundDarkness, 0...0.95) {
                    String(format: "%.0f%%", $0 * 100)
                }
            }
            if StyleValues.wallpapers.contains(style.v.stageBackground) {
                slider("Motion", $style.v.motion, 0...1) { String(format: "%.0f%%", $0 * 100) }
                Toggle("Kick on the beat", isOn: $style.v.beatZoom)
                Toggle("Visuals take on the album's colour", isOn: $style.v.tintVisuals)
                Toggle("Artist in front of the clock (motion, mono and duotone scenes)", isOn: $style.v.depth)
                if style.v.depth {
                    Toggle("…and in front of the lyrics (can hide words)", isOn: $style.v.depthOverLyrics)
                }
                if ["motion", "mono", "duotone"].contains(style.v.stageBackground) {
                    Toggle("RGB split", isOn: $style.v.rgbSplit)
                }
            }
            Picker("Particles", selection: $style.v.particles) {
                Text("None").tag("none")
                Text("Bokeh").tag("bokeh")
                Text("Stars").tag("stars")
                Text("Embers").tag("embers")
                Text("Dust").tag("dust")
                Text("Snow").tag("snow")
                Text("Rain").tag("rain")
                Text("Petals").tag("petals")
                Text("Fireflies").tag("fireflies")
                Text("Lanterns").tag("lanterns")
                Text("Comets").tag("comets")
                Text("Bubbles").tag("bubbles")
            }
            Toggle("Light leaks", isOn: $style.v.lightLeaks)
            Toggle("Stage beams", isOn: $style.v.lightBeams)
            Toggle("VHS look", isOn: $style.v.vhs)
            Toggle("Keyword bursts — fire, rain, hearts, stars… when sung", isOn: $style.v.keywordBursts)
            Toggle("React to the music (asks to listen to audio)", isOn: $style.v.audioReactive)
            Picker("Behind the lyrics", selection: $style.v.lyricsBacking) {
                Text("Nothing").tag("none")
                Text("Soft shade").tag("shade")
                Text("Glass card").tag("glass")
                Text("Band").tag("band")
                Text("Paper note").tag("paper")
                Text("Terminal").tag("terminal")
                Text("Chat bubble").tag("bubble")
                Text("Road sign").tag("sign")
            }
            slider("Lyrics size", $style.v.stageFontSize, 60...300) { String(format: "%.0f pt", $0) }
            Toggle("Edge light (stays as you set it, whatever the preset)", isOn: $style.v.edgeGlow)
            if style.v.edgeGlow {
                Picker("Edge light", selection: $style.v.edgeStyle) {
                    Text("Racing streaks").tag("race")
                    Text("Full rim").tag("rim")
                }
                .pickerStyle(.segmented)
                Picker("Edge colour", selection: $style.v.edgeColor) {
                    Text("Album art").tag("album")
                    Text("White").tag("white")
                    Text("Custom").tag("custom")
                }
                .pickerStyle(.segmented)
                if style.v.edgeColor == "custom" {
                    ColorPicker("Edge light colour", selection: Binding(
                        get: { Color(hex: style.v.edgeHex) },
                        set: { style.v.edgeHex = $0.hex }
                    ), supportsOpacity: false)
                }
                slider("Thickness", $style.v.edgeThickness, 10...220) { String(format: "%.0f pt", $0) }
                slider("Brightness", $style.v.edgeBrightness, 0.1...1) { String(format: "%.0f%%", $0 * 100) }
                Toggle("Move with the music", isOn: $style.v.edgeBeat)
                Toggle("Also on the desktop while music plays", isOn: $style.v.edgeDesktop)
            }
            Toggle("Clock", isOn: $style.v.stageClock)
            Toggle("Title card when a song starts", isOn: $style.v.titleCard)
            Toggle("Now-playing bar (hover for controls)", isOn: $style.v.stageFooter)
            Toggle("Keep screen awake while playing", isOn: $style.v.keepAwake)
            Toggle("Battery saver — lighter visuals when unplugged", isOn: $style.v.batterySaver)
            Toggle("Tell me when a new version is out", isOn: $checkForUpdates)
                .onChange(of: checkForUpdates) { UpdateChecker.shared.check() }
            Button("Preview for 10 seconds", action: preview)
        }
    }

    private var font: some View {
        Section("Font") {
            Toggle("Use my font for every style (presets keep it too)", isOn: $style.v.myFont)
            if !style.v.myFont {
                Text("Off: the visual looks and presets use the font they were designed with.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            // Picking a font means you want to see it, so it switches "use my font" on.
            let family = Binding(get: { style.v.fontFamily }, set: { style.v.fontFamily = $0; style.v.myFont = true })
            FontGallery(selection: family, weight: style.v.fontWeight, italic: style.v.italic)
            Picker("All installed fonts", selection: family) {
                ForEach(Fonts.system + Fonts.all, id: \.self) { Text($0).tag($0) }
            }
        }
    }

    private var text: some View {
        Section("Text") {
            Picker("Weight", selection: $style.v.fontWeight) {
                ForEach(["light", "regular", "medium", "semibold", "bold", "heavy", "black"], id: \.self) {
                    Text($0.capitalized).tag($0)
                }
            }
            Toggle("ALL CAPS", isOn: $style.v.uppercase)
            Toggle("Hindi, Urdu etc. in English letters", isOn: $style.v.romanize)
            Toggle("Italic", isOn: $style.v.italic)
            slider("Letter spacing", $style.v.tracking, -3...10) { String(format: "%.1f", $0) }
            slider("Line spacing", $style.v.lineSpacing, 0...60) { String(format: "%.0f", $0) }
            Picker("Alignment", selection: $style.v.alignment) {
                Text("Left").tag("leading")
                Text("Center").tag("center")
                Text("Right").tag("trailing")
            }
            .pickerStyle(.segmented)
            Toggle("Text shadow", isOn: $style.v.textShadow)
        }
    }

    private var color: some View {
        Section("Color") {
            Picker("Highlight", selection: $style.v.colorMode) {
                Text("Album art").tag("album")
                Text("White").tag("white")
                Text("Custom").tag("custom")
            }
            .pickerStyle(.segmented)
            if style.v.colorMode == "custom" {
                ColorPicker("Highlight color", selection: Binding(
                    get: { Color(hex: style.v.customHex) },
                    set: { style.v.customHex = $0.hex }
                ), supportsOpacity: false)
            }
            slider("Unsung words", $style.v.unsungOpacity, 0...0.9) { String(format: "%.0f%%", $0 * 100) }
            slider("Glow", $style.v.glow, 0...1) { String(format: "%.0f%%", $0 * 100) }
        }
    }

    private var animation: some View {
        Section("Animation") {
            Picker("Word effect", selection: $style.v.wordStyle) {
                Text("Mix — a different effect each line, punchier on the chorus").tag("mix")
                Divider()
                ForEach(StyleValues.wordEffects, id: \.0) { Text($0.1).tag($0.0) }
            }
            Picker("Line transition", selection: $style.v.transition) {
                Text("Mix — changes every line").tag("mix")
                Text("Zoom through").tag("zoom")
                Text("Flip").tag("flip")
                Text("Slide up").tag("slide")
                Text("Push sideways").tag("push")
                Text("Drop down").tag("drop")
                Text("Blur").tag("blur")
                Text("Scale").tag("scale")
                Text("Fade").tag("fade")
            }
            slider("Bounce", $style.v.bounce, 0...1) { String(format: "%.0f%%", $0 * 100) }
            Picker("Lines shown", selection: $style.v.linesShown) {
                ForEach([1, 2, 3, 5], id: \.self) { Text("\($0)").tag($0) }
            }
            .pickerStyle(.segmented)
            Toggle("Blur inactive lines", isOn: $style.v.blurInactive)
        }
    }

    @ViewBuilder
    private var desktop: some View {
        Section("Live wallpaper") {
            Toggle("Lock-screen look as the desktop wallpaper while music plays", isOn: $style.v.liveWallpaper)
            Text("Fills every screen behind your windows and icons, and goes back to your own wallpaper when the music stops.")
                .font(.caption).foregroundStyle(.secondary)
        }

        Section("Desktop overlay") {
            Toggle("Show lyrics on desktop", isOn: $style.v.showOnDesktop)
            if style.v.showOnDesktop {
                Picker("Style", selection: $style.v.desktopLayout) {
                    Text("Lines").tag("lines")
                    Divider()
                    ForEach(StyleValues.layouts.filter { StyleValues.visualLayouts.contains($0.0) }, id: \.0) {
                        Text($0.1).tag($0.0)
                    }
                }
                slider("Size", $style.v.fontSize, 16...80) { String(format: "%.0f pt", $0) }
                slider("Width", $style.v.width, 360...1400) { String(format: "%.0f", $0) }
                Picker("Background", selection: $style.v.background) {
                    Text("None").tag("none")
                    Text("Blur").tag("blur")
                    Text("Glass").tag("glass")
                    Text("Dim").tag("dim")
                }
                .pickerStyle(.segmented)
                if style.v.background != "none" {
                    slider("Background strength", $style.v.backgroundOpacity, 0.1...1) {
                        String(format: "%.0f%%", $0 * 100)
                    }
                }
                Toggle("Show song title", isOn: $style.v.showHeader)
                Toggle("Lock position (clicks pass through)", isOn: $style.v.clickThrough)
                Button("Reset position", action: resetPosition)
            }
        }
    }

    private func slider(_ title: String, _ value: Binding<Double>, _ range: ClosedRange<Double>,
                        _ label: @escaping (Double) -> String) -> some View {
        LabeledContent(title) {
            HStack {
                Slider(value: value, in: range).frame(width: 200)
                Text(label(value.wrappedValue)).monospacedDigit().frame(width: 64, alignment: .trailing)
            }
        }
    }
}
