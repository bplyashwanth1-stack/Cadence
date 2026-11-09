import AppKit
import SwiftUI

// MARK: - Welcome

/// The first-launch guide: what Cadence does, the two permissions it needs (and why), and how to try it.
/// Cadence has no window or Dock icon of its own, so without this a new user sees nothing happen.
/// Shown once; the menu's Welcome Guide… opens it again.
final class Welcome {
    static let shownKey = "welcomeShown"
    static var shown: Bool { UserDefaults.standard.bool(forKey: shownKey) }

    private var window: NSWindow?

    func show(preview: @escaping () -> Void, iconVisible: @escaping () -> Bool) {
        if window == nil {
            let view = WelcomeView(preview: preview, iconVisible: iconVisible, done: { [weak self] in self?.window?.close() })
            let window = NSWindow(contentViewController: NSHostingController(rootView: view))
            window.title = "Welcome to Cadence"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        UserDefaults.standard.set(true, forKey: Self.shownKey)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

/// Whether Cadence may control a player app, without asking.
enum PlayerAccess: Equatable {
    case allowed, denied, notAsked, notRunning, checking

    static func check(_ bundleID: String) -> PlayerAccess {
        guard NSWorkspace.shared.runningApplications.contains(where: { $0.bundleIdentifier == bundleID }) else { return .notRunning }
        var target = AEAddressDesc()
        let created = bundleID.withCString {
            AECreateDesc(DescType(typeApplicationBundleID), $0, bundleID.utf8.count, &target)
        }
        guard created == noErr else { return .notAsked }
        defer { AEDisposeDesc(&target) }
        switch AEDeterminePermissionToAutomateTarget(&target, AEEventClass(typeWildCard), AEEventID(typeWildCard), false) {
        case noErr: return .allowed
        case OSStatus(errAEEventNotPermitted): return .denied
        default: return .notAsked
        }
    }
}

struct WelcomeView: View {
    let preview: () -> Void
    let iconVisible: () -> Bool
    let done: () -> Void

    @State private var page = 0
    @State private var spotify = PlayerAccess.checking
    @State private var music = PlayerAccess.checking
    @State private var hearing = false
    @State private var iconShown = true
    @State private var checkingAccess = false
    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch page {
                case 0: intro
                case 1: permissions
                default: tryIt
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(28)

            Divider()
            HStack {
                HStack(spacing: 6) {
                    ForEach(0..<3) { i in
                        Circle().fill(i == page ? Color.accentColor : Color.secondary.opacity(0.3)).frame(width: 7, height: 7)
                    }
                }
                Spacer()
                if page > 0 { Button("Back") { page -= 1 } }
                Button(page < 2 ? "Continue" : "Done") {
                    if page < 2 { page += 1 } else { done() }
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .frame(width: 520, height: 470)
        .onAppear(perform: refresh)
        .onReceive(tick) { _ in refresh() }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: "music.mic")
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(Color.accentColor)
            Text("Lyrics on your lock screen")
                .font(.system(size: 26, weight: .bold, design: .rounded))
            Text("While Spotify, Apple Music or YouTube plays, Cadence fills your lock screen with the song's lyrics, animated word by word, over artwork that moves with the beat.")
                .fixedSize(horizontal: false, vertical: true)
            row("menubar.arrow.up.rectangle", "It lives in the menu bar",
                "Look for the 🎤 at the top right of your screen. There's no Dock icon or main window.")
            if !iconShown {
                VStack(alignment: .leading, spacing: 8) {
                    Label("macOS is hiding the 🎤 right now", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange).font(.headline)
                    Text("Turn Cadence on under Allow in the Menu Bar, or make room if your menu bar is full (icons beside the camera notch get hidden). Opening Cadence again from Applications always brings up its settings.")
                        .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Button("Open Menu Bar Settings") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.ControlCenter-Settings.extension")!)
                    }
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.orange.opacity(0.1)))
            }
        }
    }

    private var permissions: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Two permissions")
                .font(.system(size: 24, weight: .bold, design: .rounded))
            Text("macOS asks for these the first time. Nothing is sent anywhere, and nothing is saved unless you record a clip.")
                .foregroundStyle(.secondary)
            permissionRow(
                icon: "music.note", title: "Control Spotify and Music",
                why: "To read which song is playing and where it's up to, so the lyrics stay in time.",
                status: playerStatus, ok: spotify == .allowed || music == .allowed,
                action: playerAction)
            permissionRow(
                icon: "waveform", title: "Hear the music (optional)",
                why: "So the visuals hit on the beat and lyric timing can be checked against the singing. Without it, Cadence follows the lyric timing.",
                status: hearing ? "Hearing the music"
                    : NowPlaying.shared.isPlaying ? "Music is playing but Cadence hears silence: allow it in Privacy & Security, or an audio app that processes sound (like an equalizer) may be blocking it"
                    : "Not hearing anything yet — play a song",
                ok: hearing,
                action: audioAction)
        }
    }

    private var tryIt: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Try it")
                .font(.system(size: 24, weight: .bold, design: .rounded))
            row("play.circle", "Play a song", "In Spotify, Apple Music, or YouTube in your browser.")
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "eye").font(.title2).frame(width: 30)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Preview it here").font(.headline)
                    Text("Shows the lock-screen view on your desktop for 10 seconds.").foregroundStyle(.secondary)
                    Button("Preview Lock Screen", action: preview)
                }
            }
            row("lock", "Lock your Mac", "Press ⌃⌘Q with music playing. Hover the bottom of the screen for controls.")
            row("sparkles", "Make it yours",
                "🎤 › Presets for nearly 90 looks (♥ your favourites, ⌃⌥] and ⌃⌥[ to switch), Record a 10-Second Clip to share, and Lyrics When I'm Away.")
        }
    }

    private func row(_ icon: String, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).font(.title2).frame(width: 30)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(text).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func permissionRow(icon: String, title: String, why: String, status: String, ok: Bool,
                               action: (String, () -> Void)?) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).font(.title2).frame(width: 30)
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.headline)
                Text(why).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Label(status, systemImage: ok ? "checkmark.circle.fill" : "circle.dashed")
                    .foregroundStyle(ok ? Color.green : Color.secondary)
                if let action { Button(action.0, action: action.1) }
            }
        }
    }

    private var playerStatus: String {
        if spotify == .allowed || music == .allowed {
            return "Allowed" + (spotify == .allowed && music == .allowed ? " for both" : spotify == .allowed ? " for Spotify" : " for Music")
        }
        if spotify == .denied || music == .denied { return "Turned off — allow Cadence under Automation" }
        if spotify == .notRunning && music == .notRunning { return "Open Spotify or Music, then allow it" }
        return "Not allowed yet"
    }

    private var audioAction: (String, () -> Void)? {
        guard !hearing else { return nil }
        let open: () -> Void = {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AudioCapture")!)
        }
        return ("Open Privacy Settings", open)
    }

    private var playerAction: (String, () -> Void)? {
        if spotify == .allowed || music == .allowed { return nil }
        if spotify == .denied || music == .denied {
            return ("Open Automation Settings", {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!)
            })
        }
        return ("Allow", {
            DispatchQueue.global().async {
                for id in ["com.spotify.client", "com.apple.Music"] where PlayerAccess.check(id) == .notAsked {
                    Player.requestPermission(bundleID: id)
                }
            }
        })
    }

    private func refresh() {
        iconShown = iconVisible()
        hearing = AudioPulse.shared.snapshot() != nil
        // The permission check can be slow (or hang); never on the main thread.
        guard !checkingAccess else { return }
        checkingAccess = true
        DispatchQueue.global().async {
            let s = PlayerAccess.check("com.spotify.client"), m = PlayerAccess.check("com.apple.Music")
            DispatchQueue.main.async { spotify = s; music = m; checkingAccess = false }
        }
    }
}
