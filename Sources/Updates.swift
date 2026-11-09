import AppKit

// MARK: - Update notice

/// Once a day, asks GitHub for Cadence's latest release. When it's newer than this build, the menu shows
/// "Update Available". Nothing is downloaded or installed; the item opens the release page (or, for a Homebrew
/// install, offers the upgrade command). Turn it off in Settings › Lock Screen.
final class UpdateChecker {
    static let shared = UpdateChecker()

    static let releasesPage = URL(string: "https://github.com/bplyashwanth1-stack/Cadence/releases/latest")!
    private static let latestAPI = URL(string: "https://api.github.com/repos/bplyashwanth1-stack/Cadence/releases/latest")!
    static let defaultsKey = "checkForUpdates"

    /// The newer version on GitHub, e.g. "1.1", or nil when this build is current (or checking is off).
    private(set) var available: String?
    private var timer: Timer?

    static var enabled: Bool { UserDefaults.standard.object(forKey: defaultsKey) as? Bool ?? true }
    static var current: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0" }

    /// Installed by Homebrew, where the app lives in the Cellar (even when reached through a link).
    static var viaHomebrew: Bool { Bundle.main.bundleURL.resolvingSymlinksInPath().path.contains("/Cellar/") }

    func start() {
        check()
        timer = Timer.scheduledTimer(withTimeInterval: 24 * 60 * 60, repeats: true) { [weak self] _ in self?.check() }
    }

    func check() {
        guard Self.enabled else { available = nil; return }
        var request = URLRequest(url: Self.latestAPI, timeoutInterval: 15)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Cadence/\(Self.current)", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: request) { [weak self] data, response, _ in
            guard let data, (response as? HTTPURLResponse)?.statusCode == 200,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tag = json["tag_name"] as? String else { return }
            let latest = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
            DispatchQueue.main.async {
                self?.available = Self.isNewer(latest, than: Self.current) ? latest : nil
            }
        }.resume()
    }

    /// Compares dotted versions number by number, so 1.10 is newer than 1.9.
    static func isNewer(_ a: String, than b: String) -> Bool {
        let x = a.split(separator: ".").map { Int($0) ?? 0 }
        let y = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(x.count, y.count) {
            let p = i < x.count ? x[i] : 0, q = i < y.count ? y[i] : 0
            if p != q { return p > q }
        }
        return false
    }

    /// What the menu item does: the release page, or the Homebrew command for a Homebrew install.
    func showUpdate() {
        guard Self.viaHomebrew else {
            NSWorkspace.shared.open(Self.releasesPage)
            return
        }
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Cadence \(available ?? "") is available"
        alert.informativeText = "You installed Cadence with Homebrew. To update, run this in Terminal, then quit and reopen Cadence:\n\nbrew upgrade cadence"
        alert.addButton(withTitle: "Copy Command")
        alert.addButton(withTitle: "What's New")
        alert.addButton(withTitle: "Close")
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString("brew upgrade cadence", forType: .string)
        case .alertSecondButtonReturn:
            NSWorkspace.shared.open(Self.releasesPage)
        default:
            break
        }
    }
}
