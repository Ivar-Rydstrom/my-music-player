import XCTest
@testable import PlayerCore

final class UpdateArchiveTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appending(path: "UpdateArchiveTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder.appending(path: "Hummery.app/Contents/MacOS"), withIntermediateDirectories: true)
        try Data("binary".utf8).write(to: folder.appending(path: "Hummery.app/Contents/MacOS/Hummery"))
        try Data("<plist/>".utf8).write(to: folder.appending(path: "Hummery.app/Contents/Info.plist"))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    func testDittoReleaseArchiveIsAccepted() throws {
        let zip = folder.appending(path: "release.zip")
        try run("/usr/bin/ditto", ["-c", "-k", "--sequesterRsrc", "--keepParent", folder.appending(path: "Hummery.app").path, zip.path])
        let entries = try UpdateArchive.entries(in: Data(contentsOf: zip))
        XCTAssertTrue(entries.contains { $0.path == "Hummery.app/Contents/MacOS/Hummery" })
        XCTAssertEqual(try UpdateArchive.validate(entries), "Hummery.app")
    }

    func testSymlinkInArchiveIsRejected() throws {
        try FileManager.default.createSymbolicLink(atPath: folder.appending(path: "Hummery.app/Contents/Escape").path,
            withDestinationPath: NSHomeDirectory())
        let zip = folder.appending(path: "link.zip")
        try run("/usr/bin/zip", ["-q", "-r", "-y", zip.path, "Hummery.app"], in: folder)
        let entries = try UpdateArchive.entries(in: Data(contentsOf: zip))
        XCTAssertThrowsError(try UpdateArchive.validate(entries)) {
            XCTAssertEqual($0 as? UpdateArchive.Problem, .symlink("Hummery.app/Contents/Escape"))
        }
    }

    func testUnsafePathsAreRejected() {
        for path in ["/Applications/Hummery.app/x", "Hummery.app/../../.zshrc", "../Hummery.app/x", "Hummery.app/./x", "Hummery.app//x", "Hummery.app\\..\\x"] {
            XCTAssertThrowsError(try UpdateArchive.validate([.init(path: path, unixMode: 0o100644)]), path) {
                XCTAssertEqual($0 as? UpdateArchive.Problem, .unsafePath(path))
            }
        }
    }

    func testLayoutMustBeOneAppPlusOptionalMetadata() throws {
        let file: (String) -> UpdateArchive.Entry = { .init(path: $0, unixMode: 0o100644) }
        XCTAssertEqual(try UpdateArchive.validate([file("Hummery.app/"), file("Hummery.app/Contents/Info.plist"), file("__MACOSX/Hummery.app/._x")]), "Hummery.app")
        XCTAssertThrowsError(try UpdateArchive.validate([file("Hummery.app/a"), file("Other.app/a")]))
        XCTAssertThrowsError(try UpdateArchive.validate([file("Hummery.app/a"), file("install.sh")]))
        XCTAssertThrowsError(try UpdateArchive.validate([file("__MACOSX/x")]))
        XCTAssertThrowsError(try UpdateArchive.validate([]))
    }

    func testGarbageIsUnreadable() {
        XCTAssertThrowsError(try UpdateArchive.entries(in: Data("not a zip at all, just some text".utf8)))
        XCTAssertThrowsError(try UpdateArchive.entries(in: Data()))
    }

    private func run(_ tool: String, _ arguments: [String], in directory: URL? = nil) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        process.currentDirectoryURL = directory
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0, "\(tool) \(arguments)")
    }
}
