import SwiftUI
import Combine
#if SWIFT_PACKAGE
import PlayerCore
#endif

struct ContentView: View {
    @Environment(\.playerTheme) private var theme
    @ObservedObject var model: AppModel
    @ObservedObject var workspace: Workspace
    @Environment(\.openSettings) private var openSettings
    @FocusState private var commandFocused: Bool
    @State private var rowFrame: CGRect?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Sidebar(model: model, workspace: workspace).frame(width: 224)
                Divider()
                mainContent.frame(maxWidth: .infinity, maxHeight: .infinity)
                if workspace.queueVisible {
                    Divider()
                    QueueColumn(player: model.playback, workspace: workspace).frame(width: 248)
                }
            }
            .ignoresSafeArea(.container, edges: .top)
            Divider()
            PlayerBar(model: model, player: model.playback, workspace: workspace)
        }
        .background(theme.background)
        .background(WindowReader { window in
            workspace.window = window
            // AppKit focuses the first text field on launch, which would swallow Space. Start with
            // nothing focused; type-to-find still routes letters into the command bar.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                if window.firstResponder is NSTextView { window.makeFirstResponder(nil) }
            }
            #if DEBUG
            applyDebugWindowSize(window)
            #endif
        })
        .overlay {
            if workspace.showShortcuts {
                ShortcutsOverlay(workspace: workspace, queueSupported: workspace.queueSupported, musicVolume: model.playback.isMusicApp)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.12), value: workspace.showShortcuts)
        .task {
            workspace.model = model
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
        .task(id: "\(model.isLive)-\(model.usesMusicApp)-\(workspace.scope.rawValue)-\(workspace.libraryQuery)") {
            guard workspace.isSearching else { return }
            workspace.selections["search"] = []
            await model.search(workspace.libraryQuery, catalog: workspace.scope == .catalog && !model.usesMusicApp)
        }
        .onChange(of: model.usesMusicApp) { _, musicApp in
            if musicApp && workspace.scope == .catalog { workspace.scope = .library }
        }
        .onChange(of: workspace.commandFocusRequest) { _, _ in
            commandFocused = true
            workspace.placeCaretAtEndIfNeeded()
        }
        .onChange(of: workspace.commandBlurRequest) { _, _ in commandFocused = false }
        .onChange(of: commandFocused) { _, focused in workspace.commandFocused = focused }
        .alert("Couldn't complete that action", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("OK") { model.error = nil }
        } message: { Text(model.error ?? "") }
        .overlay(alignment: .bottom) {
            if let notice = model.notice {
                HStack(spacing: 10) {
                    Text(notice).font(.system(size: 13))
                    Button { model.notice = nil } label: { Image(systemName: "xmark") }.buttonStyle(.plain).foregroundStyle(theme.muted).accessibilityLabel("Dismiss")
                }
                .padding(.horizontal, 14).padding(.vertical, 9)
                .background(.regularMaterial, in: Capsule())
                .padding(.bottom, 64)
                .task(id: notice) { try? await Task.sleep(for: .seconds(6)); if model.notice == notice { model.notice = nil } }
            }
        }
    }

    private var listTitle: String {
        model.selectedID == "recent" ? "Recently played" : model.selectedID == "favorites" ? "Favorites" : model.playlist?.name ?? "Your music"
    }

    private var mainContent: some View {
        let rows = workspace.rows()
        return VStack(alignment: .leading, spacing: 0) {
            CommandBar(model: model, workspace: workspace, focus: $commandFocused)
                .padding(.horizontal, 16).padding(.top, 8)
            Group {
                if workspace.isSearching { SearchHeader(model: model, workspace: workspace) }
                else { titleRow(visible: rows.count) }
            }
            .padding(.horizontal, 18).frame(height: 46)
            TrackListHeader(workspace: workspace, rowFrame: rowFrame)
            Divider().padding(.horizontal, 10)
            ZStack(alignment: .bottom) {
                if !workspace.isSearching && model.loadingPlaylistID == model.selectedID {
                    ProgressView("Loading songs…").frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if rows.isEmpty {
                    emptyState.frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    TrackList(model: model, workspace: workspace, rows: rows).id(workspace.listKey)
                }
                if workspace.selection.count > 1 {
                    SelectionBar(model: model, workspace: workspace).padding(.bottom, 14)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.easeOut(duration: 0.15), value: workspace.selection.count > 1)
        }
        .onPreferenceChange(RowFrameKey.self) { frame in if let frame, frame != rowFrame { rowFrame = frame } }
    }

    private func titleRow(visible: Int) -> some View {
        let total = model.tracks.count
        let minutes = Int(model.tracks.reduce(0) { $0 + $1.duration } / 60)
        let filtering = !(workspace.filters[workspace.playlistKey] ?? "").isEmpty
        return HStack(spacing: 10) {
            Text(listTitle).font(.system(size: 17, weight: .semibold)).lineLimit(1)
                .help(model.playlist?.subtitle ?? "")
            Text(filtering ? "\(visible) of \(total) songs" : "\(total) songs · \(durationText(minutes))")
                .font(.system(size: 12)).foregroundStyle(theme.muted).monospacedDigit().lineLimit(1)
            if model.selectedID == "favorites" && model.isLive && !model.usesMusicApp {
                Text("This session only").font(.system(size: 12)).foregroundStyle(theme.muted)
                    .help("Favorite requests accepted in this session. Account favorites are not imported yet.")
            }
            Spacer(minLength: 8)
            if model.selectedID == "recent", !model.recentTracks.isEmpty {
                Button("Clear history") { model.recentTracks = [] }.buttonStyle(.borderless).font(.system(size: 12))
            }
            Button { workspace.playPlaylist(shuffled: true) } label: { Label("Shuffle", systemImage: "shuffle") }
                .help("Shuffle playlist (⇧⌘↩)").disabled(model.tracks.isEmpty)
            Button { workspace.playPlaylist(shuffled: false) } label: { Label("Play", systemImage: "play.fill") }
                .buttonStyle(AccentButtonStyle())
                .help("Play playlist (⌘↩)").disabled(model.tracks.isEmpty)
        }
        .controlSize(.regular)
    }

    private func durationText(_ minutes: Int) -> String {
        minutes >= 60 ? "\(minutes / 60) hr \(minutes % 60) min" : "\(minutes) min"
    }

    @ViewBuilder private var emptyState: some View {
        if workspace.isSearching {
            if workspace.libraryQuery.isEmpty {
                ContentUnavailableView("Search your music", systemImage: "magnifyingglass",
                    description: Text("Type a song, artist, or album. ↑ ↓ to move, Return to play, Esc to go back."))
            } else if model.searching {
                ProgressView()
            } else {
                ContentUnavailableView.search(text: workspace.libraryQuery)
            }
        } else if !(workspace.filters[workspace.playlistKey] ?? "").isEmpty {
            ContentUnavailableView {
                Label("Nothing in \(listTitle) matches", systemImage: "line.3.horizontal.decrease")
            } description: {
                Text("Press Tab to search your whole library instead.")
            } actions: {
                Button("Search library") { workspace.focusCommandBar(scope: .library) }
            }
        } else {
            ContentUnavailableView(model.selectedID == "recent" ? "Nothing played yet" : "No songs here yet", systemImage: "music.note",
                description: Text("Pick a playlist on the left, or press ⇧⌘K to search your library."))
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
        if ProcessInfo.processInfo.arguments.contains("--hide-queue") { workspace.showQueue = false }
        else if ProcessInfo.processInfo.arguments.contains("--show-queue") { workspace.showQueue = true }
    }
    /// Screenshot helpers: --demo-playing, --select-rows 2,3,5, --hover-row N, --query text, --scope library, --show-shortcuts.
    private func applyDebugState() async {
        let args = ProcessInfo.processInfo.arguments
        if args.contains("--demo-playing") {
            try? await model.playback.play(model.tracks, at: 1)
            model.playback.seek(83)
        }
        if let rows = argument("--select-rows") {
            let numbers = Set(rows.split(separator: ",").compactMap { Int($0) })
            workspace.selection = Set(workspace.rows().filter { numbers.contains($0.number) }.map(\.id))
        }
        if let hover = argument("--hover-row") { workspace.debugHoverRow = Int(hover) }
        if let scope = argument("--scope").flatMap(SearchScope.init(rawValue:)) { workspace.setScope(scope) }
        if let query = argument("--query") {
            workspace.queryText = query
            try? await Task.sleep(for: .milliseconds(300))
            workspace.focusCommandBar()
            workspace.caretToEndOnFocus = true
            workspace.placeCaretAtEndIfNeeded()
            if let row = argument("--result-row").flatMap(Int.init) {
                try? await Task.sleep(for: .milliseconds(700))
                for _ in 0..<row { workspace.moveSelection(1) }
            }
        }
        if let sidebar = argument("--sidebar-filter") { workspace.sidebarFilter = sidebar }
        if args.contains("--show-shortcuts") { workspace.showShortcuts = true }
        if args.contains("--hold-command") { workspace.commandHeld = true }
    }
    #endif
}

// MARK: - Sidebar

struct Sidebar: View {
    @Environment(\.playerTheme) private var theme
    @Environment(\.openSettings) private var openSettings
    @ObservedObject var model: AppModel
    @ObservedObject var workspace: Workspace
    @FocusState private var filterFocused: Bool

    private var matches: (MusicPlaylist) -> Bool {
        let filter = workspace.sidebarFilter
        return { filter.isEmpty || $0.name.localizedStandardContains(filter) }
    }

    var body: some View {
        let pinned = workspace.pinnedPlaylists
        let others = model.sortedPlaylists.filter { !model.pinned.contains($0.id) && matches($0) }
        VStack(alignment: .leading, spacing: 0) {
            Color.clear.frame(height: 44)
            VStack(alignment: .leading, spacing: 1) {
                sectionHeader("Library")
                row("Recently played", id: "recent", icon: "clock.arrow.circlepath", count: model.recentTracks.count, shortcut: nil)
                row("Favorites", id: "favorites", icon: "star", count: favoritesCount, shortcut: nil)
                if !pinned.isEmpty {
                    sectionHeader("Pinned").padding(.top, 14)
                    ForEach(Array(pinned.enumerated()), id: \.element.id) { offset, playlist in
                        if matches(playlist) { playlistRow(playlist, shortcut: offset < 9 ? offset + 1 : nil) }
                    }
                }
                HStack {
                    sectionHeader("Playlists")
                    Spacer()
                    Text("\(model.playlists.filter { !model.pinned.contains($0.id) }.count)").font(.system(size: 11)).foregroundStyle(theme.muted).monospacedDigit()
                    Button { model.perform { await model.refresh() } } label: { Image(systemName: "arrow.clockwise").font(.system(size: 11, weight: .medium)) }
                        .buttonStyle(.plain).foregroundStyle(theme.muted).help("Refresh library (⌘R)").accessibilityLabel("Refresh library")
                }.padding(.top, 14).padding(.trailing, 14)
                filterField.padding(.horizontal, 10).padding(.top, 4).padding(.bottom, 6)
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(others) { playlistRow($0, shortcut: nil) }
                    if others.isEmpty && !workspace.sidebarFilter.isEmpty {
                        Text("No playlists match “\(workspace.sidebarFilter)”").font(.system(size: 12)).foregroundStyle(theme.muted)
                            .padding(.horizontal, 16).padding(.vertical, 8)
                    }
                }.padding(.bottom, 8)
            }
            Divider()
            footer
        }
        .background(theme.surface.opacity(theme.isDark ? 0.7 : 0.55))
        .onChange(of: workspace.sidebarFilterRequest) { _, _ in filterFocused = true }
        .onChange(of: filterFocused) { _, focused in workspace.sidebarFilterFocused = focused }
    }

    private var favoritesCount: Int? {
        if !model.isLive { return model.favorites.count }
        return model.usesMusicApp && !model.favoriteTracks.isEmpty ? model.favoriteTracks.count : nil
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(theme.muted)
            .padding(.horizontal, 16).padding(.bottom, 3)
    }

    private var filterField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").font(.system(size: 11, weight: .medium)).foregroundStyle(theme.muted)
            TextField("Filter playlists", text: $workspace.sidebarFilter)
                .textFieldStyle(.plain).font(.system(size: 12)).focused($filterFocused)
                .onSubmit {
                    if let first = model.sortedPlaylists.first(where: matches) { workspace.select(first.id) }
                }
            if workspace.sidebarFilter.isEmpty {
                if !filterFocused { Text("⌥⌘F").font(.system(size: 10, weight: .medium, design: .rounded)).foregroundStyle(theme.muted.opacity(0.8)) }
            } else {
                Button { workspace.sidebarFilter = "" } label: { Image(systemName: "xmark.circle.fill").font(.system(size: 11)) }
                    .buttonStyle(.plain).foregroundStyle(theme.muted).accessibilityLabel("Clear playlist filter")
            }
        }
        .padding(.horizontal, 8).frame(height: 26)
        .background(theme.background.opacity(theme.isDark ? 0.6 : 0.8), in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(filterFocused ? theme.accent.opacity(0.7) : theme.text.opacity(0.14)))
    }

    private func count(for playlist: MusicPlaylist) -> Int? {
        if let loaded = model.loadedTracks[playlist.id] { return loaded.count }
        return playlist.tracks.isEmpty ? nil : playlist.tracks.count
    }

    private func playlistRow(_ playlist: MusicPlaylist, shortcut: Int?) -> some View {
        row(playlist.name, id: playlist.id, icon: "music.note.list", artwork: playlist.artwork, count: count(for: playlist), shortcut: shortcut)
            .contextMenu {
                Button("Play") { Task { await model.select(playlist.id); workspace.playPlaylist(shuffled: false) } }
                Button("Shuffle") { Task { await model.select(playlist.id); workspace.playPlaylist(shuffled: true) } }
                Divider()
                Button(model.pinned.contains(playlist.id) ? "Unpin" : "Pin to top") { model.pin(playlist) }
            }
    }

    private func row(_ title: String, id: String, icon: String, artwork: URL? = nil, count: Int?, shortcut: Int?) -> some View {
        SidebarRow(title: title, icon: icon, artwork: artwork, count: count, shortcut: shortcut,
                   selected: model.selectedID == id && !workspace.isSearching, showShortcut: workspace.commandHeld) {
            workspace.select(id)
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Circle().fill(model.isLive ? theme.accent : Color.orange).frame(width: 7, height: 7)
            VStack(alignment: .leading, spacing: 1) {
                Text(model.usesMusicApp ? "Music.app" : model.isLive ? "Apple Music" : "Sample library").font(.system(size: 12, weight: .medium))
                Text(model.isLive ? "Connected" : "Simulated, no audio").font(.system(size: 11)).foregroundStyle(theme.muted)
            }
            Spacer()
            Button { openSettings() } label: {
                Image(systemName: "gearshape").font(.system(size: 13)).frame(width: 26, height: 26).contentShape(Rectangle())
            }.buttonStyle(.plain).foregroundStyle(theme.muted).help("Settings (⌘,)").accessibilityLabel("Settings")
        }.padding(.horizontal, 14).padding(.vertical, 10)
    }
}

