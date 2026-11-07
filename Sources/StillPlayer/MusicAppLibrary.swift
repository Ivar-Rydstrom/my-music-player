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

/// Keeps Music running without putting its window in front of Still.
enum MusicAppProcess {
    static let bundleIdentifier = "com.apple.Music"

    static var isRunning: Bool {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).contains { !$0.isTerminated }
    }

    /// Launches Music hidden when it is not running. A running Music is left alone:
    /// asking LaunchServices to open it again sends a reopen event, which shows its window.
    @MainActor
    static func launchHiddenIfNeeded() async throws {
        guard !isRunning else { return }
        let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
            ?? URL(fileURLWithPath: "/System/Applications/Music.app")
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.hides = true
        configuration.addsToRecentItems = false
        _ = try await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
    }
}

/// Synchronous Apple events run on one actor, away from the UI. Descriptors never leave it.
actor MusicAppBridge {
    func handshake() throws { _ = try execute(MusicAppScripts.handshake) }
    func playlists() throws -> [MusicPlaylist] {
        let result = try execute(MusicAppScripts.playlists)
        return (0..<result.numberOfItems).compactMap { index in
            guard let row = result.atIndex(index + 1), let id = row.atIndex(1)?.stringValue,
                  let name = row.atIndex(2)?.stringValue, name != MusicAppScripts.queuePlaylistName else { return nil }
            let editable = row.atIndex(3)?.booleanValue ?? false
            return MusicPlaylist(id: id, name: name, subtitle: editable ? "From your library" : "From your library · read-only playlist", artwork: URL(string: "music-artwork://playlist/\(id)"), canAddTracks: editable)
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
        try Self.decodeSnapshot(execute(MusicAppScripts.snapshot))
    }
    static func decodeSnapshot(_ result: NSAppleEventDescriptor) throws -> MusicAppSnapshot {
        guard result.numberOfItems == 7 else { throw MusicAutomationError(number: -1, message: "Unexpected player response.") }
        let row = result.atIndex(6)
        let playlistID = result.atIndex(7)?.stringValue.flatMap { $0.isEmpty ? nil : $0 }
        let track = row.flatMap { $0.numberOfItems == 7 ? decodeRow($0, playlistID: playlistID) : nil }
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
                artwork: URL(string: "music-artwork://track/\(id)" + (playlistID.map { "?playlist=\($0)" } ?? "")),
                resourceType: "music-app-track", sourcePlaylistID: playlistID,
                sourceIndex: playlistID == nil ? nil : offset,
                isFavorite: columns.atIndex(6)?.atIndex(offset)?.booleanValue,
                playCount: columns.atIndex(7)?.atIndex(offset).map { Int($0.int32Value) })
        }
    }
    private static func decodeRow(_ row: NSAppleEventDescriptor, playlistID: String? = nil) -> LibraryTrack? {
        guard let id = row.atIndex(1)?.stringValue else { return nil }
        return LibraryTrack(id: id, title: row.atIndex(2)?.stringValue ?? "Untitled",
            artist: row.atIndex(3)?.stringValue ?? "", album: row.atIndex(4)?.stringValue ?? "",
            duration: row.atIndex(5)?.doubleValue ?? 0, artwork: URL(string: "music-artwork://track/\(id)" + (playlistID.map { "?playlist=\($0)" } ?? "")), resourceType: "music-app-track", sourcePlaylistID: playlistID,
            isFavorite: row.atIndex(6)?.booleanValue, playCount: row.atIndex(7).map { Int($0.int32Value) })
    }
}

