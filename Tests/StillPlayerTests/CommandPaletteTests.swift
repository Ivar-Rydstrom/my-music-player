import XCTest
import PlayerCore
@testable import StillPlayer

final class CommandPaletteTests: XCTestCase {
    private let playing = PaletteContext(currentTitle: "Kerala", currentIsFavorite: false, themeID: "paper")

    private func titles(_ sections: [PaletteSection], _ group: PaletteGroup) -> [String] {
        sections.first { $0.group == group }?.items.map(\.title) ?? []
    }

    private func sections(_ query: String, context: PaletteContext? = nil, songs: [LibraryTrack] = [],
                          playlists: [MusicPlaylist] = SampleLibrary.playlists, step: PaletteStep = .root,
                          recent: [String] = []) -> [PaletteSection] {
        PaletteEngine.sections(query: query, step: step, commands: PaletteCatalog.commands(context ?? playing), songs: songs,
                               playlists: playlists, playingPlaylistID: nil, recentIDs: recent)
    }

    func testFuzzyMatchRequiresEveryLetterInOrder() {
        XCTAssertNotNil(FuzzyMatcher.match("tsd", in: "Toggle sidebar"))
        XCTAssertNil(FuzzyMatcher.match("xyz", in: "Toggle sidebar"))
        XCTAssertNil(FuzzyMatcher.match("rabedis", in: "Toggle sidebar"), "Letters out of order don't match")
        XCTAssertEqual(FuzzyMatcher.match("sid", in: "Hide sidebar")?.indices, [5, 6, 7])
    }

    func testContiguousPrefixAndWordStartsRankHigher() throws {
        let prefix = try XCTUnwrap(FuzzyMatcher.match("fav", in: "Favorite “Kerala”")).score
        let wordStart = try XCTUnwrap(FuzzyMatcher.match("fav", in: "Show favorites")).score
        let scattered = try XCTUnwrap(FuzzyMatcher.match("fav", in: "Fade a view")).score
        XCTAssertGreaterThan(prefix, wordStart)
        XCTAssertGreaterThan(wordStart, scattered)
        let initials = try XCTUnwrap(FuzzyMatcher.match("ts", in: "Toggle sidebar")).score
        let middle = try XCTUnwrap(FuzzyMatcher.match("ts", in: "Bitstream")).score
        XCTAssertGreaterThan(middle, 0)
        XCTAssertNotNil(FuzzyMatcher.match("ts", in: "Toggle sidebar")?.indices.first { $0 == 7 }, "Prefers the word start of “sidebar”")
        _ = initials
    }

    func testFavFindsTheFavoritesListThenTheFavoriteCommand() {
        let result = sections("fav")
        XCTAssertEqual(titles(result, .topHit), ["Favorites"])
        XCTAssertFalse(titles(result, .playlists).contains("Favorites"), "The top hit isn't repeated in its group")
        XCTAssertEqual(titles(result, .commands).first, "Favorite “Kerala”")
    }

    func testTypingSettingsFindsSettingsFirstThenItsSections() {
        let result = sections("sett")
        XCTAssertEqual(titles(result, .topHit), ["Settings"])
        XCTAssertEqual(Array(titles(result, .commands).prefix(3)), ["Settings: Appearance", "Settings: Connection", "Settings: Updates"])
    }

    func testKeywordsFindCommandsWithoutEmphasis() throws {
        let result = sections("prefs")
        let item = try XCTUnwrap(result.flatMap(\.items).first)
        XCTAssertEqual(item.action, .settings(nil))
        XCTAssertTrue(item.matched.isEmpty)
    }

    func testThemeCommandsSkipTheCurrentTheme() {
        let all = PaletteCatalog.commands(playing).map(\.title)
        XCTAssertTrue(all.contains("Theme: Sage"))
        XCTAssertFalse(all.contains("Theme: Paper"))
    }

    func testMusicAppVolumeCommandsOnlyInMusicAppMode() {
        XCTAssertFalse(PaletteCatalog.commands(playing).contains { $0.id == "volume-up" })
        var musicApp = playing; musicApp.isMusicApp = true
        XCTAssertTrue(PaletteCatalog.commands(musicApp).contains { $0.id == "volume-up" })
    }

    func testNoCurrentSongMeansNoCurrentSongCommands() {
        let idle = PaletteContext(currentTitle: nil)
        XCTAssertFalse(PaletteCatalog.commands(idle).contains { $0.action == .favoriteCurrent || $0.action == .revealCurrent })
        XCTAssertNil(sections("", context: idle).first { $0.group == .nowPlaying })
    }

    func testMixedResultsAreGroupedSongsPlaylistsCommands() {
        let result = sections("on", songs: SampleLibrary.tracks.filter { $0.matches("on") })
        XCTAssertEqual(result.first?.group, .topHit)
        XCTAssertEqual(result.map(\.group), [.topHit, .songs, .playlists, .commands])
        XCTAssertLessThanOrEqual(titles(result, .songs).count, PaletteEngine.songLimit + 1)
        XCTAssertTrue(titles(result, .songs).last?.hasPrefix("Show all") ?? false, "More songs than fit offers the full list")
    }

    func testPlaylistsMatchByName() {
        let result = sections("long way")
        XCTAssertEqual(titles(result, .topHit), ["The long way home"])
        if case .openPlaylist(let id) = result[0].items[0].action { XCTAssertEqual(id, "demo-drive") } else { XCTFail() }
    }

    func testEmptyQueryShowsNowPlayingRecentPlaylistsAndSuggestions() {
        let result = sections("", recent: ["sleep-30", "theme-sage"])
        XCTAssertEqual(result.map(\.group), [.nowPlaying, .recent, .playlists, .suggestions])
        XCTAssertEqual(titles(result, .recent), ["Sleep timer: 30 minutes", "Theme: Sage"])
        XCTAssertEqual(titles(result, .playlists), ["After hours", "In the flow", "On repeat", "The long way home"])
        XCTAssertFalse(titles(result, .suggestions).contains("Sleep timer: 30 minutes"), "Suggestions don't repeat recents")
    }

    func testAddToPlaylistStepOnlyOffersEditablePlaylists() {
        var lists = SampleLibrary.playlists
        lists[1].canAddTracks = false
        let step = PaletteStep.addToPlaylist(tracks: [SampleLibrary.tracks[1]], label: "“Kerala”")
        let all = sections("", playlists: lists, step: step)
        XCTAssertEqual(all.map(\.group), [.destinations])
        XCTAssertFalse(titles(all, .destinations).contains(lists[1].name))
        XCTAssertEqual(titles(sections("rep", playlists: lists, step: step), .destinations), ["On repeat"])
    }
}
