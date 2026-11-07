import SwiftUI

@main
struct HummeryApp: App {
    @StateObject private var model = AppModel()
    @StateObject private var themes = ThemeStore()
    @StateObject private var updater = AppUpdater()
    @StateObject private var workspace = Workspace()
    @StateObject private var shortcuts = ShortcutStore.shared
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
            // Every key below is the user's (Settings › Keyboard). The window's key monitor runs the
            // command; the menu shows the key, or none when it was removed.
            CommandGroup(replacing: .newItem) {}
            CommandGroup(replacing: .saveItem) {}
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") { Task { await updater.check(userInitiated: true) } }.disabled(updater.isBusy)
            }
            CommandGroup(replacing: .appSettings) { item("Settings…", .settings) }
            CommandGroup(replacing: .textEditing) {
                item("Command Palette…", .palette)
                item("Actions for Selected Song…", .songActions)
                item("Filter This Playlist", .filter)
                item("Search Library…", .searchLibrary)
            }
            CommandMenu("Go") {
                item("Back", .back).disabled(!workspace.canGoBack)
                item("Forward", .forward).disabled(!workspace.canGoForward)
                item("Reveal Current Song", .revealCurrent).disabled(model.playback.current == nil)
                Divider()
                Button("Recently Played") { workspace.select("recent") }
                Button("Favorites") { workspace.select("favorites") }
                Divider()
                item("Previous Playlist", .previousList)
                item("Next Playlist", .nextList)
            }
            CommandMenu("Playback") {
                item("Play / Pause", .playPause)
                item("Next Song", .nextSong)
                item("Previous Song", .previousSong)
                Divider()
                item("Play Playlist", .playPlaylist)
                item("Shuffle Playlist", .shufflePlaylist)
                item("Favorite Current Song", .favoriteCurrent).disabled(model.playback.current == nil)
                if let current = model.playback.current {
                    AddToPlaylistMenu(model: model, tracks: [current], title: "Add Current Song to Playlist")
                } else {
                    Button("Add Current Song to Playlist") {}.disabled(true)
                }
                Divider()
                item("Volume Up", .volumeUp).disabled(!model.playback.isMusicApp)
                item("Volume Down", .volumeDown).disabled(!model.playback.isMusicApp)
                Divider()
                item("Refresh Library", .refresh)
            }
            CommandGroup(after: .sidebar) {
                item(workspace.sidebarCollapsed ? "Show Sidebar" : "Hide Sidebar", .toggleSidebar)
                item(workspace.pillExpanded ? "Collapse Player" : (workspace.queueSupported ? "Expand Player and Queue" : "Expand Player"), .expandPlayer)
            }
            CommandGroup(replacing: .help) { item("Keyboard Shortcuts", .shortcutsHelp) }
        }
        Settings {
            SettingsView(model: model, store: themes, updater: updater).modifier(Themed(store: themes))
        }
    }

    /// A menu item for a command, showing its current key.
    private func item(_ title: String, _ action: ShortcutAction) -> some View {
        Button(title) { workspace.run(action) }.shortcut(shortcuts.binding(action))
    }
}
