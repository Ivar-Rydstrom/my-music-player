import Foundation
#if SWIFT_PACKAGE
import PlayerCore
#endif

// The command palette's plain data model: what can be run, how results are matched and ranked, and
// which actions each result offers. No SwiftUI here, so ranking and filtering are unit-testable.

/// Something the palette can do. Executed by `PaletteController.perform`, which the window wires up.
enum PaletteCommand: Hashable {
    case togglePlayback, next, previous, seekToStart
    case setShuffle(Bool), setRepeat(Bool), volume(up: Bool)
    case favoriteCurrent, revealCurrent
    case sleep(minutes: Int?)
    case toggleSidebar, expandPlayer, refresh, clearRecent, checkForUpdates, showShortcuts, filterPlaylist
    case showResults(String)
    case settings(tab: String?), theme(String)
    case open(String)
    case playPlaylist(String, shuffled: Bool)
    case play(LibraryTrack), playRelated(LibraryTrack), playNext([LibraryTrack]), addToQueue([LibraryTrack])
    case favorite(LibraryTrack), reveal(LibraryTrack)
    case add([LibraryTrack], toPlaylist: String)
}

/// A nested step pushed onto the palette. Its title shows as a breadcrumb in the input.
enum PaletteStep: Hashable {
    case addToPlaylist([LibraryTrack], subject: String)
    var breadcrumb: String { "Add to playlist" }
    var subject: String { switch self { case .addToPlaylist(_, let subject): subject } }
    var placeholder: String { "Choose a playlist…" }
}

enum PaletteAction: Hashable {
    case run(PaletteCommand)
    case push(PaletteStep)
}

enum PaletteKind: Hashable {
    case command
    case song(LibraryTrack)
    case playlist(id: String)
    case current(LibraryTrack)
}

enum PaletteIcon: Hashable {
    case symbol(String)
    case artwork(URL?, seed: String)
    case swatch(String)
}

struct PaletteItem: Identifiable, Hashable {
    var id: String
    var kind: PaletteKind
    var title: String
    var subtitle = ""
    var keywords: [String] = []
    var icon: PaletteIcon
    var shortcut: String?
    /// What Return does, shown on the highlighted row and in the footer ("Play", "Open", "Run").
    var hint: String
    var action: PaletteAction
    /// Overrides the kind's label on the right of a row.
    var label: String?

    var typeLabel: String {
        if let label { return label }
        return switch kind {
        case .command: "Command"
        case .song: "Song"
        case .playlist: "Playlist"
        case .current: "Now playing"
        }
    }
    var isSong: Bool { if case .song = kind { true } else if case .current = kind { true } else { false } }
    var track: LibraryTrack? {
        switch kind {
        case .song(let track), .current(let track): track
        default: nil
        }
    }
}

struct PaletteSection: Identifiable, Equatable {
    var title: String?
    var items: [PaletteItem]
    var id: String { title ?? "results" }
}

/// A snapshot of what the palette needs to know about the app.
struct PaletteContext {
    var current: LibraryTrack?
    var isPlaying = false
    var favorites: Set<String> = []
    var shuffle = false
    var repeatAll = false
    var isMusicApp = false
    var queueSupported = true
    var sleepActive = false
    var sidebarCollapsed = false
    var hasRecentlyPlayed = false
    var playlists: [MusicPlaylist] = []
    var themes: [(id: String, name: String)] = []
    var currentTheme = ""
    var selectedID: String?
    /// Songs selected in the list, so "Add selected songs to playlist" can act on them.
    var selectedTracks: [LibraryTrack] = []
    /// Each command's current key, shown beside it. Removed keys are simply absent.
    var keys: [ShortcutAction: String] = PaletteContext.standardKeys

    static let standardKeys = Dictionary(uniqueKeysWithValues: ShortcutAction.allCases.compactMap { action in
        action.standard.map { (action, $0.display) }
    })
}

// MARK: - Fuzzy matching

struct FuzzyMatch: Equatable {
    var score: Int
    /// Character offsets in the candidate that matched, for emphasis.
    var indices: [Int]
}

