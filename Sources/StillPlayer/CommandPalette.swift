import SwiftUI
#if SWIFT_PACKAGE
import PlayerCore
#endif

// MARK: - Model

enum PaletteKey { case up, down, run, escape }

/// Where the palette is: the root list, or the second step of "Add to playlist".
enum PaletteStep: Equatable {
    case root
    case addToPlaylist(tracks: [LibraryTrack], label: String)
}

struct PaletteState: Equatable {
    var isOpen = false
    var query = ""
    var step: PaletteStep = .root
    var highlight = 0
}

enum PaletteGroup: String {
    case topHit = "Top hit"
    case nowPlaying = "Now playing"
    case recent = "Recent"
    case songs = "Songs"
    case playlists = "Playlists"
    case commands = "Commands"
    case suggestions = "Suggestions"
    case destinations = "Add to playlist"
}

/// What a row does. The view layer decides how; the model only names it.
enum PaletteAction: Hashable {
    case playPause, next, previous, shuffle(Bool), repeatAll(Bool), seekToStart, volume(Int)
    case favoriteCurrent, addCurrentToPlaylist, revealCurrent
    case sleep(Int?), toggleSidebar, expandPlayer, refresh, clearRecent, checkUpdates, shortcuts, filterPlaylist
    case settings(String?), theme(String)
    case openPlaylist(String), playSong(String), showAllResults(String)
    case addTracks(toPlaylist: String)
}

enum PaletteIcon: Equatable {
    case symbol(String)
    case artwork(URL?, seed: String)
}

struct PaletteItem: Identifiable, Equatable {
    var id: String
    var title: String
    var subtitle: String? = nil
    var icon: PaletteIcon
    /// Extra words that find this row but aren't shown ("prefs" finds Settings).
    var keywords: [String] = []
    var shortcut: String? = nil
    /// The verb on the right: "Run", "Play", "Open".
    var hint: String = "Run"
    var opensStep = false
    var action: PaletteAction
    /// Offsets into `title` that matched the query, for emphasis.
    var matched: [Int] = []
    var score = 0
}

struct PaletteSection: Identifiable, Equatable {
    var group: PaletteGroup
    var items: [PaletteItem]
    var id: String { group.rawValue }
}

/// Fuzzy subsequence matching, VS Code / Raycast style. Contiguous runs, word starts and an early
/// first match score higher; every skipped character costs a little.
enum FuzzyMatcher {
    static func match(_ query: String, in text: String) -> (score: Int, indices: [Int])? {
        let needle = Array(query.lowercased().filter { !$0.isWhitespace })
        guard !needle.isEmpty else { return (0, []) }
        let hay = Array(text.lowercased())
        guard needle.count <= hay.count else { return nil }

        // A contiguous hit beats any scattered one.
        if let range = text.range(of: String(query.lowercased().trimmingCharacters(in: .whitespaces)), options: [.caseInsensitive, .diacriticInsensitive]) {
            let start = text.distance(from: text.startIndex, to: range.lowerBound)
            let length = text.distance(from: range.lowerBound, to: range.upperBound)
            // Equal hits tie, so the catalog's own order decides; an exact title gets a small edge.
            var score = 1000 + length * 12 - start * 3 + (length == hay.count ? 60 : 0)
            if start == 0 { score += 200 } else if isWordStart(hay, start) { score += 120 }
            return (score, Array(start..<(start + length)).filter { !hay[$0].isWhitespace })
        }

        var indices: [Int] = []
        var score = 0
        var position = 0
        for char in needle {
            // Prefer the next word-start occurrence when it isn't far away, so "tsb" hits "Toggle SideBar".
            var found: Int?
            var fallback: Int?
            var cursor = position
            while cursor < hay.count {
                if hay[cursor] == char {
                    if fallback == nil { fallback = cursor }
                    if isWordStart(hay, cursor) || indices.last == cursor - 1 { found = cursor; break }
                }
                cursor += 1
            }
            guard let index = found ?? fallback else { return nil }
            if let last = indices.last {
                if index == last + 1 { score += 14 } else { score -= min(index - last - 1, 12) }
            } else {
                score -= min(index, 20)
            }
            if isWordStart(hay, index) { score += 18 }
            indices.append(index)
            position = index + 1
        }
        if indices.first == 0 { score += 20 }
        return (200 + score - hay.count / 4, indices)
    }

