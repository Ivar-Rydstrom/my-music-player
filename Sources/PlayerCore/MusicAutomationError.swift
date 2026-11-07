import Foundation

public struct MusicAutomationError: LocalizedError, Sendable {
    public var number: Int
    public var message: String
    public init(number: Int, message: String) { self.number = number; self.message = message }
    public var errorDescription: String? {
        switch number {
        case -1743:
            return "macOS denied Automation access (-1743). Allow Hummery to control Music in System Settings > Privacy & Security > Automation, then reconnect."
        case -10004:
            return "Music rejected this request with a sandbox privilege error (-10004). This is an app configuration problem, even if Automation access is allowed. Original error: \(message)"
        case -1712:
            return "Music did not respond in time. Open Music, dismiss any sign-in or setup dialogs, allow Automation access if prompted, and retry."
        case -600, -609:
            return "Music is not available. Open Music and reconnect."
        case -1728:
            return "Music could not find that item. Refresh the playlist; it may have changed in Music or on another device."
        default:
            return "Music automation failed (\(number)): \(message)"
        }
    }
}
