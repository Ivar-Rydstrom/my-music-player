import Foundation

public struct LibraryTrack: Identifiable, Hashable, Sendable {
    public let id: String
    public var title: String
    public var artist: String
    public var album: String
    public var duration: Double
    public var artwork: URL?
    public var resourceType: String
    public var sourcePlaylistID: String?
    public var sourceIndex: Int?
    public var isFavorite: Bool?
    public var playCount: Int?

    public init(id: String, title: String, artist: String, album: String, duration: Double,
                artwork: URL? = nil, resourceType: String = "songs", sourcePlaylistID: String? = nil,
                sourceIndex: Int? = nil, isFavorite: Bool? = nil, playCount: Int? = nil) {
        self.id = id; self.title = title; self.artist = artist; self.album = album
        self.duration = duration; self.artwork = artwork; self.resourceType = resourceType
        self.sourcePlaylistID = sourcePlaylistID; self.sourceIndex = sourceIndex
        self.isFavorite = isFavorite; self.playCount = playCount
    }

    public func matches(_ query: String) -> Bool {
        query.isEmpty || [title, artist, album].contains { $0.localizedStandardContains(query) }
    }
}

public struct MusicPlaylist: Identifiable, Hashable, Sendable {
    public let id: String
    public var name: String
    public var subtitle: String
    public var artwork: URL?
    public var tracks: [LibraryTrack]
    public var canAddTracks: Bool
    public init(id: String, name: String, subtitle: String, artwork: URL? = nil, tracks: [LibraryTrack] = [], canAddTracks: Bool = true) {
        self.id = id; self.name = name; self.subtitle = subtitle; self.artwork = artwork; self.tracks = tracks
        self.canAddTracks = canAddTracks
    }
}

/// A queue occurrence has its own identity, so a song can appear more than once.
public struct QueueItem: Identifiable, Equatable, Sendable {
    public let id: UUID
    public var track: LibraryTrack
    public init(track: LibraryTrack) { id = UUID(); self.track = track }
}

public struct DemoQueue: Sendable {
    public private(set) var items: [QueueItem] = []
    public private(set) var index = 0
    public var current: QueueItem? { items.indices.contains(index) ? items[index] : nil }
    public var upcoming: [QueueItem] { Array(items.dropFirst(index + 1)) }
    public init() {}

    public mutating func replace(with tracks: [LibraryTrack], startingAt offset: Int = 0) {
        items = tracks.map(QueueItem.init)
        index = items.isEmpty ? 0 : min(max(offset, 0), items.count - 1)
    }
    public mutating func insert(_ tracks: [LibraryTrack], next: Bool) {
        let position = next && current != nil ? index + 1 : items.count
        items.insert(contentsOf: tracks.map(QueueItem.init), at: position)
    }
    @discardableResult public mutating func advance(repeatAll: Bool = false) -> Bool {
        if index + 1 < items.count { index += 1; return true }
        if repeatAll && !items.isEmpty { index = 0; return true }
        return false
    }
    public mutating func previous() { index = max(0, index - 1) }
    public mutating func shuffleUpcoming() {
        guard index + 1 < items.count else { return }
        let next = index + 1
        items.replaceSubrange(next..<items.count, with: items[next...].shuffled())
    }
    public mutating func remove(_ id: UUID) {
        guard let position = items.firstIndex(where: { $0.id == id }), position > index else { return }
        items.remove(at: position)
    }
    public mutating func move(_ id: UUID, by delta: Int) {
        guard let source = items.firstIndex(where: { $0.id == id }) else { return }
        let destination = source + delta
        guard source > index, destination > index, items.indices.contains(destination) else { return }
        items.swapAt(source, destination)
    }
}

public func clockText(_ seconds: Double) -> String {
    let value = seconds.isFinite ? max(0, Int(seconds)) : 0
    return String(format: "%d:%02d", value / 60, value % 60)
}
