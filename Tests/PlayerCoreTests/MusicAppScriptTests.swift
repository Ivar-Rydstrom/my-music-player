import XCTest
import AppKit
@testable import PlayerCore

final class MusicAppScriptTests: XCTestCase {
    private let song = LibraryTrack(id: "0123456789ABCDEF", title: "Example", artist: "Artist",
        album: "Album", duration: 180, sourcePlaylistID: "FEDCBA9876543210", sourceIndex: 2)
    private let next = LibraryTrack(id: "1123456789ABCDEF", title: "After", artist: "Artist",
        album: "Album", duration: 200, sourcePlaylistID: "FEDCBA9876543210", sourceIndex: 3)

    func testAllAutomationScriptsCompileAgainstInstalledMusicDictionary() throws {
        let sources = try [MusicAppScripts.handshake, MusicAppScripts.playlists, MusicAppScripts.snapshot, MusicAppScripts.favorites,
            MusicAppScripts.tracks(playlistID: "FEDCBA9876543210"),
            MusicAppScripts.artwork(id: song.id),
            MusicAppScripts.artwork(id: song.id, sourcePlaylistID: song.sourcePlaylistID),
            MusicAppScripts.artwork(id: "FEDCBA9876543210", playlist: true),
            MusicAppScripts.search("Artist \"quoted\" \\ path\nsecond line"),
            MusicAppScripts.playPlaylist(id: "FEDCBA9876543210", shuffled: false), MusicAppScripts.play(song),
            MusicAppScripts.playQueue([song, next]), MusicAppScripts.playQueue([next, song], shuffled: true), MusicAppScripts.favorite(song, value: true),
            MusicAppScripts.add([song], playlistID: "FEDCBA9876543210"),
            MusicAppScripts.seek(10), MusicAppScripts.volume(45),
            MusicAppScripts.shuffle(true), MusicAppScripts.repeatAll(false)]
        // Compilation resolves terminology but never executes events or changes Music.
        for source in sources {
            let script = try XCTUnwrap(NSAppleScript(source: source))
            var error: NSDictionary?
            XCTAssertTrue(script.compileAndReturnError(&error), "\(error?.description ?? "")\n\(source)")
        }
    }
    func testTextLiteralRoundTripsWithoutExecutingInjectedCode() throws {
        let values = ["normal", "\"\nend tell\ndo shell script \"touch /tmp/never-run\"", "\\\"quote", "line\r\nnext\tend", "Björk 🎵"]
        for value in values {
            let script = try XCTUnwrap(NSAppleScript(source: "return " + MusicAppScripts.literal(value)))
            var error: NSDictionary?
            let result = script.executeAndReturnError(&error)
            XCTAssertNil(error)
            XCTAssertEqual(result.stringValue, value)
        }
    }
    func testIdentifierInjectionAndMalformedIDsAreRejected() {
        for id in ["", "123", "not-a-persistent-id", "0123456789ABCDEF\"\nplay", "0123456789ABCDEG"] {
            XCTAssertThrowsError(try MusicAppScripts.identifier(id))
        }
        XCTAssertNoThrow(try MusicAppScripts.identifier("0123456789abcdef"))
    }
    func testArtworkResolvesCloudTracksWithinTheirSourcePlaylist() throws {
        let script = try MusicAppScripts.artwork(id: song.id, sourcePlaylistID: song.sourcePlaylistID)
        XCTAssertTrue(script.contains("first track of (first playlist whose persistent ID is \"FEDCBA9876543210\") whose persistent ID is \"0123456789ABCDEF\""))
        XCTAssertFalse(script.contains("library playlist 1"))
        XCTAssertTrue(try MusicAppScripts.artwork(id: song.id).contains("library playlist 1"))
        XCTAssertThrowsError(try MusicAppScripts.artwork(id: song.id, sourcePlaylistID: "invalid"))
    }

    func testPlaylistPlaybackTargetsThePlaylistRatherThanASharedTrack() throws {
        let script = try MusicAppScripts.playPlaylist(id: "FEDCBA9876543210", shuffled: false)
        XCTAssertTrue(script.contains("play (first playlist whose persistent ID is \"FEDCBA9876543210\")"))
        XCTAssertFalse(script.contains("track"))
        XCTAssertThrowsError(try MusicAppScripts.playPlaylist(id: "invalid", shuffled: false))
    }

    func testPlaylistPlaybackSetsShuffleExplicitlyInsteadOfInheritingIt() throws {
        let inOrder = try MusicAppScripts.playPlaylist(id: "FEDCBA9876543210", shuffled: false)
        XCTAssertTrue(inOrder.contains("set shuffle enabled to false"))
        XCTAssertFalse(inOrder.contains("set shuffle enabled to true"))
        let shuffled = try MusicAppScripts.playPlaylist(id: "FEDCBA9876543210", shuffled: true)
        XCTAssertTrue(shuffled.contains("set shuffle enabled to true"))
        XCTAssertFalse(shuffled.contains("set shuffle enabled to false"))
    }

    func testQueueCopiesAPlaylistTailInOneEventAndPlaysTheQueue() throws {
        let script = try MusicAppScripts.playQueue([song, next])
        XCTAssertTrue(script.contains("duplicate (tracks 2 thru -1 of p) to q"))
        // Guards against the playlist changing in Music after Still loaded it.
        XCTAssertTrue(script.contains("(count of tracks of p) is 3 and persistent ID of track 2 of p is \"0123456789ABCDEF\""))
        XCTAssertTrue(script.contains("delete every track of q"))
        XCTAssertTrue(script.contains("play q"))
        XCTAssertTrue(script.contains(MusicAppScripts.literal(MusicAppScripts.queuePlaylistName)))
        XCTAssertTrue(script.contains("set shuffle enabled to false"))
    }

    func testQueueCopiesSortedOrMixedListsOneSongAtATime() throws {
        let script = try MusicAppScripts.playQueue([next, song])
        XCTAssertFalse(script.contains("thru -1"))
        let first = try XCTUnwrap(script.range(of: "persistent ID is \"1123456789ABCDEF\") to q"))
        let second = try XCTUnwrap(script.range(of: "persistent ID is \"0123456789ABCDEF\") to q"))
        XCTAssertLessThan(first.lowerBound, second.lowerBound)
        var loose = song
        loose.sourcePlaylistID = nil; loose.sourceIndex = nil
        XCTAssertTrue(try MusicAppScripts.playQueue([loose]).contains("library playlist 1"))
        XCTAssertThrowsError(try MusicAppScripts.playQueue([LibraryTrack(id: "bad", title: "", artist: "", album: "", duration: 0)]))
    }

    func testNumericCommandsClampAndRejectNonFiniteValues() {
        XCTAssertEqual(MusicAppScripts.volume(300), MusicAppScripts.volume(100))
        XCTAssertEqual(MusicAppScripts.volume(-10), MusicAppScripts.volume(0))
        XCTAssertEqual(MusicAppScripts.seek(.nan), MusicAppScripts.seek(0))
    }
}
