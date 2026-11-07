import XCTest
@testable import PlayerCore

final class AppUpdateTests: XCTestCase {
    func testVersionParsingAcceptsTagsAndIgnoresSuffixes() {
        XCTAssertEqual(AppVersion("v1.2.3")?.components, [1, 2, 3])
        XCTAssertEqual(AppVersion("0.4")?.components, [0, 4])
        XCTAssertEqual(AppVersion("2.0.0-beta.1")?.components, [2, 0, 0])
        XCTAssertEqual(AppVersion("1.0+42")?.description, "1.0")
        for invalid in ["", "v", "1..2", "1.2.x", "-1.0", "1.2.3.4.5", "１.0"] {
            XCTAssertNil(AppVersion(invalid), invalid)
        }
    }

    func testVersionOrderingIsNumericAndPadsMissingComponents() throws {
        let order = ["0.1.0", "0.1.1", "0.2", "0.10.0", "1.0.0", "1.0.10"].compactMap(AppVersion.init)
        XCTAssertEqual(order, order.sorted())
        XCTAssertEqual(AppVersion("1.0"), AppVersion("1.0.0"))
        XCTAssertFalse(try XCTUnwrap(AppVersion("1.0")) < XCTUnwrap(AppVersion("1.0.0")))
    }

    func testNewerReleaseSelectsZipArchiveAndDigest() throws {
        let release = try decode(tag: "v0.3.0", assets: [
            asset("Hummery-0.3.0.dmg"),
            asset("Hummery-0.3.0.zip", digest: "sha256:" + String(repeating: "AB", count: 32))
        ])
        let update = try XCTUnwrap(AppUpdateCheck.evaluate(release, current: XCTUnwrap(AppVersion("0.2.9"))))
        XCTAssertEqual(update.version.description, "0.3.0")
        XCTAssertEqual(update.archiveURL.lastPathComponent, "Hummery-0.3.0.zip")
        XCTAssertEqual(update.archiveSHA256, String(repeating: "ab", count: 32))
        XCTAssertEqual(update.notes, "Notes")
    }

    func testSameOrOlderReleaseIsNotAnUpdate() throws {
        let release = try decode(tag: "v0.3.0", assets: [asset("Hummery-0.3.0.zip")])
        XCTAssertNil(try AppUpdateCheck.evaluate(release, current: XCTUnwrap(AppVersion("0.3"))))
        XCTAssertNil(try AppUpdateCheck.evaluate(release, current: XCTUnwrap(AppVersion("1.0.0"))))
    }

    func testPrereleasesAndDraftsAreIgnored() throws {
        let current = try XCTUnwrap(AppVersion("0.1.0"))
        XCTAssertNil(try AppUpdateCheck.evaluate(decode(tag: "v0.2.0", prerelease: true, assets: [asset("Hummery-0.2.0.zip")]), current: current))
        XCTAssertNil(try AppUpdateCheck.evaluate(decode(tag: "v0.2.0", draft: true, assets: [asset("Hummery-0.2.0.zip")]), current: current))
    }

    func testMalformedReleasesExplainTheProblem() throws {
        let current = try XCTUnwrap(AppVersion("0.1.0"))
        XCTAssertThrowsError(try AppUpdateCheck.evaluate(decode(tag: "nightly", assets: []), current: current)) {
            XCTAssertEqual($0 as? AppUpdateError, .invalidVersion("nightly"))
        }
        XCTAssertThrowsError(try AppUpdateCheck.evaluate(decode(tag: "v0.2.0", assets: [asset("Hummery-0.2.0.dmg")]), current: current)) {
            XCTAssertEqual($0 as? AppUpdateError, .missingArchive("v0.2.0"))
        }
    }

    func testUpdateNotesDropTheFirstInstallParagraph() {
        let body = "**First install:** open the DMG and drag Hummery to Applications.\r\n\r\n## What's Changed\r\n* Faster artwork\r\n\r\n**Full Changelog**: link"
        XCTAssertEqual(AppUpdateCheck.updateNotes(body), "## What's Changed\n* Faster artwork\n\n**Full Changelog**: link")
        XCTAssertEqual(AppUpdateCheck.updateNotes("  Plain notes\n"), "Plain notes")
    }

    func testOnlyWellFormedSHA256DigestsAreKept() {
        XCTAssertNil(AppUpdateCheck.sha256(fromDigest: nil))
        XCTAssertNil(AppUpdateCheck.sha256(fromDigest: "md5:abc"))
        XCTAssertNil(AppUpdateCheck.sha256(fromDigest: "sha256:abc"))
        XCTAssertNil(AppUpdateCheck.sha256(fromDigest: "sha256:" + String(repeating: "zz", count: 32)))
    }

    func testLatestReleaseURLRejectsMalformedRepositories() {
        XCTAssertEqual(AppUpdateCheck.latestReleaseURL(repository: "Ivar-Rydstrom/my-music-player")?.absoluteString,
            "https://api.github.com/repos/Ivar-Rydstrom/my-music-player/releases/latest")
        for invalid in ["", "owner", "owner/", "a/b/c", "owner/name?x=1", "../etc"] {
            XCTAssertNil(AppUpdateCheck.latestReleaseURL(repository: invalid), invalid)
        }
    }

    private func asset(_ name: String, digest: String? = nil) -> [String: Any] {
        var value: [String: Any] = ["name": name, "browser_download_url": "https://github.com/o/r/releases/download/v/\(name)", "size": 1024]
        if let digest { value["digest"] = digest }
        return value
    }

    private func decode(tag: String, draft: Bool = false, prerelease: Bool = false, assets: [[String: Any]]) throws -> GitHubRelease {
        let json: [String: Any] = ["tag_name": tag, "name": "Hummery", "body": "Notes\n", "html_url": "https://github.com/o/r/releases/tag/\(tag)",
            "draft": draft, "prerelease": prerelease, "assets": assets]
        return try JSONDecoder().decode(GitHubRelease.self, from: JSONSerialization.data(withJSONObject: json))
    }
}
