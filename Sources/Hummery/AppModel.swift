import SwiftUI
import Combine
#if SWIFT_PACKAGE
import PlayerCore
#endif

@MainActor
final class AppModel: ObservableObject {
    @Published var playlists = SampleLibrary.playlists
    @Published var selectedID: String? = UserDefaults.standard.string(forKey: "sample.lastPlaylist") ?? "demo-focus"
    @Published var loadedTracks: [String: [LibraryTrack]] = [:]
    @Published var searchResults: [LibraryTrack] = []
    @Published var favorites = Set<String>(UserDefaults.standard.stringArray(forKey: "sample.favorites") ?? ["demo-2", "demo-9"])
    @Published var pinned = Set<String>(UserDefaults.standard.stringArray(forKey: "sample.pins") ?? ["demo-focus", "demo-evening"])
    @Published var isLive = false
    @Published var usesMusicApp = false
    @Published var recentTracks: [LibraryTrack] = []
    @Published var favoriteTracks: [LibraryTrack] = []
    @Published var isConnecting = false
    @Published var connectionStatus = "Not connected"
    @Published var accountStorefront: String?
    @Published var canStream = false
    @Published var cloudLibraryEnabled = false
    @Published var loadingPlaylistID: String?
    @Published var searching = false
    @Published var error: String?
    @Published var notice: String?
    @Published var log: [String] = []
    let playback = PlaybackController()
    private var service: any LibraryServing = SampleMusicLibrary()
    private var session = UUID()
    private var subscriptions = Set<AnyCancellable>()
    private var preferencePrefix: String { usesMusicApp ? "musicApp" : isLive ? "live" : "sample" }

