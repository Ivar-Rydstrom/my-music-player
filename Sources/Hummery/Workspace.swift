import SwiftUI
import AppKit
#if SWIFT_PACKAGE
import PlayerCore
#endif

enum SortKey: String { case number, title, artist, album, duration }
struct TrackSort: Equatable { var key: SortKey = .number; var ascending = true }

struct TrackRowItem: Identifiable, Equatable {
    let id: String
    let number: Int
    let track: LibraryTrack
}

/// UI-only state for the main window: the Arc-style frame (sidebar, peek, history), the command
/// palette, per-list filters/selection/sort, the floating player, and window-level keyboard handling.
/// Playback and library behaviour stay in `AppModel`.
@MainActor
final class Workspace: ObservableObject {
    weak var model: AppModel? { didSet { palette.workspace = self } }
    weak var window: NSWindow?

    // Lists
    @Published var filters: [String: String] = [:]
    @Published var selections: [String: Set<String>] = [:]
    @Published var sorts: [String: TrackSort] = [:]
    /// Non-nil while the content card shows "all results" for a palette search.
    @Published var resultsQuery: String?
    @Published var filterVisible = false
    @Published var filterFocusRequest = 0
    /// Library search without the palette (⇧⌘F): the results view's own search field.
    @Published var searchFocusRequest = 0
    var searchFocused = false
    @Published var scrollRequest: String?
    var filterFocused = false
    private var anchorRow: String?

    // Frame
    @Published var sidebarCollapsed = UserDefaults.standard.bool(forKey: "sidebar.collapsed") {
        didSet { UserDefaults.standard.set(sidebarCollapsed, forKey: "sidebar.collapsed") }
    }
    @Published var sidebarPeek = false
    @Published private(set) var backStack: [String] = []
    @Published private(set) var forwardStack: [String] = []

    // Overlays
    /// The command palette (Raycast-style: one ranked list, an action panel per result).
    let palette = PaletteController()
    /// The user's key bindings for every command.
    let shortcuts = ShortcutStore.shared
    @Published var pillExpanded = false
    @Published var showShortcuts = false

    var debugHoverRow: Int?
    var debugMusicAppLayout = false
    private var monitor: Any?

    // MARK: Derived state

    var playlistKey: String { "playlist:" + (model?.selectedID ?? "none") }
    var listKey: String { resultsQuery == nil ? playlistKey : "search" }
    var isShowingResults: Bool { resultsQuery != nil }
    var queueSupported: Bool { !(model?.usesMusicApp ?? false) && !debugMusicAppLayout }

    var filterText: String {
        get { filters[playlistKey] ?? "" }
        set { filters[playlistKey] = newValue }
    }
    var selection: Set<String> {
        get { selections[listKey] ?? [] }
        set { selections[listKey] = newValue }
    }
    var sort: TrackSort {
        get { sorts[listKey] ?? TrackSort() }
        set { sorts[listKey] = newValue }
    }

    /// The name shown in the sidebar's address bar.
    var contextTitle: String {
        if let resultsQuery { return resultsQuery.isEmpty ? "Search library" : "Results for “\(resultsQuery)”" }
        guard let model else { return "Hummery" }
        return Workspace.title(for: model.selectedID, in: model)
    }

    static func title(for id: String?, in model: AppModel) -> String {
        switch id {
        case "recent": "Recently played"
        case "favorites": "Favorites"
        default: model.playlists.first { $0.id == id }?.name ?? "Your music"
        }
    }

    func rows() -> [TrackRowItem] {
        guard let model else { return [] }
        let source = resultsQuery == nil ? model.tracks : model.searchResults
        let query = resultsQuery == nil ? filterText : ""
        let items = source.enumerated()
            .map { TrackRowItem(id: "\($0.offset):\($0.element.id)", number: $0.offset + 1, track: $0.element) }
            .filter { $0.track.matches(query) }
        let order = sort
        guard order.key != .number else { return order.ascending ? items : items.reversed() }
        return items.sorted { lhs, rhs in
            let result: ComparisonResult
            switch order.key {
            case .title: result = lhs.track.title.localizedStandardCompare(rhs.track.title)
            case .artist: result = lhs.track.artist.localizedStandardCompare(rhs.track.artist)
            case .album: result = lhs.track.album.localizedStandardCompare(rhs.track.album)
            case .duration: result = lhs.track.duration == rhs.track.duration ? .orderedSame : lhs.track.duration < rhs.track.duration ? .orderedAscending : .orderedDescending
            case .number: result = .orderedSame
            }
            if result == .orderedSame { return lhs.number < rhs.number }
            return order.ascending ? result == .orderedAscending : result == .orderedDescending
        }
    }

