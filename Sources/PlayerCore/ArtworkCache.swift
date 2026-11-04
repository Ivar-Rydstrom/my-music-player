import Foundation
import CryptoKit
import ImageIO
import UniformTypeIdentifiers

/// Used only by the artwork actor. Files contain display-sized images, never originals.
public struct ArtworkCache {
    private let directory: URL
    private let lifetime: TimeInterval
    private var writes = 0

    public init(directory: URL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("StillPlayer/Artwork-v1"), lifetime: TimeInterval = 7 * 24 * 60 * 60) {
        self.directory = directory
        self.lifetime = lifetime
    }

    public func read(_ url: URL, now: Date = Date()) -> Data? {
        let file = location(url)
        guard let modified = try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
              now.timeIntervalSince(modified) < lifetime,
              let data = try? Data(contentsOf: file),
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0,
              CGImageSourceGetStatus(source) == .statusComplete else { return nil }
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
            includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        let dated = files.map { ($0, (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast) }
            .sorted { $0.1 > $1.1 }
        for (index, entry) in dated.enumerated() where index >= 512 || Date().timeIntervalSince(entry.1) >= lifetime {
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
