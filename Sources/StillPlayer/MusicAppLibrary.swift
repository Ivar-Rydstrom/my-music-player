import AppKit
#if SWIFT_PACKAGE
import PlayerCore
#endif

struct MusicAppSnapshot: Sendable {
    var track: LibraryTrack?
    var isPlaying: Bool
    var position: Double
    var shuffle: Bool
    var repeatAll: Bool
    var volume: Double
}

/// Synchronous Apple events run on one actor, away from the UI. Descriptors never leave it.
actor MusicAppBridge {
    func handshake() throws { _ = try execute(MusicAppScripts.handshake) }
    func playlists() throws -> [MusicPlaylist] {
        let result = try execute(MusicAppScripts.playlists)
        return (0..<result.numberOfItems).compactMap { index in
            guard let row = result.atIndex(index + 1), let id = row.atIndex(1)?.stringValue,
                  let name = row.atIndex(2)?.stringValue else { return nil }
            let editable = row.atIndex(3)?.booleanValue ?? false
            return MusicPlaylist(id: id, name: name, subtitle: editable ? "Your Music library" : "Your Music library · read-only playlist", artwork: URL(string: "music-artwork://playlist/\(id)"), canAddTracks: editable)
        }
    }
    func tracks(in playlist: MusicPlaylist) throws -> [LibraryTrack] {
        try decodeColumns(execute(MusicAppScripts.tracks(playlistID: playlist.id)), playlistID: playlist.id)
    }
    func favorites() throws -> [LibraryTrack] {
        try decodeColumns(execute(MusicAppScripts.favorites))
    }
    func search(_ query: String) throws -> [LibraryTrack] {
        try decodeColumns(execute(MusicAppScripts.search(query)))
    }
    func snapshot() throws -> MusicAppSnapshot {
        let result = try execute(MusicAppScripts.snapshot)
        guard result.numberOfItems == 6 else { throw MusicAutomationError(number: -1, message: "Unexpected player response.") }
        let row = result.atIndex(6)
        let track = row.flatMap { $0.numberOfItems == 7 ? decodeRow($0) : nil }
        return MusicAppSnapshot(track: track, isPlaying: result.atIndex(1)?.stringValue == "playing",
            position: result.atIndex(2)?.doubleValue ?? 0, shuffle: result.atIndex(3)?.booleanValue ?? false,
            repeatAll: result.atIndex(4)?.stringValue == "all", volume: result.atIndex(5)?.doubleValue ?? 50)
    }
    func artworkData(_ source: String) throws -> Data? {
        let result = try execute(source)
        // Missing value is an enum descriptor, not image data.
        let data = result.data
        return data.count > 16 ? data : nil
    }
    func run(_ source: String) throws { _ = try execute(source) }

    private func execute(_ source: String) throws -> NSAppleEventDescriptor {
        guard let script = NSAppleScript(source: source) else { throw MusicAutomationError(number: -1, message: "Could not create automation script.") }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        if let error {
            throw MusicAutomationError(number: error[NSAppleScript.errorNumber] as? Int ?? -1,
                message: error[NSAppleScript.errorMessage] as? String ?? "Unknown Apple event error.")
        }
        return result
    }
    private func decodeColumns(_ columns: NSAppleEventDescriptor, playlistID: String? = nil) throws -> [LibraryTrack] {
        guard columns.numberOfItems == 7, let ids = columns.atIndex(1) else {
            throw MusicAutomationError(number: -1, message: "Unexpected library response.")
        }
        let count = ids.numberOfItems
        guard (1...7).allSatisfy({ columns.atIndex($0)?.numberOfItems == count }) else {
            throw MusicAutomationError(number: -1, message: "Music changed while reading the playlist. Refresh and retry.")
        }
        return (0..<count).compactMap { index in
            let offset = index + 1
            guard let id = ids.atIndex(offset)?.stringValue else { return nil }
            return LibraryTrack(id: id,
                title: columns.atIndex(2)?.atIndex(offset)?.stringValue ?? "Untitled",
                artist: columns.atIndex(3)?.atIndex(offset)?.stringValue ?? "",
                album: columns.atIndex(4)?.atIndex(offset)?.stringValue ?? "",
                duration: columns.atIndex(5)?.atIndex(offset)?.doubleValue ?? 0,
                artwork: URL(string: "music-artwork://track/\(id)"),
                resourceType: "music-app-track", sourcePlaylistID: playlistID,
                sourceIndex: playlistID == nil ? nil : offset,
                isFavorite: columns.atIndex(6)?.atIndex(offset)?.booleanValue,
                playCount: columns.atIndex(7)?.atIndex(offset).map { Int($0.int32Value) })
        }
    }
    private func decodeRow(_ row: NSAppleEventDescriptor) -> LibraryTrack? {
        guard let id = row.atIndex(1)?.stringValue else { return nil }
        return LibraryTrack(id: id, title: row.atIndex(2)?.stringValue ?? "Untitled",
            artist: row.atIndex(3)?.stringValue ?? "", album: row.atIndex(4)?.stringValue ?? "",
            duration: row.atIndex(5)?.doubleValue ?? 0, artwork: URL(string: "music-artwork://track/\(id)"), resourceType: "music-app-track",
            isFavorite: row.atIndex(6)?.booleanValue, playCount: row.atIndex(7).map { Int($0.int32Value) })
    }
}