    func selectedTracks() -> [LibraryTrack] {
        let ids = selection
        return rows().filter { ids.contains($0.id) }.map(\.track)
    }

    func toggleSort(_ key: SortKey) {
        var next = sort
        if key == .number { next = TrackSort() }
        else if next.key == key { next.ascending.toggle() }
        else { next = TrackSort(key: key, ascending: true) }
        sort = next
    }

    // MARK: Filter (⌘F)

    func revealFilter() {
        if resultsQuery != nil { resultsQuery = nil }
        filterVisible = true
        filterFocusRequest += 1
    }

    /// Escape in the filter: clear the text first, then put the field away.
    func escapeFilter() {
        if !filterText.isEmpty { filterText = "" } else { filterVisible = false; window?.makeFirstResponder(nil) }
    }

    // MARK: Selection and playback

    /// Click, ⌘-click and ⇧-click on a row, like a Finder list.
    func click(row: TrackRowItem, command: Bool, shift: Bool) {
        if shift, let anchor = anchorRow {
            let rows = rows()
            if let from = rows.firstIndex(where: { $0.id == anchor }), let to = rows.firstIndex(where: { $0.id == row.id }) {
                let range = rows[min(from, to)...max(from, to)].map(\.id)
                selection = command ? selection.union(range) : Set(range)
                return
            }
        }
        if command {
            if selection.contains(row.id) { selection.remove(row.id) } else { selection.insert(row.id) }
        } else {
            selection = [row.id]
        }
        anchorRow = row.id
    }

    func selectAll() { selection = Set(rows().map(\.id)) }

    func moveSelection(_ delta: Int, extend: Bool = false) {
        let rows = rows()
        guard !rows.isEmpty else { return }
        let current = selection
        let anchor = delta > 0 ? rows.lastIndex { current.contains($0.id) } : rows.firstIndex { current.contains($0.id) }
        let next = anchor.map { min(max($0 + delta, 0), rows.count - 1) } ?? (delta > 0 ? 0 : rows.count - 1)
        selection = extend ? current.union([rows[next].id]) : [rows[next].id]
        if !extend { anchorRow = rows[next].id }
        scrollRequest = rows[next].id
    }

    func playSelection() {
        guard let model else { return }
        let rows = rows()
        guard !rows.isEmpty else { return }
        let ids = selection
        let index = rows.firstIndex { ids.contains($0.id) } ?? 0
        let context = listContext
        model.perform { try await model.playback.play(rows.map(\.track), at: index, context: context) }
    }

    /// The list rows play from, so its Play button and sidebar mark know it's playing. Search
    /// results aren't a list of their own.
    private var listContext: String? { resultsQuery == nil ? model?.selectedID : nil }

    /// Opens the list a song came from and selects it there.
    func reveal(_ track: LibraryTrack) {
        guard let model else { return }
        let target = track.sourcePlaylistID ?? model.playback.contextID
            ?? model.playlists.first { $0.tracks.contains { $0.id == track.id } }?.id
        guard let target else { return }
        select(target)
        Task {
            await model.select(target)
            if let row = rows().first(where: { $0.track.id == track.id }) {
                selection = [row.id]; anchorRow = row.id; scrollRequest = row.id
            }
        }
    }

    func play(row: TrackRowItem) {
        guard let model else { return }
        let rows = rows()
        let index = rows.firstIndex { $0.id == row.id } ?? 0
        let context = listContext
        model.perform { try await model.playback.play(rows.map(\.track), at: index, context: context) }
    }

    /// Plays the open list from the top (in order, or shuffled).
    func playPlaylist(shuffled: Bool) {
        guard let model, !model.tracks.isEmpty else { return }
        let context = model.selectedID
        model.perform { try await model.playback.playPlaylist(model.playlist, tracks: model.tracks, context: context, shuffled: shuffled) }
    }

