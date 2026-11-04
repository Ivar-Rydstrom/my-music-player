import XCTest
@testable import PlayerCore

final class ArtworkMemoryCacheTests: XCTestCase {
    private func url(_ index: Int) -> URL { URL(string: "music-artwork://track/\(index)")! }
    private let data = Data([1, 2, 3])

    func testLargePlaylistAndSidebarStayCachedBeyond256Entries() {
        var cache = ArtworkMemoryCache()
        for i in 0..<326 { cache.write(data, for: url(i)) }
        for i in 0..<326 { XCTAssertEqual(cache.read(url(i)), data) }
    }

    func testOverflowEvictsOnlyLeastRecentlyUsedEntry() {
        var cache = ArtworkMemoryCache(capacity: 3)
        for i in 0..<3 { cache.write(data, for: url(i)) }
        XCTAssertEqual(cache.read(url(0)), data)
        cache.write(data, for: url(3))
        XCTAssertNil(cache.read(url(1)))
        for i in [0, 2, 3] { XCTAssertEqual(cache.read(url(i)), data) }
    }

    func testExpiryIsNotExtendedByReads() {
        var cache = ArtworkMemoryCache(lifetime: 10)
        let start = Date()
        cache.write(data, for: url(0), now: start)
        XCTAssertEqual(cache.read(url(0), now: start.addingTimeInterval(5)), data)
        XCTAssertNil(cache.read(url(0), now: start.addingTimeInterval(11)))
    }

    func testReplacingAnEntryDoesNotEvictAnother() {
        var cache = ArtworkMemoryCache(capacity: 2)
        cache.write(data, for: url(0))
        cache.write(data, for: url(1))
        cache.write(Data([4]), for: url(0))
        XCTAssertEqual(cache.read(url(0)), Data([4]))
        XCTAssertEqual(cache.read(url(1)), data)
    }
}
