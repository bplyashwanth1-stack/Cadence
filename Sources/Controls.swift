import AppKit
import Combine
import SwiftUI

extension NowPlaying {
    /// Whether the full-screen lock-screen view is showing.
    func stageVisible(_ s: StyleValues) -> Bool {
        (s.showOnLockScreen && ((active && locked) || previewing)) || idleShowing
    }

    /// The stage as the desktop wallpaper: while music plays and the Mac is unlocked.
    func wallpaperVisible(_ s: StyleValues) -> Bool {
        s.liveWallpaper && isPlaying && !locked && !previewing && !idleShowing
    }

    /// The wallpaper on one screen, only while it can be seen.
    func wallpaperVisible(_ s: StyleValues, screen: Int) -> Bool {
        wallpaperVisible(s) && !WallpaperVisibility.shared.hidden.contains(screen)
    }
}

/// Which screens' wallpapers can actually be seen. A wallpaper hidden behind a full-screen app or covering
/// windows stops drawing, so it costs nothing while you can't see it.
final class WallpaperVisibility: ObservableObject {
    static let shared = WallpaperVisibility()
    @Published private(set) var hidden: Set<Int> = []

    func set(_ screen: Int, visible: Bool) {
        if visible { hidden.remove(screen) } else { hidden.insert(screen) }
    }
}

final class HoverState: ObservableObject {
    static let shared = HoverState()
    @Published var hovering = false {
        didSet { if !hovering { presetsOpen = false; lyricsOpen = false } }
    }
    @Published var presetsOpen = false {
        didSet { if presetsOpen { lyricsOpen = false } }
    }
    /// The lyrics tools above the bar (only one panel at a time).
    @Published var lyricsOpen = false {
        didSet { if lyricsOpen { presetsOpen = false } }
    }
    /// Open the lyrics editor as soon as the Mac is unlocked (typing isn't possible on the lock screen).
    @Published var editAfterUnlock = false
}

private func timeString(_ seconds: Double) -> String {
    let s = max(0, Int(seconds.rounded()))
    return String(format: "%d:%02d", s / 60, s % 60)
}

/// Glass pill with artwork, song, progress and — on hover — previous / play-pause / next.
struct NowPlayingBar: View {
    @ObservedObject private var style = Style.shared
    @ObservedObject private var player = NowPlaying.shared
    @ObservedObject private var hover = HoverState.shared
    @State private var dragFraction: Double?  // set while scrubbing
    @State private var barHovered = false