enum Fuzzy {
    /// Matches every query word against the candidate. Whole-phrase and word-start matches rank
    /// highest; a loose subsequence ("plps" → "Play/Pause") still matches, but low.
    static func match(_ query: String, in candidate: String) -> FuzzyMatch? {
        let needle = fold(query).trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else { return FuzzyMatch(score: 0, indices: []) }
        let hay = Array(fold(candidate))
        let starts = wordStarts(hay)

        // 1. The whole query appears as written.
        if let range = bestOccurrence(of: Array(needle), in: hay, starts: starts) {
            var score = 1000 - range.lowerBound * 2 - (hay.count - needle.count)
            if range.lowerBound == 0 { score += 400 } else if starts.contains(range.lowerBound) { score += 250 }
            return FuzzyMatch(score: score, indices: Array(range))
        }
        // 2. Every word appears somewhere (any order), ideally at word starts.
        let words = needle.split(separator: " ").map(Array.init)
        if words.count > 1 {
            var indices: [Int] = [], score = 600
            for word in words {
                guard let range = bestOccurrence(of: word, in: hay, starts: starts) else { indices = []; score = 0; break }
                score += starts.contains(range.lowerBound) ? 60 : 0
                score -= range.lowerBound
                indices += Array(range)
            }
            if score > 0 { return FuzzyMatch(score: score, indices: indices.sorted()) }
        }
        // 3. Chunks of a subsequence: each letter continues the previous match or starts a word
        //    ("fcs" → Favorite current song). Loose scatter like "sett" → "Seek to start" is rejected.
        let compact = Array(needle.replacingOccurrences(of: " ", with: ""))
        guard compact.count >= 2 else { return nil }
        var indices: [Int] = [], position = 0, score = 300
        for (offset, char) in compact.enumerated() {
            let index: Int
            if let last = indices.last, last + 1 < hay.count, hay[last + 1] == char {
                index = last + 1
                score += 15
            } else if let start = (position..<hay.count).first(where: { hay[$0] == char && starts.contains($0) }) {
                index = start
                score += 25 - (offset == 0 ? 0 : min(start - position, 20))
            } else {
                return nil
            }
            indices.append(index)
            position = index + 1
        }
        return FuzzyMatch(score: max(score, 1), indices: indices)
    }

    static func fold(_ text: String) -> String {
        String(text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).map { $0.isLetter || $0.isNumber ? $0 : " " })
    }

    private static func wordStarts(_ hay: [Character]) -> Set<Int> {
        var starts = Set<Int>()
        for index in hay.indices where hay[index] != " " && (index == 0 || hay[index - 1] == " ") { starts.insert(index) }
        return starts
    }

    private static func bestOccurrence(of needle: [Character], in hay: [Character], starts: Set<Int>) -> Range<Int>? {
        guard !needle.isEmpty, needle.count <= hay.count else { return nil }
        var first: Range<Int>?
        for start in 0...(hay.count - needle.count) where hay[start] == needle[0] {
            if Array(hay[start..<start + needle.count]) == needle {
                if starts.contains(start) { return start..<start + needle.count }
                if first == nil { first = start..<start + needle.count }
            }
        }
        return first
    }
}

// MARK: - Catalog

