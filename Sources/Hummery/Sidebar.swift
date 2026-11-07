import SwiftUI
#if SWIFT_PACKAGE
import PlayerCore
#endif

/// Arc's sidebar, for music: traffic lights and toggle on top, an address bar showing where you are
/// (click it for the palette), Library and Playlists sections, and a quiet icon row at the bottom.
/// It sits straight on the window frame, with no panel colour of its own.
struct Sidebar: View {
    @Environment(\.playerTheme) private var theme
    @Environment(\.openSettings) private var openSettings
    @ObservedObject private var shortcuts = ShortcutStore.shared
    @ObservedObject var model: AppModel
    @ObservedObject var player: PlaybackController
    @ObservedObject var workspace: Workspace
    /// True inside the hover-peek panel, which floats over the content.
    var floating = false
    @State private var playlistsHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            topRow
            AddressBar(workspace: workspace).padding(.horizontal, 10).padding(.top, 4).padding(.bottom, 14)
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    sectionLabel("Library")
                    row("Recently played", id: "recent", icon: "clock.arrow.circlepath")
                    row("Favorites", id: "favorites", icon: "star")
                    Rectangle().fill(theme.frameInk.opacity(0.10)).frame(height: 1)
                        .padding(.horizontal, 14).padding(.vertical, 10)
                    playlistsHeader
                    ForEach(Workspace.alphabetical(model.playlists)) { playlist in
                        row(playlist.name, id: playlist.id, icon: nil, artwork: playlist.artwork)
                            .contextMenu {
                                Button("Open") { workspace.select(playlist.id) }
                                Button("Play") { Task { await model.select(playlist.id); workspace.playPlaylist(shuffled: false) } }
                                Button("Shuffle") { Task { await model.select(playlist.id); workspace.playPlaylist(shuffled: true) } }
                            }
                    }
                }
                .padding(.horizontal, 8).padding(.bottom, 12)
            }
            .scrollIndicators(.never)
            bottomBar
        }
        .foregroundStyle(theme.frameInk)
    }

    // MARK: Pieces

    private var topRow: some View {
        HStack(spacing: 2) {
            TrafficLights(window: workspace.window).padding(.leading, 8).padding(.trailing, 12)
            ChromeButton(symbol: "sidebar.left", help: shortcuts.hint(floating ? "Keep sidebar open" : "Hide sidebar", .toggleSidebar), size: 13.5) {
                withAnimation(.spring(response: 0.38, dampingFraction: 0.86)) { workspace.toggleSidebar() }
            }
            Spacer(minLength: 0)
            ChromeButton(symbol: "arrow.left", help: shortcuts.hint("Back", .back), size: 13) { workspace.goBack() }.disabled(!workspace.canGoBack)
            ChromeButton(symbol: "arrow.right", help: shortcuts.hint("Forward", .forward), size: 13) { workspace.goForward() }.disabled(!workspace.canGoForward)
        }
        .padding(.horizontal, 6)
        .frame(height: 44)
        .background(WindowDragArea())
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title).font(.system(size: 11.5, weight: .semibold)).foregroundStyle(theme.frameMuted)
            .padding(.horizontal, 10).frame(height: 24, alignment: .bottom).padding(.bottom, 4)
    }

    /// Like Arc's "Tidy / Clear": a quiet action that appears when you hover the section.
    private var playlistsHeader: some View {
        HStack {
            Text("Playlists").font(.system(size: 11.5, weight: .semibold)).foregroundStyle(theme.frameMuted)
            Spacer()
            Button { model.perform { await model.refresh() } } label: {
                HStack(spacing: 4) { Image(systemName: "arrow.clockwise").font(.system(size: 10, weight: .semibold)); Text("Refresh") }
                    .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.plain).foregroundStyle(theme.frameMuted)
            .opacity(playlistsHovered ? 1 : 0).help(shortcuts.hint("Refresh library", .refresh)).accessibilityLabel("Refresh library")
        }
        .padding(.horizontal, 10).frame(height: 24).padding(.bottom, 4)
        .contentShape(Rectangle())
        .onHover { playlistsHovered = $0 }
    }

    private func row(_ title: String, id: String, icon: String?, artwork: URL? = nil) -> some View {
        SidebarRow(title: title, icon: icon, artwork: artwork,
                   selected: model.selectedID == id && !workspace.isShowingResults,
                   playing: isPlaying(id), isPlaying: player.isPlaying) {
            workspace.select(id)
            if floating { withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) { workspace.sidebarPeek = false } }
        }
    }

    /// Only the playing list gets a mark; nothing else is promoted.
    private func isPlaying(_ id: String) -> Bool {
        guard let current = player.current else { return false }
        // The list the app started playback from; otherwise the playlist Music reports.
        if let context = player.contextID { return context == id }
        return current.sourcePlaylistID == id
    }

    private var bottomBar: some View {
        HStack(spacing: 2) {
            HStack(spacing: 7) {
                Circle().fill(connected ? Color.green.opacity(0.85) : Color.orange).frame(width: 7, height: 7)
                    .shadow(color: (connected ? Color.green : .orange).opacity(0.5), radius: 3)
                Text(statusText).font(.system(size: 11.5, weight: .medium)).foregroundStyle(theme.frameMuted).lineLimit(1)
            }
            .padding(.leading, 8)
            .help(model.isLive ? model.connectionStatus : "Sample library: simulated playback, no audio")
            Spacer(minLength: 4)
            ChromeButton(symbol: "arrow.clockwise", help: shortcuts.hint("Refresh library", .refresh), size: 12.5) { model.perform { await model.refresh() } }
            ChromeButton(symbol: "keyboard", help: shortcuts.hint("Keyboard shortcuts", .shortcutsHelp), size: 12.5) { workspace.showShortcuts = true }
            ChromeButton(symbol: "gearshape", help: shortcuts.hint("Settings", .settings), size: 13) { openSettings() }
        }
        .padding(.horizontal, 8).frame(height: 40).padding(.bottom, 4)
    }

    private var connected: Bool { model.isLive || workspace.debugMusicAppLayout }

    private var statusText: String {
        if model.usesMusicApp || workspace.debugMusicAppLayout { return "Music.app" }
        return model.isLive ? "Apple Music" : "Sample · no audio"
    }
}