struct SidebarRow: View {
    @Environment(\.playerTheme) private var theme
    var title: String
    var icon: String
    var artwork: URL?
    var count: Int?
    var shortcut: Int?
    var selected: Bool
    var showShortcut: Bool
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if artwork != nil || icon == "music.note.list" {
                    Artwork(url: artwork, seed: title, size: 20, cornerRadius: 4)
                } else {
                    Image(systemName: icon).font(.system(size: 12, weight: .medium)).frame(width: 20)
                        .foregroundStyle(selected ? theme.accent : theme.muted)
                }
                Text(title).font(.system(size: 13, weight: selected ? .medium : .regular)).lineLimit(1)
                Spacer(minLength: 4)
                if let shortcut, showShortcut {
                    KeyCap("⌘\(shortcut)")
                } else if let count {
                    Text("\(count)").font(.system(size: 11)).monospacedDigit().foregroundStyle(theme.muted)
                }
            }
            .padding(.horizontal, 8).frame(height: 28)
            .background(selected ? theme.accent.opacity(0.16) : hovering ? theme.text.opacity(0.05) : .clear, in: RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain).padding(.horizontal, 8)
        .onHover { hovering = $0 }
        .help(shortcut.map { "\(title) (⌘\($0))" } ?? title)
    }
}