enum PaletteCatalog {
    static func commands(_ context: PaletteContext) -> [PaletteItem] {
        var items: [PaletteItem] = []
        func add(_ id: String, _ title: String, _ symbol: String, _ command: PaletteCommand, shortcut: String? = nil, keywords: [String] = [], hint: String = "Run") {
            items.append(PaletteItem(id: "cmd." + id, kind: .command, title: title, keywords: keywords, icon: .symbol(symbol),
                                     shortcut: shortcut, hint: hint, action: .run(command)))
        }
        let hasCurrent = context.current != nil
        // Playback
        if hasCurrent {
            add("toggle", context.isPlaying ? "Pause" : "Play", context.isPlaying ? "pause.fill" : "play.fill", .togglePlayback,
                shortcut: context.keys[.playPauseQuick] ?? context.keys[.playPause], keywords: ["play pause", "resume", "stop"])
            add("next", "Next song", "forward.fill", .next, shortcut: context.keys[.nextSong], keywords: ["skip"])
            add("previous", "Previous song", "backward.fill", .previous, shortcut: context.keys[.previousSong], keywords: ["back"])
            add("seek", "Seek to start", "backward.end.fill", .seekToStart, keywords: ["restart", "beginning"])
        }
        add("shuffle", context.shuffle ? "Shuffle off" : "Shuffle on", "shuffle", .setShuffle(!context.shuffle), keywords: ["shuffle"])
        add("repeat", context.repeatAll ? "Repeat off" : "Repeat on", "repeat", .setRepeat(!context.repeatAll), keywords: ["repeat", "loop"])
        if context.isMusicApp {
            add("volup", "Volume up", "speaker.wave.3.fill", .volume(up: true), shortcut: context.keys[.volumeUp], keywords: ["louder"])
            add("voldown", "Volume down", "speaker.wave.1.fill", .volume(up: false), shortcut: context.keys[.volumeDown], keywords: ["quieter"])
        }
        // Current song
        if let current = context.current {
            let favorite = context.favorites.contains(current.id)
            add("favcurrent", favorite ? "Unfavorite current song" : "Favorite current song", favorite ? "star.slash" : "star",
                .favoriteCurrent, shortcut: context.keys[.favoriteCurrent], keywords: ["love", "like", "star", current.title])
            items.append(PaletteItem(id: "cmd.addcurrent", kind: .command, title: "Add current song to playlist", subtitle: current.title,
                                     keywords: ["playlist", current.title], icon: .symbol("text.badge.plus"), hint: "Choose",
                                     action: .push(.addToPlaylist([current], subject: current.title))))
            add("revealcurrent", "Reveal current song in playlist", "scope", .revealCurrent, shortcut: context.keys[.revealCurrent], keywords: ["show", "find", "locate", "go to"])
        }
        // Selected songs (in the list)
        if !context.selectedTracks.isEmpty {
            let tracks = context.selectedTracks
            let subject = tracks.count == 1 ? tracks[0].title : "\(tracks.count) songs"
            let title = tracks.count == 1 ? "Add selected song to playlist" : "Add \(tracks.count) selected songs to playlist"
            items.append(PaletteItem(id: "cmd.addselected", kind: .command, title: title, subtitle: tracks.count == 1 ? tracks[0].title : "",
                                     keywords: ["playlist", "selection", "add to"], icon: .symbol("text.badge.plus"), hint: "Choose",
                                     action: .push(.addToPlaylist(tracks, subject: subject))))
        }
        // Utilities
        for minutes in [15, 30, 45, 60] {
            add("sleep\(minutes)", "Sleep timer: \(minutes) minutes", "moon", .sleep(minutes: minutes), keywords: ["sleep", "timer", "pause after"])
        }
        if context.sleepActive { add("sleepcancel", "Cancel sleep timer", "moon.zzz", .sleep(minutes: nil), keywords: ["sleep", "timer"]) }
        add("sidebar", context.sidebarCollapsed ? "Show sidebar" : "Hide sidebar", "sidebar.left", .toggleSidebar, shortcut: context.keys[.toggleSidebar],
            keywords: ["toggle sidebar", "collapse"])
        add("player", context.queueSupported ? "Show player and queue" : "Expand player", "rectangle.expand.vertical", .expandPlayer,
            shortcut: context.keys[.expandPlayer], keywords: context.queueSupported ? ["queue", "up next", "now playing"] : ["now playing", "volume"])
        add("filter", "Filter this playlist", "line.3.horizontal.decrease", .filterPlaylist, shortcut: context.keys[.filter], keywords: ["find", "search in"])
        add("refresh", "Refresh library", "arrow.clockwise", .refresh, shortcut: context.keys[.refresh], keywords: ["reload", "sync"])
        if context.hasRecentlyPlayed { add("clearrecent", "Clear recently played", "clock.badge.xmark", .clearRecent, keywords: ["history"]) }
        add("updates", "Check for updates", "arrow.down.circle", .checkForUpdates, keywords: ["update", "version"])
        add("shortcuts", "Keyboard shortcuts", "keyboard", .showShortcuts, shortcut: context.keys[.shortcutsHelp], keywords: ["keys", "help", "hotkeys"])
        // Settings
        add("settings", "Settings", "gearshape", .settings(tab: nil), shortcut: context.keys[.settings], keywords: ["preferences", "options"], hint: "Open")
        add("settings.appearance", "Settings: Appearance", "paintpalette", .settings(tab: "appearance"), keywords: ["settings", "theme", "colors"], hint: "Open")
        add("settings.connection", "Settings: Connection", "link", .settings(tab: "connection"), keywords: ["settings", "music app", "apple music", "account"], hint: "Open")
        add("settings.updates", "Settings: Updates", "arrow.down.circle", .settings(tab: "updates"), keywords: ["settings"], hint: "Open")
        add("settings.keyboard", "Settings: Keyboard", "command", .settings(tab: "keyboard"),
            keywords: ["settings", "shortcut", "keybinding", "hotkey", "palette"], hint: "Open")
        for theme in context.themes where theme.id != context.currentTheme {
            items.append(PaletteItem(id: "cmd.theme." + theme.id, kind: .command, title: "Theme: \(theme.name)", keywords: ["appearance", "color"],
                                     icon: .swatch(theme.id), hint: "Switch", action: .run(.theme(theme.id))))
        }
        // Places
        items.append(place("recent", "Recently played", "clock.arrow.circlepath"))
        items.append(place("favorites", "Favorites", "star"))
        return items
    }

