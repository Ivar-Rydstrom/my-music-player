import SwiftUI
#if SWIFT_PACKAGE
import PlayerCore
#endif

extension ThemeColor {
    var color: Color { Color(red: red, green: green, blue: blue) }
    init(color: Color) {
        let rgb = NSColor(color).usingColorSpace(.sRGB) ?? .black
        self.init(rgb.redComponent, rgb.greenComponent, rgb.blueComponent)
    }
}

struct PlayerTheme {
    var base: ThemeColor
    var panel: ThemeColor
    var highlight: ThemeColor
    var glow: ThemeColor
    var background: Color { base.color }
    var surface: Color { panel.color }
    var accent: Color { highlight.readable(on: [base, panel], minimum: 3).color }
    var buttonInk: Color { ThemeColor(color: accent).readableInk.color }
    var text: Color { base.readableInk.color }
    var muted: Color { base.readableInk.mixed(with: base, amount: 0.38).readable(on: [base, panel], minimum: 4.5).color }
    var isDark: Bool { base.readableInk == .white }
    var wash: LinearGradient { LinearGradient(colors: [highlight.color.opacity(0.16), glow.color.opacity(0.08), .clear], startPoint: .topLeading, endPoint: .bottomTrailing) }
}

struct ThemePreset: Identifiable {
    var id: String
    var name: String
    var background: String
    var surface: String
    var accent: String
    var companion: String
    var theme: PlayerTheme { PlayerTheme(base: ThemeColor(hex: background)!, panel: ThemeColor(hex: surface)!, highlight: ThemeColor(hex: accent)!, glow: ThemeColor(hex: companion)!) }
    static let all: [ThemePreset] = [
        .init(id: "sage", name: "Sage", background: "181E1C", surface: "202925", accent: "C3DCA3", companion: "75B8A7"),
        .init(id: "dusk", name: "Dusk", background: "201C2B", surface: "2C253B", accent: "D5BBFA", companion: "E797AF"),
        .init(id: "tide", name: "Tide", background: "141F2B", surface: "1D2D3B", accent: "97D6E8", companion: "A3ACE9"),
        .init(id: "ember", name: "Ember", background: "291D1B", surface: "362724", accent: "F1B28D", companion: "DE97AA"),
        .init(id: "graphite", name: "Graphite", background: "19191C", surface: "242428", accent: "D8D8E0", companion: "9FA4B8"),
        .init(id: "paper", name: "Paper", background: "F4F1EA", surface: "E8E4DA", accent: "4E6951", companion: "BF966F")
    ]
}

struct ThemePreferences: Codable {
    var preset = "sage"
    var hue = 0.42
    var saturation = 0.45
    var intensity = 0.4
    var light = false
    var automatic = true
    var background = "#181E1C"
    var surface = "#202925"
    var accent = "#C3DCA3"
    var companion = "#75B8A7"
    var generated: PlayerTheme {
        let seed = ThemeColor(color: Color(hue: hue, saturation: saturation, brightness: 1))
        let base = light ? ThemeColor.white.mixed(with: seed, amount: 0.06 + intensity * 0.13) : ThemeColor.black.mixed(with: seed, amount: 0.07 + intensity * 0.12)
        let panel = base.mixed(with: light ? .black : seed, amount: light ? 0.055 : 0.05)
        let accent = light ? seed.mixed(with: .black, amount: 0.48) : seed.mixed(with: .white, amount: 0.4)
        let glow = ThemeColor(color: Color(hue: (hue + 0.16).truncatingRemainder(dividingBy: 1), saturation: saturation, brightness: light ? 0.6 : 0.95))
        return PlayerTheme(base: base, panel: panel, highlight: accent, glow: glow)
    }
    var theme: PlayerTheme {
        if let choice = ThemePreset.all.first(where: { $0.id == preset }) { return choice.theme }
        if automatic { return generated }
        let base = ThemeColor(hex: background) ?? generated.base
        let panel = ThemeColor(hex: surface) ?? generated.panel
        return PlayerTheme(base: base, panel: panel, highlight: ThemeColor(hex: accent) ?? generated.highlight, glow: ThemeColor(hex: companion) ?? generated.glow)
    }
}

@MainActor
final class ThemeStore: ObservableObject {
    @Published var preferences: ThemePreferences {
        didSet { if let data = try? JSONEncoder().encode(preferences) { UserDefaults.standard.set(data, forKey: "appearance.theme.v1") } }
    }
    init() {
        preferences = UserDefaults.standard.data(forKey: "appearance.theme.v1").flatMap { try? JSONDecoder().decode(ThemePreferences.self, from: $0) } ?? ThemePreferences()
    }
    var theme: PlayerTheme { preferences.theme }
    func customize() {
        let current = theme
        preferences.background = current.base.hex; preferences.surface = current.panel.hex
        preferences.accent = current.highlight.hex; preferences.companion = current.glow.hex
        let color = NSColor(current.highlight.color).usingColorSpace(.sRGB)!
        preferences.hue = color.hueComponent; preferences.saturation = color.saturationComponent
        preferences.light = !current.isDark; preferences.preset = "custom"
    }
    func setAutomatic(_ enabled: Bool) {
        if !enabled {
            let current = theme
            preferences.background = current.base.hex; preferences.surface = current.panel.hex
            preferences.accent = current.highlight.hex; preferences.companion = current.glow.hex
        }
        preferences.automatic = enabled
    }
}

private struct PlayerThemeKey: EnvironmentKey { static let defaultValue = ThemePreset.all[0].theme }
extension EnvironmentValues {
    var playerTheme: PlayerTheme { get { self[PlayerThemeKey.self] } set { self[PlayerThemeKey.self] = newValue } }
}
struct Themed: ViewModifier {
    @ObservedObject var store: ThemeStore
    func body(content: Content) -> some View {
        content.environment(\.playerTheme, store.theme).foregroundStyle(store.theme.text)
            .preferredColorScheme(store.theme.isDark ? .dark : .light).tint(store.theme.accent)
    }
}