struct AddressBar: View {
    @Environment(\.playerTheme) private var theme
    @ObservedObject var workspace: Workspace
    @State private var hovering = false
    @ObservedObject private var shortcuts = ShortcutStore.shared
    var body: some View {
        let key = shortcuts.display(.palette)
        Button { workspace.openPalette() } label: {
            HStack(spacing: 8) {
                Text(workspace.contextTitle).font(.system(size: 13, weight: .medium)).lineLimit(1)
                    .foregroundStyle(theme.frameInk.opacity(0.85))
                Spacer(minLength: 4)
                if hovering, let key {
                    Text(key).font(.system(size: 11, weight: .medium, design: .rounded)).foregroundStyle(theme.frameMuted)
                        .transition(.opacity)
                }
            }
            .padding(.horizontal, 12).frame(height: 36)
            .background(theme.addressFill.opacity(hovering ? 1.4 : 1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { inside in withAnimation(.easeOut(duration: 0.12)) { hovering = inside } }
        .help(key.map { "Search or run a command (\($0))" } ?? "Search or run a command")
        .accessibilityLabel("\(workspace.contextTitle). Open command palette")
    }
}

struct SidebarRow: View {
    @Environment(\.playerTheme) private var theme
    var title: String
    var icon: String?
    var artwork: URL?
    var selected: Bool
    var playing: Bool
    var isPlaying: Bool
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if let icon {
                    Image(systemName: icon).font(.system(size: 13, weight: .medium)).frame(width: 18)
                        .foregroundStyle(selected ? theme.frameInk : theme.frameInk.opacity(0.75))
                } else {
                    Artwork(url: artwork, seed: title, size: 18, cornerRadius: 4.5)
                }
                Text(title).font(.system(size: 13, weight: selected ? .semibold : .medium)).lineLimit(1)
                    .foregroundStyle(theme.frameInk.opacity(selected ? 1 : 0.88))
                Spacer(minLength: 4)
                if playing {
                    Image(systemName: "waveform").font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(theme.frameInk.opacity(0.75))
                        .symbolEffect(.variableColor.iterative, options: .repeating, isActive: isPlaying)
                        .accessibilityLabel("Playing")
                }
            }
            .padding(.horizontal, 10).frame(height: 34)
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: 9, style: .continuous).fill(theme.sidebarSelection)
                        .shadow(color: .black.opacity(theme.frameIsDark ? 0.18 : 0.08), radius: 1.5, y: 1)
                } else if hovering {
                    RoundedRectangle(cornerRadius: 9, style: .continuous).fill(theme.sidebarHover)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
