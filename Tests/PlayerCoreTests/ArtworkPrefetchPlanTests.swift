import XCTest
@testable import PlayerCore

final class ArtworkPrefetchPlanTests: XCTestCase {
    private func tracks(_ count: Int) -> [URL] {
        (0..<count).map { URL(string: "music-artwork://track/\($0)")! }
    }
    private let covers = (0..<20).map { URL(string: "music-artwork://playlist/\($0)")! }

    func testEntirePlaylistAndOffscreenSidebarEventuallyLoad() {
        var plan = ArtworkPrefetchPlan()
        let songs = tracks(54)
        plan.setTracks(songs)
        plan.setPlaylists(covers)
        var loaded: [URL] = []
        while let url = plan.next() { loaded.append(url) }
        XCTAssertEqual(loaded.count, songs.count + covers.count)
        XCTAssertEqual(Set(loaded), Set(songs + covers))
        XCTAssertEqual(Array(loaded.prefix(8)), Array(songs.prefix(8)))
        XCTAssertEqual(loaded[8], covers[0])
    }

    func testSwitchingPlaylistDropsUnstartedOldTracks() {
        var plan = ArtworkPrefetchPlan()
        let songs = tracks(54)
        plan.setTracks(songs)
        XCTAssertEqual(plan.next(), songs[0])
        let replacement = URL(string: "music-artwork://track/new")!
        plan.setTracks([replacement])
        XCTAssertEqual(plan.next(), replacement)
        XCTAssertNil(plan.next())
    }

    func testRepeatedRegistrationDoesNotRestartOrDuplicateWork() {
        var plan = ArtworkPrefetchPlan()
        let songs = tracks(2)
        plan.setTracks(songs + songs)
        XCTAssertEqual(plan.next(), songs[0])
        plan.setTracks(songs)
        XCTAssertEqual(plan.next(), songs[1])
        XCTAssertNil(plan.next())
        plan.setTracks(songs)
        XCTAssertNil(plan.next())
    }

    func testRestartRevisitsCurrentInventoryWithoutRestoringOldPlaylist() {
        var plan = ArtworkPrefetchPlan()
        plan.setTracks(tracks(54))
        plan.setPlaylists(covers)
        _ = plan.next()
        let replacement = URL(string: "music-artwork://track/replacement")!
        plan.setTracks([replacement])
        plan.restart()
        var loaded: [URL] = []
        while let url = plan.next() { loaded.append(url) }
        XCTAssertEqual(loaded, [replacement] + covers)
    }

    func testSidebarCanLoadWithoutAnOpenPlaylist() {
        var plan = ArtworkPrefetchPlan()
        plan.setPlaylists(covers + [URL(string: "https://example.com/image.png")!])
        var loaded: [URL] = []
        while let url = plan.next() { loaded.append(url) }
        XCTAssertEqual(loaded, covers)
    }
}