    init() {
        playback.$current.combineLatest(playback.$isPlaying, playback.$contextID)
            .removeDuplicates { $0 == $1 }
            .sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &subscriptions)
        playback.$errorMessage.compactMap { $0 }.sink { [weak self] message in
            self?.error = message
            self?.record(message)
        }.store(in: &subscriptions)
        playback.$current.removeDuplicates(by: { $0?.id == $1?.id }).compactMap { $0 }.sink { [weak self] track in
            guard let self else { return }
            if self.recentTracks.first?.id != track.id {
                self.recentTracks.removeAll { $0.id == track.id }
                self.recentTracks.insert(track, at: 0)
                self.recentTracks = Array(self.recentTracks.prefix(100))
            }
        }.store(in: &subscriptions)
        playback.$current.removeDuplicates().compactMap { $0 }.sink { [weak self] track in
            guard let self, self.usesMusicApp else { return }
            self.mergeFavoriteStates([track])
        }.store(in: &subscriptions)
    }

    var playlist: MusicPlaylist? { playlists.first { $0.id == selectedID } }
    var tracks: [LibraryTrack] {
        if selectedID == "recent" { return recentTracks }
        if selectedID == "favorites" {
            let known = isLive ? favoriteTracks + loadedTracks.values.flatMap { $0 } + searchResults : SampleLibrary.tracks
            var seen = Set<String>()
            return known.filter { favorites.contains($0.id) && seen.insert($0.id).inserted }
        }
        guard let playlist else { return [] }
        return loadedTracks[playlist.id] ?? playlist.tracks
    }
    var sortedPlaylists: [MusicPlaylist] {
        playlists.sorted {
            if pinned.contains($0.id) != pinned.contains($1.id) { return pinned.contains($0.id) }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }
    func record(_ message: String) {
        log.insert("\(Date().formatted(date: .omitted, time: .standard))  \(message)", at: 0)
        if log.count > 250 { log.removeLast(log.count - 250) }
    }
    func perform(_ action: @escaping @MainActor () async throws -> Void) {
        Task { do { try await action() } catch { self.error = error.localizedDescription; record("Failed: \(error.localizedDescription)") } }
    }
    func select(_ id: String?) async {
        selectedID = id
        guard let id else { return }
        UserDefaults.standard.set(id, forKey: preferencePrefix + ".lastPlaylist")
        if usesMusicApp, id == "favorites", let library = service as? MusicAppLibrary {
            let token = session
            do {
                let fetched = try await library.favorites()
                guard token == session else { return }
                favoriteTracks = fetched
                favorites = Set(favoriteTracks.map(\.id))
            } catch { if token == session { self.error = error.localizedDescription } }
            return
        }
        guard let playlist, loadedTracks[id] == nil else { return }
        let token = session
        loadingPlaylistID = id
        do {
            let tracks = try await service.tracks(in: playlist)
            guard token == session else { return }
            loadedTracks[id] = tracks
            if usesMusicApp { mergeFavoriteStates(tracks) }
            record("Loaded \(tracks.count) songs from \(playlist.name).")
        } catch { if token == session { self.error = error.localizedDescription } }
        if loadingPlaylistID == id { loadingPlaylistID = nil }
    }
    func connect() async {
        guard !isConnecting else { return }
        isConnecting = true; error = nil
        defer { isConnecting = false }
        let library = MusicAppLibrary()
        do {
            guard Bundle.main.object(forInfoDictionaryKey: "NSAppleEventsUsageDescription") != nil else {
                throw LibraryFailure.message("Run the Hummery app bundle to connect to Music. Use scripts/run-local.sh or run the Xcode scheme. The bare Swift package executable is for samples.")
            }
            connectionStatus = "Waiting for Music automation permission"
            record("Connecting to Music.app. No developer membership required.")
            try await library.prepare()
            connectionStatus = "Loading Music playlists"
            record("Music automation handshake succeeded. Loading playlists.")
            let fetched = try await library.playlists()
            connectionStatus = "Reading Music playback state"
            let snapshot = try await library.snapshot()
            recentTracks = []
            session = UUID(); service = library; usesMusicApp = true; isLive = true
            accountStorefront = nil; canStream = false; cloudLibraryEnabled = false
            playlists = fetched; loadedTracks = [:]; searchResults = []; favoriteTracks = []; favorites = []
            pinned = Set(UserDefaults.standard.stringArray(forKey: "musicApp.pins") ?? [])
            let restored = UserDefaults.standard.string(forKey: "musicApp.lastPlaylist")
            selectedID = fetched.contains { $0.id == restored } ? restored : fetched.first?.id
            playback.configure(musicApp: library, snapshot: snapshot)
            connectionStatus = "Connected to Music.app"
            UserDefaults.standard.set(true, forKey: "musicApp.restoreConnection")
            UserDefaults.standard.set(false, forKey: "account.restoreConnection")
            record("Connected. \(fetched.count) playlists. Music handles playback and account sync.")
            await select(selectedID)
        } catch {
            self.error = "\(connectionStatus): \(error.localizedDescription)"
            connectionStatus = isLive ? "Reconnect failed; existing session retained" : "Connection failed"
            record("Music.app connection failed: \(error.localizedDescription)")
        }
    }
    func connectMusicKit() async {
        guard !isConnecting else { return }
        isConnecting = true
        error = nil
        defer { isConnecting = false }
        let apple = AppleMusicLibrary()
        do {
            let account = try await apple.authorize { stage in
                self.connectionStatus = stage
                self.record(stage + ".")
            }
            record("Account verified. Storefront: \(account.storefront). Catalog playback: \(account.canStream ? "available" : "unavailable"). Sync Library: \(account.cloudLibraryEnabled ? "enabled" : "disabled").")
            connectionStatus = "Loading playlists"
            let fetched = try await apple.playlists()
            recentTracks = []
            session = UUID(); service = apple; isLive = true
            usesMusicApp = false; favoriteTracks = []
            accountStorefront = account.storefront; canStream = account.canStream
            cloudLibraryEnabled = account.cloudLibraryEnabled
            playback.configure(library: apple)
            playlists = fetched; loadedTracks = [:]; searchResults = []; favorites = []
            pinned = Set(UserDefaults.standard.stringArray(forKey: "live.pins") ?? [])
            let restored = UserDefaults.standard.string(forKey: "live.lastPlaylist")
            selectedID = fetched.contains { $0.id == restored } ? restored : fetched.first?.id
            record("Loaded \(fetched.count) account playlists. Pagination completed.")
            await select(selectedID)
            connectionStatus = "Connected"
            UserDefaults.standard.set(true, forKey: "account.restoreConnection")
            UserDefaults.standard.set(false, forKey: "musicApp.restoreConnection")
            if !account.canStream { notice = "Connected. Catalog streaming is unavailable for this account." }
            else if !account.cloudLibraryEnabled { notice = "Connected. Enable Sync Library in Music to use your cloud library." }
        } catch {
            let stage = connectionStatus
            let detail = error as NSError
            self.error = "\(stage): \(error.localizedDescription)"
            connectionStatus = isLive ? "Reconnect failed; existing session retained" : "Connection failed"
            record("\(stage) failed [\(detail.domain) \(detail.code)]: \(error.localizedDescription)")
        }
    }
    func useSamples() {
        recentTracks = []
        session = UUID(); playback.configure(library: nil); service = SampleMusicLibrary(); isLive = false; usesMusicApp = false
        favoriteTracks = []
        connectionStatus = "Not connected"; accountStorefront = nil; canStream = false; cloudLibraryEnabled = false
        UserDefaults.standard.set(false, forKey: "account.restoreConnection")
        UserDefaults.standard.set(false, forKey: "musicApp.restoreConnection")
        playlists = SampleLibrary.playlists; loadedTracks = [:]; searchResults = []
        favorites = Set(UserDefaults.standard.stringArray(forKey: "sample.favorites") ?? ["demo-2", "demo-9"])
        pinned = Set(UserDefaults.standard.stringArray(forKey: "sample.pins") ?? ["demo-focus", "demo-evening"])
        selectedID = UserDefaults.standard.string(forKey: "sample.lastPlaylist") ?? "demo-focus"
        record("Switched to samples. No account writes or audio.")
    }
    func restoreConnectionIfNeeded() async {
        if UserDefaults.standard.bool(forKey: "musicApp.restoreConnection") {
            await connect()
            return
        }
        guard UserDefaults.standard.bool(forKey: "account.restoreConnection"),
              MusicAccountSetup.inspect().issue == nil,
              MusicAccountSetup.isAuthorized else { return }
        await connectMusicKit()
    }
    func search(_ term: String, catalog: Bool) async {
        let token = session
        guard !term.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { searchResults = []; searching = false; return }
        searching = true
        do {
            try await Task.sleep(for: .milliseconds(300))
            try Task.checkCancellation()
            let result = try await service.search(term, catalog: catalog)
            try Task.checkCancellation()
            guard token == session else { return }
            searchResults = result; searching = false
            if usesMusicApp { mergeFavoriteStates(result) }
        } catch is CancellationError { }
        catch { if token == session { self.error = error.localizedDescription; searching = false } }
    }
    func favorite(_ track: LibraryTrack) async throws {
        let token = session
        if let library = service as? MusicAppLibrary {
            let value = !favorites.contains(track.id)
            try await library.setFavorite(track, value: value)
            guard token == session else { return }
            if value {
                favorites.insert(track.id)
                var saved = track; saved.isFavorite = true
                favoriteTracks.removeAll { $0.id == track.id }; favoriteTracks.append(saved)
            } else {
                favorites.remove(track.id); favoriteTracks.removeAll { $0.id == track.id }
            }
            notice = value ? "Added to favorites." : "Removed from favorites."
            record("\(value ? "Favorited" : "Unfavorited") \(track.title) in Music.")
            return
        }
        if !isLive && favorites.contains(track.id) { favorites.remove(track.id) }
        else {
            try await service.favorite(track)
            guard token == session else { return }
            favorites.insert(track.id)
            notice = isLive ? "Added to favorites." : "Saved to sample favorites."
            record("\(isLive ? "Apple accepted favorite request for" : "Favorited") \(track.title).")
        }
        if !isLive { UserDefaults.standard.set(Array(favorites), forKey: "sample.favorites") }
    }
    func add(_ tracks: [LibraryTrack], to playlist: MusicPlaylist) async throws {
        guard !tracks.isEmpty else { return }
        let token = session
        try await service.add(tracks, to: playlist)
        guard token == session else { return }
        loadedTracks[playlist.id] = nil
        notice = "Added \(tracks.count) song(s) to \(playlist.name)."
        record("Playlist addition accepted: \(playlist.name). Confirm on iPhone.")
        if selectedID == playlist.id { await select(playlist.id) }
    }
    func pin(_ playlist: MusicPlaylist) {
        if pinned.contains(playlist.id) { pinned.remove(playlist.id) } else { pinned.insert(playlist.id) }
        UserDefaults.standard.set(Array(pinned), forKey: preferencePrefix + ".pins")
    }
    func refresh() async {
        let token = session
        do {
            let refreshed = try await service.playlists()
            guard token == session else { return }
            playlists = refreshed
            loadedTracks = [:]
            await select(selectedID)
            record("Library refreshed.")
        } catch { if token == session { self.error = error.localizedDescription } }
    }
    private func mergeFavoriteStates(_ tracks: [LibraryTrack]) {
        var updated = favorites
        for track in tracks {
            guard let favorite = track.isFavorite else { continue }
            if favorite { updated.insert(track.id) }
            else { updated.remove(track.id) }
        }
        if updated != favorites { favorites = updated }
    }
}
