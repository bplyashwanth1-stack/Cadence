import AppKit
import Carbon.HIToolbox

// MARK: - Lyrics when idle

/// An optional screensaver: while music plays and the Mac sits untouched for a few minutes, the lock-screen view
/// fills the screen. Any key press or mouse move brings the desktop back. Off unless turned on in Settings or the
/// menu. Kept in UserDefaults rather than the look, so presets never switch it.
final class IdleLyrics {
    static let shared = IdleLyrics()
    static let enabledKey = "idleLyrics"
    static let minutesKey = "idleMinutes"
    static let minuteChoices = [1, 2, 5, 10, 15]

    private var timer: Timer?

    static var enabled: Bool {
        get { UserDefaults.standard.bool(forKey: enabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    static var minutes: Int {
        let saved = UserDefaults.standard.integer(forKey: minutesKey)
        return saved > 0 ? saved : 2
    }

    func start() {
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in self?.check() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// Seconds since the last key press, click or mouse move anywhere.
    private static var idleSeconds: Double {
        CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
    }

    private func check() {
        let player = NowPlaying.shared
        let idle = Self.idleSeconds
        if player.idleShowing {
            if idle < 0.5 || !player.isPlaying || player.locked || !Self.enabled {
                player.idleShowing = false
                Log.write("idle lyrics: hidden")
            }
        } else if Self.enabled, player.isPlaying, !player.locked, !player.previewing, !ClipRecorder.shared.recording,
                  idle >= Double(Self.minutes * 60) {
            player.idleShowing = true
            Log.write("idle lyrics: showing after \(Int(idle)) s idle")
        }
    }
}

// MARK: - Look shortcuts

/// System-wide shortcuts to step through looks (your favourites, if you have any): ⌃⌥] next, ⌃⌥[ previous.
/// Carbon hot keys need no Accessibility permission.
enum LookShortcuts {
    private static var refs: [EventHotKeyRef?] = []

    static func register() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var id = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &id)
            DispatchQueue.main.async { Presets.step(id.id == 1 ? 1 : -1) }
            return noErr
        }, 1, &spec, nil, nil)
        let modifiers = UInt32(controlKey | optionKey)
        for (index, key) in [(1, kVK_ANSI_RightBracket), (2, kVK_ANSI_LeftBracket)] {
            var ref: EventHotKeyRef?
            let id = EventHotKeyID(signature: OSType(0x4344_4E43), id: UInt32(index))  // "CDNC"
            if RegisterEventHotKey(UInt32(key), modifiers, id, GetApplicationEventTarget(), 0, &ref) == noErr {
                refs.append(ref)
            } else {
                Log.write("look shortcut \(index) couldn't be registered")
            }
        }
    }
}
