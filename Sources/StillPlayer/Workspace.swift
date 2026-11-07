import SwiftUI
import AppKit
#if SWIFT_PACKAGE
import PlayerCore
#endif

/// Where the command bar looks. `.playlist` filters the open list in place; the others search.
enum SearchScope: String, CaseIterable, Identifiable {
    case playlist, library, catalog
    var id: String { rawValue }
    var title: String {
        switch self {
        case .playlist: "Playlist"
        case .library: "Library"
        case .catalog: "Catalog"
        }
    }
}

enum SortKey: String { case number, title, artist, album, duration }
struct TrackSort: Equatable { var key: SortKey = .number; var ascending = true }

struct TrackRowItem: Identifiable, Equatable {
    let id: String
    let number: Int
    let track: LibraryTrack
}

/// UI-only state for the main window: command bar, per-list filters/selection/sort, panels, and the
/// window-level keyboard handling. Playback and library behaviour stay in `AppModel`.
@MainActor
final class Workspace: ObservableObject {
    weak var model: AppModel?
    weak var window: NSWindow?

    @Published var scope: SearchScope = .playlist
    @Published var filters: [String: String] = [:]
    @Published var libraryQuery = ""
    @Published var selections: [String: Set<String>] = [:]
    @Published var sorts: [String: TrackSort] = [:]
    @Published var sidebarFilter = ""
    @Published var showShortcuts = false
    @Published var showQueue = UserDefaults.standard.object(forKey: "queue.visible") as? Bool ?? true {
        didSet { UserDefaults.standard.set(showQueue, forKey: "queue.visible") }
    }
    @Published var commandFocusRequest = 0
    @Published var commandBlurRequest = 0
    @Published var sidebarFilterRequest = 0
    @Published var scrollRequest: String?
    @Published var commandHeld = false
    var commandFocused = false
    var sidebarFilterFocused = false
    var caretToEndOnFocus = false
    var debugHoverRow: Int?
    var debugMusicAppLayout = false
    private var monitor: Any?

    // MARK: Derived state

    var playlistKey: String { "playlist:" + (model?.selectedID ?? "none") }
    var listKey: String { scope == .playlist ? playlistKey : "search" }
    var isSearching: Bool { scope != .playlist }
    var availableScopes: [SearchScope] { model?.usesMusicApp == true || debugMusicAppLayout ? [.playlist, .library] : SearchScope.allCases }
    var queueSupported: Bool { !(model?.usesMusicApp ?? false) && !debugMusicAppLayout }
    var queueVisible: Bool { queueSupported && showQueue }

    var queryText: String {
        get { scope == .playlist ? filters[playlistKey] ?? "" : libraryQuery }
        set { if scope == .playlist { filters[playlistKey] = newValue } else { libraryQuery = newValue } }
    }
    var selection: Set<String> {
        get { selections[listKey] ?? [] }
        set { selections[listKey] = newValue }
    }
    var sort: TrackSort {
        get { sorts[listKey] ?? TrackSort() }
        set { sorts[listKey] = newValue }
    }

