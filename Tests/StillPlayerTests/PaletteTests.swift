import XCTest
import SwiftUI
import AppKit
import PlayerCore
@testable import StillPlayer

final class PaletteTests: XCTestCase {
    private var context: PaletteContext {
        var context = PaletteContext()
        context.current = SampleLibrary.tracks[1]
        context.isPlaying = true
        context.favorites = ["demo-9"]
        context.playlists = SampleLibrary.playlists.sorted { $0.name < $1.name }
        context.themes = ThemePreset.all.map { ($0.id, $0.name) }
        context.currentTheme = "paper"
        return context
    }

    private func titles(_ query: String, recents: [String] = [], songs: [LibraryTrack] = SampleLibrary.tracks, context: PaletteContext? = nil) -> [String] {
        PaletteSearch.results(query: query, context: context ?? self.context, songs: songs, recents: recents).flatMap(\.items).map(\.title)
    }

    // MARK: Fuzzy matching

    func testWholeWordPrefixBeatsMidWordAndSubsequence() throws {
        let prefix = try XCTUnwrap(Fuzzy.match("fav", in: "Favorite current song"))
        XCTAssertEqual(prefix.indices, [0, 1, 2])
        let wordStart = try XCTUnwrap(Fuzzy.match("cur", in: "Favorite current song"))
        XCTAssertEqual(wordStart.indices, [9, 10, 11])
        let loose = try XCTUnwrap(Fuzzy.match("fcs", in: "Favorite current song"))
        XCTAssertEqual(loose.indices, [0, 9, 17], "Subsequence prefers word starts")
        XCTAssertGreaterThan(prefix.score, wordStart.score)
        XCTAssertGreaterThan(wordStart.score, loose.score)
    }

    func testWordsMatchInAnyOrderAndIgnorePunctuationAndCase() throws {
        XCTAssertNotNil(Fuzzy.match("theme sage", in: "Theme: Sage"))
        XCTAssertNotNil(Fuzzy.match("sage theme", in: "Theme: Sage"))
        XCTAssertNotNil(Fuzzy.match("BEYONCE", in: "Beyoncé"))
        XCTAssertNil(Fuzzy.match("xyz", in: "Theme: Sage"))
        XCTAssertNil(Fuzzy.match("q", in: "Theme"))
        XCTAssertNil(Fuzzy.match("hs", in: "Theme sage"), "Loose matches must start on a word")
        XCTAssertNil(Fuzzy.match("sett", in: "Seek to start"), "Scattered letters are noise, not a match")
        XCTAssertNil(Fuzzy.match("sett", in: "Sleep timer: 15 minutes"))
    }

    // MARK: Ranking

    func testSettingsQueryPutsSettingsFirstAndListsItsSections() {
        let results = titles("sett")
        XCTAssertEqual(results.first, "Settings")
        XCTAssertTrue(results.contains("Settings: Appearance"))
        XCTAssertTrue(results.contains("Settings: Connection"))
        XCTAssertTrue(results.contains("Settings: Updates"))
        XCTAssertTrue(results.contains("Settings: Keyboard"))
        XCTAssertEqual(results.count, 5, "Nothing else matches")
    }

    func testFavQueryMixesTheCommandWithPlaces() {
        let results = titles("fav")
        XCTAssertEqual(Array(results.prefix(2)).sorted(), ["Favorite current song", "Favorites"])
    }

    func testSongsPlaylistsAndCommandsAreMixedInOneRankedList() {
        let sections = PaletteSearch.results(query: "frank", context: context, songs: SampleLibrary.tracks, recents: [])
        XCTAssertEqual(sections.count, 1, "One mixed list, not separate groups")
        let items = sections[0].items
        XCTAssertEqual(Set(items.map(\.title)), ["Pink + White", "Nights"], "Songs match on artist")
        XCTAssertEqual(titles("flow").first, "In the flow")
        XCTAssertTrue(titles("night").contains("Nights"))
    }

    func testThemeSwitchingSkipsTheCurrentTheme() {
        let results = titles("theme")
        XCTAssertTrue(results.contains("Theme: Sage"))
        XCTAssertFalse(results.contains("Theme: Paper"))
    }

