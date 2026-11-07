import XCTest
import PlayerCore
@testable import Hummery

@MainActor
final class PlaylistPlayButtonTests: XCTestCase {
    private let focus = Array(SampleLibrary.tracks.prefix(3))
    private let evening = Array(SampleLibrary.tracks.suffix(3))

    func testListThatStartedPlaybackOwnsTheCurrentTrack() async throws {
        let player = PlaybackController()
        XCTAssertFalse(player.isCurrentContext("focus", tracks: focus))

        try await player.playPlaylist(nil, tracks: focus, context: "focus")
        XCTAssertTrue(player.isPlaying)
        XCTAssertTrue(player.isCurrentContext("focus", tracks: focus))
        XCTAssertFalse(player.isCurrentContext("evening", tracks: evening))

        // Pressing the button again pauses and resumes without restarting the list.
        let first = player.current
        try await player.toggle()
        XCTAssertFalse(player.isPlaying)
        XCTAssertTrue(player.isCurrentContext("focus", tracks: focus))
        try await player.toggle()
        XCTAssertTrue(player.isPlaying)
        XCTAssertEqual(player.current, first)
    }

    func testPlayingFromAnotherListOrSearchReleasesTheContext() async throws {
        let player = PlaybackController()
        try await player.play(focus, at: 1, context: "focus")
        XCTAssertTrue(player.isCurrentContext("focus", tracks: focus))

        try await player.play(evening, context: "evening")
        XCTAssertFalse(player.isCurrentContext("focus", tracks: focus))
        XCTAssertTrue(player.isCurrentContext("evening", tracks: evening))

        try await player.play(focus)
        XCTAssertFalse(player.isCurrentContext("focus", tracks: focus))
    }

    func testListNoLongerOwnsATrackItDoesNotContain() async throws {
        let player = PlaybackController()
        try await player.play(focus, context: "focus")
        XCTAssertFalse(player.isCurrentContext("focus", tracks: evening))
    }
}