    var body: some View {
        let visible = style.v.stageFooter && player.stageVisible(style.v) && player.track != nil
        ZStack(alignment: .bottom) {
            TimelineView(.periodic(from: .now, by: 0.25)) { context in
                pill(position: player.position(at: context.date))
            }
            .frame(height: ControlsWindow.barHeight)
            if hover.presetsOpen {
                PresetList()
                    .padding(.bottom, ControlsWindow.barHeight - 6)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.trailing, 30)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            if hover.lyricsOpen {
                LyricStylePanel()
                    .padding(.bottom, ControlsWindow.barHeight - 6)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.trailing, 30)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .opacity(visible ? 1 : 0)
        .animation(.easeInOut(duration: 0.6), value: visible)
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: hover.presetsOpen)
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: hover.lyricsOpen)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }

    private func pill(position: Double) -> some View {
        let duration = max(player.duration, 1)
        let fraction = min(max(position / duration, 0), 1)
        let shape = RoundedRectangle(cornerRadius: 26, style: .continuous)
        return HStack(spacing: 16) {
            if let art = player.artwork {
                Image(nsImage: art)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .shadow(color: .black.opacity(0.3), radius: 6, y: 2)
            }
            VStack(alignment: .leading, spacing: 7) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(player.track?.title ?? "").font(.system(size: 16, weight: .semibold, design: .rounded))
                    Text(player.track?.artist ?? "").font(.system(size: 13, design: .rounded)).opacity(0.7)
                }
                .lineLimit(1)
                progress(fraction: fraction, position: position, duration: duration)
            }
            .frame(width: 250, alignment: .leading)
            if hover.hovering {
                controls
                    .transition(.move(edge: .trailing).combined(with: .opacity).combined(with: .scale(scale: 0.8)))
            }
        }
        .foregroundStyle(Color.white)
        .padding(.vertical, 14)
        .padding(.leading, 14)
        .padding(.trailing, 22)
        .background { glass(shape) }
        .animation(.spring(response: 0.38, dampingFraction: 0.8), value: hover.hovering)
    }

    /// Click or drag anywhere on the bar to scrub; the song jumps when the drag ends.
    private func progress(fraction: Double, position: Double, duration: Double) -> some View {
        let shown = dragFraction ?? fraction
        let shownPosition = dragFraction.map { $0 * duration } ?? position
        let active = barHovered || dragFraction != nil
        return VStack(spacing: 4) {
            GeometryReader { geo in
                let width = geo.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.22))
                    Capsule().fill(Color.white).frame(width: width * shown)
                    Circle()
                        .fill(Color.white)
                        .frame(width: 12, height: 12)
                        .shadow(color: .black.opacity(0.3), radius: 3)
                        .offset(x: width * shown - 6)
                        .opacity(active ? 1 : 0)
                }
                .frame(height: active ? 8 : 4)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { dragFraction = min(max($0.location.x / width, 0), 1) }
                    .onEnded { value in
                        let target = min(max(value.location.x / width, 0), 1)
                        player.seek(to: target * duration)
                        dragFraction = nil
                    })
                .onHover { barHovered = $0 }
            }
            .frame(height: 14)  // taller hit area than the visible bar
            .animation(.spring(response: 0.3, dampingFraction: 0.75), value: active)
            HStack {
                Text(timeString(shownPosition))
                Spacer()
                Text("-" + timeString(duration - shownPosition))
            }
            .font(.system(size: 10.5, weight: .medium, design: .rounded))
            .monospacedDigit()
            .opacity(0.65)
        }
    }

    private var controls: some View {
        HStack(spacing: 18) {
            button("backward.fill", size: 20) { player.control("previous track") }
            button(player.isPlaying ? "pause.fill" : "play.fill", size: 28) { player.control("playpause") }
            button("forward.fill", size: 20) { player.control("next track") }
            Rectangle().fill(Color.white.opacity(0.25)).frame(width: 1, height: 28)
            HStack(spacing: 2) {
                button("chevron.left", size: 15) { Presets.step(-1) }
                    .help("Previous preset")
                presetsButton
                button("chevron.right", size: 15) { Presets.step(1) }
                    .help("Next preset")
            }
            Rectangle().fill(Color.white.opacity(0.25)).frame(width: 1, height: 28)
            button(style.v.edgeGlow ? "light.max" : "light.min", size: 18) { style.v.edgeGlow.toggle() }
                .opacity(style.v.edgeGlow ? 1 : 0.45)
                .help(style.v.edgeGlow ? "Turn the edge light off" : "Turn the edge light on")
            button("textformat", size: 18) { hover.lyricsOpen.toggle() }
                .help("Lyric style, font and fixes")
        }
        .padding(.leading, 4)
    }

    private var presetsButton: some View {
        Button { hover.presetsOpen.toggle() } label: {
            HStack(spacing: 3) {
                Image(systemName: "sparkles").font(.system(size: 18, weight: .bold))
                Image(systemName: "chevron.up")
                    .font(.system(size: 9, weight: .heavy))
                    .rotationEffect(.degrees(hover.presetsOpen ? 180 : 0))
            }
            .frame(width: 44, height: 40)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .help("Choose a preset")
    }

    private func button(_ symbol: String, size: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .bold))
                .frame(width: 40, height: 40)
                .contentShape(Rectangle())
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(PressableStyle())
    }

    @ViewBuilder
    private func glass(_ shape: RoundedRectangle) -> some View {
        // glassEffect only exists in the macOS 26 SDK; older toolchains build the fallback alone.
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            shape.fill(Color.black.opacity(0.12)).glassEffect(.regular, in: shape)
        } else {
            VisualEffect().clipShape(shape)
        }
        #else
        VisualEffect().clipShape(shape)
        #endif
    }
}

