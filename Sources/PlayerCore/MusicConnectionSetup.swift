import Foundation

/// Build identity checks only. The MusicKit App Service is verified by a service request.
public struct MusicConnectionSetup: Sendable {
    public var bundleID: String
    public var teamID: String?
    public var hasSigningCertificate: Bool
    public var hasUsageDescription: Bool
    public var isAppBundle: Bool

    public init(bundleID: String, teamID: String?, hasSigningCertificate: Bool,
                hasUsageDescription: Bool, isAppBundle: Bool) {
        self.bundleID = bundleID; self.teamID = teamID
        self.hasSigningCertificate = hasSigningCertificate
        self.hasUsageDescription = hasUsageDescription; self.isAppBundle = isAppBundle
    }

    public var issue: String? {
        if !isAppBundle || !hasUsageDescription {
            return "Open and run Hummery.xcodeproj in Xcode. Account access requires the app bundle with its Apple Music permission description."
        }
        if bundleID.isEmpty || bundleID.hasPrefix("com.example.") || bundleID.contains("yourname") {
            return "Choose your own bundle identifier in Config/Local.xcconfig, then register that exact App ID with MusicKit enabled in the Apple Developer portal."
        }
        if !hasSigningCertificate || teamID?.isEmpty != false {
            return "This build has no Apple developer signing identity. Enroll in the Apple Developer Program, add the account in Xcode > Settings > Accounts, select your team, and run a signed build."
        }
        return nil
    }
}
