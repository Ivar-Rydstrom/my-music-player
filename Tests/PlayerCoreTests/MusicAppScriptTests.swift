import XCTest
import AppKit
@testable import PlayerCore

final class MusicAppScriptTests: XCTestCase {
    private let song = LibraryTrack(id: "0123456789ABCDEF", title: "Example", artist: "Artist",
        album: "Album", duration: 180, sourcePlaylistID: "FEDCBA9876543210", sourceIndex: 2)

    func testAllAutomationScriptsCompileAgainstInstalledMusicDictionary() throws {
        let sources = try [MusicAppScripts.handshake, MusicAppScripts.playlists, MusicAppScripts.snapshot, MusicAppScripts.favorites,
            MusicAppScripts.tracks(playlistID: "FEDCBA9876543210"),
            MusicAppScripts.artwork(id: song.id),
            MusicAppScripts.artwork(id: song.id, sourcePlaylistID: song.sourcePlaylistID),
            MusicAppScripts.artwork(id: "FEDCBA9876543210", playlist: true),
            MusicAppScripts.search("Artist \"quoted\" \\ path\nsecond line"),
            MusicAppScripts.play(song), MusicAppScripts.favorite(song, value: true),
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

    func testNumericCommandsClampAndRejectNonFiniteValues() {
        XCTAssertEqual(MusicAppScripts.volume(300), MusicAppScripts.volume(100))
        XCTAssertEqual(MusicAppScripts.volume(-10), MusicAppScripts.volume(0))
        XCTAssertEqual(MusicAppScripts.seek(.nan), MusicAppScripts.seek(0))
    }
}
