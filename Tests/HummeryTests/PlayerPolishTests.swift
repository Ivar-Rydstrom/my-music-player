import XCTest
import SwiftUI
import PlayerCore
@testable import Hummery

final class PlayerPolishTests: XCTestCase {
    func testNowPlayingArtworkKeepsMusicPlaylistContext() throws {
        let script = NSAppleScript(source: """
            return {"playing", 12, true, "off", 50, {"0123456789ABCDEF", "Song", "Artist", "Album", 180, false, 0}, "FEDCBA9876543210"}
            """)!
        var error: NSDictionary?
        let snapshot = try MusicAppBridge.decodeSnapshot(script.executeAndReturnError(&error))
        XCTAssertNil(error)
        XCTAssertEqual(snapshot.track?.sourcePlaylistID, "FEDCBA9876543210")
        XCTAssertEqual(snapshot.track?.artwork?.absoluteString,
            "music-artwork://track/0123456789ABCDEF?playlist=FEDCBA9876543210")
        XCTAssertTrue(snapshot.shuffle)
    }

    func testNowPlayingWithoutAScriptablePlaylistStillDecodes() throws {
        let script = NSAppleScript(source: """
            return {"paused", 12, false, "off", 50, {"0123456789ABCDEF", "Song", "Artist", "Album", 180, false, 0}, ""}
            """)!
        var error: NSDictionary?
        let snapshot = try MusicAppBridge.decodeSnapshot(script.executeAndReturnError(&error))
        XCTAssertNil(error)
        XCTAssertNil(snapshot.track?.sourcePlaylistID)
        XCTAssertEqual(snapshot.track?.artwork?.absoluteString, "music-artwork://track/0123456789ABCDEF")
    }

    @MainActor func testPresetAndGeneratedPalettesKeepTextAndControlsReadable() {
        var themes = ThemePreset.all.map(\.theme)
        var custom = ThemePreferences()
        custom.preset = "custom"
        for light in [false, true] {
            custom.light = light
            for hue in stride(from: 0.0, through: 1.0, by: 0.1) {
                for depth in [0.0, 0.5, 1.0] {
                    custom.hue = hue; custom.intensity = depth
                    themes.append(custom.theme)
                }
            }
        }
        for theme in themes {
            for background in [theme.base, theme.panel] {
                XCTAssertGreaterThanOrEqual(ThemeColor(color: theme.text).contrast(with: background), 4.5)
                XCTAssertGreaterThanOrEqual(ThemeColor(color: theme.muted).contrast(with: background), 4.5)
                XCTAssertGreaterThanOrEqual(ThemeColor(color: theme.accent).contrast(with: background), 3)
            }
            XCTAssertGreaterThanOrEqual(ThemeColor(color: theme.buttonInk).contrast(with: ThemeColor(color: theme.accent)), 4.5)
        }
    }
    @MainActor func testManualThemePreservesExactUserColorsAndCodableRoundTrip() throws {
        var preferences = ThemePreferences()
        preferences.preset = "custom"; preferences.automatic = false
        preferences.background = "#121212"; preferences.surface = "#303030"
        preferences.accent = "#AABBCC"; preferences.companion = "#DDEEFF"
        let decoded = try JSONDecoder().decode(ThemePreferences.self, from: JSONEncoder().encode(preferences))
        XCTAssertEqual(decoded.theme.base.hex, "#121212")
        XCTAssertEqual(decoded.theme.panel.hex, "#303030")
        XCTAssertEqual(decoded.theme.highlight.hex, "#AABBCC")
        XCTAssertEqual(decoded.theme.glow.hex, "#DDEEFF")
    }
    @MainActor func testSleepTimerPausesOnceAndSessionSwitchCancelsIt() async throws {
        let player = PlaybackController()
        try await player.play(SampleLibrary.tracks)
        player.setSleepTimer(minutes: 15)
        let deadline = try XCTUnwrap(player.sleepUntil)
        player.tick(now: deadline.addingTimeInterval(-1))
        XCTAssertNotNil(player.sleepUntil)
        XCTAssertTrue(player.isPlaying)
        player.tick(now: deadline)
        for _ in 0..<5 { await Task.yield() }
        XCTAssertNil(player.sleepUntil)
        XCTAssertFalse(player.isPlaying)
        try await player.toggle()
        player.tick(now: deadline.addingTimeInterval(1))
        XCTAssertTrue(player.isPlaying)
        player.setSleepTimer(minutes: 30)
        player.configure(library: nil)
        XCTAssertNil(player.sleepUntil)
    }
    @MainActor func testHistoryDeduplicatesAndClearQueueKeepsCurrentSong() async throws {
        let model = AppModel()
        let tracks = Array(SampleLibrary.tracks.prefix(3))
        try await model.playback.play(tracks)
        XCTAssertEqual(model.recentTracks.map(\.id), [tracks[0].id])
        model.playback.tick()
        XCTAssertEqual(model.recentTracks.count, 1)
        try await model.playback.next()
        XCTAssertEqual(model.recentTracks.map(\.id), [tracks[1].id, tracks[0].id])
        model.playback.clearUpcoming()
        XCTAssertTrue(model.playback.upcoming.isEmpty)
        XCTAssertEqual(model.playback.current?.id, tracks[1].id)
        model.recentTracks = []
        model.playback.tick()
        XCTAssertTrue(model.recentTracks.isEmpty)
        model.useSamples()
        try await model.playback.play(tracks, at: 1)
        XCTAssertEqual(model.recentTracks.map(\.id), [tracks[1].id])
    }
}