    private static func isWordStart(_ hay: [Character], _ index: Int) -> Bool {
        index == 0 || !(hay[index - 1].isLetter || hay[index - 1].isNumber)
    }
}

/// Everything the command list depends on, so it can be built (and tested) without the UI.
struct PaletteContext {
    var currentTitle: String?
    var currentIsFavorite = false
    var isMusicApp = false
    var queueSupported = true
    var shuffle = false
    var repeatAll = false
    var sleepActive = false
    var sidebarCollapsed = false
    var hasRecent = false
    var themeID = "sage"
}

enum PaletteCatalog {
    static func commands(_ context: PaletteContext) -> [PaletteItem] {
        var items: [PaletteItem] = []
        func add(_ id: String, _ title: String, _ icon: String, _ action: PaletteAction, shortcut: String? = nil,
                 keywords: [String] = [], hint: String = "Run", opensStep: Bool = false) {
            items.append(PaletteItem(id: id, title: title, icon: .symbol(icon), keywords: keywords, shortcut: shortcut,
                                     hint: hint, opensStep: opensStep, action: action))
        }
        let hasCurrent = context.currentTitle != nil
        // Playback
        add("play-pause", "Play / Pause", "playpause.fill", .playPause, shortcut: "Space", keywords: ["resume", "stop"])
        add("next", "Next song", "forward.fill", .next, shortcut: "⌘→", keywords: ["skip"])
        add("previous", "Previous song", "backward.fill", .previous, shortcut: "⌘←", keywords: ["back"])
        add("shuffle", context.shuffle ? "Turn shuffle off" : "Turn shuffle on", "shuffle", .shuffle(!context.shuffle), keywords: ["shuffle", "random"])
        add("repeat", context.repeatAll ? "Turn repeat off" : "Turn repeat on", "repeat", .repeatAll(!context.repeatAll), keywords: ["repeat", "loop"])
        if hasCurrent { add("seek-start", "Seek to start", "backward.end.fill", .seekToStart, keywords: ["restart", "beginning"]) }
        if context.isMusicApp {
            add("volume-up", "Volume up", "speaker.wave.3.fill", .volume(10), shortcut: "⌘↑", keywords: ["louder"])
            add("volume-down", "Volume down", "speaker.wave.1.fill", .volume(-10), shortcut: "⌘↓", keywords: ["quieter"])
        }
        // Current song
        if let title = context.currentTitle {
            add("favorite-current", context.currentIsFavorite ? "Unfavorite “\(title)”" : "Favorite “\(title)”",
                context.currentIsFavorite ? "star.slash" : "star", .favoriteCurrent, shortcut: "⌘L",
                keywords: ["favorite", "love", "like", "unfavorite", "current song"])
            add("add-current", "Add “\(title)” to playlist…", "text.badge.plus", .addCurrentToPlaylist,
                keywords: ["add current song to playlist"], hint: "Choose", opensStep: true)
            add("reveal-current", "Reveal “\(title)” in its playlist", "scope", .revealCurrent, keywords: ["show current song", "locate", "find"], hint: "Show")
        }
        // Utilities
        for minutes in [15, 30, 45, 60] {
            add("sleep-\(minutes)", "Sleep timer: \(minutes) minutes", "moon", .sleep(minutes), keywords: ["pause after", "sleep"])
        }
        if context.sleepActive { add("sleep-cancel", "Cancel sleep timer", "moon.zzz", .sleep(nil), keywords: ["sleep"]) }
        add("toggle-sidebar", context.sidebarCollapsed ? "Show sidebar" : "Hide sidebar", "sidebar.left", .toggleSidebar, shortcut: "⌘S", keywords: ["toggle sidebar", "collapse"])
        add("expand-player", context.queueSupported ? "Expand player and queue" : "Expand player", "rectangle.expand.vertical",
            .expandPlayer, shortcut: "⇧⌘U", keywords: context.queueSupported ? ["show queue", "up next", "now playing"] : ["now playing"])
        add("filter", "Filter this playlist", "line.3.horizontal.decrease", .filterPlaylist, shortcut: "⌘F", keywords: ["find in playlist"])
        add("refresh", "Refresh library", "arrow.clockwise", .refresh, shortcut: "⌘R", keywords: ["reload", "sync"])
        if context.hasRecent { add("clear-recent", "Clear recently played", "clock.badge.xmark", .clearRecent, keywords: ["history"]) }
        add("check-updates", "Check for updates…", "arrow.down.circle", .checkUpdates, keywords: ["update", "version"])
        add("shortcuts", "Keyboard shortcuts", "keyboard", .shortcuts, shortcut: "⌘/", keywords: ["help", "keys"])
        // Settings
        add("settings", "Settings", "gearshape", .settings(nil), shortcut: "⌘,", keywords: ["settings", "preferences", "prefs"], hint: "Open")
        add("settings-appearance", "Settings: Appearance", "paintpalette", .settings("appearance"), keywords: ["theme", "colors"], hint: "Open")
        add("settings-connection", "Settings: Connection", "link", .settings("connection"), keywords: ["music app", "account", "connect"], hint: "Open")
        add("settings-updates", "Settings: Updates", "arrow.down.circle", .settings("updates"), hint: "Open")
        for preset in ThemePreset.all where preset.id != context.themeID {
            add("theme-\(preset.id)", "Theme: \(preset.name)", "circle.lefthalf.filled", .theme(preset.id), keywords: ["appearance", "color"], hint: "Switch")
        }
        return items
    }

