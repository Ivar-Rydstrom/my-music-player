import SwiftUI
import Combine
#if SWIFT_PACKAGE
import PlayerCore
#endif

/// The window is an Arc-style frame: a theme gradient with the sidebar sitting directly on it and
/// the content as an inset rounded card. The player floats as a pill at the bottom of the card.
struct ContentView: View {
    @Environment(\.playerTheme) private var theme
    @ObservedObject var model: AppModel
    @ObservedObject var workspace: Workspace
    @ObservedObject var palette: PaletteController
    @ObservedObject var themes: ThemeStore
    var updater: AppUpdater
    @Environment(\.openSettings) private var openSettings

    init(model: AppModel, workspace: Workspace, themes: ThemeStore, updater: AppUpdater) {
        self.model = model
        self.workspace = workspace
        self.palette = workspace.palette
        self.themes = themes
        self.updater = updater
    }

    static let sidebarWidth: CGFloat = 244
    private let spring = Animation.spring(response: 0.38, dampingFraction: 0.86)

    var body: some View {
        ZStack(alignment: .topLeading) {
            HStack(spacing: 0) {
                if !workspace.sidebarCollapsed {
                    Sidebar(model: model, player: model.playback, workspace: workspace)
                        .frame(width: Self.sidebarWidth)
                        .transition(.move(edge: .leading).combined(with: .opacity))
                }
                ContentCard(model: model, player: model.playback, workspace: workspace)
                    .padding(.top, workspace.sidebarCollapsed ? 6 : 8)
                    .padding(.bottom, workspace.sidebarCollapsed ? 6 : 8)
                    .padding(.trailing, workspace.sidebarCollapsed ? 6 : 8)
                    .padding(.leading, workspace.sidebarCollapsed ? 6 : 0)
            }
            if workspace.sidebarCollapsed { peekLayer }
        }
        .background { ZStack { theme.frameGradient; WindowDragArea() }.ignoresSafeArea() }
        .ignoresSafeArea()
        .animation(spring, value: workspace.sidebarCollapsed)
        .animation(.spring(response: 0.32, dampingFraction: 0.88), value: workspace.sidebarPeek)
        .background(WindowReader { window in
            workspace.window = window
            Self.hideStandardButtons(window)
            NotificationCenter.default.addObserver(forName: NSWindow.didExitFullScreenNotification, object: window, queue: .main) { note in
                if let window = note.object as? NSWindow { MainActor.assumeIsolated { Self.hideStandardButtons(window) } }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                if window.firstResponder is NSTextView { window.makeFirstResponder(nil) }
            }
            #if DEBUG
            applyDebugWindowSize(window)
            #endif
        })
        .overlay {
            if palette.isOpen {
                CommandPalette(palette: palette, model: model)
                    .transition(.asymmetric(insertion: .opacity.combined(with: .scale(scale: 0.98, anchor: .top)), removal: .opacity))
            }
        }
        .animation(.spring(response: 0.26, dampingFraction: 0.9), value: palette.isOpen)
        .overlay {
            if workspace.showShortcuts {
                ShortcutsOverlay(workspace: workspace, queueSupported: workspace.queueSupported, musicVolume: model.playback.isMusicApp)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.12), value: workspace.showShortcuts)
        .task {
            workspace.model = model
            workspace.openSettingsAction = { openSettings() }
            wirePalette()
            workspace.installKeyMonitor()
            if ProcessInfo.processInfo.arguments.contains("--sample-library") { model.useSamples() }
            #if DEBUG
            applyDebugSelection()
            #endif
            await model.select(model.selectedID)
            if ProcessInfo.processInfo.arguments.contains("--connect-music") {
                await model.connect()
                let report = "Music.app connection: \(model.usesMusicApp ? "connected" : "failed"); playlist count: \(model.usesMusicApp ? model.playlists.count : 0); \(model.error ?? "no error")\n"
                FileHandle.standardOutput.write(Data(report.utf8))
            } else if !ProcessInfo.processInfo.arguments.contains("--sample-library") { await model.restoreConnectionIfNeeded() }
            if ProcessInfo.processInfo.arguments.contains("--show-settings") || ProcessInfo.processInfo.arguments.contains("--connect-music") { openSettings() }
            #if DEBUG
            await applyDebugState()
            #endif
        }
        .task(id: model.tracks.compactMap(\.artwork)) {
            await MusicArtworkLoader.shared.prefetchTracks(model.tracks.compactMap(\.artwork))
        }
        .task(id: model.playlists.compactMap(\.artwork)) {
            await MusicArtworkLoader.shared.prefetchPlaylists(model.playlists.compactMap(\.artwork))
        }
        .task(id: "\(model.isLive)-\(model.usesMusicApp)-\(workspace.resultsQuery ?? "")") {
            guard let query = workspace.resultsQuery else { return }
            await model.search(query, catalog: false)
        }
        .alert("Couldn't complete that action", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("OK") { model.error = nil }
        } message: { Text(model.error ?? "") }
    }

