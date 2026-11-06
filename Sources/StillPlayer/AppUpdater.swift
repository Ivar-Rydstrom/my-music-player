import AppKit
import CryptoKit
import Security
#if SWIFT_PACKAGE
import PlayerCore
#endif

/// Checks GitHub Releases for a newer build and installs it in place.
@MainActor
final class AppUpdater: ObservableObject {
    enum Phase: Equatable {
        case idle
        case checking
        case upToDate
        case available(AppRelease)
        case installing(AppRelease, step: String)
        case failed(String)
    }

    enum Prompt: Equatable {
        case available(AppRelease)
        case upToDate
        case problem(title: String, detail: String)
    }

    private enum Keys {
        static let automatic = "updates.automatic"
        static let lastCheck = "updates.lastCheck"
        static let skipped = "updates.skippedVersion"
        static let pending = "updates.pendingVersion"
    }

    @Published private(set) var phase: Phase = .idle
    @Published var prompt: Prompt?
    @Published var automaticallyChecks: Bool {
        didSet {
            defaults.set(automaticallyChecks, forKey: Keys.automatic)
            automaticallyChecks ? scheduleChecks() : schedule?.cancel()
        }
    }

    let currentVersion = (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String).flatMap(AppVersion.init)
    let releasesPage: URL?
    private let repository = Bundle.main.object(forInfoDictionaryKey: "StillUpdateRepository") as? String
    private let defaults = UserDefaults.standard
    private var schedule: Task<Void, Never>?

    var lastCheck: Date? { defaults.object(forKey: Keys.lastCheck) as? Date }
    var isBusy: Bool {
        switch phase { case .checking, .installing: return true; default: return false }
    }

    init() {
        automaticallyChecks = defaults.object(forKey: Keys.automatic) as? Bool ?? true
        releasesPage = repository.flatMap { URL(string: "https://github.com/\($0)/releases") }
        reportUnfinishedInstall()
        if automaticallyChecks { scheduleChecks() }
    }

    /// Checks shortly after launch, then about once a day while Still stays open.
    private func scheduleChecks() {
        schedule?.cancel()
        schedule = Task { [weak self] in
            try? await Task.sleep(for: .seconds(8))
            while !Task.isCancelled {
                guard let self else { return }
                if Date().timeIntervalSince(self.lastCheck ?? .distantPast) > 20 * 60 * 60 {
                    await self.check(userInitiated: false)
                }
                try? await Task.sleep(for: .seconds(60 * 60))
            }
        }
    }

    func check(userInitiated: Bool) async {
        guard !isBusy else { return }
        // `updates.feedURL` points checks at a test feed, e.g. `--args -updates.feedURL http://127.0.0.1:8000/latest.json`.
        // Downloads still have to pass the same signature check.
        let feed = defaults.string(forKey: "updates.feedURL").flatMap(URL.init(string:))
        guard let currentVersion, let url = feed ?? repository.flatMap(AppUpdateCheck.latestReleaseURL) else {
            report("This build has no version or update source configured.", title: "Can't check for updates", show: userInitiated)
            return
        }
        phase = .checking
        do {
            var request = URLRequest(url: url, timeoutInterval: 20)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.setValue("Still-Updater", forHTTPHeaderField: "User-Agent")
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if status == 404 {
                defaults.set(Date(), forKey: Keys.lastCheck)
                phase = .upToDate
                if userInitiated { prompt = .upToDate }
                return
            }
            guard status == 200 else { throw UpdateInstaller.Failure("GitHub answered with HTTP \(status). Try again later.") }
            defaults.set(Date(), forKey: Keys.lastCheck)
            let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
            if let update = try AppUpdateCheck.evaluate(release, current: currentVersion) {
                phase = .available(update)
                if userInitiated || defaults.string(forKey: Keys.skipped) != update.version.description {
                    prompt = .available(update)
                }
            } else {
                phase = .upToDate
                if userInitiated { prompt = .upToDate }
            }
        } catch {
            report(error.localizedDescription, title: "Couldn't check for updates", show: userInitiated)
        }
    }

