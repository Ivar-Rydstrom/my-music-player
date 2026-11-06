import SwiftUI

@main
struct StillPlayerApp: App {
    @StateObject private var model = AppModel()
    @StateObject private var themes = ThemeStore()
    @StateObject private var updater = AppUpdater()
    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
                .frame(minWidth: 980, minHeight: 650)
                .modifier(Themed(store: themes))
                .modifier(UpdatePrompt(updater: updater))
        }
        .defaultSize(width: 1280, height: 820)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") { Task { await updater.check(userInitiated: true) } }.disabled(updater.isBusy)
            }
            CommandMenu("Playback") {
                Button("Play / pause") { model.perform { try await model.playback.toggle() } }.keyboardShortcut("p", modifiers: [.command])
                Button("Next song") { model.perform { try await model.playback.next() } }.keyboardShortcut(.rightArrow, modifiers: [.command])
                Button("Previous song") { model.perform { try await model.playback.previous() } }.keyboardShortcut(.leftArrow, modifiers: [.command])
                Divider()
                Button("Refresh library") { model.perform { await model.refresh() } }.keyboardShortcut("r", modifiers: [.command])
            }
        }
        Settings {
            SettingsView(model: model, store: themes, updater: updater).modifier(Themed(store: themes))
        }
    }
}
