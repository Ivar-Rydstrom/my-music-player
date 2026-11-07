import SwiftUI

@main
struct StillPlayerApp: App {
    @StateObject private var model = AppModel()
    @StateObject private var themes = ThemeStore()
    @StateObject private var updater = AppUpdater()
    @StateObject private var workspace = Workspace()
    var body: some Scene {
        WindowGroup {
            ContentView(model: model, workspace: workspace, themes: themes, updater: updater)
                .frame(minWidth: 980, minHeight: 650)
                .modifier(Themed(store: themes))
                .modifier(UpdatePrompt(updater: updater))
                #if DEBUG
                .onAppear {
                    if let theme = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("--theme=") }) {
                        themes.preferences.preset = String(theme.dropFirst("--theme=".count))
                    }
                }
                #endif
        }
        .defaultSize(width: 1280, height: 820)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(replacing: .saveItem) {}
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") { Task { await updater.check(userInitiated: true) } }.disabled(updater.isBusy)
            }
            CommandGroup(replacing: .textEditing) {
                Button("Command Palette…") { workspace.togglePalette() }.keyboardShortcut("p", modifiers: [.command, .shift])
                Button("Search…") { workspace.togglePalette() }.keyboardShortcut("k", modifiers: [.command])
                Button("Filter This Playlist") { workspace.revealFilter() }.keyboardShortcut("f", modifiers: [.command])
            }
            CommandMenu("Go") {
                Button("Back") { workspace.goBack() }.keyboardShortcut("[", modifiers: [.command]).disabled(!workspace.canGoBack)
                Button("Forward") { workspace.goForward() }.keyboardShortcut("]", modifiers: [.command]).disabled(!workspace.canGoForward)
                Divider()
                Button("Recently Played") { workspace.select("recent") }
                Button("Favorites") { workspace.select("favorites") }
                Divider()
                Button("Previous Playlist") { workspace.selectAdjacent(-1) }.keyboardShortcut(.upArrow, modifiers: [.command, .option])
                Button("Next Playlist") { workspace.selectAdjacent(1) }.keyboardShortcut(.downArrow, modifiers: [.command, .option])
            }
            CommandMenu("Playback") {
                Button("Play / Pause") { model.perform { try await model.playback.toggle() } }.keyboardShortcut("p", modifiers: [.command])
                Button("Next Song") { model.perform { try await model.playback.next() } }.keyboardShortcut(.rightArrow, modifiers: [.command])
                Button("Previous Song") { model.perform { try await model.playback.previous() } }.keyboardShortcut(.leftArrow, modifiers: [.command])
                Divider()
                Button("Play Playlist") { workspace.playPlaylist(shuffled: false) }.keyboardShortcut(.return, modifiers: [.command])
                Button("Shuffle Playlist") { workspace.playPlaylist(shuffled: true) }.keyboardShortcut(.return, modifiers: [.command, .shift])
                Button("Favorite Current Song") {
                    if let current = model.playback.current { model.perform { try await model.favorite(current) } }
                }.keyboardShortcut("l", modifiers: [.command]).disabled(model.playback.current == nil)
                Divider()
                Button("Volume Up") { model.playback.setVolume(min(100, model.playback.volume + 10)) }
                    .keyboardShortcut(.upArrow, modifiers: [.command]).disabled(!model.playback.isMusicApp)
                Button("Volume Down") { model.playback.setVolume(max(0, model.playback.volume - 10)) }
                    .keyboardShortcut(.downArrow, modifiers: [.command]).disabled(!model.playback.isMusicApp)
                Divider()
                Button("Refresh Library") { model.perform { await model.refresh() } }.keyboardShortcut("r", modifiers: [.command])
            }
            CommandGroup(after: .sidebar) {
                Button(workspace.sidebarCollapsed ? "Show Sidebar" : "Hide Sidebar") {
                    withAnimation(.spring(response: 0.38, dampingFraction: 0.86)) { workspace.toggleSidebar() }
                }.keyboardShortcut("s", modifiers: [.command])
                Button(workspace.pillExpanded ? "Collapse Player" : (workspace.queueSupported ? "Expand Player and Queue" : "Expand Player")) {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) { workspace.pillExpanded.toggle() }
                }.keyboardShortcut("u", modifiers: [.command, .shift])
            }
            CommandGroup(replacing: .help) {
                Button("Keyboard Shortcuts") { workspace.showShortcuts.toggle() }.keyboardShortcut("/", modifiers: [.command])
            }
        }
        Settings {
            SettingsView(model: model, store: themes, updater: updater).modifier(Themed(store: themes))
        }
    }
}