    func skip(_ release: AppRelease) {
        defaults.set(release.version.description, forKey: Keys.skipped)
    }

    func install(_ release: AppRelease) async {
        guard !isBusy else { return }
        if let blocker = UpdateInstaller.blocker() {
            report(blocker, title: "Can't install automatically", show: true)
            return
        }
        phase = .installing(release, step: "Downloading \(release.version)…")
        do {
            let archive = try await UpdateInstaller.download(release)
            phase = .installing(release, step: "Verifying…")
            let app = try await Task.detached(priority: .userInitiated) { try UpdateInstaller.prepare(archive: archive, for: release) }.value
            phase = .installing(release, step: "Relaunching…")
            defaults.set(release.version.description, forKey: Keys.pending)
            defaults.synchronize()
            try UpdateInstaller.replaceAfterExit(with: app)
            NSApp.terminate(nil)
        } catch {
            defaults.removeObject(forKey: Keys.pending)
            report(error.localizedDescription, title: "Couldn't install the update", show: true)
        }
    }

    private func report(_ message: String, title: String, show: Bool) {
        phase = .failed(message)
        if show { prompt = .problem(title: title, detail: message) }
    }

    /// The swap runs after Still quits, so a failure is only visible on the next launch.
    private func reportUnfinishedInstall() {
        guard let pending = defaults.string(forKey: Keys.pending) else { return }
        defaults.removeObject(forKey: Keys.pending)
        guard let target = AppVersion(pending), let currentVersion, currentVersion < target else { return }
        report("macOS didn't let Still replace itself with version \(pending). Turn on Still under System Settings > Privacy & Security > App Management and try again, or install the DMG from GitHub.",
            title: "The update didn't finish", show: true)
    }
}

/// Download, verification, and replacement steps. Nothing here touches the running app until it quits.
enum UpdateInstaller {
    struct Failure: LocalizedError {
        let errorDescription: String?
        init(_ message: String) { errorDescription = message }
    }

    /// Explains why an in-place install can't work for this copy, or nil when it can.
    static func blocker() -> String? {
        let app = Bundle.main.bundleURL
        guard app.pathExtension == "app" else { return "Only the Still app bundle can install updates." }
        if app.path.contains("/AppTranslocation/") {
            return "macOS is running Still from a temporary location. Move Still to your Applications folder, open it from there, and try again."
        }
        if hostRequirement() == nil {
            return "This is a local development build, so Still can't confirm a download comes from the same signer. Install a release from GitHub to get automatic updates."
        }
        let folder = app.deletingLastPathComponent()
        guard FileManager.default.isWritableFile(atPath: folder.path) else {
            return "Still can't write to \(folder.path). Move it to a folder you can change, such as Applications."
        }
        return nil
    }