    func rows() -> [TrackRowItem] {
        guard let model else { return [] }
        let source = scope == .playlist ? model.tracks : model.searchResults
        let query = scope == .playlist ? filters[playlistKey] ?? "" : ""
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

    // MARK: Command bar

    func focusCommandBar(scope requested: SearchScope? = nil) {
        if let requested { setScope(requested) }
        commandFocusRequest += 1
    }

    func setScope(_ new: SearchScope) {
        guard new != scope, availableScopes.contains(new) else { return }
        if scope == .playlist, let text = filters[playlistKey], !text.isEmpty { libraryQuery = text }
        scope = new
    }

    func cycleScope(forward: Bool) {
        let scopes = availableScopes
        guard let index = scopes.firstIndex(of: scope) else { setScope(.playlist); return }
        setScope(scopes[(index + (forward ? 1 : scopes.count - 1)) % scopes.count])
    }

    /// Escape peels back one layer at a time: query, then search scope, then focus.
    func escapeCommandBar() {
        if !queryText.isEmpty { queryText = "" }
        else if scope != .playlist { scope = .playlist }
        else { commandBlurRequest += 1 }
    }

    // MARK: Selection and playback

    func moveSelection(_ delta: Int, extend: Bool = false) {
        let rows = rows()
        guard !rows.isEmpty else { return }
        let current = selection
        let anchor = delta > 0 ? rows.lastIndex { current.contains($0.id) } : rows.firstIndex { current.contains($0.id) }
        let next = anchor.map { min(max($0 + delta, 0), rows.count - 1) } ?? (delta > 0 ? 0 : rows.count - 1)
        selection = extend ? current.union([rows[next].id]) : [rows[next].id]
        scrollRequest = rows[next].id
    }

    func playSelection() {
        guard let model else { return }
        let rows = rows()
        guard !rows.isEmpty else { return }
        let ids = selection
        let index = rows.firstIndex { ids.contains($0.id) } ?? 0
        model.perform { try await model.playback.play(rows.map(\.track), at: index) }
    }

    func play(row: TrackRowItem) {
        guard let model else { return }
        let rows = rows()
        let index = rows.firstIndex { $0.id == row.id } ?? 0
        model.perform { try await model.playback.play(rows.map(\.track), at: index) }
    }

    func playPlaylist(shuffled: Bool) {
        guard let model, !model.tracks.isEmpty else { return }
        model.perform {
            if shuffled { model.playback.shuffle = true }
            try await model.playback.playPlaylist(model.playlist, tracks: model.tracks)
        }
    }

    // MARK: Navigation

    /// Sidebar order: Recently played, Favorites, pinned playlists, other playlists.
    var navigationOrder: [String] {
        guard let model else { return [] }
        return ["recent", "favorites"] + model.sortedPlaylists.map(\.id)
    }
    var pinnedPlaylists: [MusicPlaylist] {
        guard let model else { return [] }
        return model.sortedPlaylists.filter { model.pinned.contains($0.id) }
    }

    func select(_ id: String) {
        guard let model else { return }
        if scope != .playlist { scope = .playlist }
        Task { await model.select(id) }
    }

    func selectAdjacent(_ delta: Int) {
        let order = navigationOrder
        guard !order.isEmpty else { return }
        let index = order.firstIndex(of: model?.selectedID ?? "") ?? -1
        select(order[min(max(index + delta, 0), order.count - 1)])
    }

    func selectPinned(_ number: Int) {
        let pinned = pinnedPlaylists
        guard pinned.indices.contains(number - 1) else { return }
        select(pinned[number - 1].id)
    }

    // MARK: Keyboard

    func installKeyMonitor() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            nonisolated(unsafe) let event = event
            let consumed = MainActor.assumeIsolated { self?.handle(event) ?? false }
            return consumed ? nil : event
        }
    }

    private func handle(_ event: NSEvent) -> Bool {
        guard let window, event.window === window, window.attachedSheet == nil else {
            if event.type == .flagsChanged, commandHeld { commandHeld = false }
            return false
        }
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        if event.type == .flagsChanged {
            let held = flags == .command
            if held != commandHeld { commandHeld = held }
            return false
        }
        let editing = window.firstResponder is NSTextView
        let key = event.keyCode

        if showShortcuts {
            if key == 53 || (event.charactersIgnoringModifiers == "?" && !editing) { showShortcuts = false; return true }
            return false
        }

        if editing && commandFocused {
            switch key {
            case 125 where flags.isEmpty || flags == .shift: moveSelection(1, extend: flags == .shift); return true
            case 126 where flags.isEmpty || flags == .shift: moveSelection(-1, extend: flags == .shift); return true
            case 48 where flags.isEmpty || flags == .shift: cycleScope(forward: flags != .shift); return true
            case 36 where flags.isEmpty, 76 where flags.isEmpty: playSelection(); return true
            case 53: escapeCommandBar(); return true
            default: return false
            }
        }
        if editing {
            if key == 53 && sidebarFilterFocused { sidebarFilter = ""; window.makeFirstResponder(nil); return true }
            return false
        }

        // Nothing is being typed into.
        let inList = window.firstResponder is NSTableView
        switch key {
        case 53 where flags.isEmpty:
            if !selection.isEmpty { selection = []; return true }
            if scope != .playlist { scope = .playlist; return true }
            return false
        case 36 where flags.isEmpty && !selection.isEmpty, 76 where flags.isEmpty && !selection.isEmpty:
            playSelection(); return true
        case 125 where !inList && (flags.isEmpty || flags == .shift), 126 where !inList && (flags.isEmpty || flags == .shift):
            moveSelection(key == 125 ? 1 : -1, extend: flags == .shift); return true
        default: break
        }
        // Space plays/pauses only when it isn't being typed, so the command bar never loses spaces.
        if key == 49 && flags.isEmpty {
            if let model, model.playback.current != nil { model.perform { try await model.playback.toggle() } }
            return true
        }
        if event.charactersIgnoringModifiers == "?" && flags.subtracting(.shift).isEmpty {
            showShortcuts = true; return true
        }
        // Type anywhere to find: printable characters go to the command bar.
        if flags.subtracting(.shift).isEmpty, let typed = event.characters, typed.count == 1,
           let scalar = typed.unicodeScalars.first, CharacterSet.alphanumerics.contains(scalar) {
            queryText += typed
            caretToEndOnFocus = true
            focusCommandBar()
            return true
        }
        return false
    }

    /// After focus moves into the command bar from type-to-find, AppKit selects the whole field.
    /// Put the caret at the end so the next keystroke appends instead of replacing.
    func placeCaretAtEndIfNeeded() {
        guard caretToEndOnFocus else { return }
        caretToEndOnFocus = false
        DispatchQueue.main.async { [weak self] in
            (self?.window?.firstResponder as? NSTextView)?.moveToEndOfDocument(nil)
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