@MainActor
final class MusicAppLibrary: LibraryServing {
    let bridge = MusicAppBridge()
    func prepare() async throws {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        _ = try await NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: "/System/Applications/Music.app"), configuration: configuration)
        try await bridge.handshake()
    }
    func playlists() async throws -> [MusicPlaylist] { try await bridge.playlists() }
    func tracks(in playlist: MusicPlaylist) async throws -> [LibraryTrack] { try await bridge.tracks(in: playlist) }
    func favorites() async throws -> [LibraryTrack] { try await bridge.favorites() }
    func search(_ term: String, catalog: Bool) async throws -> [LibraryTrack] {
        guard !catalog else { throw LibraryFailure.message("Music automation searches your library. Open Music to search the Apple Music catalog.") }
        return try await bridge.search(term)
    }
    func favorite(_ track: LibraryTrack) async throws { try await setFavorite(track, value: true) }
    func setFavorite(_ track: LibraryTrack, value: Bool) async throws {
        try await bridge.run(MusicAppScripts.favorite(track, value: value))
    }
    func add(_ tracks: [LibraryTrack], to playlist: MusicPlaylist) async throws {
        guard playlist.canAddTracks else { throw LibraryFailure.message("This playlist is read-only or managed by Music. Choose a regular playlist you created.") }
        try await bridge.run(MusicAppScripts.add(tracks, playlistID: playlist.id))
    }
    func snapshot() async throws -> MusicAppSnapshot { try await bridge.snapshot() }
    func play(_ track: LibraryTrack) async throws { try await bridge.run(MusicAppScripts.play(track)) }
    func toggle() async throws { try await bridge.run(MusicAppScripts.wrap("playpause")) }
    func next() async throws { try await bridge.run(MusicAppScripts.wrap("next track")) }
    func previous() async throws { try await bridge.run(MusicAppScripts.wrap("back track")) }
    func seek(_ value: Double) async throws { try await bridge.run(MusicAppScripts.seek(value)) }
    func setVolume(_ value: Double) async throws { try await bridge.run(MusicAppScripts.volume(value)) }
    func setShuffle(_ enabled: Bool) async throws { try await bridge.run(MusicAppScripts.shuffle(enabled)) }
    func setRepeat(_ enabled: Bool) async throws { try await bridge.run(MusicAppScripts.repeatAll(enabled)) }
}

/// Serial Apple events stay off the main actor. Cache is bounded and misses expire.
actor MusicArtworkLoader {
    static let shared = MusicArtworkLoader()
    private let bridge = MusicAppBridge()
    private var cache: [URL: (Date, Data?)] = [:]
    private var pending: [URL: Task<Data?, Never>] = [:]

    func data(for url: URL) async -> Data? {
        if let entry = cache[url], Date().timeIntervalSince(entry.0) < 300 { return entry.1 }
        if let task = pending[url] { return await task.value }
        guard let script = try? MusicAppScripts.artwork(id: url.lastPathComponent,
                                                       playlist: url.host == "playlist") else { return nil }
        let task = Task { try? await bridge.artworkData(script) }
        pending[url] = task
        let data = await task.value
        pending[url] = nil
        if cache.count >= 256 { cache.removeAll(keepingCapacity: true) }
        cache[url] = (Date(), data)
        return data
    }
}