/// Every preset, opening above the bar. A real menu is a window of its own and can't appear over the lock screen,
/// so this is drawn inside the bar's window, which grows while it's open.
struct PresetList: View {
    @ObservedObject private var style = Style.shared
    @ObservedObject private var hover = HoverState.shared
    @ObservedObject private var memory = PresetMemory.shared
    @ObservedObject private var player = NowPlaying.shared

    var body: some View {
        let sections = Presets.sections(keeping: style.v)
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        VStack(spacing: 0) {
            ScrollViewReader { scroller in
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 2) {
                        ForEach(sections, id: \.name) { section in
                            header(section.name, section.symbol, section.items.count)
                            if isOpen(section) {
                                ForEach(section.items, id: \.name) { preset in
                                    row(preset.name, preset.symbol, preset.values).id("\(section.name)/\(preset.name)")
                                }
                            }
                        }
                    }
                    .padding(8)
                }
                .onAppear {
                    if let section = sections.first(where: { $0.items.contains { $0.values == style.v } }),
                       let current = section.items.first(where: { $0.values == style.v }) {
                        scroller.scrollTo("\(section.name)/\(current.name)", anchor: .center)
                    }
                }
            }
            .frame(height: ControlsWindow.listHeight - 46)
            .clipped()
            Rectangle().fill(Color.white.opacity(0.14)).frame(height: 1)
            HStack(spacing: 6) {
                pin("This song", artist: false)
                pin("This artist", artist: true)
            }
            .padding(.horizontal, 8)
            .frame(height: 45)
        }
        .frame(width: 270, height: ControlsWindow.listHeight)
        .background {
            ZStack {
                VisualEffect()
                Color.black.opacity(0.45)
            }
            .clipShape(shape)
        }
        .overlay(shape.strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
    }

    /// Keeps the current preset for this song or artist, so it comes back whenever they play.
    private func pin(_ label: String, artist: Bool) -> some View {
        let pinned = memory.isPinned(player.track, artist: artist)
        return Button { memory.togglePin(player.track, artist: artist) } label: {
            Label(label, systemImage: pinned ? "pin.fill" : "pin")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.white)
                .frame(maxWidth: .infinity)
                .frame(height: 30)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(pinned ? 0.28 : 0.1)))
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .help("Always use this preset for \(label.lowercased())")
    }

    /// Groups start folded, except Favourites and the one holding the current look; a tap opens or folds one.
    @State private var toggled: Set<String> = []

    private func isOpen(_ section: (name: String, symbol: String, items: [Presets.Item])) -> Bool {
        let natural = section.name == "Favourites" || section.items.contains { $0.values == style.v }
        return natural != toggled.contains(section.name)
    }

    private func header(_ name: String, _ symbol: String, _ count: Int) -> some View {
        let sections = Presets.sections(keeping: style.v)
        let open = sections.first { $0.name == name }.map(isOpen) ?? false
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                if toggled.contains(name) { toggled.remove(name) } else { toggled.insert(name) }
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: symbol).frame(width: 22)
                Text(name).font(.system(size: 13, weight: .bold, design: .rounded))
                Text("\(count)").font(.system(size: 12, weight: .medium, design: .rounded)).opacity(0.5)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .rotationEffect(.degrees(open ? 90 : 0))
            }
            .foregroundStyle(Color.white.opacity(0.85))
            .padding(.horizontal, 12)
            .frame(height: 34)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.white.opacity(0.06)))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .padding(.top, 4)
    }

    private func row(_ name: String, _ symbol: String, _ values: StyleValues) -> some View {
        let selected = values == style.v
        let favourite = memory.favourites.contains(name)
        return HStack(spacing: 0) {
            Button {
                Presets.pick(name, symbol, values)
                hover.presetsOpen = false
            } label: {
                HStack(spacing: 12) {
                    PresetThumb(values: values, symbol: symbol, size: CGSize(width: 40, height: 24))
                        .frame(width: 40)
                    Text(name).lineLimit(1)
                    Spacer(minLength: 0)
                    if selected { Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)) }
                }
                .padding(.leading, 12)
                .frame(height: 38)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle())
            Button { memory.toggleFavourite(name) } label: {
                Image(systemName: favourite ? "heart.fill" : "heart")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(favourite ? Color.pink : Color.white.opacity(0.45))
                    .frame(width: 36, height: 38)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle())
        }
        .font(.system(size: 15, weight: .semibold, design: .rounded))
        .foregroundStyle(Color.white)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(Color.white.opacity(selected ? 0.16 : 0)))
    }
}