    /// Whether the open list is the one playing (or paused), so Play becomes pause/resume.
    var isPlayingOpenList: Bool {
        guard let model, resultsQuery == nil else { return false }
        return model.playback.isCurrentContext(model.selectedID, tracks: model.tracks)
    }

    /// The header's Play button and the Play Playlist command: once this list is playing they pause
    /// and resume it instead of restarting it from the top.
    func playOrPauseOpenList() {
        guard let model else { return }
        if isPlayingOpenList { model.perform { try await model.playback.toggle() } } else { playPlaylist(shuffled: false) }
    }

    // MARK: Navigation

    /// Sidebar order: Recently played, Favorites, then playlists A–Z. Nothing is pinned first.
    var navigationOrder: [String] {
        guard let model else { return [] }
        return ["recent", "favorites"] + Workspace.alphabetical(model.playlists).map(\.id)
    }

    nonisolated static func alphabetical(_ playlists: [MusicPlaylist]) -> [MusicPlaylist] {
        playlists.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Opens a list and records it in back/forward history, like a browser tab.
    func select(_ id: String) {
        guard let model else { return }
        let current = model.selectedID
        if resultsQuery != nil { resultsQuery = nil }
        else if current == id { return }
        if let current, current != id {
            backStack.append(current)
            if backStack.count > 50 { backStack.removeFirst() }
            forwardStack = []
        }
        Task { await model.select(id) }
    }

    var canGoBack: Bool { !backStack.isEmpty }
    var canGoForward: Bool { !forwardStack.isEmpty }

    func goBack() {
        guard let model, let previous = backStack.popLast() else { return }
        if let current = model.selectedID { forwardStack.append(current) }
        resultsQuery = nil
        Task { await model.select(previous) }
    }

    func goForward() {
        guard let model, let next = forwardStack.popLast() else { return }
        if let current = model.selectedID { backStack.append(current) }
        resultsQuery = nil
        Task { await model.select(next) }
    }

    func selectAdjacent(_ delta: Int) {
        let order = navigationOrder
        guard !order.isEmpty else { return }
        let index = order.firstIndex(of: model?.selectedID ?? "") ?? -1
        select(order[min(max(index + delta, 0), order.count - 1)])
    }

    func showResults(for query: String) {
        resultsQuery = query
        selections["search"] = []
    }

    /// ⇧⌘F, or "Search all music" from an empty filter: searches the whole library in the card,
    /// with no palette involved.
    func searchLibrary(_ query: String = "") {
        filterVisible = false
        showResults(for: query)
        searchFocusRequest += 1
    }

    /// Escape in the library search field: clear the text first, then leave the results.
    func escapeSearch() {
        if let query = resultsQuery, !query.isEmpty { resultsQuery = "" } else { resultsQuery = nil; window?.makeFirstResponder(nil) }
    }

    // MARK: Frame

    func toggleSidebar() {
        sidebarPeek = false
        sidebarCollapsed.toggle()
    }

    // MARK: Palette

    func openPalette(query: String = "") {
        sidebarPeek = false
        pillExpanded = false
        palette.open(query: query)
    }

    /// Opens the palette at the choose-a-playlist step for these songs.
    func addToPlaylist(_ tracks: [LibraryTrack]) {
        guard !tracks.isEmpty else { return }
        sidebarPeek = false
        pillExpanded = false
        palette.open(step: .addToPlaylist(tracks, subject: tracks.count == 1 ? tracks[0].title : "\(tracks.count) songs"))
    }

    /// ⌘K on the song list: the palette opens at the selection's actions.
    func showActionsForSelection() {
        let tracks = selectedTracks()
        if tracks.count == 1, let track = tracks.first {
            sidebarPeek = false; pillExpanded = false
            palette.open(actionsFor: PaletteCatalog.song(track))
        } else if tracks.count > 1 {
            addToPlaylist(tracks)
        } else {
            openPalette()
        }
    }

    func closePalette() { palette.close() }

    /// The palette's key (⇧⌘P unless changed or removed in Settings) opens the palette, or closes it again.
    func togglePalette() { if palette.isOpen { closePalette() } else { openPalette() } }

    // MARK: Keyboard

    func installKeyMonitor() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            nonisolated(unsafe) let event = event
            let consumed = MainActor.assumeIsolated { self?.handle(event) ?? false }
            return consumed ? nil : event
        }
    }

    private func handle(_ event: NSEvent) -> Bool {
        guard let window, event.window === window, window.attachedSheet == nil else { return false }
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        let editing = window.firstResponder is NSTextView
        let key = event.keyCode
        // Every app command goes through the user's bindings, so a removed binding does nothing at all.
        let command = shortcuts.action(for: event, typing: editing)

        // The palette key wins over everything, so it also closes the palette.
        if command == .palette { togglePalette(); return true }
        if palette.isOpen {
            if palette.handle(key: key, flags: flags, characters: event.charactersIgnoringModifiers) { return true }
            if let command { run(command); return true }
            return false
        }
        if let command { run(command); return true }

        if showShortcuts {
            if key == 53 { showShortcuts = false; return true }
            return false
        }

        // Fixed keys: moving around lists and backing out. These aren't commands, so they aren't rebindable.
        if editing && (filterFocused || searchFocused) {
            switch key {
            case 125 where flags.isEmpty || flags == .shift: moveSelection(1, extend: flags == .shift); return true
            case 126 where flags.isEmpty || flags == .shift: moveSelection(-1, extend: flags == .shift); return true
            case 36 where flags.isEmpty, 76 where flags.isEmpty:
                if selection.isEmpty { moveSelection(1) }
                playSelection(); return true
            case 53:
                if searchFocused { escapeSearch() } else { escapeFilter() }
                return true
            default: return false
            }
        }
        if editing { return false }

        switch key {
        case 53 where flags.isEmpty:
            if pillExpanded { pillExpanded = false; return true }
            if !selection.isEmpty { selection = []; return true }
            if resultsQuery != nil { resultsQuery = nil; return true }
            if filterVisible { escapeFilter(); return true }
            if sidebarPeek { sidebarPeek = false; return true }
            return false
        case 36 where flags.isEmpty && !selection.isEmpty, 76 where flags.isEmpty && !selection.isEmpty:
            playSelection(); return true
        case 125 where flags.isEmpty || flags == .shift, 126 where flags.isEmpty || flags == .shift:
            moveSelection(key == 125 ? 1 : -1, extend: flags == .shift); return true
        default:
            // Plain letters do nothing unless a text field is focused: no type-to-search, no surprises.
            return false
        }
    }

    // MARK: Commands

    /// Set by the window, which owns SwiftUI's `openSettings`.
    var openSettingsAction: (() -> Void)?

    /// Runs a command, whether it came from its key, its menu item, or a button.
    func run(_ action: ShortcutAction) {
        guard let model else { return }
        let player = model.playback
        switch action {
        case .palette: togglePalette()
        case .songActions: showActionsForSelection()
        case .filter: revealFilter()
        case .searchLibrary: searchLibrary()
        case .back: goBack()
        case .forward: goForward()
        case .previousList: selectAdjacent(-1)
        case .nextList: selectAdjacent(1)
        case .revealCurrent: if let current = player.current { reveal(current) }
        case .playPause, .playPauseQuick: if player.current != nil { model.perform { try await player.toggle() } }
        case .nextSong: model.perform { try await player.next() }
        case .previousSong: model.perform { try await player.previous() }
        case .playPlaylist: playOrPauseOpenList()
        case .shufflePlaylist: playPlaylist(shuffled: true)
        case .favoriteCurrent: if let current = player.current { model.perform { try await model.favorite(current) } }
        case .volumeUp: if player.isMusicApp { player.setVolume(min(100, player.volume + 10)) }
        case .volumeDown: if player.isMusicApp { player.setVolume(max(0, player.volume - 10)) }
        case .selectAll: selectAll()
        case .toggleSidebar: withAnimation(.spring(response: 0.38, dampingFraction: 0.86)) { toggleSidebar() }
        case .expandPlayer: withAnimation(FloatingPlayer.morph) { pillExpanded.toggle() }
        case .refresh: model.perform { await model.refresh() }
        case .settings: openSettingsAction?()
        case .shortcutsHelp: showShortcuts.toggle()
        }
    }
}

/// Hands the hosting NSWindow to the workspace so key handling can be scoped to the main window.
struct WindowReader: NSViewRepresentable {
    var onWindow: (NSWindow) -> Void
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { if let window = view.window { onWindow(window) } }
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}
