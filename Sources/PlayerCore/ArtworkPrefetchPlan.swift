import Foundation

/// A small work list, rather than one task for every offscreen image.
public struct ArtworkPrefetchPlan {
    private var tracks: [URL] = []
    private var playlists: [URL] = []
    private var trackIndex = 0
    private var playlistIndex = 0
    private var consecutiveTracks = 0

    public init() {}

    @discardableResult
    public mutating func setTracks(_ urls: [URL]) -> Bool {
        let updated = unique(urls)
        guard updated != tracks else { return false }
        tracks = updated
        trackIndex = 0
        consecutiveTracks = 0
        return true
    }

    @discardableResult
    public mutating func setPlaylists(_ urls: [URL]) -> Bool {
        let updated = unique(urls)
        guard updated != playlists else { return false }
        playlists = updated
        playlistIndex = 0
        return true
    }

    public mutating func restart() {
        trackIndex = 0
        playlistIndex = 0
        consecutiveTracks = 0
    }

    public mutating func next() -> URL? {
        // Keep warming sidebar covers even during a very large open playlist.
        if playlistIndex < playlists.count && (trackIndex == tracks.count || consecutiveTracks >= 8) {
            defer { playlistIndex += 1; consecutiveTracks = 0 }
            return playlists[playlistIndex]
        }
        if trackIndex < tracks.count {
            defer { trackIndex += 1; consecutiveTracks += 1 }
            return tracks[trackIndex]
        }
        return nil
    }

    private func unique(_ urls: [URL]) -> [URL] {
        var seen = Set<URL>()
        return urls.filter { $0.scheme == "music-artwork" && seen.insert($0).inserted }
    }
}