    /// The traffic lights are drawn in the sidebar instead, so they can hide and peek with it.
    static func hideStandardButtons(_ window: NSWindow) {
        for kind in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            window.standardWindowButton(kind)?.isHidden = true
        }
    }

    // MARK: Hover-peek

    /// While collapsed, the left edge is a trigger: touching it slides the sidebar out as a floating panel.
    private var peekLayer: some View {
        ZStack(alignment: .leading) {
            Color.clear.frame(width: 10).frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .onHover { inside in if inside { workspace.sidebarPeek = true } }
            if workspace.sidebarPeek {
                Sidebar(model: model, player: model.playback, workspace: workspace, floating: true)
                    .frame(width: Self.sidebarWidth)
                    .background(theme.frameGradient, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.white.opacity(theme.frameIsDark ? 0.10 : 0.45)))
                    .shadow(color: .black.opacity(theme.frameIsDark ? 0.45 : 0.20), radius: 24, x: 6, y: 8)
                    .padding(.vertical, 6).padding(.leading, 6)
                    .onHover { inside in
                        if !inside {
                            #if DEBUG
                            if ProcessInfo.processInfo.arguments.contains("--sidebar=peek") { return }
                            #endif
                            workspace.sidebarPeek = false
                        }
                    }
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
        }
    }

    // MARK: Palette wiring

    private func wirePalette() {
        palette.perform = { command in perform(command) }
        palette.contextProvider = { [weak model, weak workspace, weak themes] in
            guard let model, let workspace else { return PaletteContext() }
            let player = model.playback
            return PaletteContext(current: player.current, isPlaying: player.isPlaying, favorites: model.favorites,
                                  shuffle: player.shuffle, repeatAll: player.repeatAll,
                                  isMusicApp: player.isMusicApp || workspace.debugMusicAppLayout,
                                  queueSupported: workspace.queueSupported && player.canEditQueue, sleepActive: player.sleepUntil != nil,
                                  sidebarCollapsed: workspace.sidebarCollapsed, hasRecentlyPlayed: !model.recentTracks.isEmpty,
                                  playlists: Workspace.alphabetical(model.playlists),
                                  themes: ThemePreset.all.map { ($0.id, $0.name) }, currentTheme: themes?.preferences.preset ?? "",
                                  selectedID: model.selectedID, selectedTracks: workspace.selectedTracks(),
                                  keys: ShortcutAction.allCases.reduce(into: [:]) { keys, action in keys[action] = workspace.shortcuts.display(action) })
        }
        palette.songProvider = { [weak model] in
            guard let model else { return [] }
            var songs: [LibraryTrack] = model.searchResults
            songs += model.tracks
            for loaded in model.loadedTracks.values { songs += loaded }
            for playlist in model.playlists { songs += playlist.tracks }
            songs += model.recentTracks
            return songs
        }
        palette.contentsProvider = { [weak model] id in
            guard let model, let playlist = model.playlists.first(where: { $0.id == id }) else { return [] }
            return Set((model.loadedTracks[id] ?? playlist.tracks).map(\.id))
        }
    }

    private func perform(_ command: PaletteCommand) {
        let player = model.playback
        switch command {
        case .togglePlayback: model.perform { try await player.toggle() }
        case .next: model.perform { try await player.next() }
        case .previous: model.perform { try await player.previous() }
        case .seekToStart: player.seek(0)
        case .setShuffle(let on): player.shuffle = on; player.applyModes()
        case .setRepeat(let on): player.repeatAll = on; player.applyModes()
        case .volume(let up): player.setVolume(up ? min(100, player.volume + 10) : max(0, player.volume - 10))
        case .favoriteCurrent: if let current = player.current { model.perform { try await model.favorite(current) } }
        case .revealCurrent: if let current = player.current { workspace.reveal(current) }
        case .sleep(let minutes):
            player.setSleepTimer(minutes: minutes)
            model.notice = minutes.map { "Pausing playback in \($0) minutes." } ?? "Sleep timer cancelled."
        case .toggleSidebar: withAnimation(spring) { workspace.toggleSidebar() }
        case .expandPlayer: withAnimation(FloatingPlayer.morph) { workspace.pillExpanded = true }
        case .refresh: model.perform { await model.refresh() }
        case .clearRecent: model.recentTracks = []
        case .checkForUpdates: Task { await updater.check(userInitiated: true) }
        case .showShortcuts: workspace.showShortcuts = true
        case .filterPlaylist: workspace.revealFilter()
        case .showResults(let query): workspace.showResults(for: query)
        case .settings(let tab):
            if let tab { UserDefaults.standard.set(tab, forKey: "settings.tab") }
            openSettings()
        case .theme(let id): themes.preferences.preset = id
        case .open(let id): workspace.select(id)
        case .playPlaylist(let id, let shuffled):
            workspace.select(id)
            Task { await model.select(id); workspace.playPlaylist(shuffled: shuffled) }
        case .play(let track):
            if let row = workspace.rows().first(where: { $0.track.id == track.id }) { workspace.play(row: row) }
            else { model.perform { try await player.play([track]) } }
        case .playNext(let tracks):
            model.perform { try await player.enqueue(tracks, next: true); model.notice = tracks.count == 1 ? "\(tracks[0].title) plays next." : "\(tracks.count) songs play next." }
        case .addToQueue(let tracks):
            model.perform { try await player.enqueue(tracks, next: false); model.notice = tracks.count == 1 ? "Added \(tracks[0].title) to the queue." : "Added \(tracks.count) songs to the queue." }
        case .favorite(let track): model.perform { try await model.favorite(track) }
        case .reveal(let track): workspace.reveal(track)
        case .add(let tracks, let id):
            if let playlist = model.playlists.first(where: { $0.id == id }) {
                model.perform {
                    try await model.add(tracks, to: playlist)
                    model.notice = tracks.count == 1 ? "Added \(tracks[0].title) to \(playlist.name)." : "Added \(tracks.count) songs to \(playlist.name)."
                }
            }
        }
    }

    #if DEBUG
    /// Values use `--name=value`: a bare value argument is treated by AppKit as a file to open,
    /// which suppresses the main window.
    private func argument(_ name: String) -> String? {
        ProcessInfo.processInfo.arguments.first { $0.hasPrefix(name + "=") }.map { String($0.dropFirst(name.count + 1)) }
    }
    private func applyDebugWindowSize(_ window: NSWindow) {
        guard let size = argument("--window-size")?.split(separator: "x").compactMap({ Double($0) }), size.count == 2 else { return }
        var frame = window.frame
        frame.size = CGSize(width: size[0], height: size[1])
        window.setFrame(frame, display: true)
        window.center()
    }
    private func applyDebugSelection() {
        if let id = argument("--select") { model.selectedID = id }
        workspace.debugMusicAppLayout = ProcessInfo.processInfo.arguments.contains("--layout-music-app")
        switch argument("--sidebar") {
        case "collapsed": workspace.sidebarCollapsed = true
        case "peek": workspace.sidebarCollapsed = true; workspace.sidebarPeek = true
        case "open": workspace.sidebarCollapsed = false
        default: break
        }
    }
    /// Screenshot helpers: --demo-playing, --select-rows=2,3,5, --hover-row=N, --filter=text, --results=text,
    /// --palette=query (+ for spaces), --palette-row=N, --palette-actions, --palette-step=add, --palette-song=N,
    /// --pill=expanded, --show-shortcuts, --history.
    private func applyDebugState() async {
        let args = ProcessInfo.processInfo.arguments
        if args.contains("--history") {
            for id in ["demo-drive", "demo-evening"] { workspace.select(id); try? await Task.sleep(for: .milliseconds(60)) }
            workspace.goBack(); workspace.goBack()
            try? await Task.sleep(for: .milliseconds(60))
        }
        if args.contains("--demo-playing") {
            workspace.playingListID = model.selectedID
            try? await model.playback.play(model.tracks, at: 1)
            model.playback.seek(83)
        }
        if let query = argument("--results") { workspace.showResults(for: query); try? await Task.sleep(for: .milliseconds(500)) }
        if let filter = argument("--filter") { workspace.revealFilter(); workspace.filterText = filter }
        if let rows = argument("--select-rows") {
            let numbers = Set(rows.split(separator: ",").compactMap { Int($0) })
            workspace.selection = Set(workspace.rows().filter { numbers.contains($0.number) }.map(\.id))
        }
        if let hover = argument("--hover-row") { workspace.debugHoverRow = Int(hover) }
        if argument("--pill") == "expanded" { workspace.pillExpanded = true }
        if let number = argument("--palette-song").flatMap(Int.init), let row = workspace.rows().first(where: { $0.number == number }) {
            // Same path as ⌘K with one song selected in the list.
            workspace.selection = [row.id]
            try? await Task.sleep(for: .milliseconds(300))
            workspace.showActionsForSelection()
        } else if argument("--palette-step") == "add" {
            try? await Task.sleep(for: .milliseconds(300))
            let selected = workspace.selectedTracks()
            if !selected.isEmpty { workspace.addToPlaylist(selected) }
            else if let current = model.playback.current { workspace.addToPlaylist([current]) }
        } else if let query = argument("--palette") {
            try? await Task.sleep(for: .milliseconds(300))
            workspace.openPalette(query: query.replacingOccurrences(of: "+", with: " "))
            try? await Task.sleep(for: .milliseconds(600))
            if let row = argument("--palette-row").flatMap(Int.init) { palette.move(row) }
            if args.contains("--palette-actions") {
                try? await Task.sleep(for: .milliseconds(200))
                palette.showActions()
            }
        }
        if args.contains("--show-shortcuts") { workspace.showShortcuts = true }
    }
    #endif
}