/// Shrinks a little while pressed.
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.85 : 1)
            .opacity(configuration.isPressed ? 0.7 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

/// Hosting view that reports hover even though Cadence is never the active app, and
/// lets the first click hit a button straight away.
final class ControlsHostingView: NSHostingView<NowPlayingBar> {
    private var tracking: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) { HoverState.shared.hovering = true }
    override func mouseExited(with event: NSEvent) { HoverState.shared.hovering = false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Small clickable window for the now-playing bar, layered above the full-screen lyrics.
final class ControlsWindow: NSPanel {
    static let barHeight: CGFloat = 120
    static let listHeight: CGFloat = 400
    private var opening: AnyCancellable?

    init(screen: NSScreen) {
        let size = NSSize(width: 920, height: Self.barHeight)
        let frame = NSRect(x: screen.frame.midX - size.width / 2, y: screen.frame.minY + 34,
                           width: size.width, height: size.height)
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        canBecomeVisibleWithoutLogin = true
        ignoresMouseEvents = true  // enabled only while the bar is showing
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.overlayWindow)) + 1)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        let hosting = ControlsHostingView(rootView: NowPlayingBar())
        hosting.sizingOptions = []
        hosting.autoresizingMask = [.width, .height]
        contentView = hosting
        orderFrontRegardless()
        LockScreen.attach(self)
        // Grows upward for the preset list or lyrics tools, then shrinks so it isn't covering anything otherwise.
        opening = HoverState.shared.$presetsOpen.combineLatest(HoverState.shared.$lyricsOpen)
            .map { $0 || $1 }.removeDuplicates().sink { [weak self] open in
            guard let self else { return }
            var frame = self.frame
            frame.size.height = Self.barHeight + (open ? Self.listHeight : 0)
            setFrame(frame, display: true)
        }
    }

    override var canBecomeKey: Bool { false }
}

/// Lyrics fixes that work by clicking, for the lock screen where you can't type: move the timing, look for other
/// lyrics, or have the editor open the moment you unlock.
struct LyricsTools: View {
    @ObservedObject private var hover = HoverState.shared
    @ObservedObject private var player = NowPlaying.shared
    @ObservedObject private var timing = SongTiming.shared

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        let id = player.track?.id
        let nudge = id.map { timing.offset($0) } ?? 0
        VStack(alignment: .leading, spacing: 6) {
            Text("This song's lyrics")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .opacity(0.7)
                .padding(.horizontal, 6)
            HStack(spacing: 6) {
                tool("Earlier", "backward.end.fill") { id.map { timing.nudge($0, by: 0.25) } }
                tool("Later", "forward.end.fill") { id.map { timing.nudge($0, by: -0.25) } }
            }
            Text(nudge == 0 ? "Timing as found"
                 : String(format: "%.2f s %@", abs(nudge), nudge > 0 ? "earlier" : "later"))
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .monospacedDigit()
                .opacity(0.6)
                .frame(maxWidth: .infinity)
            tool("Reset timing", "arrow.uturn.backward") { id.map { timing.set(0, for: $0) } }
                .disabled(nudge == 0)
                .opacity(nudge == 0 ? 0.4 : 1)
            tool("Search lyrics again", "magnifyingglass") {
                player.reloadLyrics()
                hover.lyricsOpen = false
            }
            tool(hover.editAfterUnlock ? "Editor opens when you unlock ✓" : "Edit lyrics when I unlock",
                 "square.and.pencil") { hover.editAfterUnlock.toggle() }
        }
        .foregroundStyle(Color.white)
        let _ = shape
    }

    private func tool(_ label: String, _ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(label, systemImage: symbol)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .frame(maxWidth: .infinity)
                .frame(height: 34)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.white.opacity(0.1)))
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
    }
}

