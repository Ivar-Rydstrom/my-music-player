import Foundation
import MusicKit
#if SWIFT_PACKAGE
import PlayerCore
#endif

enum LibraryFailure: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}

@MainActor
protocol LibraryServing {
    func playlists() async throws -> [MusicPlaylist]
    func tracks(in playlist: MusicPlaylist) async throws -> [LibraryTrack]
    func search(_ term: String, catalog: Bool) async throws -> [LibraryTrack]
    func favorite(_ track: LibraryTrack) async throws
    func add(_ tracks: [LibraryTrack], to playlist: MusicPlaylist) async throws
}

@MainActor
final class SampleMusicLibrary: LibraryServing {
    private var library = SampleLibrary.playlists
    func playlists() async throws -> [MusicPlaylist] { library }
    func tracks(in playlist: MusicPlaylist) async throws -> [LibraryTrack] {
        library.first { $0.id == playlist.id }?.tracks ?? []
    }
    func search(_ term: String, catalog: Bool) async throws -> [LibraryTrack] {
        SampleLibrary.tracks.filter { $0.matches(term) }
    }
    func favorite(_ track: LibraryTrack) async throws {}
    func add(_ tracks: [LibraryTrack], to playlist: MusicPlaylist) async throws {
        if let index = library.firstIndex(where: { $0.id == playlist.id }) { library[index].tracks += tracks }
    }
}

@MainActor
final class AppleMusicLibrary: LibraryServing {
    struct AccountInfo {
        var canStream: Bool
        var cloudLibraryEnabled: Bool
        var storefront: String
    }
    private var nativePlaylists: [String: Playlist] = [:]
    private(set) var songs: [String: Song] = [:]

    func authorize(progress: (String) -> Void) async throws -> AccountInfo {
        progress("Checking app setup")
        if let issue = MusicAccountSetup.inspect().issue { throw LibraryFailure.message(issue) }
        progress("Waiting for music permission")
        switch await MusicAuthorization.request() {
        case .authorized: break
        case .denied:
            throw LibraryFailure.message("Music access was denied. Enable Still in System Settings > Privacy & Security > Media & Apple Music, then reconnect.")
        case .restricted:
            throw LibraryFailure.message("Music access is restricted by account or device policy. Check Screen Time or device management settings.")
        case .notDetermined:
            throw LibraryFailure.message("Music permission has not been granted. Activate Still and try connecting again.")
        @unknown default:
            throw LibraryFailure.message("macOS returned an unknown music permission status. Try connecting again.")
        }
        // Prove token generation and an authenticated service request before claiming connection.
        progress("Verifying Apple Music access")
        let request = URLRequest(url: URL(string: "https://api.music.apple.com/v1/me/storefront")!)
        let response = try await MusicDataRequest(urlRequest: request).response()
        guard (200..<300).contains(response.urlResponse.statusCode) else {
            throw LibraryFailure.message("Apple Music access check returned HTTP \(response.urlResponse.statusCode). Confirm MusicKit is enabled for this exact App ID and that Media & Purchases is signed in on this Mac.")
        }
        struct StorefrontResponse: Decodable {
            struct Item: Decodable { var id: String }
            var data: [Item]
        }
        let storefront = try JSONDecoder().decode(StorefrontResponse.self, from: response.data).data.first?.id
        guard let storefront else { throw LibraryFailure.message("Apple Music returned no account storefront. Check the Media & Purchases account on this Mac.") }
        progress("Checking subscription")
        let subscription = try await MusicSubscription.current
        return AccountInfo(canStream: subscription.canPlayCatalogContent,
                           cloudLibraryEnabled: subscription.hasCloudLibraryEnabled, storefront: storefront)
    }

    func playlists() async throws -> [MusicPlaylist] {
        var request = MusicLibraryRequest<Playlist>()
        request.limit = 100
        var page: MusicItemCollection<Playlist>? = try await request.response().items
        var result: [MusicPlaylist] = []
        while let batch = page {
            try Task.checkCancellation()
            for playlist in batch {
                nativePlaylists[playlist.id.rawValue] = playlist
                result.append(MusicPlaylist(id: playlist.id.rawValue, name: playlist.name,
                    subtitle: playlist.curatorName ?? "Your Apple Music library",
                    artwork: playlist.artwork?.url(width: 320, height: 320)))
            }
            page = batch.hasNextBatch ? try await batch.nextBatch(limit: 100) : nil
        }
        return result
    }

    func tracks(in playlist: MusicPlaylist) async throws -> [LibraryTrack] {
        guard let native = nativePlaylists[playlist.id] else { return [] }
        let detailed = try await native.with([.tracks])
        var page = detailed.tracks
        var result: [LibraryTrack] = []
        while let batch = page {
            try Task.checkCancellation()
            for track in batch {
                if case .song(let song) = track { result.append(remember(song)) }
            }
            page = batch.hasNextBatch ? try await batch.nextBatch(limit: 100) : nil
        }
        return result
    }

    func search(_ term: String, catalog: Bool) async throws -> [LibraryTrack] {
        let found: MusicItemCollection<Song>
        if catalog {
            var request = MusicCatalogSearchRequest(term: term, types: [Song.self])
            request.limit = 25
            found = try await request.response().songs
        } else {
            var request = MusicLibrarySearchRequest(term: term, types: [Song.self])
            request.limit = 25
            found = try await request.response().songs
        }
        return found.map { remember($0) }
    }

    func remember(_ song: Song) -> LibraryTrack {
        songs[song.id.rawValue] = song
        return LibraryTrack(id: song.id.rawValue, title: song.title, artist: song.artistName,
                     album: song.albumTitle ?? "", duration: song.duration ?? 0,
                     artwork: song.artwork?.url(width: 160, height: 160),
                     resourceType: song.id.rawValue.hasPrefix("i.") ? "library-songs" : "songs")
    }

    func favorite(_ track: LibraryTrack) async throws {
        var components = URLComponents(string: "https://api.music.apple.com/v1/me/favorites")!
        components.queryItems = [URLQueryItem(name: "ids[\(track.resourceType)]", value: track.id)]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        try await perform(request)
    }

    func add(_ tracks: [LibraryTrack], to playlist: MusicPlaylist) async throws {
        let url = URL(string: "https://api.music.apple.com/v1/me/library/playlists")!
            .appendingPathComponent(playlist.id).appendingPathComponent("tracks")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["data": tracks.map {
            ["id": $0.id, "type": $0.resourceType]
        }])
        try await perform(request)
    }

    private func perform(_ request: URLRequest) async throws {
        let response = try await MusicDataRequest(urlRequest: request).response()
        guard (200..<300).contains(response.urlResponse.statusCode) else {
            throw LibraryFailure.message("Apple Music returned HTTP \(response.urlResponse.statusCode).")
        }
    }
}