    static func song(_ track: LibraryTrack) -> PaletteItem {
        PaletteItem(id: "song:\(track.id)", title: track.title, subtitle: "\(track.artist) · \(track.album)",
                    icon: .artwork(track.artwork, seed: track.album), keywords: [track.artist, track.album],
                    hint: "Play", action: .playSong(track.id))
    }

    static func playlist(_ playlist: MusicPlaylist, playing: Bool) -> PaletteItem {
        PaletteItem(id: "playlist:\(playlist.id)", title: playlist.name, subtitle: playing ? "Playing" : nil,
                    icon: .artwork(playlist.artwork, seed: playlist.name), keywords: ["playlist"],
                    hint: "Open", action: .openPlaylist(playlist.id))
    }
}

/// Turns a query into grouped, ranked sections. Pure, so ranking and filtering are unit tested.
enum PaletteEngine {
    static let songLimit = 5
    static let playlistLimit = 4
    static let commandLimit = 7

    /// Scores an item against the title first, then (weaker) its subtitle and keywords.
    static func scored(_ item: PaletteItem, query: String) -> PaletteItem? {
        var best: PaletteItem?
        if let hit = FuzzyMatcher.match(query, in: item.title) {
            var copy = item; copy.score = hit.score; copy.matched = hit.indices; best = copy
        }
        for extra in [item.subtitle].compactMap({ $0 }) + item.keywords {
            if let hit = FuzzyMatcher.match(query, in: extra), hit.score * 3 / 4 > (best?.score ?? Int.min) {
                var copy = item; copy.score = hit.score * 3 / 4; copy.matched = []; best = copy
            }
        }
        return best
    }

    static func rank(_ items: [PaletteItem], query: String) -> [PaletteItem] {
        items.compactMap { scored($0, query: query) }
            .enumerated()
            .sorted { $0.element.score != $1.element.score ? $0.element.score > $1.element.score : $0.offset < $1.offset }
            .map(\.element)
    }