    func testRecentCommandsRankHigherAndFillTheEmptyQuery() {
        XCTAssertEqual(titles("sleep").first, "Sleep timer: 15 minutes")
        XCTAssertEqual(titles("sleep", recents: ["cmd.sleep45"]).first, "Sleep timer: 45 minutes")
        let empty = PaletteSearch.results(query: "", context: context, songs: [], recents: ["cmd.sleep45", "cmd.refresh"])
        XCTAssertEqual(empty.map(\.title), ["Now playing", "Recent", "Go to"])
        XCTAssertEqual(empty[0].items.first?.title, "Kerala")
        XCTAssertEqual(empty[1].items.map(\.title), ["Sleep timer: 45 minutes", "Refresh library"])
    }

    func testEmptyQueryWithoutHistorySuggestsCurrentSongActions() {
        let empty = PaletteSearch.results(query: "", context: context, songs: [], recents: [])
        XCTAssertEqual(empty[1].title, "Suggestions")
        XCTAssertEqual(empty[1].items.first?.title, "Favorite current song")
    }

    func testResultLimitsPerKind() {
        let many = (0..<20).map { LibraryTrack(id: "t\($0)", title: "Song \($0)", artist: "A", album: "B", duration: 60) }
        let songs = titles("song", songs: many).filter { $0.hasPrefix("Song ") }
        XCTAssertEqual(songs.count, PaletteSearch.songLimit)
    }

    // MARK: Mode honesty

    func testVolumeOnlyInMusicAppModeAndQueueActionsOnlyWhereSupported() {
        XCTAssertFalse(titles("volume").contains("Volume up"))
        var musicApp = context
        musicApp.isMusicApp = true
        musicApp.queueSupported = false
        XCTAssertTrue(titles("volume", context: musicApp).contains("Volume up"))

        let song = PaletteCatalog.song(SampleLibrary.tracks[4])
        XCTAssertEqual(PaletteCatalog.actions(for: song, context: context).map(\.title),
                       ["Play", "Play next", "Add to queue", "Favorite", "Add to playlist…", "Reveal in playlist"])
        XCTAssertEqual(PaletteCatalog.actions(for: song, context: musicApp).map(\.title),
                       ["Play", "Favorite", "Add to playlist…", "Reveal in playlist"])
        XCTAssertNil(PaletteCatalog.secondary(for: song, context: musicApp))
    }

    func testCurrentSongCommandsNeedACurrentSong() {
        var idle = context
        idle.current = nil
        XCTAssertFalse(titles("current", context: idle).contains("Favorite current song"))
        var loved = context
        loved.favorites.insert(SampleLibrary.tracks[1].id)
        XCTAssertTrue(titles("current", context: loved).contains("Unfavorite current song"))
    }

    // MARK: Actions and nested steps

    func testEveryResultKindHasAnActionPanel() {
        let playlist = PaletteCatalog.playlist(SampleLibrary.playlists[0])
        XCTAssertEqual(PaletteCatalog.actions(for: playlist, context: context).map(\.title), ["Open", "Play", "Shuffle"])
        let current = PaletteCatalog.current(SampleLibrary.tracks[1], isPlaying: true)
        XCTAssertEqual(PaletteCatalog.actions(for: current, context: context).map(\.title),
                       ["Pause", "Next song", "Favorite", "Add to playlist…", "Reveal in playlist"])
        let command = PaletteCatalog.commands(context).first { $0.id == "cmd.refresh" }!
        XCTAssertEqual(PaletteCatalog.actions(for: command, context: context).count, 1)
        XCTAssertEqual(PaletteSearch.filterActions(PaletteCatalog.actions(for: playlist, context: context), query: "shu").map(\.title), ["Shuffle"])
    }

    func testAddToPlaylistStepOnlyOffersEditablePlaylists() {
        var locked = context
        locked.playlists[0].canAddTracks = false
        let track = SampleLibrary.tracks[1]
        let choices = PaletteSearch.playlistChoices(query: "", tracks: [track], context: locked).flatMap(\.items)
        XCTAssertEqual(choices.map(\.title), ["In the flow", "On repeat", "The long way home"])
        XCTAssertEqual(choices.first?.action, .run(.add([track], toPlaylist: "demo-focus")))
        XCTAssertEqual(PaletteSearch.playlistChoices(query: "rep", tracks: [track], context: locked).flatMap(\.items).map(\.title), ["On repeat"])
    }