    static func place(_ id: String, _ title: String, _ symbol: String) -> PaletteItem {
        PaletteItem(id: "place." + id, kind: .playlist(id: id), title: title, icon: .symbol(symbol), hint: "Open", action: .run(.open(id)), label: "Library")
    }

    static func playlist(_ playlist: MusicPlaylist, playing: Bool = false) -> PaletteItem {
        PaletteItem(id: "playlist." + playlist.id, kind: .playlist(id: playlist.id), title: playlist.name,
                    subtitle: playlist.tracks.isEmpty ? "Playlist" : "\(playlist.tracks.count) songs",
                    icon: .artwork(playlist.artwork, seed: playlist.name), hint: "Open", action: .run(.open(playlist.id)))
    }

    static func song(_ track: LibraryTrack) -> PaletteItem {
        PaletteItem(id: "song." + track.id, kind: .song(track), title: track.title, subtitle: "\(track.artist) — \(track.album)",
                    keywords: [track.artist, track.album], icon: .artwork(track.artwork, seed: track.album), hint: "Play", action: .run(.play(track)))
    }

    static func current(_ track: LibraryTrack, isPlaying: Bool) -> PaletteItem {
        PaletteItem(id: "current." + track.id, kind: .current(track), title: track.title, subtitle: "\(track.artist) — \(isPlaying ? "Playing" : "Paused")",
                    keywords: [track.artist, "now playing", "current"], icon: .artwork(track.artwork, seed: track.album),
                    hint: isPlaying ? "Pause" : "Play", action: .run(.togglePlayback))
    }

