import Foundation
import Security
import MusicKit
#if SWIFT_PACKAGE
import PlayerCore
#endif

enum MusicAccountSetup {
    static var isAuthorized: Bool { MusicAuthorization.currentStatus == .authorized }
    static func inspect() -> MusicConnectionSetup {
        var code: SecStaticCode?
        var information: CFDictionary?
        var team: String?
        var hasCertificate = false
        if SecStaticCodeCreateWithPath(Bundle.main.bundleURL as CFURL, [], &code) == errSecSuccess,
           let code,
           SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &information) == errSecSuccess,
           let info = information as? [String: Any] {
            team = info[kSecCodeInfoTeamIdentifier as String] as? String
            hasCertificate = !(info[kSecCodeInfoCertificates as String] as? [SecCertificate] ?? []).isEmpty
        }
        return MusicConnectionSetup(
            bundleID: Bundle.main.bundleIdentifier ?? "",
            teamID: team,
            hasSigningCertificate: hasCertificate,
            hasUsageDescription: !(Bundle.main.object(forInfoDictionaryKey: "NSAppleMusicUsageDescription") as? String ?? "").isEmpty,
            isAppBundle: Bundle.main.bundleURL.pathExtension == "app"
        )
    }

    static var authorization: String {
        switch MusicAuthorization.currentStatus {
        case .notDetermined: return "Not requested"
        case .authorized: return "Allowed"
        case .denied: return "Denied in System Settings"
        case .restricted: return "Restricted by system or account policy"
        @unknown default: return "Unknown"
        }
    }
}
