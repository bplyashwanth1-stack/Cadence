import AppKit
import Security

// MARK: - Updates

/// Once a day, asks GitHub for Cadence's latest release. When it's newer than this build, the menu shows
/// "Update Available". For a copy installed from a GitHub release, that installs the update and relaunches; a
/// Homebrew install gets the brew command, and anything else (a local build) gets the release page.
/// Turn the check off in Settings › Lock screen.
final class UpdateChecker {
    static let shared = UpdateChecker()

    static let releasesPage = URL(string: "https://github.com/bplyashwanth1-stack/Cadence/releases/latest")!
    private static let latestAPI = URL(string: "https://api.github.com/repos/bplyashwanth1-stack/Cadence/releases/latest")!
    static let defaultsKey = "checkForUpdates"

    /// Releases are signed with this certificate (scripts and secrets in the repo); an update is only installed
    /// when the download carries the same signature, so a tampered download is refused.
    private static let releaseRequirement =
        "identifier \"local.cadence.lyrics\" and certificate leaf = H\"8de7d9b987e77ab2c40695712c936d4fc527fc6b\""

    /// The newer version on GitHub, e.g. "1.3", or nil when this build is current (or checking is off).
    private(set) var available: String?
    private var download: URL?  // that release's Cadence.zip
    private(set) var installing = false
    private var timer: Timer?

    static var enabled: Bool { UserDefaults.standard.object(forKey: defaultsKey) as? Bool ?? true }
    static var current: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0" }

    /// Installed by Homebrew, where the app lives in the Cellar (even when reached through a link).
    static var viaHomebrew: Bool { Bundle.main.bundleURL.resolvingSymlinksInPath().path.contains("/Cellar/") }

    /// This copy came from a GitHub release (signed with the release certificate), so it can update itself.
    static var canSelfUpdate: Bool {
        !viaHomebrew && FileManager.default.isWritableFile(atPath: Bundle.main.bundleURL.deletingLastPathComponent().path)
            && signedForRelease(Bundle.main.bundleURL)
    }

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
            let assets = json["assets"] as? [[String: Any]] ?? []
            let zip = assets.first { $0["name"] as? String == "Cadence.zip" }?["browser_download_url"] as? String
            DispatchQueue.main.async {
                self?.available = Self.isNewer(latest, than: Self.current) ? latest : nil
                self?.download = zip.flatMap(URL.init(string:))
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

    /// What the menu item does.
    func showUpdate() {
        NSApp.activate(ignoringOtherApps: true)
        let version = available ?? ""
        let alert = NSAlert()
        alert.messageText = "Cadence \(version) is available"
        if Self.viaHomebrew {
            alert.informativeText = "You installed Cadence with Homebrew. To update, run this in Terminal, then quit and reopen Cadence:\n\nbrew upgrade cadence"
            alert.addButton(withTitle: "Copy Command")
        } else if Self.canSelfUpdate, download != nil {
            alert.informativeText = "You have \(Self.current). Cadence will download the update, check its signature, replace itself and reopen. It takes a few seconds."
            alert.addButton(withTitle: "Install and Relaunch")
        } else {
            alert.informativeText = "You have \(Self.current). Download the new version from GitHub and replace Cadence in your Applications folder."
            alert.addButton(withTitle: "Download")
        }
        alert.addButton(withTitle: "What's New")
        alert.addButton(withTitle: "Later")
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            if Self.viaHomebrew {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString("brew upgrade cadence", forType: .string)
            } else if Self.canSelfUpdate, let download {
                install(from: download, version: version)
            } else {
                NSWorkspace.shared.open(Self.releasesPage)
            }
        case .alertSecondButtonReturn:
            NSWorkspace.shared.open(Self.releasesPage)
        default:
            break
        }
    }

    // MARK: Installing

    private func install(from url: URL, version: String) {
        guard !installing else { return }
        installing = true
        PresetToast.shared.show("Downloading Cadence \(version)…", "arrow.down.circle")
        Log.write("update: downloading \(url.absoluteString)")
        URLSession.shared.downloadTask(with: url) { [weak self] file, response, error in
            let result: Result<URL, Error>
            if let file, (response as? HTTPURLResponse)?.statusCode == 200 {
                result = Result { try Self.unpackAndVerify(file, version: version) }
            } else {
                result = .failure(error ?? UpdateError("The download didn't finish."))
            }
            DispatchQueue.main.async { self?.finishInstall(result, version: version) }
        }.resume()
    }

    struct UpdateError: LocalizedError {
        let errorDescription: String?
        init(_ message: String) { errorDescription = message }
    }

    /// Unzips the download and checks it's Cadence, signed for release, and the version promised.
    static func unpackAndVerify(_ zip: URL, version: String) throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("cadence-update-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let ditto = Process()
        ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        ditto.arguments = ["-x", "-k", zip.path, folder.path]
        try ditto.run()
        ditto.waitUntilExit()
        let app = folder.appendingPathComponent("Cadence.app")
        guard ditto.terminationStatus == 0, FileManager.default.fileExists(atPath: app.path) else {
            throw UpdateError("The download couldn't be unpacked.")
        }
        guard signedForRelease(app) else { throw UpdateError("The download isn't signed by Cadence, so it wasn't installed.") }
        let downloaded = Bundle(url: app)?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        guard downloaded == version else { throw UpdateError("The download is version \(downloaded ?? "?"), not \(version).") }
        return app
    }

    private func finishInstall(_ result: Result<URL, Error>, version: String) {
        installing = false
        switch result {
        case .success(let app):
            do {
                let current = Bundle.main.bundleURL
                _ = try FileManager.default.replaceItemAt(current, withItemAt: app)
                Log.write("update: installed \(version), relaunching")
                // Reopen the new copy once this one has quit.
                let relaunch = Process()
                relaunch.executableURL = URL(fileURLWithPath: "/bin/sh")
                relaunch.arguments = ["-c", "sleep 1; /usr/bin/open \"$0\"", current.path]
                try relaunch.run()
                NSApp.terminate(nil)
            } catch {
                fail(error)
            }
        case .failure(let error):
            fail(error)
        }
    }

    private func fail(_ error: Error) {
        Log.write("update failed: \(error.localizedDescription)")
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Couldn't install the update"
        alert.informativeText = error.localizedDescription + "\n\nYou can download it from GitHub instead."
        alert.addButton(withTitle: "Open GitHub")
        alert.addButton(withTitle: "Close")
        if alert.runModal() == .alertFirstButtonReturn { NSWorkspace.shared.open(Self.releasesPage) }
    }

    /// Whether the app at `url` is validly signed with Cadence's release certificate.
    static func signedForRelease(_ url: URL) -> Bool {
        var code: SecStaticCode?
        var requirement: SecRequirement?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess, let code,
              SecRequirementCreateWithString(releaseRequirement as CFString, [], &requirement) == errSecSuccess
        else { return false }
        let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSStrictValidate | kSecCSCheckNestedCode)
        return SecStaticCodeCheckValidity(code, flags, requirement) == errSecSuccess
    }
}
