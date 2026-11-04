import XCTest
@testable import PlayerCore

final class QueueTests: XCTestCase {
    let songs = SampleLibrary.tracks

    func testRepeatedSongsHaveIndependentOccurrences() {
        var queue = DemoQueue()
        queue.replace(with: [songs[0], songs[0], songs[1]])
        XCTAssertNotEqual(queue.items[0].id, queue.items[1].id)
        queue.remove(queue.items[1].id)
        XCTAssertEqual(queue.items.map(\.track.id), [songs[0].id, songs[1].id])
        XCTAssertEqual(queue.current?.track, songs[0])
    }
    func testInsertionPreservesOrderAndCurrentTrack() {
        var queue = DemoQueue()
        queue.replace(with: Array(songs.prefix(3)), startingAt: 1)
        queue.insert([songs[4], songs[5]], next: true)
        queue.insert([songs[6]], next: false)
        XCTAssertEqual(queue.current?.track, songs[1])
        XCTAssertEqual(queue.upcoming.map(\.track), [songs[4], songs[5], songs[2], songs[6]])
    }
    func testQueueEditsCannotRemoveOrMoveCurrentOrPlayedItems() {
        var queue = DemoQueue()
        queue.replace(with: Array(songs.prefix(4)), startingAt: 1)
        let original = queue.items
        queue.remove(original[0].id)
        queue.remove(original[1].id)
        queue.move(original[2].id, by: -1)
        XCTAssertEqual(queue.items, original)
        queue.move(original[3].id, by: -1)
        XCTAssertEqual(queue.upcoming.map(\.track), [songs[3], songs[2]])
    }
    func testRepeatAndEndOfQueue() {
        var queue = DemoQueue()
        queue.replace(with: [songs[0]])
        XCTAssertFalse(queue.advance())
        XCTAssertTrue(queue.advance(repeatAll: true))
        XCTAssertEqual(queue.current?.track, songs[0])
        queue.replace(with: [])
        XCTAssertNil(queue.current)
        XCTAssertFalse(queue.advance(repeatAll: true))
    }
    func testFilteringAndTimeFormatting() {
        XCTAssertTrue(songs[0].matches("TYCHO"))
        XCTAssertTrue(songs[0].matches("Dive"))
        XCTAssertFalse(songs[0].matches("Bonobo"))
        XCTAssertEqual(clockText(316), "5:16")
        XCTAssertEqual(clockText(-2), "0:00")
        XCTAssertEqual(clockText(.nan), "0:00")
    }
    func testShufflingPreservesPlayedItemsAndEveryUpcomingOccurrence() {
        var queue = DemoQueue()
        queue.replace(with: Array(songs.prefix(6)), startingAt: 2)
        let playedAndCurrent = Array(queue.items.prefix(3))
        let upcomingIDs = Set(queue.upcoming.map(\.id))
        queue.shuffleUpcoming()
        XCTAssertEqual(Array(queue.items.prefix(3)), playedAndCurrent)
        XCTAssertEqual(Set(queue.upcoming.map(\.id)), upcomingIDs)
    }
}