    @MainActor func testControllerPushesStepsAndBackspaceOrEscapeGoesBack() {
        let palette = PaletteController()
        let context = self.context
        palette.contextProvider = { context }
        palette.songProvider = { SampleLibrary.tracks }
        var ran: [PaletteCommand] = []
        palette.perform = { ran.append($0) }

        palette.open(query: "kerala")
        XCTAssertEqual(palette.highlightedItem?.title, "Kerala")
        XCTAssertTrue(palette.handle(key: 40, flags: .command, characters: "k"), "⌘K opens the action panel")
        XCTAssertEqual(palette.actionsItem?.title, "Kerala")
        palette.actionsQuery = "playlist"
        XCTAssertTrue(palette.handle(key: 36, flags: [], characters: "\r"))
        XCTAssertNil(palette.actionsItem)
        XCTAssertEqual(palette.step?.breadcrumb, "Add to playlist")
        XCTAssertEqual(palette.query, "", "A pushed step starts with an empty input")

        XCTAssertTrue(palette.handle(key: 51, flags: [], characters: nil), "⌫ on an empty input pops the step")
        XCTAssertNil(palette.step)
        XCTAssertEqual(palette.query, "kerala", "Going back restores the query")

        palette.open(step: .addToPlaylist([SampleLibrary.tracks[1]], subject: "Kerala"))
        palette.query = "repeat"
        XCTAssertFalse(palette.handle(key: 51, flags: [], characters: nil), "⌫ with text just edits the text")
        XCTAssertTrue(palette.handle(key: 36, flags: [], characters: "\r"))
        XCTAssertEqual(ran, [.add([SampleLibrary.tracks[1]], toPlaylist: "demo-repeat")])
        XCTAssertFalse(palette.isOpen)

        palette.open()
        XCTAssertTrue(palette.handle(key: 53, flags: [], characters: nil))
        XCTAssertFalse(palette.isOpen, "Esc at the root closes")
    }

    @MainActor func testRunningACommandRemembersIt() {
        UserDefaults.standard.removeObject(forKey: "palette.recents")
        let palette = PaletteController()
        let context = self.context
        palette.contextProvider = { context }
        palette.open(query: "refresh")
        XCTAssertEqual(palette.highlightedItem?.id, "cmd.refresh")
        _ = palette.handle(key: 36, flags: [], characters: "\r")
        XCTAssertEqual(palette.recents.first, "cmd.refresh")
        UserDefaults.standard.removeObject(forKey: "palette.recents")
    }

    // MARK: Merge additions

    func testSelectedSongsGetTheirOwnAddToPlaylistCommandThatLeadsTheEmptyPalette() throws {
        var selected = context
        selected.selectedTracks = Array(SampleLibrary.tracks.prefix(3))
        let empty = PaletteSearch.results(query: "", context: selected, songs: [], recents: ["cmd.addselected", "cmd.refresh"])
        XCTAssertEqual(empty.map(\.title), ["Selection", "Now playing", "Recent", "Go to"])
        XCTAssertEqual(empty[0].items.map(\.title), ["Add 3 selected songs to playlist"], "First row, so Return runs it")
        XCTAssertEqual(empty[2].items.map(\.title), ["Refresh library"], "Not repeated under Recent")
        let item = try XCTUnwrap(PaletteCatalog.commands(selected).first { $0.id == "cmd.addselected" })
        XCTAssertEqual(item.action, .push(.addToPlaylist(selected.selectedTracks, subject: "3 songs")))
        XCTAssertTrue(titles("add current", context: selected).contains("Add current song to playlist"), "The playing song keeps its own command")
        XCTAssertFalse(titles("selected").contains { $0.contains("selected") }, "No selection, no command")
    }

    func testAddStepListsPlaylistsThatAlreadyHaveTheSongLastAndSaysSo() {
        let track = SampleLibrary.tracks[1]
        let choices = PaletteSearch.playlistChoices(query: "", tracks: [track], context: context,
                                                    contents: { $0 == "demo-focus" ? [track.id] : [] }).flatMap(\.items)
        XCTAssertEqual(choices.last?.title, "In the flow")
        XCTAssertEqual(choices.last?.subtitle, "Already in this playlist")
        XCTAssertNotEqual(choices.first?.title, "In the flow")
    }