// MARK: - Content card

/// The inset rounded card holding the list. The playlist's cover washes the header only.
struct ContentCard: View {
    @ObservedObject private var shortcuts = ShortcutStore.shared
    @Environment(\.playerTheme) private var theme
    @ObservedObject var model: AppModel
    @ObservedObject var player: PlaybackController
    @ObservedObject var workspace: Workspace

    var body: some View {
        let rows = workspace.rows()
        VStack(alignment: .leading, spacing: 0) {
            Group {
                if workspace.isShowingResults { ResultsHeader(model: model, workspace: workspace) }
                else { PlaylistHeader(model: model, workspace: workspace, visible: rows.count) }
            }
            TrackListHeader(workspace: workspace).padding(.horizontal, TrackMetrics.horizontalInset)
            ZStack {
                if !workspace.isShowingResults && model.loadingPlaylistID == model.selectedID {
                    ProgressView("Loading songs…").frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if rows.isEmpty {
                    emptyState.frame(maxWidth: .infinity, maxHeight: .infinity).padding(.bottom, 80)
                } else {
                    TrackList(model: model, workspace: workspace, rows: rows).id(workspace.listKey)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(alignment: .top) { HeaderWash(model: model, workspace: workspace) }
        .background(theme.background)
        .overlay(alignment: .bottom) { notice }
        .overlay { FloatingPlayer(model: model, player: player, workspace: workspace) }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(theme.text.opacity(theme.isDark ? 0.07 : 0.05)))
        .shadow(color: .black.opacity(theme.isDark ? 0.30 : 0.10), radius: 8, y: 2)
        .shadow(color: .black.opacity(theme.isDark ? 0.18 : 0.05), radius: 1, y: 0.5)
    }

    @ViewBuilder private var notice: some View {
        if let notice = model.notice {
            HStack(spacing: 10) {
                Text(notice).font(.system(size: 13))
                Button { model.notice = nil } label: { Image(systemName: "xmark") }.buttonStyle(.plain).foregroundStyle(theme.muted).accessibilityLabel("Dismiss")
            }
            .padding(.horizontal, 14).padding(.vertical, 9)
            .background(.regularMaterial, in: Capsule())
            .shadow(color: .black.opacity(0.12), radius: 10, y: 3)
            .padding(.bottom, 96)
            .task(id: notice) { try? await Task.sleep(for: .seconds(6)); if model.notice == notice { model.notice = nil } }
        }
    }

    private var listTitle: String { Workspace.title(for: model.selectedID, in: model) }

    @ViewBuilder private var emptyState: some View {
        if workspace.isShowingResults {
            if model.searching { ProgressView() }
            else if (workspace.resultsQuery ?? "").trimmingCharacters(in: .whitespaces).isEmpty {
                ContentUnavailableView("Search your library", systemImage: "magnifyingglass",
                                       description: Text("Type a song, artist or album. ↓ moves into the results, Return plays."))
            } else { ContentUnavailableView.search(text: workspace.resultsQuery ?? "") }
        } else if !workspace.filterText.isEmpty {
            ContentUnavailableView {
                Label("Nothing in \(listTitle) matches", systemImage: "line.3.horizontal.decrease")
            } description: {
                Text(shortcuts.display(.searchLibrary).map { "Search your whole library with \($0)." } ?? "Search your whole library instead.")
            } actions: {
                Button("Search all music for “\(workspace.filterText)”") { workspace.searchLibrary(workspace.filterText) }
            }
        } else {
            ContentUnavailableView(model.selectedID == "recent" ? "Nothing played yet" : "No songs here yet", systemImage: "music.note",
                description: Text(shortcuts.display(.searchLibrary).map { "Pick a playlist on the left, or press \($0) to search your library." }
                                  ?? "Pick a playlist on the left, or use Edit › Search Library."))
        }
    }
}

/// D's soft cover wash, kept to the header: the playlist's artwork, heavily blurred, fading into the card.
struct HeaderWash: View {
    @Environment(\.playerTheme) private var theme
    @ObservedObject var model: AppModel
    @ObservedObject var workspace: Workspace
    var body: some View {
        GeometryReader { proxy in
            Group {
                if workspace.isShowingResults || model.selectedID == "recent" || model.selectedID == "favorites" {
                    LinearGradient(colors: [theme.highlight.color.opacity(theme.isDark ? 0.30 : 0.26), theme.glow.color.opacity(theme.isDark ? 0.18 : 0.20)],
                                   startPoint: .topLeading, endPoint: .trailing)
                } else {
                    Artwork(url: model.playlist?.artwork, seed: model.playlist?.name ?? "Still", size: proxy.size.width)
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .blur(radius: 56).saturation(1.25).opacity(theme.isDark ? 0.55 : 0.42)
                }
            }
        }
        .frame(height: 170).clipped()
        .mask(LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black.opacity(0.75), location: 0.45), .init(color: .clear, location: 1)],
                             startPoint: .top, endPoint: .bottom))
        .allowsHitTesting(false)
        .animation(.easeInOut(duration: 0.35), value: model.selectedID)
    }
}

