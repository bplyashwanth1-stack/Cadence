import AppKit
import Combine
import IOKit.pwr_mgt
import ServiceManagement
import SwiftUI

// MARK: - Windows

private let overlayLevel = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.overlayWindow)))

/// Full-screen lyrics shown above the lock screen.
final class StageWindow: NSWindow {
    init(screen: NSScreen) {
        super.init(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        setFrame(screen.frame, display: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        canBecomeVisibleWithoutLogin = true
        level = overlayLevel
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        // Separate layers so the slow background doesn't redraw at the lyrics' frame rate (see StageBackdrop).
        let container = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
        for root in [AnyView(StageBackdrop()), AnyView(StageDepth(overLyrics: false)), AnyView(StageView()),
                     AnyView(StageDepth(overLyrics: true)), AnyView(TranslationHost())] {
            let hosting = NSHostingView(rootView: root)
            hosting.sizingOptions = []
            hosting.frame = container.bounds
            hosting.autoresizingMask = [.width, .height]
            container.addSubview(hosting)
        }
        contentView = container
        orderFrontRegardless()
        LockScreen.attach(self)
    }
}

/// The stage as a live desktop wallpaper while music plays: above the picture, below the desktop icons and every
/// window. One per screen, and each screen can show a different visual. Never takes clicks.
final class WallpaperWindow: NSWindow {
    init(screen: NSScreen, index: Int) {
        super.init(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        setFrame(screen.frame, display: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) + 1)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        let container = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
        for root in [AnyView(StageBackdrop()), AnyView(StageDepth(overLyrics: false)), AnyView(StageView()),
                     AnyView(StageDepth(overLyrics: true))] {
            let hosting = NSHostingView(rootView: root.environment(\.isWallpaper, true).environment(\.stageScreen, index))
            hosting.sizingOptions = []
            hosting.frame = container.bounds
            hosting.autoresizingMask = [.width, .height]
            container.addSubview(hosting)
        }
        contentView = container
        orderFrontRegardless()
        NotificationCenter.default.addObserver(forName: NSWindow.didChangeOcclusionStateNotification, object: self,
                                               queue: .main) { [weak self] _ in
            guard let self else { return }
            WallpaperVisibility.shared.set(index, visible: self.occlusionState.contains(.visible))
        }
    }

    override var canBecomeKey: Bool { false }
}

/// The edge light around the desktop (off unless enabled). Never takes clicks.
final class EdgeGlowWindow: NSPanel {
    init(screen: NSScreen) {
        super.init(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        setFrame(screen.frame, display: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        level = overlayLevel
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        let hosting = NSHostingView(rootView: DesktopEdgeGlow())
        hosting.sizingOptions = []
        contentView = hosting
        orderFrontRegardless()
    }

    override var canBecomeKey: Bool { false }
}

/// Floating lyrics on the desktop (off unless enabled).
final class OverlayWindow: NSPanel {
    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        isMovableByWindowBackground = true
        level = overlayLevel
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        let hosting = NSHostingView(rootView: OverlayView())
        hosting.sizingOptions = []
        contentView = hosting
    }

    override var canBecomeKey: Bool { false }
}

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let style = Style.shared
    private let player = NowPlaying.shared
    private var stage: StageWindow?
    private var controls: ControlsWindow?
    private var overlay: OverlayWindow?
    private var edgeGlow: EdgeGlowWindow?
    private var wallpapers: [WallpaperWindow] = []
    private var lyricsEditor: LyricsEditorWindow?
    private var settings: NSWindow?
    private var statusItem: NSStatusItem!
    private var timer: Timer?
    private var previewEnd: DispatchWorkItem?
    private var sleepAssertion: IOPMAssertionID = 0
    private var subscriptions = Set<AnyCancellable>()

    private let frameName = "CadenceOverlay"

    func applicationDidFinishLaunching(_ notification: Notification) {
        _ = Fonts.bundled  // registers the bundled fonts before any view uses them
        AutoSync.shared.start()
        buildMenu()
        // The first time a browser with YouTube open refuses to run Cadence's JavaScript, say how to allow it.
        NotificationCenter.default.addObserver(forName: .youTubeBlocked, object: nil, queue: .main) { [weak self] note in
            guard let name = note.object as? String else { return }
            var told = UserDefaults.standard.stringArray(forKey: "youTubeSetupShown") ?? []
            guard !told.contains(name) else { return }
            told.append(name)
            UserDefaults.standard.set(told, forKey: "youTubeSetupShown")
            self?.youTubeSetup()
        }
        buildWindows()
        NotificationCenter.default.addObserver(self, selector: #selector(buildWindows),
                                               name: NSApplication.didChangeScreenParametersNotification, object: nil)

        // @Published fires before the value is stored, so react on the next runloop turn.
        style.$v.map(\.syncLyrics).removeDuplicates().filter { $0 }
            .sink { _ in UserLyrics.moveToCloud() }
            .store(in: &subscriptions)
        style.$v.map(\.clickThrough).removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.overlay?.ignoresMouseEvents = $0 }
            .store(in: &subscriptions)
        style.$v.map { [$0.fontSize, Double($0.linesShown), $0.width, $0.lineSpacing, $0.showHeader ? 1 : 0,
                        StyleValues.visualLayouts.contains($0.desktopLayout) ? 1 : 0] }
            .removeDuplicates().dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.resizeOverlay() }
            .store(in: &subscriptions)
        Publishers.CombineLatest3(player.$locked, player.$isPlaying, style.$v)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateKeepAwake() }
            .store(in: &subscriptions)
        // The controls window only takes clicks while the bar is actually showing.
        Publishers.CombineLatest4(player.$locked, player.$active, player.$previewing, style.$v)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                let showing = self.style.v.stageFooter && self.player.stageVisible(self.style.v)
                self.controls?.ignoresMouseEvents = !showing
                if !showing { HoverState.shared.hovering = false }
            }
            .store(in: &subscriptions)

        let distributed = DistributedNotificationCenter.default()
        distributed.addObserver(forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
            self?.player.locked = true
        }
        distributed.addObserver(forName: .init("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in
            self?.player.locked = false
            // Asked for from the lock screen, where typing isn't possible.
            if HoverState.shared.editAfterUnlock {
                HoverState.shared.editAfterUnlock = false
                self?.openLyricsEditor()
            }
        }
        // Lets scripts trigger the preview: post "local.cadence.preview" as a distributed notification.
        // Settings' "Tap to sync this song…" button.
        distributed.addObserver(forName: .init("local.cadence.tapsync"), object: nil, queue: .main) { [weak self] _ in
            self?.openTapSync()
        }
        distributed.addObserver(forName: .init("local.cadence.preview"), object: nil, queue: .main) { [weak self] _ in
            self?.preview()
        }
        // Scripts can open the lyrics editor and Settings too.
        distributed.addObserver(forName: .init("local.cadence.editlyrics"), object: nil, queue: .main) { [weak self] _ in
            self?.openLyricsEditor()
        }
        distributed.addObserver(forName: .init("local.cadence.settings"), object: nil, queue: .main) { [weak self] _ in
            self?.openSettings()
        }

        // Ask for Automation permission up front, then start polling once it's answered.
        DispatchQueue.global().async {
            for app in NSWorkspace.shared.runningApplications {
                if let id = app.bundleIdentifier, ["com.spotify.client", "com.apple.Music"].contains(id) {
                    Player.requestPermission(bundleID: id)
                }
            }
            DispatchQueue.main.async { self.startPolling() }
        }
    }

    private func startPolling() {
        // Every 0.5 s, or 0.25 s for YouTube: reading one tab is quick, and a pause or seek in the browser shows
        // up that much sooner.
        var tick = 0
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            guard let self else { return }
            tick += 1
            if tick % 2 == 0 || self.player.track?.id.hasPrefix("youtube") == true { self.player.poll() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        player.poll()
    }

    /// Stops the display sleeping on the lock screen while lyrics are playing there.
    private func updateKeepAwake() {
        let s = style.v
        let wanted = s.keepAwake && s.showOnLockScreen && player.isPlaying && player.locked
        if wanted && sleepAssertion == 0 {
            IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                                        IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                        "Cadence lyrics on lock screen" as CFString, &sleepAssertion)
        } else if !wanted && sleepAssertion != 0 {
            IOPMAssertionRelease(sleepAssertion)
            sleepAssertion = 0
        }
    }

    // MARK: Windows

    @objc private func buildWindows() {
        stage?.close()
        controls?.close()
        edgeGlow?.close()
        wallpapers.forEach { $0.close() }
        wallpapers = NSScreen.screens.enumerated().map { WallpaperWindow(screen: $1, index: $0) }
        if let screen = NSScreen.screens.first {
            edgeGlow = EdgeGlowWindow(screen: screen)
            stage = StageWindow(screen: screen)
            controls = ControlsWindow(screen: screen)  // created after the stage so it sits on top
            controls?.ignoresMouseEvents = !(style.v.stageFooter && player.stageVisible(style.v))
        }

        overlay?.close()
        let window = OverlayWindow()
        if !window.setFrameUsingName(frameName) { window.setFrame(defaultFrame(), display: false) }
        window.setFrameAutosaveName(frameName)
        window.ignoresMouseEvents = style.v.clickThrough
        window.orderFrontRegardless()
        overlay = window
        resizeOverlay()
    }

    private func overlaySize() -> NSSize {
        let s = style.v
        let lines = Double(s.linesShown)
        let screenHeight = NSScreen.main?.visibleFrame.height ?? 900
        let styled = StyleValues.visualLayouts.contains(s.desktopLayout)
        let height = styled ? s.fontSize * 6 + (s.showHeader ? 50 : 0) + 80
            : s.fontSize * 2.9 * lines + s.lineSpacing * lines + (s.showHeader ? 50 : 0) + 120
        return NSSize(width: s.width + 60, height: min(height, screenHeight * 0.9))
    }

    private func defaultFrame() -> NSRect {
        let size = overlaySize()
        let screen = (NSScreen.main ?? NSScreen.screens[0]).visibleFrame
        return NSRect(x: screen.midX - size.width / 2, y: screen.minY + 40, width: size.width, height: size.height)
    }

    /// Keeps the overlay centred on the same point while its size follows the style.
    private func resizeOverlay() {
        guard let overlay else { return }
        let size = overlaySize()
        var frame = NSRect(x: overlay.frame.midX - size.width / 2, y: overlay.frame.midY - size.height / 2,
                           width: size.width, height: size.height)
        // Keep it fully on whichever screen it's on.
        if let visible = (overlay.screen ?? NSScreen.main)?.visibleFrame {
            frame.origin.x = min(max(frame.minX, visible.minX), visible.maxX - frame.width)
            frame.origin.y = min(max(frame.minY, visible.minY), visible.maxY - frame.height)
        }
        overlay.setFrame(frame, display: true)
    }

    private func resetPosition() {
        overlay?.setFrame(defaultFrame(), display: true)
    }

    /// Shows the lock-screen view on the desktop for 10 seconds so it can be tuned without locking.
    private func preview() {
        previewEnd?.cancel()
        Log.write("preview: playing=\(player.isPlaying) lyrics=\(player.lyrics.count) stage=\(stage?.frame ?? .zero)")
        player.previewing = true
        let end = DispatchWorkItem { [weak self] in self?.player.previewing = false }
        previewEnd = end
        DispatchQueue.main.asyncAfter(deadline: .now() + 10, execute: end)
    }

    // MARK: Menu

    private func buildMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "music.mic", accessibilityDescription: "Cadence")
        let menu = NSMenu()
        menu.delegate = self
        menu.addItem(item("Show on Lock Screen", #selector(toggleLockScreen)))
        menu.addItem(item("Show on Desktop", #selector(toggleDesktop)))
        menu.addItem(item("Live Wallpaper on Desktop", #selector(toggleWallpaper)))
        menu.addItem(item("Edge Light", #selector(toggleEdgeLight)))
        menu.addItem(item("Shuffle Looks Each Song", #selector(toggleShuffle)))
        menu.addItem(fontMenu())
        menu.addItem(item("Preview Lock Screen (10s)", #selector(previewStage)))
        menu.addItem(.separator())
        menu.addItem(presetsMenu())
        menu.addItem(choiceMenu("Lyric Animation", [("mix", "Mix — changes every line")] + StyleValues.wordEffects,
                                #selector(pickWordStyle(_:))))
        let covers: [(String, String)] = [
            ("auto", "Auto — cuts between scenes"), ("motion", "Motion wallpaper"), ("mono", "Black & White"), ("cover", "Floating cover"),
            ("disc", "Disc"), ("duotone", "Duotone"), ("vinyl", "Vinyl"), ("kaleido", "Kaleidoscope"),
            ("polaroid", "Polaroid"), ("cassette", "Cassette"), ("lake", "Moonlit Lake"), ("cinema", "Cinema"), ("retro", "Retro Grid"),
        ]
        let worlds: [(String, String)] = WorldScene.kinds.map { ($0.tag, $0.name.components(separatedBy: " — ")[0]) }
        let visuals: [(String, String)] = [("visualmix", "Visual Mix — cuts between the visuals")]
            + Visuals.kinds.map { ($0.tag, $0.name.components(separatedBy: " — ")[0]) }
        let plain: [(String, String)] = [("aurora", "Aurora"), ("black", "Black")]
        menu.addItem(choiceMenu("Background", covers + worlds + visuals + plain, #selector(pickBackground(_:))))
        menu.addItem(choiceMenu("Layout", StyleValues.layouts, #selector(pickLayout(_:))))
        menu.addItem(item("Always Use This Preset for This Song", #selector(pinSong)))
        menu.addItem(item("Always Use This Preset for This Artist", #selector(pinArtist)))
        menu.addItem(.separator())
        menu.addItem(item("Settings…", #selector(openSettings), key: ","))
        menu.addItem(timingMenu())
        let hearing = item("⚠︎ Cadence Can't Hear the Music…", #selector(explainAudio))
        hearing.isHidden = true
        menu.addItem(hearing)
        menu.addItem(item("Edit Lyrics…", #selector(openLyricsEditor)))
        menu.addItem(item("Search Lyrics Again", #selector(reloadLyrics)))
        menu.addItem(item("Set Up YouTube…", #selector(youTubeSetup)))
        menu.addItem(item("Launch at Login", #selector(toggleLogin)))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Cadence", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    /// A submenu of options; the tag lives in representedObject and the current one gets a checkmark on open.
    private func choiceMenu(_ title: String, _ options: [(String, String)], _ action: Selector) -> NSMenuItem {
        let parent = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        submenu.delegate = self
        for (tag, label) in options {
            let option = item(label, action)
            option.representedObject = tag
            submenu.addItem(option)
        }
        parent.submenu = submenu
        return parent
    }

    /// Built-in presets, then the user's own, then saving the current look. Rebuilt on open so new saves show up.
    private func presetsMenu() -> NSMenuItem {
        let parent = NSMenuItem(title: "Presets", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        submenu.delegate = self
        parent.submenu = submenu
        fillPresets(submenu)
        return parent
    }

    private func fillPresets(_ submenu: NSMenu) {
        submenu.removeAllItems()
        // Favourites right at the top, then one submenu per group.
        let favourites = PresetMemory.shared.favourites
        let liked = Presets.all(keeping: style.v).filter { favourites.contains($0.name) }
        if !liked.isEmpty {
            submenu.addItem(NSMenuItem.sectionHeader(title: "Favourites"))
            for preset in liked {
                let option = item(preset.name, #selector(pickPreset(_:)))
                option.image = NSImage(systemSymbolName: preset.symbol, accessibilityDescription: nil)
                option.representedObject = preset.values
                submenu.addItem(option)
            }
            submenu.addItem(.separator())
        }
        for group in Presets.grouped {
            let parent = NSMenuItem(title: group.name, action: nil, keyEquivalent: "")
            parent.image = NSImage(systemSymbolName: group.symbol, accessibilityDescription: nil)
            let menu = NSMenu()
            menu.delegate = self
            for preset in group.presets {
                let option = item(preset.name, #selector(pickPreset(_:)))
                option.image = NSImage(systemSymbolName: preset.symbol, accessibilityDescription: nil)
                option.toolTip = preset.blurb
                option.representedObject = preset.values(keeping: style.v)
                menu.addItem(option)
            }
            parent.submenu = menu
            submenu.addItem(parent)
        }
        let custom = PresetStore.shared.custom
        if !custom.isEmpty { submenu.addItem(.separator()) }
        for preset in custom {
            let option = item(preset.name, #selector(pickPreset(_:)))
            option.image = NSImage(systemSymbolName: "star.fill", accessibilityDescription: nil)
            option.representedObject = preset.values(keeping: style.v)
            submenu.addItem(option)
        }
        submenu.addItem(.separator())
        submenu.addItem(item("Save Current Look as Preset…", #selector(savePreset)))
    }

    @objc private func pickPreset(_ sender: NSMenuItem) {
        if let values = sender.representedObject as? StyleValues { style.v = values }
    }

    @objc private func savePreset() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Save current look as a preset"
        alert.informativeText = "Background, lyric animation, font and effects are saved together."
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        field.placeholderString = "My Vibe"
        alert.accessoryView = field
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        if alert.runModal() == .alertFirstButtonReturn {
            PresetStore.shared.save(field.stringValue, style.v)
        }
    }

    @objc private func pickWordStyle(_ sender: NSMenuItem) {
        style.v.wordStyle = sender.representedObject as? String ?? "mix"
        // In the word stack, effects only show when it isn't using the highlighter box.
        style.v.stackStyle = "effect"
    }

    @objc private func pickBackground(_ sender: NSMenuItem) {
        style.v.stageBackground = sender.representedObject as? String ?? "auto"
    }

    @objc private func pickLayout(_ sender: NSMenuItem) {
        style.v.stageLayout = sender.representedObject as? String ?? "stack"
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    func menuWillOpen(_ menu: NSMenu) {
        for entry in menu.items where entry.action == #selector(explainAudio) {
            entry.isHidden = !(style.v.audioReactive && player.isPlaying && AudioPulse.shared.health() != .fine
                               && AudioPulse.shared.health() != .notRunning)
        }
        for entry in menu.items where entry.action == #selector(youTubeSetup) {
            entry.isHidden = YouTube.blocked.isEmpty || !style.v.youtube
        }
        // The timing submenu shows this song's current nudge and only offers what applies.
        if let id = player.track?.id {
            let nudge = SongTiming.shared.offset(id)
            for entry in menu.items {
                if entry.action == #selector(resetSongTiming) {
                    entry.title = nudge == 0 ? "Reset This Song" : String(format: "Reset This Song (now %+.2f s)", nudge)
                    entry.isHidden = nudge == 0
                }
                if entry.action == #selector(removeTapped) { entry.isHidden = !SongTiming.shared.tappedIDs.contains(id) }
                if entry.action == #selector(openTapSync) || entry.action == #selector(openTapSyncWords) {
                    entry.isEnabled = !player.lyrics.isEmpty
                }
            }
        }
        let states: [String: Bool] = [
            "Show on Lock Screen": style.v.showOnLockScreen,
            "Show on Desktop": style.v.showOnDesktop,
            "Live Wallpaper on Desktop": style.v.liveWallpaper,
            "Edge Light": style.v.edgeGlow,
            "Shuffle Looks Each Song": style.v.shuffleLooks,
            "Launch at Login": SMAppService.mainApp.status == .enabled,
        ]
        let chosen: [Selector: String] = [
            #selector(pickWordStyle(_:)): style.v.wordStyle,
            #selector(pickBackground(_:)): style.v.stageBackground,
            #selector(pickLayout(_:)): style.v.stageLayout,
            #selector(pickFont(_:)): style.v.myFont ? style.v.fontFamily : "",
        ]
        if menu.items.contains(where: { $0.action == #selector(savePreset) }) { fillPresets(menu) }
        for item in menu.items where item.action == #selector(pinSong) || item.action == #selector(pinArtist) {
            item.state = PresetMemory.shared.isPinned(player.track, artist: item.action == #selector(pinArtist)) ? .on : .off
        }
        for item in menu.items {
            if item.action == #selector(pickPreset(_:)) {
                item.state = (item.representedObject as? StyleValues) == style.v ? .on : .off
            }
            if let on = states[item.title] { item.state = on ? .on : .off }
            if let action = item.action, let current = chosen[action] {
                item.state = item.representedObject as? String == current ? .on : .off
            }
        }
    }

    @objc private func toggleLockScreen() { style.v.showOnLockScreen.toggle() }
    @objc private func toggleDesktop() { style.v.showOnDesktop.toggle() }
    @objc private func toggleWallpaper() { style.v.liveWallpaper.toggle() }
    @objc private func toggleEdgeLight() { style.v.edgeGlow.toggle() }
    @objc private func toggleShuffle() { style.v.shuffleLooks.toggle() }

    /// The featured fonts, quick to reach from the menu bar; each shows in its own typeface.
    private func fontMenu() -> NSMenuItem {
        let parent = NSMenuItem(title: "Lyrics Font", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        submenu.delegate = self
        let own = item("Default (Each Style's Own Font)", #selector(pickFont(_:)))
        own.representedObject = ""
        submenu.addItem(own)
        submenu.addItem(.separator())
        for family in Fonts.featured {
            let option = item(family, #selector(pickFont(_:)))
            option.representedObject = family
            if let font = NSFont(name: family, size: 14) ?? NSFontManager.shared.font(withFamily: family, traits: [], weight: 5, size: 14) {
                option.attributedTitle = NSAttributedString(string: family, attributes: [.font: font])
            }
            submenu.addItem(option)
        }
        parent.submenu = submenu
        return parent
    }

    @objc private func pickFont(_ sender: NSMenuItem) {
        guard let family = sender.representedObject as? String else { return }
        if family.isEmpty {
            style.v.myFont = false
        } else {
            style.v.fontFamily = family
            style.v.myFont = true
        }
    }
    @objc private func previewStage() { preview() }
    @objc private func reloadLyrics() { player.reloadLyrics() }

    /// How to let each browser that's refusing run Cadence's JavaScript.
    @objc private func youTubeSetup() {
        let browsers = YouTube.blocked.isEmpty ? YouTube.browsers.filter { $0.bundleID == "com.google.Chrome" } : YouTube.blocked
        let alert = NSAlert()
        alert.messageText = "Let Cadence read YouTube"
        alert.informativeText = "To follow YouTube, Cadence reads the video's position from the page. "
            + "Each browser needs one switch turned on for that:\n\n"
            + browsers.map { "• \($0.setting)" }.joined(separator: "\n\n")
            + "\n\nLyrics start as soon as it's on — no restart needed."
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
    @objc private func pinSong() { PresetMemory.shared.togglePin(player.track, artist: false) }
    @objc private func pinArtist() { PresetMemory.shared.togglePin(player.track, artist: true) }

    // MARK: This song's timing

    private var tapSync: TapSyncWindow?

    private func timingMenu() -> NSMenuItem {
        let parent = NSMenuItem(title: "This Song's Timing", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        submenu.delegate = self
        submenu.addItem(item("Show Lyrics Earlier (0.25 s)", #selector(nudgeEarlier)))
        submenu.addItem(item("Show Lyrics Later (0.25 s)", #selector(nudgeLater)))
        submenu.addItem(item("Reset This Song", #selector(resetSongTiming)))
        submenu.addItem(.separator())
        submenu.addItem(item("Tap to Sync This Song…", #selector(openTapSync)))
        submenu.addItem(item("Tap to Sync Word by Word…", #selector(openTapSyncWords)))
        submenu.addItem(item("Remove My Tapped Timing", #selector(removeTapped)))
        parent.submenu = submenu
        return parent
    }

    @objc private func nudgeEarlier() { player.track.map { SongTiming.shared.nudge($0.id, by: 0.25) } }
    @objc private func nudgeLater() { player.track.map { SongTiming.shared.nudge($0.id, by: -0.25) } }
    @objc private func resetSongTiming() { player.track.map { SongTiming.shared.set(0, for: $0.id) } }

    @objc private func removeTapped() {
        guard let id = player.track?.id else { return }
        SongTiming.shared.removeTapped(id)
        player.reloadLyrics()
    }

    /// What to do when the music can't be heard, depending on how it's failing.
    @objc private func explainAudio() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Cadence can't hear the music"
        if AudioPulse.shared.health() == .silent {
            alert.informativeText = "Sound reaches Cadence as silence, which usually means the System Audio Recording permission is off. Turn Cadence on in System Settings › Privacy & Security › Screen & System Audio Recording, then quit and reopen Cadence. Until then, visuals follow the lyric timing instead of the beat."
            alert.addButton(withTitle: "Open Privacy Settings")
        } else {
            alert.informativeText = "macOS's audio service isn't sending Cadence any sound. Restarting it usually fixes this: paste the copied command into Terminal and enter your password (sound drops out for a second). Until then, visuals follow the lyric timing instead of the beat."
            alert.addButton(withTitle: "Copy Fix Command")
        }
        alert.addButton(withTitle: "Close")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        if AudioPulse.shared.health() == .silent {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AudioCapture")!)
        } else {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString("sudo killall coreaudiod", forType: .string)
        }
    }

    @objc private func openLyricsEditor() {
        if lyricsEditor == nil { lyricsEditor = LyricsEditorWindow() }
        NSApp.activate(ignoringOtherApps: true)
        lyricsEditor?.makeKeyAndOrderFront(nil)
    }

    @objc private func openTapSyncWords() { startTapSync(byWord: true) }

    @objc private func openTapSync() { startTapSync(byWord: false) }

    private func startTapSync(byWord: Bool) {
        guard let session = TapSync(player: player, byWord: byWord) else { return }
        tapSync?.close()
        let window = TapSyncWindow(session: session)
        tapSync = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    @objc private func openSettings() {
        if settings == nil {
            let view = SettingsView(preview: { [weak self] in self?.preview() },
                                    resetPosition: { [weak self] in self?.resetPosition() })
            let window = NSWindow(contentViewController: NSHostingController(rootView: view))
            window.title = "Cadence"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            window.center()
            settings = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settings?.makeKeyAndOrderFront(nil)
    }

    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            Log.write("launch at login failed: \(error)")
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