    static func sections(query rawQuery: String, step: PaletteStep, commands: [PaletteItem], songs: [LibraryTrack],
                         playlists: [MusicPlaylist], playingPlaylistID: String?, recentIDs: [String]) -> [PaletteSection] {
        let query = rawQuery.trimmingCharacters(in: .whitespaces)
        if case .addToPlaylist = step {
            let targets = Workspace.alphabetical(playlists.filter(\.canAddTracks)).map { playlist in
                PaletteItem(id: "dest:\(playlist.id)", title: playlist.name, icon: .artwork(playlist.artwork, seed: playlist.name),
                            hint: "Add", action: .addTracks(toPlaylist: playlist.id))
            }
            let items = query.isEmpty ? targets : rank(targets, query: query)
            return items.isEmpty ? [] : [PaletteSection(group: .destinations, items: items)]
        }

        let playlistItems = Workspace.alphabetical(playlists).map { PaletteCatalog.playlist($0, playing: $0.id == playingPlaylistID) }
        if query.isEmpty {
            var sections: [PaletteSection] = []
            let current = commands.filter { ["favorite-current", "add-current", "reveal-current"].contains($0.id) }
            if !current.isEmpty { sections.append(PaletteSection(group: .nowPlaying, items: current)) }
            let recent = recentIDs.compactMap { id in commands.first { $0.id == id } }.filter { item in !current.contains { $0.id == item.id } }
            if !recent.isEmpty { sections.append(PaletteSection(group: .recent, items: Array(recent.prefix(3)))) }
            sections.append(PaletteSection(group: .playlists, items: Array(playlistItems.prefix(6))))
            let shown = Set(sections.flatMap(\.items).map(\.id))
            let suggested = ["shuffle", "sleep-30", "expand-player", "toggle-sidebar", "settings", "shortcuts"]
                .compactMap { id in commands.first { $0.id == id } }.filter { !shown.contains($0.id) }
            sections.append(PaletteSection(group: .suggestions, items: Array(suggested.prefix(4))))
            return sections
        }

        let library = [
            PaletteItem(id: "playlist:recent", title: "Recently played", icon: .symbol("clock.arrow.circlepath"), keywords: ["history"], hint: "Open", action: .openPlaylist("recent")),
            PaletteItem(id: "playlist:favorites", title: "Favorites", icon: .symbol("star"), keywords: ["loved"], hint: "Open", action: .openPlaylist("favorites"))
        ]
        var songItems = rank(songs.map(PaletteCatalog.song), query: query)
        var listItems = rank(library + playlistItems, query: query)
        var commandItems = rank(commands, query: query)
        var sections: [PaletteSection] = []

        // Top hit: the single strongest row of any kind, lifted out of its group.
        let candidates = [songItems.first, listItems.first, commandItems.first].compactMap { $0 }
        if let top = candidates.max(by: { $0.score < $1.score }), top.score >= 900 {
            sections.append(PaletteSection(group: .topHit, items: [top]))
            songItems.removeAll { $0.id == top.id }
            listItems.removeAll { $0.id == top.id }
            commandItems.removeAll { $0.id == top.id }
        }
        if !songItems.isEmpty || songs.count > songLimit {
            var shown = Array(songItems.prefix(songLimit))
            if songs.count > songLimit {
                shown.append(PaletteItem(id: "all-results", title: "Show all \(songs.count) songs for “\(query)”", icon: .symbol("list.bullet"),
                                         hint: "Open", action: .showAllResults(query)))
            }
            sections.append(PaletteSection(group: .songs, items: shown))
        }
        if !listItems.isEmpty { sections.append(PaletteSection(group: .playlists, items: Array(listItems.prefix(playlistLimit)))) }
        if !commandItems.isEmpty { sections.append(PaletteSection(group: .commands, items: Array(commandItems.prefix(commandLimit)))) }
        return sections
    }
}

// MARK: - View

/// A dark glass panel over the window, modelled on Arc's command bar: a big input, then rows with an
/// icon, a title, and a right-aligned action hint. The highlighted row is a pill tinted by the theme.
struct CommandPaletteView: View {
    @Environment(\.playerTheme) private var theme
    @ObservedObject var model: AppModel
    @ObservedObject var player: PlaybackController
    @ObservedObject var workspace: Workspace
    var themeID: String
    var run: (PaletteItem) -> Void
    @FocusState private var focused: Bool
    @State private var hovered: String?

    private var query: Binding<String> {
        Binding(get: { workspace.palette.query }, set: { workspace.palette.query = $0; workspace.palette.highlight = 0 })
    }

    var body: some View {
        let sections = currentSections()
        let flat = sections.flatMap(\.items)
        GeometryReader { proxy in
            ZStack(alignment: .top) {
                Color.black.opacity(theme.isDark ? 0.18 : 0.06).ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { workspace.closePalette() }
                panel(sections: sections, flat: flat)
                    .frame(width: min(700, proxy.size.width - 120))
                    .padding(.top, max(56, proxy.size.height * 0.17))
            }
        }
        .environment(\.colorScheme, .dark)
        .onAppear {
            focused = true
            workspace.paletteKeys = { key in handle(key) }
            DispatchQueue.main.async { (workspace.window?.firstResponder as? NSTextView)?.moveToEndOfDocument(nil) }
        }
        .onDisappear { workspace.paletteKeys = nil }
        .task(id: searchKey) {
            guard case .root = workspace.palette.step else { return }
            await model.search(workspace.palette.query, catalog: false)
        }
    }

    private var searchKey: String { "\(workspace.palette.query)|\(model.isLive)|\(model.usesMusicApp)" }

    func currentSections() -> [PaletteSection] {
        PaletteEngine.sections(query: workspace.palette.query, step: workspace.palette.step,
                               commands: PaletteCatalog.commands(context), songs: songs,
                               playlists: model.playlists, playingPlaylistID: player.current?.sourcePlaylistID ?? playingPlaylistGuess,
                               recentIDs: UserDefaults.standard.stringArray(forKey: "palette.recent") ?? [])
    }