struct PlaylistHeader: View {
    @ObservedObject private var shortcuts = ShortcutStore.shared
    @Environment(\.playerTheme) private var theme
    @ObservedObject var model: AppModel
    @ObservedObject var workspace: Workspace
    var visible: Int
    @FocusState private var filterFocused: Bool

    private var id: String? { model.selectedID }
    private var isLibrary: Bool { id == "recent" || id == "favorites" }

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            cover
            VStack(alignment: .leading, spacing: 5) {
                Text(Workspace.title(for: id, in: model)).font(.system(size: 24, weight: .bold, design: .rounded)).lineLimit(1)
                Text(detail).font(.system(size: 12.5)).foregroundStyle(theme.muted).lineLimit(1).monospacedDigit()
            }
            .layoutPriority(1)
            Spacer(minLength: 12)
            if workspace.filterVisible { filterField.transition(.move(edge: .trailing).combined(with: .opacity)) }
            else {
                HeaderIconButton(symbol: "line.3.horizontal.decrease", help: shortcuts.hint("Filter this playlist", .filter)) { workspace.revealFilter() }
            }
            if id == "recent", !model.recentTracks.isEmpty {
                Button("Clear") { model.recentTracks = [] }.buttonStyle(SoftCapsuleStyle(prominent: false)).help("Clear recently played")
            }
            Button { workspace.playPlaylist(shuffled: true) } label: { Label("Shuffle", systemImage: "shuffle") }
                .buttonStyle(SoftCapsuleStyle(prominent: false)).help(shortcuts.hint("Shuffle", .shufflePlaylist)).disabled(model.tracks.isEmpty)
            Button { workspace.playPlaylist(shuffled: false) } label: { Label("Play", systemImage: "play.fill") }
                .buttonStyle(SoftCapsuleStyle(prominent: true)).help(shortcuts.hint("Play", .playPlaylist)).disabled(model.tracks.isEmpty)
        }
        .padding(.leading, 22).padding(.trailing, 20).padding(.top, 22).padding(.bottom, 14)
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: workspace.filterVisible)
        .onChange(of: workspace.filterFocusRequest) { _, _ in
            DispatchQueue.main.async { filterFocused = true }
        }
        .onChange(of: filterFocused) { _, focused in workspace.filterFocused = focused }
    }

    @ViewBuilder private var cover: some View {
        if isLibrary {
            Image(systemName: id == "recent" ? "clock.arrow.circlepath" : "star.fill")
                .font(.system(size: 24, weight: .semibold)).foregroundStyle(theme.buttonInk)
                .frame(width: 64, height: 64)
                .background(LinearGradient(colors: [theme.accent, theme.accent.opacity(0.72)], startPoint: .topLeading, endPoint: .bottomTrailing),
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .shadow(color: .black.opacity(0.16), radius: 8, y: 4)
        } else {
            Artwork(url: model.playlist?.artwork, seed: model.playlist?.name ?? "Still", size: 64, cornerRadius: 10)
                .shadow(color: .black.opacity(0.18), radius: 8, y: 4)
        }
    }

    private var detail: String {
        let total = model.tracks.count
        if model.loadingPlaylistID == id { return "Loading…" }
        if !workspace.filterText.isEmpty { return "\(visible) of \(total) songs" }
        let minutes = Int(model.tracks.reduce(0) { $0 + $1.duration } / 60)
        let duration = minutes >= 60 ? "\(minutes / 60) hr \(minutes % 60) min" : "\(minutes) min"
        var parts = ["\(total) song\(total == 1 ? "" : "s")", duration]
        if id == "favorites" && model.isLive && !model.usesMusicApp { parts.append("This session only") }
        else if let subtitle = model.playlist?.subtitle, !subtitle.isEmpty { parts.append(subtitle) }
        return parts.joined(separator: " · ")
    }

    private var filterField: some View {
        HStack(spacing: 6) {
            Image(systemName: "line.3.horizontal.decrease").font(.system(size: 11, weight: .semibold)).foregroundStyle(theme.muted)
            TextField("Filter", text: Binding(get: { workspace.filterText }, set: { workspace.filterText = $0 }))
                .textFieldStyle(.plain).font(.system(size: 12.5)).focused($filterFocused)
                .accessibilityLabel("Filter this playlist")
            if !workspace.filterText.isEmpty {
                Button { workspace.filterText = "" } label: { Image(systemName: "xmark.circle.fill").font(.system(size: 11)) }
                    .buttonStyle(.plain).foregroundStyle(theme.muted).accessibilityLabel("Clear filter")
            } else {
                Button { workspace.escapeFilter() } label: { Text("esc").font(.system(size: 10, weight: .medium, design: .rounded)) }
                    .buttonStyle(.plain).foregroundStyle(theme.muted).help("Close filter (Esc)")
            }
        }
        .padding(.horizontal, 10).frame(width: 190, height: 30)
        .onAppear { DispatchQueue.main.async { filterFocused = true } }
        .background(theme.text.opacity(theme.isDark ? 0.08 : 0.055), in: Capsule())
        .overlay(Capsule().strokeBorder(filterFocused ? theme.accent.opacity(0.55) : .clear, lineWidth: 1.2))
    }
}

