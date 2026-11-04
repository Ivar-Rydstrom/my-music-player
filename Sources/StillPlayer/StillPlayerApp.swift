import SwiftUI

@main
struct StillPlayerApp: App {
    @StateObject private var model = AppModel()
    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
                .frame(minWidth: 980, minHeight: 650)
                .preferredColorScheme(.dark)
                .tint(Palette.accent)
        }
        .defaultSize(width: 1280, height: 820)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}

enum Palette {
    static let background = Color(red: 0.095, green: 0.105, blue: 0.105)
    static let surface = Color(red: 0.125, green: 0.14, blue: 0.14)
    static let accent = Color(red: 0.79, green: 0.88, blue: 0.65)
    static let muted = Color(red: 0.56, green: 0.61, blue: 0.59)
}