    /// The running app's designated requirement. Nil for ad hoc builds, whose requirement changes with every build.
    static func hostRequirement() -> SecRequirement? {
        var code: SecCode?
        var staticCode: SecStaticCode?
        var information: CFDictionary?
        var requirement: SecRequirement?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code,
              SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode,
              SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &information) == errSecSuccess,
              let info = information as? [String: Any],
              !(info[kSecCodeInfoCertificates as String] as? [SecCertificate] ?? []).isEmpty,
              SecCodeCopyDesignatedRequirement(staticCode, [], &requirement) == errSecSuccess else { return nil }
        return requirement
    }

    static func download(_ release: AppRelease) async throws -> URL {
        var request = URLRequest(url: release.archiveURL, timeoutInterval: 120)
        request.setValue("Still-Updater", forHTTPHeaderField: "User-Agent")
        let (temporary, response) = try await URLSession.shared.download(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            try? FileManager.default.removeItem(at: temporary)
            throw Failure("The download failed with HTTP \(status).")
        }
        // A replacement directory sits on the app's volume, so the final swap is a rename.
        let workspace = try FileManager.default.url(for: .itemReplacementDirectory, in: .userDomainMask,
            appropriateFor: Bundle.main.bundleURL, create: true)
        let archive = workspace.appending(path: "update.zip")
        try FileManager.default.moveItem(at: temporary, to: archive)
        return archive
    }

    /// Checks the archive, expands it, and confirms the app inside is the expected, same-signer build.
    static func prepare(archive: URL, for release: AppRelease) throws -> URL {
        if let expected = release.archiveSHA256, try sha256(of: archive) != expected {
            throw Failure("The download doesn't match the checksum GitHub published for it.")
        }
        let expanded = archive.deletingLastPathComponent().appending(path: "Expanded")
        try run("/usr/bin/ditto", ["-x", "-k", archive.path, expanded.path])
        let apps = try FileManager.default.contentsOfDirectory(at: expanded, includingPropertiesForKeys: nil).filter { $0.pathExtension == "app" }
        guard apps.count == 1, let app = apps.first else { throw Failure("The download doesn't contain exactly one app.") }
        let info = NSDictionary(contentsOf: app.appending(path: "Contents/Info.plist")) as? [String: Any] ?? [:]
        guard info["CFBundleIdentifier"] as? String == Bundle.main.bundleIdentifier else {
            throw Failure("The download is a different app (\(info["CFBundleIdentifier"] as? String ?? "no identifier")).")
        }
        guard (info["CFBundleShortVersionString"] as? String).flatMap(AppVersion.init) == release.version else {
            throw Failure("The downloaded app doesn't report version \(release.version).")
        }
        try verifySignature(of: app)
        try? run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", app.path])
        return app
    }

    static func verifySignature(of app: URL) throws {
        guard let requirement = hostRequirement() else { throw Failure("This build has no stable signature to compare against.") }
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(app as CFURL, [], &code) == errSecSuccess, let code else {
            throw Failure("The downloaded app's signature couldn't be read.")
        }
        let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSStrictValidate | kSecCSCheckNestedCode)
        let status = SecStaticCodeCheckValidityWithErrors(code, flags, requirement, nil)
        guard status == errSecSuccess else {
            throw Failure("The downloaded app isn't signed by the same certificate as this copy of Still (OSStatus \(status)).")
        }
    }

    /// Starts a small script that waits for Still to quit, swaps the bundles, and reopens Still.
    /// If the swap fails, it restores the previous copy and opens that instead.
    static func replaceAfterExit(with replacement: URL) throws {
        let workspace = replacement.deletingLastPathComponent().deletingLastPathComponent()
        let script = workspace.appending(path: "install.sh")
        try swapScript.write(to: script, atomically: true, encoding: .utf8)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [script.path, String(ProcessInfo.processInfo.processIdentifier), Bundle.main.bundleURL.path,
            replacement.path, workspace.appending(path: "Previous.app").path, workspace.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
    }

    static let swapScript = """
        #!/bin/sh
        pid="$1"; current="$2"; replacement="$3"; backup="$4"; workspace="$5"
        tries=0
        while kill -0 "$pid" 2>/dev/null; do
          tries=$((tries + 1))
          [ "$tries" -gt 300 ] && exit 1
          sleep 0.2
        done
        if mv "$current" "$backup"; then
          if mv "$replacement" "$current"; then
            rm -rf "$workspace"
          else
            mv "$backup" "$current"
          fi
        fi
        open "$current"
        """

    static func sha256(of file: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty { hasher.update(data: chunk) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func run(_ tool: String, _ arguments: [String]) throws {
        let process = Process()
        let errors = Pipe()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = errors
        try process.run()
        let output = errors.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let detail = String(decoding: output, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            throw Failure("\(URL(fileURLWithPath: tool).lastPathComponent) failed: \(detail)")
        }
    }
}