@MainActor
final class MusicAppLibrary: LibraryServing {
    let bridge = MusicAppBridge()
    func prepare() async throws {
        try await MusicAppProcess.launchHiddenIfNeeded()
        try await bridge.handshake()
    }
    /// User-initiated requests relaunch Music hidden if it was quit. Otherwise the
    /// Apple event would launch Music itself, and that launch shows its window.
    private func send(_ source: String) async throws {
        try await MusicAppProcess.launchHiddenIfNeeded()
        try await bridge.run(source)
    }
    func playlists() async throws -> [MusicPlaylist] {
        try await MusicAppProcess.launchHiddenIfNeeded()
        return try await bridge.playlists()
    }
    func tracks(in playlist: MusicPlaylist) async throws -> [LibraryTrack] {
        try await MusicAppProcess.launchHiddenIfNeeded()
        return try await bridge.tracks(in: playlist)
    }
    func favorites() async throws -> [LibraryTrack] {
        try await MusicAppProcess.launchHiddenIfNeeded()
        return try await bridge.favorites()
    }
    func search(_ term: String, catalog: Bool) async throws -> [LibraryTrack] {
        guard !catalog else { throw LibraryFailure.message("Music automation searches your library. Open Music to search the Apple Music catalog.") }
        try await MusicAppProcess.launchHiddenIfNeeded()
        return try await bridge.search(term)
    }
    func favorite(_ track: LibraryTrack) async throws { try await setFavorite(track, value: true) }
    func setFavorite(_ track: LibraryTrack, value: Bool) async throws {
        try await send(MusicAppScripts.favorite(track, value: value))
    }
    func add(_ tracks: [LibraryTrack], to playlist: MusicPlaylist) async throws {
        guard playlist.canAddTracks else { throw LibraryFailure.message("This playlist is read-only or managed by Music. Choose a regular playlist you created.") }
        try await send(MusicAppScripts.add(tracks, playlistID: playlist.id))
    }
    /// Polling never launches Music. Callers check `MusicAppProcess.isRunning` first.
    func snapshot() async throws -> MusicAppSnapshot { try await bridge.snapshot() }
    func play(_ track: LibraryTrack) async throws { try await send(MusicAppScripts.play(track)) }
    func play(_ playlist: MusicPlaylist, shuffled: Bool) async throws {
        try await send(MusicAppScripts.playPlaylist(id: playlist.id, shuffled: shuffled))
    }
    func play(queue tracks: [LibraryTrack], shuffled: Bool) async throws {
        try await send(MusicAppScripts.playQueue(tracks, shuffled: shuffled))
    }
    func pause() async throws { try await send(MusicAppScripts.wrap("pause")) }
    func toggle() async throws { try await send(MusicAppScripts.wrap("playpause")) }
    func next() async throws { try await send(MusicAppScripts.wrap("next track")) }
    func previous() async throws { try await send(MusicAppScripts.wrap("back track")) }
    func seek(_ value: Double) async throws { try await send(MusicAppScripts.seek(value)) }
    func setVolume(_ value: Double) async throws { try await send(MusicAppScripts.volume(value)) }
    func setShuffle(_ enabled: Bool) async throws { try await send(MusicAppScripts.shuffle(enabled)) }
    func setRepeat(_ enabled: Bool) async throws { try await send(MusicAppScripts.repeatAll(enabled)) }
}

