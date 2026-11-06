import Foundation

/// A dotted numeric version such as `0.3.1`. A leading `v` and any `-prerelease` or `+build` suffix are ignored.
public struct AppVersion: Comparable, CustomStringConvertible, Sendable {
    public let components: [Int]

    public init?(_ string: String) {
        var text = Substring(string.trimmingCharacters(in: .whitespaces))
        if text.first == "v" || text.first == "V" { text = text.dropFirst() }
        if let suffix = text.firstIndex(where: { $0 == "-" || $0 == "+" }) { text = text[..<suffix] }
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...4).contains(parts.count) else { return nil }
        var numbers: [Int] = []
        for part in parts {
            guard !part.isEmpty, part.allSatisfy(\.isASCII), let number = Int(part), number >= 0 else { return nil }
            numbers.append(number)
        }
        components = numbers
    }

    public var description: String { components.map(String.init).joined(separator: ".") }

    public static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        let count = max(lhs.components.count, rhs.components.count)
        for index in 0..<count {
            let left = index < lhs.components.count ? lhs.components[index] : 0
            let right = index < rhs.components.count ? rhs.components[index] : 0
            if left != right { return left < right }
        }
        return false
    }

    public static func == (lhs: AppVersion, rhs: AppVersion) -> Bool { !(lhs < rhs) && !(rhs < lhs) }
}

/// The subset of GitHub's release payload the updater reads.
public struct GitHubRelease: Decodable, Sendable {
    public struct Asset: Decodable, Sendable {
        public let name: String
        public let browserDownloadURL: URL
        public let size: Int
        /// `sha256:<hex>`, published by GitHub for release assets.
        public let digest: String?

        enum CodingKeys: String, CodingKey {
            case name, size, digest
            case browserDownloadURL = "browser_download_url"
        }
    }

    public let tagName: String
    public let name: String?
    public let body: String?
    public let htmlURL: URL
    public let draft: Bool
    public let prerelease: Bool
    public let assets: [Asset]

    enum CodingKeys: String, CodingKey {
        case name, body, draft, prerelease, assets
        case tagName = "tag_name"
        case htmlURL = "html_url"
    }
}

/// A release that can replace the running app.
public struct AppRelease: Equatable, Sendable {
    public let version: AppVersion
    public let notes: String
    public let pageURL: URL
    public let archiveURL: URL
    public let archiveSize: Int
    /// Lowercase hex SHA-256 of the archive, when GitHub provides one.
    public let archiveSHA256: String?
}

public enum AppUpdateError: LocalizedError, Equatable {
    case invalidVersion(String)
    case missingArchive(String)

    public var errorDescription: String? {
        switch self {
        case .invalidVersion(let tag): return "The latest release tag \"\(tag)\" isn't a version number."
        case .missingArchive(let tag): return "Release \(tag) has no Still-*.zip download."
        }
    }
}

public enum AppUpdateCheck {
    /// Returns the release when it's newer than `current`, or nil when the app is up to date.
    public static func evaluate(_ release: GitHubRelease, current: AppVersion) throws -> AppRelease? {
        guard !release.draft, !release.prerelease else { return nil }
        guard let version = AppVersion(release.tagName) else { throw AppUpdateError.invalidVersion(release.tagName) }
        guard current < version else { return nil }
        guard let archive = release.assets.first(where: { $0.name.hasPrefix("Still-") && $0.name.hasSuffix(".zip") }) else {
            throw AppUpdateError.missingArchive(release.tagName)
        }
        return AppRelease(version: version, notes: updateNotes(release.body ?? ""),
            pageURL: release.htmlURL, archiveURL: archive.browserDownloadURL, archiveSize: archive.size,
            archiveSHA256: sha256(fromDigest: archive.digest))
    }

    /// Release notes without the first-install paragraph the release workflow adds for DMG downloads.
    static func updateNotes(_ body: String) -> String {
        body.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n\n")
            .filter { !$0.hasPrefix(firstInstallMarker) }
            .joined(separator: "\n\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Must match the start of the `--notes` text in .github/workflows/release.yml.
    static let firstInstallMarker = "**First install:**"

    static func sha256(fromDigest digest: String?) -> String? {
        guard let digest, digest.lowercased().hasPrefix("sha256:") else { return nil }
        let hex = digest.dropFirst("sha256:".count).lowercased()
        guard hex.count == 64, hex.allSatisfy(\.isHexDigit) else { return nil }
        return hex
    }

    /// GitHub's latest-release endpoint for an `owner/name` repository.
    public static func latestReleaseURL(repository: String) -> URL? {
        let parts = repository.split(separator: "/")
        let isName: (Substring) -> Bool = { part in
            guard let first = part.first, first.isASCII, first.isLetter || first.isNumber else { return false }
            return part.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || "-_.".contains($0)) }
        }
        guard parts.count == 2, parts.allSatisfy(isName) else { return nil }
        return URL(string: "https://api.github.com/repos/\(parts[0])/\(parts[1])/releases/latest")
    }
}
