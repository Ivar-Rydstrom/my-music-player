import XCTest
@testable import PlayerCore

final class MusicAutomationErrorTests: XCTestCase {
    func testSandboxDenialDoesNotTellUserToGrantPermissionAgain() {
        let text = MusicAutomationError(number: -10004, message: "A privilege violation occurred.").localizedDescription
        XCTAssertTrue(text.contains("sandbox privilege"))
        XCTAssertTrue(text.contains("-10004"))
        XCTAssertTrue(text.contains("A privilege violation occurred."))
        XCTAssertFalse(text.contains("Allow Hummery to control Music in System Settings"))
    }
    func testAutomationDenialExplainsWhereToGrantPermission() {
        let text = MusicAutomationError(number: -1743, message: "Not authorized").localizedDescription
        XCTAssertTrue(text.contains("Privacy & Security > Automation"))
        XCTAssertTrue(text.contains("-1743"))
    }
}