struct ResultsHeader: View {
    @Environment(\.playerTheme) private var theme
    @ObservedObject var model: AppModel
    @ObservedObject var workspace: Workspace
    @FocusState private var focused: Bool
    var body: some View {
        let query = workspace.resultsQuery ?? ""
        HStack(alignment: .center, spacing: 16) {
            Image(systemName: "magnifyingglass").font(.system(size: 22, weight: .semibold)).foregroundStyle(theme.buttonInk)
                .frame(width: 64, height: 64)
                .background(theme.accent, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 5) {
                TextField("Search your library", text: Binding(get: { workspace.resultsQuery ?? "" }, set: { workspace.resultsQuery = $0 }))
                    .textFieldStyle(.plain).font(.system(size: 24, weight: .bold, design: .rounded))
                    .focused($focused).accessibilityLabel("Search your library")
                Text(query.isEmpty ? "Songs, artists and albums in your \(model.usesMusicApp ? "Music library" : "library")"
                     : model.searching ? "Searching…" : "\(model.searchResults.count) songs in your \(model.usesMusicApp ? "Music library" : "library")")
                    .font(.system(size: 12.5)).foregroundStyle(theme.muted)
            }
            Spacer()
            Button { workspace.resultsQuery = nil } label: { Label("Done", systemImage: "arrow.uturn.backward") }
                .buttonStyle(SoftCapsuleStyle(prominent: false)).help("Back to \(Workspace.title(for: model.selectedID, in: model)) (Esc)")
        }
        .padding(.leading, 22).padding(.trailing, 20).padding(.top, 22).padding(.bottom, 14)
        .onAppear { if workspace.searchFocusRequest > 0 && query.isEmpty { DispatchQueue.main.async { focused = true } } }
        .onChange(of: workspace.searchFocusRequest) { _, _ in DispatchQueue.main.async { focused = true } }
        .onChange(of: focused) { _, value in workspace.searchFocused = value }
        .onDisappear { workspace.searchFocused = false }
    }
}