    func testManySongHitsOfferShowAllResults() {
        let many = (0..<20).map { LibraryTrack(id: "t\($0)", title: "Song \($0)", artist: "A", album: "B", duration: 60) }
        let results = titles("song", songs: many)
        XCTAssertEqual(results.last, "Show all 20 songs for “song”")
        XCTAssertFalse(titles("kerala").contains { $0.hasPrefix("Show all") })
    }

    func testFilterCommandIsInThePalette() {
        XCTAssertTrue(titles("filter").contains("Filter this playlist"))
    }
}

final class PaletteShortcutTests: XCTestCase {
    func testDefaultIsShiftCommandPAndRoundTripsThroughStorage() {
        XCTAssertEqual(PaletteShortcut.standard.display, "⇧⌘P")
        let custom = PaletteShortcut(keyCode: 40, key: "K", modifiers: [.command, .option])
        XCTAssertEqual(PaletteShortcut(storage: custom.storage), custom)
        XCTAssertEqual(custom.display, "⌥⌘K")
        XCTAssertEqual(PaletteShortcut(storage: "garbage"), .standard, "Unreadable settings fall back to the default")
    }

    func testShortcutsThatWouldFireWhileTypingOrClashAreRejected() {
        XCTAssertNotNil(PaletteShortcut(keyCode: 35, key: "P", modifiers: []).problem, "A bare letter would fire while typing")
        XCTAssertNotNil(PaletteShortcut(keyCode: 35, key: "P", modifiers: [.shift]).problem)
        XCTAssertNotNil(PaletteShortcut(keyCode: 35, key: "P", modifiers: [.option]).problem, "⌥P types π")
        XCTAssertEqual(PaletteShortcut(keyCode: 35, key: "P", modifiers: [.command]).problem, "⌘P is already used for Play / Pause.")
        XCTAssertNotNil(PaletteShortcut(keyCode: 1, key: "S", modifiers: [.command]).problem)
        XCTAssertNil(PaletteShortcut.standard.problem)
        XCTAssertNil(PaletteShortcut(keyCode: 49, key: "Space", modifiers: [.option, .command]).problem)
        XCTAssertNil(PaletteShortcut(keyCode: 122, key: "F1", modifiers: []).problem, "Function keys may stand alone")
    }

    func testMenuFormMatchesTheStoredKey() {
        XCTAssertEqual(PaletteShortcut.standard.keyboardShortcut, KeyboardShortcut("p", modifiers: [.command, .shift]))
        XCTAssertNil(PaletteShortcut(keyCode: 122, key: "F1", modifiers: []).keyboardShortcut)
    }

    func testARemovedBindingStaysRemovedAndShowsOnNoMenu() {
        XCTAssertNil(PaletteShortcut.stored(PaletteShortcut.unboundStorage), "Removed means no key at all")
        XCTAssertEqual(PaletteShortcut.stored(PaletteShortcut.standard.storage), .standard)
        XCTAssertEqual(PaletteShortcut.stored("garbage"), .standard, "Only an explicit removal unbinds; bad data falls back")
        let custom = PaletteShortcut(keyCode: 40, key: "K", modifiers: [.command, .option])
        XCTAssertEqual(PaletteShortcut.stored("garbage", default: custom), custom, "Each binding falls back to its own default")
    }

    @MainActor func testWithTheBindingRemovedThePaletteKeyNoLongerOpensThePalette() throws {
        let defaults = UserDefaults.standard
        let saved = defaults.string(forKey: PaletteShortcut.storageKey)
        defer { if let saved { defaults.set(saved, forKey: PaletteShortcut.storageKey) } else { defaults.removeObject(forKey: PaletteShortcut.storageKey) } }
        let event = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.command, .shift], timestamp: 0,
                                                    windowNumber: 0, context: nil, characters: "P", charactersIgnoringModifiers: "p",
                                                    isARepeat: false, keyCode: 35))
        defaults.removeObject(forKey: PaletteShortcut.storageKey)
        XCTAssertEqual(PaletteShortcut.current?.matches(event), true, "Unset means the ⇧⌘P default")
        defaults.set(PaletteShortcut.unboundStorage, forKey: PaletteShortcut.storageKey)
        XCTAssertNil(PaletteShortcut.current)
    }
}
