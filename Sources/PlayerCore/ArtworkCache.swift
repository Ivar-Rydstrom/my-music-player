import Foundation
import CryptoKit
import ImageIO
import UniformTypeIdentifiers

/// Used only by the artwork actor. Files contain display-sized images, never originals.
public struct ArtworkCache {
    private let directory: URL
    private let lifetime: TimeInterval
    private let capacity: Int
    private var writes = 0

    public init(directory: URL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Hummery/Artwork-v1"), lifetime: TimeInterval = 7 * 24 * 60 * 60, capacity: Int = 512) {
        self.directory = directory
        self.lifetime = lifetime
        self.capacity = max(1, capacity)
    }

    public func read(_ url: URL, now: Date = Date()) -> Data? {
        let file = location(url)
        guard let modified = try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
              now.timeIntervalSince(modified) < lifetime,
              let data = try? Data(contentsOf: file),
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0,
              CGImageSourceGetStatus(source) == .statusComplete else { return nil }
        // Recency and expiry are separate: reading must not renew the artwork's age.
        var accessedFile = file
        var values = URLResourceValues()
        values.contentAccessDate = now
        try? accessedFile.setResourceValues(values)
        return data
    }

    public mutating func write(_ data: Data, for url: URL) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: location(url), options: .atomic)
        writes += 1
        if writes % 32 == 1 { prune() }
    }

    public static func thumbnail(_ data: Data, pixels: Int) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: max(1, pixels),
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination) ? output as Data : nil
    }

    private func location(_ url: URL) -> URL {
        let hash = SHA256.hash(data: Data(url.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(hash).appendingPathExtension("png")
    }

    private func prune() {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey, .contentAccessDateKey])) ?? []
        let dated = files.map { file -> (URL, Date, Date) in
            let values = try? file.resourceValues(forKeys: [.contentModificationDateKey, .contentAccessDateKey])
            let modified = values?.contentModificationDate ?? .distantPast
            return (file, modified, values?.contentAccessDate ?? modified)
        }.sorted { $0.2 > $1.2 }
        for (index, entry) in dated.enumerated() where index >= capacity || Date().timeIntervalSince(entry.1) >= lifetime {
            try? FileManager.default.removeItem(at: entry.0)
        }
    }
}

/// A visible image keeps its request alive across transient Music misses.
/// Sleep is cancellable so disappearing/reused rows stop retrying immediately.
public enum ArtworkRetry {
    public static func load(
        delays: [Duration] = [.milliseconds(300), .seconds(1), .seconds(3), .seconds(10), .seconds(30)],
        attempt: @Sendable () async -> Data?,
        sleep: @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) async -> Data? {
        for index in 0...delays.count {
            guard !Task.isCancelled else { return nil }
            let data = await attempt()
            guard !Task.isCancelled else { return nil }
            if let data { return data }
            guard index < delays.count else { return nil }
            do { try await sleep(delays[index]) }
            catch { return nil }
        }
        return nil
    }
}
