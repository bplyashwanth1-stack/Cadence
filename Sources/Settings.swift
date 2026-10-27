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

    var body: some View {
        Form {
            Section {
                LabeledContent("Now playing") {
                    Text(player.track.map { "\($0.title) — \($0.artist)" } ?? "Nothing").lineLimit(1)
                }
                if !player.status.isEmpty {
                    LabeledContent("Lyrics") { Text(player.status) }
                }
            }

            lockScreen
            font
            text
            color
            animation
            desktop

            Section("Sync") {
                slider("Timing offset", $style.v.offset, -3...3) { String(format: "%+.1f s", $0) }
                Button("Search lyrics again") { player.reloadLyrics() }
            }

            Section {
                Button("Reset all settings") { style.v = StyleValues() }
            }
        }
        .formStyle(.grouped)
        .frame(width: 540, height: 760)
    }

    private var lockScreen: some View {
        Section("Lock screen") {
            Toggle("Show lyrics on lock screen", isOn: $style.v.showOnLockScreen)
            Picker("Layout", selection: $style.v.stageLayout) {
                Text("Word stack").tag("stack")
                Text("Lines").tag("lines")
            }
            .pickerStyle(.segmented)
            if style.v.stageLayout == "stack" {
                Toggle("Icons beside words", isOn: $style.v.stageIcons)
                Toggle("3D drift", isOn: $style.v.stageDrift)
            }
            Picker("Background", selection: $style.v.stageBackground) {
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
            if ["aurora", "album", "gradient"].contains(style.v.stageBackground) {
                slider("Background darkness", $style.v.backgroundDarkness, 0...0.95) {
                    String(format: "%.0f%%", $0 * 100)
                }
            }
            slider("Lyrics size", $style.v.stageFontSize, 60...300) { String(format: "%.0f pt", $0) }
            Toggle("Edge glow (pulses with the vocals)", isOn: $style.v.edgeGlow)
            Toggle("Clock", isOn: $style.v.stageClock)
            Toggle("Now-playing bar (hover for controls)", isOn: $style.v.stageFooter)
            Toggle("Keep screen awake while playing", isOn: $style.v.keepAwake)
            Button("Preview for 10 seconds", action: preview)
        }
    }

    private var font: some View {
        Section("Font") {
            FontGallery(selection: $style.v.fontFamily, weight: style.v.fontWeight, italic: style.v.italic)
            Picker("All installed fonts", selection: $style.v.fontFamily) {
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
                Text("Reveal — words rise in as sung").tag("reveal")
                Text("Bounce — words spring in").tag("bounce")
                Text("Bloom — words flash in and settle").tag("bloom")
                Text("Typewriter — letter by letter").tag("typewriter")
                Text("Karaoke fill — colour sweeps through").tag("fill")
                Text("Wave — karaoke fill that floats").tag("wave")
                Text("Pop — words hop when sung").tag("pop")
                Text("Fade — words brighten").tag("fade")
            }
            Picker("Line transition", selection: $style.v.transition) {
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

    private var desktop: some View {
        Section("Desktop overlay") {
            Toggle("Show lyrics on desktop", isOn: $style.v.showOnDesktop)
            if style.v.showOnDesktop {
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
