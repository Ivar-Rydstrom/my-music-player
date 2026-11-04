import XCTest
import AppKit
import ImageIO
@testable import PlayerCore

final class ArtworkCacheTests: XCTestCase {
    private func sourceImage() throws -> Data {
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 800,
            pixelsHigh: 600, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
            isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        return try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
    }

    func testThumbnailBoundsAndAspectRatio() throws {
        let data = try XCTUnwrap(ArtworkCache.thumbnail(sourceImage(), pixels: 96))
        let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        XCTAssertEqual(image.width, 96)
        XCTAssertEqual(image.height, 72)
        XCTAssertNil(ArtworkCache.thumbnail(Data("invalid".utf8), pixels: 96))
    }

    func testCacheSurvivesRelaunchAndExpires() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = try XCTUnwrap(URL(string: "music-artwork://track/0123456789ABCDEF?playlist=FEDCBA9876543210"))
        let data = try XCTUnwrap(ArtworkCache.thumbnail(sourceImage(), pixels: 320))
        var first = ArtworkCache(directory: directory, lifetime: 60)
        first.write(data, for: url)
        let relaunched = ArtworkCache(directory: directory, lifetime: 60)
        XCTAssertEqual(relaunched.read(url), data)
        XCTAssertNil(relaunched.read(url, now: Date().addingTimeInterval(120)))
        XCTAssertNil(relaunched.read(URL(string: "music-artwork://track/FEDCBA9876543210")!))
    }

    func testDiskPruningPreservesRecentlyReadCoversWithoutRenewingExpiry() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        var cache = ArtworkCache(directory: directory, lifetime: 60, capacity: 3)
        let data = try XCTUnwrap(ArtworkCache.thumbnail(sourceImage(), pixels: 96))
        let urls = (0..<33).map { URL(string: "music-artwork://track/\($0)")! }
        for url in urls.prefix(32) { cache.write(data, for: url) }
        XCTAssertEqual(cache.read(urls[0], now: Date().addingTimeInterval(10)), data)
        cache.write(data, for: urls[32]) // Triggers periodic pruning.
        XCTAssertEqual(cache.read(urls[0]), data)
        XCTAssertNil(cache.read(urls[1]))
        XCTAssertNil(cache.read(urls[0], now: Date().addingTimeInterval(120)))
    }

    func testCorruptDiskEntryIsAMiss() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = URL(string: "music-artwork://playlist/0123456789ABCDEF")!
        var cache = ArtworkCache(directory: directory)
        cache.write(Data("not an image".utf8), for: url)
        XCTAssertNil(cache.read(url))
    }
}