struct HeaderIconButton: View {
    @Environment(\.playerTheme) private var theme
    var symbol: String
    var help: String
    var action: () -> Void
    @State private var hovering = false
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 13, weight: .semibold))
                .foregroundStyle(hovering ? theme.text : theme.muted)
                .frame(width: 30, height: 30)
                .background(theme.text.opacity(hovering ? 0.08 : 0), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain).help(help).accessibilityLabel(help)
        .onHover { hovering = $0 }
    }
}

/// Soft capsule buttons drawn from the theme, so they keep their color when the window is inactive.
struct SoftCapsuleStyle: ButtonStyle {
    @Environment(\.playerTheme) private var theme
    @Environment(\.isEnabled) private var enabled
    var prominent: Bool
    var compact = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12.5, weight: .semibold))
            .labelStyle(.titleAndIcon)
            .lineLimit(1).fixedSize()
            .foregroundStyle(prominent ? theme.buttonInk : theme.text.opacity(0.85))
            .padding(.horizontal, compact ? 12 : 15).frame(height: compact ? 28 : 30)
            .background(Capsule().fill(prominent ? AnyShapeStyle(theme.accent) : AnyShapeStyle(theme.text.opacity(theme.isDark ? 0.09 : 0.06))))
            .opacity(enabled ? (configuration.isPressed ? 0.78 : 1) : 0.45)
            .contentShape(Capsule())
    }
}