/// Visible tracks and headers go ahead of sidebar covers and speculative prefetch.
/// Only one Music artwork request is in flight; metadata and playback use a separate bridge.
actor MusicArtworkLoader {
    static let shared = MusicArtworkLoader()
    private let bridge = MusicAppBridge()
    private var disk = ArtworkCache()
    private var cache = ArtworkMemoryCache()
    private var rowThumbnails = ArtworkMemoryCache()
    private var misses: [URL: Date] = [:]
    private var waiting: [URL: [CheckedContinuation<Data?, Never>]] = [:]
    private var queue: [(url: URL, priority: Int)] = []
    private var running = false
    private var backgroundPlan = ArtworkPrefetchPlan()
    private var backgroundTask: Task<Void, Never>?
    private var backgroundGeneration = UUID()

    func data(for url: URL, priority: Int = 0, retryMissing: Bool = false) async -> Data? {
        if let data = cache.read(url) { return data }
        if let data = disk.read(url) {
            remember(data, for: url)
            return data
        }
        if !retryMissing, let date = misses[url], Date().timeIntervalSince(date) < 30 { return nil }
        return await withCheckedContinuation { continuation in
            if waiting[url] != nil {
                waiting[url]?.append(continuation)
                if let index = queue.firstIndex(where: { $0.url == url }) {
                    queue[index].priority = min(priority, queue[index].priority)
                }
            } else {
                waiting[url] = [continuation]
                queue.append((url, priority))
            }
            if !running {
                running = true
                Task { await drain() }
            }
        }
    }

    func prefetchTracks(_ urls: [URL]) {
        if backgroundPlan.setTracks(urls) { startBackgroundLoading() }
    }

    func prefetchPlaylists(_ urls: [URL]) {
        if backgroundPlan.setPlaylists(urls) { startBackgroundLoading() }
    }

    private func startBackgroundLoading() {
        backgroundTask?.cancel()
        // Revisit any earlier misses still belonging to the current inventory.
        backgroundPlan.restart()
        let generation = UUID()
        backgroundGeneration = generation
        backgroundTask = Task(priority: .background) {
            defer { if backgroundGeneration == generation { backgroundTask = nil } }
            do {
                // Give visible rows a head start when a playlist or library changes.
                try await Task.sleep(for: .milliseconds(250))
                var failed: [URL] = []
                while !Task.isCancelled, let url = backgroundPlan.next() {
                    if await data(for: url, priority: 2) == nil { failed.append(url) }
                    await Task.yield()
                }
                // Finish the initial pass before retrying temporary misses offscreen.
                for delay in [1, 3, 10, 30] where !failed.isEmpty {
                    try await Task.sleep(for: .seconds(delay))
                    let retry = failed
                    failed = []
                    for url in retry {
                        try Task.checkCancellation()
                        if await data(for: url, priority: 2, retryMissing: true) == nil { failed.append(url) }
                        await Task.yield()
                    }
                }
            } catch { /* A new playlist or library superseded this background pass. */ }
        }
    }

    func thumbnail(for url: URL, pixels: Int) async -> Data? {
        if pixels <= 96, let thumbnail = rowThumbnails.read(url) { return thumbnail }
        let priority = url.host == "track" || pixels > 96 ? 0 : 1
        // Negative caching suppresses speculative prefetch, not recovery of a visible row.
        // Keep retrying this same URL; SwiftUI's .task(id:) does not restart after a nil result.
        let loaded = await ArtworkRetry.load {
            await self.data(for: url, priority: priority, retryMissing: true)
        }
        guard let data = loaded else { return nil }
        guard pixels <= 96 else { return data }
        guard let thumbnail = ArtworkCache.thumbnail(data, pixels: 96) else { return nil }
        rowThumbnails.write(thumbnail, for: url)
        return thumbnail
    }

    private func drain() async {
        while !queue.isEmpty {
            // min preserves insertion order among requests with the same priority.
            let index = queue.indices.min { queue[$0].priority < queue[$1].priority }!
            let url = queue.remove(at: index).url
            let playlistID = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first { $0.name == "playlist" }?.value
            let script = try? MusicAppScripts.artwork(id: url.lastPathComponent,
                playlist: url.host == "playlist", sourcePlaylistID: playlistID)
            // Artwork is speculative; never launch Music for it.
            let original = if let script, MusicAppProcess.isRunning { try? await bridge.artworkData(script) } else { nil as Data? }
            let data = original.flatMap { ArtworkCache.thumbnail($0, pixels: 320) }
            if let data {
                misses[url] = nil
                remember(data, for: url)
                disk.write(data, for: url)
            } else {
                if misses.count >= 256 { misses.removeAll() }
                misses[url] = Date()
            }
            let continuations = waiting.removeValue(forKey: url) ?? []
            for continuation in continuations { continuation.resume(returning: data) }
        }
        running = false
    }

    private func remember(_ data: Data, for url: URL) {
        cache.write(data, for: url)
    }
}
