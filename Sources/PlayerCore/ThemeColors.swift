import Foundation

/// sRGB color math shared by the editor and its contrast checks.
public struct ThemeColor: Codable, Equatable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public init(_ red: Double, _ green: Double, _ blue: Double) {
        self.red = min(1, max(0, red)); self.green = min(1, max(0, green)); self.blue = min(1, max(0, blue))
    }
    public init?(hex: String) {
        let trimmed = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = trimmed.hasPrefix("#") ? String(trimmed.dropFirst()) : trimmed
        guard value.count == 6, value.allSatisfy({ $0.isHexDigit }), let number = UInt32(value, radix: 16) else { return nil }
        self.init(Double((number >> 16) & 255) / 255, Double((number >> 8) & 255) / 255, Double(number & 255) / 255)
    }
    public var hex: String { String(format: "#%02X%02X%02X", Int((red * 255).rounded()), Int((green * 255).rounded()), Int((blue * 255).rounded())) }
    public var luminance: Double {
        func linear(_ v: Double) -> Double { v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }
    public func contrast(with other: ThemeColor) -> Double {
        (max(luminance, other.luminance) + 0.05) / (min(luminance, other.luminance) + 0.05)
    }
    public func mixed(with other: ThemeColor, amount: Double) -> ThemeColor {
        let t = min(1, max(0, amount))
        return ThemeColor(red + (other.red - red) * t, green + (other.green - green) * t, blue + (other.blue - blue) * t)
    }
    public static let white = ThemeColor(1, 1, 1)
    public static let black = ThemeColor(0, 0, 0)
    public var readableInk: ThemeColor { contrast(with: .white) >= contrast(with: .black) ? .white : .black }
    /// Move a color toward the shared readable ink until it works on both surfaces.
    public func readable(on backgrounds: [ThemeColor], minimum: Double) -> ThemeColor {
        guard !backgrounds.isEmpty else { return self }
        let ink = (ThemeColor.white.contrast(with: backgrounds[0]) < ThemeColor.black.contrast(with: backgrounds[0])) ? ThemeColor.black : ThemeColor.white
        for step in 0...100 {
            let candidate = mixed(with: ink, amount: Double(step) / 100)
            if backgrounds.allSatisfy({ candidate.contrast(with: $0) >= minimum }) { return candidate }
        }
        return ink
    }
}