/// The lyric style panel above the bar: pick a style or a font, or fix this song's lyrics — all by clicking.
struct LyricStylePanel: View {
    @ObservedObject private var style = Style.shared
    @ObservedObject private var hover = HoverState.shared
    @State private var tab = "style"

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        VStack(spacing: 8) {
            HStack(spacing: 4) {
                tabButton("Style", "style")
                tabButton("Font", "font")
                tabButton("Fix", "fix")
            }
            ScrollViewReader { scroller in
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 2) {
                        switch tab {
                        case "font": fonts
                        case "fix": LyricsTools()
                        default: styles
                        }
                    }
                }
                .onAppear { scroller.scrollTo(style.v.stageLayout, anchor: .center) }
            }
        }
        .foregroundStyle(Color.white)
        .padding(8)
        .frame(width: 290, height: ControlsWindow.listHeight - 10)
        .background {
            ZStack {
                VisualEffect()
                Color.black.opacity(0.45)
            }
            .clipShape(shape)
        }
        .overlay(shape.strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
    }

    private func tabButton(_ label: String, _ tag: String) -> some View {
        Button { tab = tag } label: {
            Text(label)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .frame(maxWidth: .infinity)
                .frame(height: 28)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(tab == tag ? 0.25 : 0.06)))
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
    }

    private var styles: some View {
        let original = Presets.defaultLayout(for: style.v)
        let name = StyleValues.layouts.first { $0.0 == original.layout }?.1.components(separatedBy: " — ")[0] ?? original.layout
        return Group {
            row("Default", detail: original.preset.map { "\(name), from \($0)" } ?? "\(name), Cadence's original",
                selected: style.v.stageLayout == original.layout) {
                style.v.stageLayout = original.layout
            }
            Rectangle().fill(Color.white.opacity(0.15)).frame(height: 1).padding(.vertical, 4)
            allStyles
        }
    }

    private var allStyles: some View {
        ForEach(StyleValues.layouts, id: \.0) { tag, label in
            row(label.components(separatedBy: " — ")[0], detail: label.components(separatedBy: " — ").dropFirst().first,
                selected: style.v.stageLayout == tag) {
                style.v.stageLayout = tag
            }
            .id(tag)
        }
    }

    private var fonts: some View {
        Group {
            row("Default", detail: "Each style's own font, as designed", selected: !style.v.myFont) {
                style.v.myFont = false
            }
            ForEach(Fonts.featured, id: \.self) { family in
                row(family, font: family, selected: style.v.myFont && style.v.fontFamily == family) {
                    style.v.fontFamily = family
                    style.v.myFont = true
                }
            }
        }
    }

    private func row(_ title: String, detail: String? = nil, font: String? = nil, selected: Bool,
                     action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(font.map { StyleValues.font(family: $0, size: 15, weight: .regular, italic: false) }
                              ?? .system(size: 14, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                    if let detail {
                        Text(detail).font(.system(size: 11, weight: .medium, design: .rounded)).opacity(0.55).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                if selected { Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)) }
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 38)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.white.opacity(selected ? 0.18 : 0)))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
    }
}