// MARK: - Artwork

struct Artwork: View {
    @Environment(\.playerTheme) private var theme
    var url: URL?
    var seed: String
    var size: CGFloat
    var cornerRadius: CGFloat = 8
    @State private var localImage: NSImage?
    private var hue: Double { Double(seed.utf8.reduce(0) { $0 + Int($1) } % 100) / 100 }
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius).fill(Color(hue: hue, saturation: 0.27, brightness: 0.32).gradient)
            GeometryReader { proxy in
                ZStack {
                    ForEach(0..<7) { index in
                        Circle().stroke(.white.opacity(0.14), lineWidth: max(1, size / 90))
                            .frame(width: proxy.size.width * (0.3 + Double(index) * 0.2))
                    }
                }.position(x: proxy.size.width * 0.75, y: proxy.size.height * 0.7)
            }.clipped()
            if url?.scheme == "music-artwork" {
                if let localImage {
                    Image(nsImage: localImage).resizable().scaledToFill()
                }
            } else if let url {
                AsyncImage(url: url) { image in image.resizable().scaledToFill() } placeholder: { Color.clear }
            }
        }.frame(width: size, height: size).clipShape(RoundedRectangle(cornerRadius: cornerRadius)).accessibilityHidden(true)
        .task(id: url) {
            localImage = nil
            guard let url, url.scheme == "music-artwork" else { return }
            let data = await MusicArtworkLoader.shared.thumbnail(for: url, pixels: size > 48 ? 320 : 96)
            guard !Task.isCancelled else { return }
            localImage = data.flatMap { NSImage(data: $0) }
        }
    }
}