    /// The action panel for a result (→ or ⌘K). The first entry is what Return does.
    static func actions(for item: PaletteItem, context: PaletteContext) -> [PaletteItem] {
        func action(_ id: String, _ title: String, _ symbol: String, _ action: PaletteAction, shortcut: String? = nil) -> PaletteItem {
            PaletteItem(id: item.id + ".act." + id, kind: .command, title: title, icon: .symbol(symbol), shortcut: shortcut,
                        hint: title.hasSuffix("…") ? "Choose" : "Run", action: action)
        }
        switch item.kind {
        case .song(let track), .current(let track):
            let isCurrent: Bool = { if case .current = item.kind { return true }; return false }()
            let favorite = context.favorites.contains(track.id)
            var list: [PaletteItem] = []
            if isCurrent {
                list.append(action("toggle", context.isPlaying ? "Pause" : "Play", context.isPlaying ? "pause.fill" : "play.fill", .run(.togglePlayback), shortcut: "↵"))
                list.append(action("next", "Next song", "forward.fill", .run(.next)))
            } else {
                list.append(action("play", "Play", "play.fill", .run(.play(track)), shortcut: "↵"))
                // Only Music continues a lone song with related songs (Autoplay).
                if context.isMusicApp { list.append(action("related", "Play related", "dot.radiowaves.left.and.right", .run(.playRelated(track)))) }
            }
            if context.queueSupported && !isCurrent {
                list.append(action("next", "Play next", "text.line.first.and.arrowtriangle.forward", .run(.playNext([track])), shortcut: "⌘↵"))
                list.append(action("queue", "Add to queue", "text.line.last.and.arrowtriangle.forward", .run(.addToQueue([track]))))
            }
            list.append(action("favorite", favorite ? "Unfavorite" : "Favorite", favorite ? "star.slash" : "star", .run(.favorite(track)), shortcut: "⌘L"))
            list.append(action("add", "Add to playlist…", "text.badge.plus", .push(.addToPlaylist([track], subject: track.title))))
            list.append(action("reveal", "Reveal in playlist", "scope", .run(isCurrent ? .revealCurrent : .reveal(track))))
            return list
        case .playlist(let id):
            return [
                action("open", "Open", "arrow.up.forward.square", .run(.open(id)), shortcut: "↵"),
                action("play", "Play", "play.fill", .run(.playPlaylist(id, shuffled: false))),
                action("shuffle", "Shuffle", "shuffle", .run(.playPlaylist(id, shuffled: true)), shortcut: "⌘↵")
            ]
        case .command:
            return [action("run", item.hint == "Run" ? "Run command" : item.hint, item.icon.symbolName ?? "command", item.action, shortcut: "↵")]
        }
    }

    /// ⌘↵ from the result list: Play next for songs (where the queue is real), Shuffle for playlists.
    static func secondary(for item: PaletteItem, context: PaletteContext) -> PaletteAction? {
        switch item.kind {
        case .song(let track): context.queueSupported ? .run(.playNext([track])) : nil
        case .playlist(let id): .run(.playPlaylist(id, shuffled: true))
        default: nil
        }
    }
}

extension PaletteIcon {
    var symbolName: String? { if case .symbol(let name) = self { name } else { nil } }
}

// MARK: - Search

enum PaletteSearch {
    static let songLimit = 6
    static let playlistLimit = 4
    static let commandLimit = 8

    /// Root level. Empty query: now playing, recent commands (or suggestions), playlists.
    /// Otherwise one mixed list ranked by match quality, commands among songs and playlists.
    static func results(query: String, context: PaletteContext, songs: [LibraryTrack], recents: [String]) -> [PaletteSection] {
        let commands = PaletteCatalog.commands(context)
        let playlists = context.playlists.map { PaletteCatalog.playlist($0) }
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            var sections: [PaletteSection] = []
            let byID = Dictionary(commands.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            // A live selection is the most likely reason to open the palette, so it leads and is highlighted.
            if let selected = byID["cmd.addselected"] {
                sections.append(PaletteSection(title: "Selection", items: [selected]))
            }
            if let current = context.current {
                sections.append(PaletteSection(title: "Now playing", items: [PaletteCatalog.current(current, isPlaying: context.isPlaying)]))
            }
            let recent = recents.compactMap { byID[$0] }.prefix(4)
            if !recent.isEmpty {
                sections.append(PaletteSection(title: "Recent", items: recent.filter { $0.id != "cmd.addselected" }))
            } else {
                let suggested = ["cmd.favcurrent", "cmd.addcurrent", "cmd.shuffle", "cmd.sleep30", "cmd.settings"].compactMap { byID[$0] }
                sections.append(PaletteSection(title: "Suggestions", items: Array(suggested.prefix(4))))
            }
            let shown = Set(sections.flatMap(\.items).map(\.id))
            let places = [PaletteCatalog.place("recent", "Recently played", "clock.arrow.circlepath"), PaletteCatalog.place("favorites", "Favorites", "star")]
            sections.append(PaletteSection(title: "Go to", items: (places + playlists).filter { !shown.contains($0.id) }.prefix(6).map { $0 }))
            return sections
        }

        let recentBoost = Dictionary(recents.enumerated().map { ($0.element, 40 - $0.offset * 5) }, uniquingKeysWith: { first, _ in first })
        var seen = Set<String>()
        let uniqueSongs = songs.filter { seen.insert($0.id).inserted }.map(PaletteCatalog.song)
        func ranked(_ items: [PaletteItem], limit: Int, boost: Int) -> [(PaletteItem, Int)] {
            items.compactMap { item -> (PaletteItem, Int)? in
                guard let score = score(trimmed, item) else { return nil }
                return (item, score + boost + (recentBoost[item.id] ?? 0))
            }
            .sorted { $0.1 == $1.1 ? $0.0.title.localizedStandardCompare($1.0.title) == .orderedAscending : $0.1 > $1.1 }
            .prefix(limit).map { $0 }
        }
        let songHits = ranked(uniqueSongs, limit: .max, boost: 10)
        var merged = (ranked(commands, limit: commandLimit, boost: 0)
                      + ranked(playlists, limit: playlistLimit, boost: 20)
                      + songHits.prefix(songLimit))
            .sorted { $0.1 == $1.1 ? $0.0.title.localizedStandardCompare($1.0.title) == .orderedAscending : $0.1 > $1.1 }
            .map(\.0)
        if songHits.count > songLimit {
            merged.append(PaletteItem(id: "results." + trimmed, kind: .command, title: "Show all \(songHits.count) songs for “\(trimmed)”",
                                      icon: .symbol("list.bullet.rectangle"), hint: "Show", action: .run(.showResults(trimmed)), label: "Results"))
        }
        return merged.isEmpty ? [] : [PaletteSection(title: nil, items: merged)]
    }