    private var songs: [LibraryTrack] {
        let query = workspace.palette.query.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return [] }
        // The service filters by substring; drop stale results while a new search is in flight.
        return model.searchResults.filter { $0.matches(query) || FuzzyMatcher.match(query, in: $0.title) != nil }
    }

    private var playingPlaylistGuess: String? {
        guard let current = player.current else { return nil }
        return model.playlists.first { ($0.id == model.selectedID) && model.tracks.contains { $0.id == current.id } }?.id
    }

    private var context: PaletteContext {
        PaletteContext(currentTitle: player.current?.title,
                       currentIsFavorite: player.current.map { model.favorites.contains($0.id) } ?? false,
                       isMusicApp: player.isMusicApp || workspace.debugMusicAppLayout,
                       queueSupported: workspace.queueSupported, shuffle: player.shuffle, repeatAll: player.repeatAll,
                       sleepActive: player.sleepUntil != nil, sidebarCollapsed: workspace.sidebarCollapsed,
                       hasRecent: !model.recentTracks.isEmpty, themeID: themeID)
    }

    private func handle(_ key: PaletteKey) {
        let flat = currentSections().flatMap(\.items)
        switch key {
        case .down: if !flat.isEmpty { workspace.palette.highlight = (workspace.palette.highlight + 1) % flat.count }
        case .up: if !flat.isEmpty { workspace.palette.highlight = (workspace.palette.highlight - 1 + flat.count) % flat.count }
        case .run:
            if flat.indices.contains(workspace.palette.highlight) { run(flat[workspace.palette.highlight]) }
        case .escape:
            if case .addToPlaylist = workspace.palette.step {
                workspace.palette.step = .root; workspace.palette.query = ""; workspace.palette.highlight = 0
            } else if !workspace.palette.query.isEmpty {
                workspace.palette.query = ""; workspace.palette.highlight = 0
            } else {
                workspace.closePalette()
            }
        }
    }

    // MARK: Pieces

    private func panel(sections: [PaletteSection], flat: [PaletteItem]) -> some View {
        VStack(spacing: 0) {
            inputRow
            if !flat.isEmpty {
                Rectangle().fill(.white.opacity(0.08)).frame(height: 1)
                results(sections: sections, flat: flat)
            } else if !workspace.palette.query.isEmpty {
                Rectangle().fill(.white.opacity(0.08)).frame(height: 1)
                Text(model.searching ? "Searching…" : "No matches for “\(workspace.palette.query)”")
                    .font(.system(size: 13)).foregroundStyle(.white.opacity(0.5))
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 22).frame(height: 52)
            }
        }
        .background {
            ZStack {
                VisualEffectBlur(material: .hudWindow)
                Color(red: 0.13, green: 0.13, blue: 0.14).opacity(0.80)
            }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.white.opacity(0.10)))
        .overlay(RoundedRectangle(cornerRadius: 14.5, style: .continuous).stroke(.black.opacity(0.35), lineWidth: 0.5).padding(-0.5))
        .shadow(color: .black.opacity(0.38), radius: 34, y: 16)
        .accessibilityAddTraits(.isModal)
    }

    private var inputRow: some View {
        HStack(spacing: 12) {
            if case let .addToPlaylist(_, label) = workspace.palette.step {
                HStack(spacing: 5) {
                    Image(systemName: "text.badge.plus").font(.system(size: 11, weight: .semibold))
                    Text("Add \(label) to").font(.system(size: 13, weight: .semibold)).lineLimit(1)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 10).frame(height: 26)
                .background(theme.paletteHighlight, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .fixedSize()
            } else {
                Image(systemName: "magnifyingglass").font(.system(size: 15, weight: .medium)).foregroundStyle(.white.opacity(0.75))
            }
            TextField("", text: query, prompt: Text(placeholder).foregroundStyle(.white.opacity(0.42)))
                .textFieldStyle(.plain)
                .font(.system(size: 19, weight: .regular))
                .foregroundStyle(.white)
                .focused($focused)
                .accessibilityLabel("Search music or run a command")
            if model.searching { ProgressView().controlSize(.small).tint(.white) }
        }
        .padding(.horizontal, 20).frame(height: 60)
    }

    private var placeholder: String {
        if case .addToPlaylist = workspace.palette.step { return "Choose a playlist…" }
        return "Search songs, playlists, or commands…"
    }

    private func results(sections: [PaletteSection], flat: [PaletteItem]) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(sections) { section in
                        Text(section.group.rawValue)
                            .font(.system(size: 11, weight: .semibold)).foregroundStyle(.white.opacity(0.42))
                            .padding(.horizontal, 14).padding(.top, 10).padding(.bottom, 4)
                        ForEach(section.items) { item in
                            let index = flat.firstIndex { $0.id == item.id } ?? 0
                            row(item, highlighted: index == workspace.palette.highlight)
                                .id(item.id)
                                .onTapGesture { workspace.palette.highlight = index; run(item) }
                                .onHover { inside in if inside { hovered = item.id } }
                        }
                    }
                }
                .padding(.horizontal, 8).padding(.bottom, 8)
            }
            .frame(maxHeight: 440)
            .fixedSize(horizontal: false, vertical: true)
            .scrollIndicators(.never)
            .onChange(of: workspace.palette.highlight) { _, index in
                if flat.indices.contains(index) { proxy.scrollTo(flat[index].id) }
            }
        }
    }

    private func row(_ item: PaletteItem, highlighted: Bool) -> some View {
        HStack(spacing: 12) {
            icon(item.icon)
            HStack(spacing: 8) {
                emphasized(item)
                    .font(.system(size: 13.5))
                    .lineLimit(1)
                if let subtitle = item.subtitle {
                    Text(subtitle).font(.system(size: 12.5)).foregroundStyle(.white.opacity(0.45)).lineLimit(1)
                }
            }
            Spacer(minLength: 12)
            if let shortcut = item.shortcut, !highlighted {
                HStack(spacing: 3) { ForEach(shortcut.components(separatedBy: " "), id: \.self) { DarkKeyCap($0) } }
            }
            if highlighted || item.shortcut == nil {
                HStack(spacing: 8) {
                    Text(item.hint).font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(.white.opacity(highlighted ? 0.95 : 0.32))
                    Image(systemName: item.opensStep || item.hint == "Open" ? "arrow.right" : "return")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(highlighted ? Color.black.opacity(0.75) : .white.opacity(0.4))
                        .frame(width: 20, height: 20)
                        .background(highlighted ? Color.white.opacity(0.92) : .clear, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(.white.opacity(highlighted ? 0 : 0.18)))
                }
                .opacity(highlighted || hovered == item.id ? 1 : 0.9)
            }
        }
        .padding(.horizontal, 12).frame(height: 42)
        .background {
            if highlighted {
                RoundedRectangle(cornerRadius: 9, style: .continuous).fill(theme.paletteHighlight)
            } else if hovered == item.id {
                RoundedRectangle(cornerRadius: 9, style: .continuous).fill(.white.opacity(0.04))
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(highlighted ? [.isButton, .isSelected] : .isButton)
    }

    @ViewBuilder private func icon(_ icon: PaletteIcon) -> some View {
        switch icon {
        case let .symbol(name):
            Image(systemName: name).font(.system(size: 11.5, weight: .semibold)).foregroundStyle(.white.opacity(0.85))
                .frame(width: 22, height: 22)
                .background(.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        case let .artwork(url, seed):
            Artwork(url: url, seed: seed, size: 22, cornerRadius: 5)
        }
    }

    /// Matched letters in full white and semibold, the rest slightly softer.
    private func emphasized(_ item: PaletteItem) -> Text {
        guard !item.matched.isEmpty else { return Text(item.title).fontWeight(.medium).foregroundColor(.white.opacity(0.92)) }
        let marks = Set(item.matched)
        var result = Text("")
        for (offset, char) in item.title.enumerated() {
            let piece = Text(String(char))
            result = result + (marks.contains(offset) ? piece.fontWeight(.bold).foregroundColor(.white) : piece.fontWeight(.medium).foregroundColor(.white.opacity(0.72)))
        }
        return result
    }
}

struct DarkKeyCap: View {
    var label: String
    init(_ label: String) { self.label = label }
    var body: some View {
        Text(label)
            .font(.system(size: 11, weight: .medium, design: .rounded))
            .foregroundStyle(.white.opacity(0.5))
            .padding(.horizontal, 5).frame(minWidth: 20, minHeight: 19)
            .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
    }
}

struct VisualEffectBlur: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blending: NSVisualEffectView.BlendingMode = .withinWindow
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material; view.blendingMode = blending; view.state = .active
        return view
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) { view.material = material; view.blendingMode = blending }
}