// MARK: - Artwork

/// Playlist and song artwork. Without a real image it draws a calm generated cover from `seed`.
struct Artwork: View {
    @Environment(\.playerTheme) private var theme
    var url: URL?
    var seed: String
    var size: CGFloat
    var cornerRadius: CGFloat = 8
    @State private var localImage: NSImage?
    private var hash: Int { seed.utf8.reduce(7) { ($0 &* 31 &+ Int($1)) & 0xFFFF } }
    private var hue: Double { Double(hash % 100) / 100 }
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(hue: hue, saturation: 0.30, brightness: 0.52),
                                    Color(hue: (hue + 0.07).truncatingRemainder(dividingBy: 1), saturation: 0.32, brightness: 0.28)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            if size > 15 {
                GeometryReader { proxy in
                    let side = proxy.size.width
                    ZStack {
                        ForEach(0..<7) { index in
                            Circle().stroke(.white.opacity(0.13), lineWidth: max(1, side / 110))
                                .frame(width: side * (0.3 + Double(index) * 0.2))
                        }
                    }.position(x: side * (0.55 + Double(hash % 7) * 0.05), y: proxy.size.height * (0.55 + Double(hash % 5) * 0.06))
                }.clipped()
            }
            if url?.scheme == "music-artwork" {
                if let localImage {
                    Image(nsImage: localImage).resizable().scaledToFill()
                }
            } else if let url {
                AsyncImage(url: url) { image in image.resizable().scaledToFill() } placeholder: { Color.clear }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .accessibilityHidden(true)
        .task(id: url) {
            localImage = nil
            guard let url, url.scheme == "music-artwork" else { return }
            let data = await MusicArtworkLoader.shared.thumbnail(for: url, pixels: size > 48 ? 320 : 96)
            guard !Task.isCancelled else { return }
            localImage = data.flatMap { NSImage(data: $0) }
        }
    }
}
