import XCTest
@testable import PlayerCore

final class MusicConnectionSetupTests: XCTestCase {
    private var configured: MusicConnectionSetup {
        MusicConnectionSetup(bundleID: "com.listener.Hummery", teamID: "ABCDEFGHIJ",
            hasSigningCertificate: true, hasUsageDescription: true, isAppBundle: true)
    }
    func testConfiguredBuildCanAttemptServiceConnection() {
        XCTAssertNil(configured.issue)
    }
    func testCommandLineExecutableCannotRequestAccess() {
        var setup = configured
        setup.isAppBundle = false
        XCTAssertNotNil(setup.issue)
    }
    func testMissingPrivacyDescriptionBlocksAccess() {
        var setup = configured
        setup.hasUsageDescription = false
        XCTAssertNotNil(setup.issue)
    }
    func testPlaceholderIdentifierIsRejectedEvenWhenSigned() {
        var setup = configured
        setup.bundleID = "com.example.Hummery"
        XCTAssertNotNil(setup.issue)
    }
    func testAdHocBuildIsRejectedEvenWithATeamString() {
        var setup = configured
        setup.hasSigningCertificate = false
        XCTAssertNotNil(setup.issue)
    }
    func testCertificateWithoutDeveloperTeamIsRejected() {
        var setup = configured
        setup.teamID = nil
        XCTAssertNotNil(setup.issue)
    }
}
