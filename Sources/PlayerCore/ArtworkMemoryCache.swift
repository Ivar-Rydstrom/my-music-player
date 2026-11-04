import Foundation

/// Bounded LRU cache. Adding one image evicts one old entry, never the whole playlist.
public struct ArtworkMemoryCache {
    private struct Entry {
        var data: Data
        var created: Date
        var accessed: UInt64
    }
    private var entries: [URL: Entry] = [:]
    private var clock: UInt64 = 0
    private let capacity: Int
    private let lifetime: TimeInterval

    public init(capacity: Int = 512, lifetime: TimeInterval = 7 * 24 * 60 * 60) {
        self.capacity = max(1, capacity)
        self.lifetime = lifetime
    }

    public mutating func read(_ url: URL, now: Date = Date()) -> Data? {
        guard var entry = entries[url] else { return nil }
        guard now.timeIntervalSince(entry.created) < lifetime else {
            entries[url] = nil
            return nil
        }
        clock += 1
        entry.accessed = clock
        entries[url] = entry
        return entry.data
    }

    public mutating func write(_ data: Data, for url: URL, now: Date = Date()) {
        if entries[url] == nil, entries.count >= capacity,
           let oldest = entries.min(by: { $0.value.accessed < $1.value.accessed })?.key {
            entries[oldest] = nil
        }
        clock += 1
        entries[url] = Entry(data: data, created: now, accessed: clock)
    }
}