    /// Title matches count fully; subtitles and keywords count, but less.
    static func score(_ query: String, _ item: PaletteItem) -> Int? {
        let title = Fuzzy.match(query, in: item.title)?.score
        let subtitle = item.isSong ? Fuzzy.match(query, in: item.subtitle).map { $0.score * 7 / 10 } : nil
        let keyword = item.keywords.compactMap { Fuzzy.match(query, in: $0)?.score }.max().map { $0 * 6 / 10 }
        return [title, subtitle, keyword].compactMap { $0 }.max()
    }

    /// The "Add to playlist" step: only playlists that accept songs.
    /// Playlists that already hold every one of the songs are listed last and say so.
    static func playlistChoices(query: String, tracks: [LibraryTrack], context: PaletteContext,
                                contents: (String) -> Set<String> = { _ in [] }) -> [PaletteSection] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        let ids = Set(tracks.map(\.id))
        let editable = context.playlists.filter(\.canAddTracks).map { ($0, !ids.isEmpty && ids.isSubset(of: contents($0.id))) }
        let ordered = editable.filter { !$0.1 } + editable.filter(\.1)
        let items: [PaletteItem] = ordered.map { playlist, already in
            let count = playlist.tracks.isEmpty ? "" : "\(playlist.tracks.count) songs"
            let note = tracks.count == 1 ? "Already in this playlist" : "Already has these songs"
            return PaletteItem(id: "choose." + playlist.id, kind: .command, title: playlist.name,
                               subtitle: already ? note : count,
                               icon: .artwork(playlist.artwork, seed: playlist.name), hint: already ? "Add again" : "Add",
                               action: .run(.add(tracks, toPlaylist: playlist.id)), label: already ? "Added" : "Playlist")
        }
        guard !trimmed.isEmpty else { return [PaletteSection(title: "Playlists", items: items)] }
        var scored: [(item: PaletteItem, score: Int, order: Int)] = []
        for (offset, item) in items.enumerated() {
            guard let match = Fuzzy.match(trimmed, in: item.title) else { continue }
            scored.append((item, match.score - (item.label == "Added" ? 500 : 0), offset))
        }
        scored.sort { $0.score == $1.score ? $0.order < $1.order : $0.score > $1.score }
        let filtered = scored.map(\.item)
        return [PaletteSection(title: trimmed.isEmpty ? "Playlists" : nil, items: filtered)]
    }

    static func filterActions(_ actions: [PaletteItem], query: String) -> [PaletteItem] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return actions }
        return actions.filter { Fuzzy.match(trimmed, in: $0.title) != nil }
    }
}
