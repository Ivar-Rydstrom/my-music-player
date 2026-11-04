import Foundation
import MusicKit
import Combine
#if SWIFT_PACKAGE
import PlayerCore
#endif

struct PlaybackRow: Identifiable {
    var id: String
    var track: LibraryTrack
}

@MainActor
final class PlaybackController: ObservableObject {
    @Published private(set) var current: LibraryTrack?
    @Published private(set) var upcoming: [PlaybackRow] = []
    @Published private(set) var isPlaying = false
    @Published private(set) var progress: Double = 0
    @Published var shuffle = false
    @Published var repeatAll = false
    @Published private(set) var volume: Double = 50
    @Published private(set) var sleepUntil: Date?
    @Published var errorMessage: String?
    private var demo = DemoQueue()
    private var nativeLibrary: AppleMusicLibrary?
    private var musicApp: MusicAppLibrary?
    private var generation = UUID()
    private var polling = false
    private var pollingSuspended = false
    private var lastTick = Date()
    private var ticker: AnyCancellable?
    init() {
        ticker = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()
            .sink { [weak self] _ in self?.tick() }
    }
    private var player: ApplicationMusicPlayer { .shared }
    var isLive: Bool { nativeLibrary != nil || musicApp != nil }
    var isMusicApp: Bool { musicApp != nil }
    var canEditQueue: Bool { !isMusicApp }

    func configure(library: AppleMusicLibrary?) {
        if nativeLibrary != nil { player.stop() }
        sleepUntil = nil
        generation = UUID(); musicApp = nil; pollingSuspended = false
        nativeLibrary = library
        demo = DemoQueue()
        current = nil; upcoming = []; isPlaying = false; progress = 0
        shuffle = false; repeatAll = false
    }

    func configure(musicApp library: MusicAppLibrary, snapshot: MusicAppSnapshot) {
        configure(library: nil)
        musicApp = library
        accept(snapshot)
    }

    func play(_ tracks: [LibraryTrack], at offset: Int = 0) async throws {
        guard !tracks.isEmpty else { return }
        if let musicApp {
            try await musicApp.setShuffle(shuffle)
            try await musicApp.play(tracks[min(max(0, offset), tracks.count - 1)])
            await pollMusicApp()
        } else if let library = nativeLibrary {
            let songs = try tracks.map { track -> Song in
                guard let song = library.songs[track.id] else {
                    throw LibraryFailure.message("This track is no longer loaded. Refresh the playlist.")
                }
                return song
            }
            player.queue = ApplicationMusicPlayer.Queue(for: songs, startingAt: songs[min(offset, songs.count - 1)])
            applyModes()
            try await player.play()
        } else {
            demo.replace(with: tracks, startingAt: offset)
            if shuffle { demo.shuffleUpcoming() }
            progress = 0; isPlaying = true
        }
        lastTick = Date(); refresh()
    }

    func toggle() async throws {
        if let musicApp { try await musicApp.toggle(); await pollMusicApp() }
        else if nativeLibrary != nil {
            if player.state.playbackStatus == .playing { player.pause() }
            else if current != nil { try await player.play() }
        } else if current != nil { isPlaying.toggle() }
        lastTick = Date(); refresh()
    }

    func next() async throws {
        if let musicApp { try await musicApp.next(); await pollMusicApp() }
        else if nativeLibrary != nil { try await player.skipToNextEntry() }
        else { if !demo.advance(repeatAll: repeatAll) { isPlaying = false }; progress = 0 }
        refresh()
    }
    func previous() async throws {
        if let musicApp { try await musicApp.previous(); await pollMusicApp() }
        else if nativeLibrary != nil { try await player.skipToPreviousEntry() }
        else { if progress < 3 { demo.previous() }; progress = 0 }
        refresh()
    }
    func seek(_ value: Double) {
        let bounded = min(max(0, value), current?.duration ?? 0)
        if let musicApp {
            sendToMusic { try await musicApp.seek(bounded) }
        } else if nativeLibrary != nil { player.playbackTime = bounded }
        progress = bounded
    }
    func enqueue(_ tracks: [LibraryTrack], next: Bool) async throws {
        guard canEditQueue else { throw LibraryFailure.message("Music manages Up Next. Open Music to edit its queue.") }
        if let library = nativeLibrary {
            let songs = try tracks.map { track -> Song in
                guard let song = library.songs[track.id] else { throw LibraryFailure.message("Reload this track before queueing it.") }
                return song
            }
            try await player.queue.insert(songs, position: next ? .afterCurrentEntry : .tail)
        } else { demo.insert(tracks, next: next) }
        refresh()
    }
    func remove(_ id: String) {
        guard canEditQueue else { return }
        if nativeLibrary != nil {
            guard let index = player.queue.entries.firstIndex(where: { $0.id == id }),
                  let currentIndex = player.queue.entries.firstIndex(where: { $0.id == player.queue.currentEntry?.id }),
                  index > currentIndex else { return }
            player.queue.entries.remove(at: index)
        } else if let uuid = UUID(uuidString: id) { demo.remove(uuid) }
        refresh()
    }
    func move(_ id: String, by delta: Int) {
        guard canEditQueue else { return }
        if nativeLibrary != nil {
            var entries = player.queue.entries
            guard let source = entries.firstIndex(where: { $0.id == id }),
                  let currentIndex = entries.firstIndex(where: { $0.id == player.queue.currentEntry?.id }),
                  source > currentIndex, source + delta > currentIndex,
                  entries.indices.contains(source + delta) else { return }
            entries.swapAt(source, source + delta)
            player.queue.entries = entries
        } else if let uuid = UUID(uuidString: id) { demo.move(uuid, by: delta) }
        refresh()
    }
    func applyModes() {
        if let musicApp {
            let shuffle = shuffle, repeatAll = repeatAll
            sendToMusic {
                try await musicApp.setShuffle(shuffle)
                try await musicApp.setRepeat(repeatAll)
            }
            return
        }
        guard nativeLibrary != nil else {
            if shuffle { demo.shuffleUpcoming(); refresh() }
            return
        }
        player.state.shuffleMode = shuffle ? .songs : .off
        player.state.repeatMode = repeatAll ? .all : MusicPlayer.RepeatMode.none
    }
    func setSleepTimer(minutes: Int?) {
        sleepUntil = minutes.map { Date().addingTimeInterval(Double($0) * 60) }
    }
    func clearUpcoming() {
        for entry in upcoming { remove(entry.id) }
    }
    private func pauseForSleep() async throws {
        if let musicApp { try await musicApp.pause(); await pollMusicApp() }
        else if nativeLibrary != nil { player.pause() }
        else { isPlaying = false }
        refresh()
    }
    func tick(now: Date = Date()) {
        if let deadline = sleepUntil, now >= deadline {
            sleepUntil = nil
            let token = generation
            Task {
                guard token == generation else { return }
                do { try await pauseForSleep() }
                catch { if token == generation { errorMessage = error.localizedDescription } }
            }
        }
        defer { lastTick = Date() }
        if musicApp != nil {
            guard !polling, !pollingSuspended else { return }
            polling = true
            Task { await pollMusicApp(); polling = false }
            return
        }
        if !isLive && isPlaying {
            progress += min(Date().timeIntervalSince(lastTick), 2)
            if progress >= (current?.duration ?? 0) {
                progress = 0
                if !demo.advance(repeatAll: repeatAll) { isPlaying = false }
            }
        }
        refresh()
    }
    private func refresh() {
        guard musicApp == nil else { return }
        if let library = nativeLibrary {
            isPlaying = player.state.playbackStatus == .playing
            progress = max(0, player.playbackTime)
            if case .song(let song) = player.queue.currentEntry?.item { current = library.remember(song) }
            else { current = nil }
            let entries = Array(player.queue.entries)
            let index = entries.firstIndex { $0.id == player.queue.currentEntry?.id }
            upcoming = entries.dropFirst(index.map { $0 + 1 } ?? 0).compactMap { entry in
                guard case .song(let song) = entry.item else { return nil }
                return PlaybackRow(id: entry.id, track: library.remember(song))
            }
        } else {
            current = demo.current?.track
            upcoming = demo.upcoming.map { PlaybackRow(id: $0.id.uuidString, track: $0.track) }
        }
    }

    func setVolume(_ value: Double) {
        guard let musicApp else { return }
        volume = value
        sendToMusic { try await musicApp.setVolume(value) }
    }
    private func sendToMusic(_ action: @escaping @MainActor () async throws -> Void) {
        let token = generation
        Task {
            do { try await action() }
            catch { if token == generation { errorMessage = error.localizedDescription } }
        }
    }
    private func pollMusicApp() async {
        guard let musicApp else { return }
        let token = generation
        do {
            let snapshot = try await musicApp.snapshot()
            guard token == generation else { return }
            accept(snapshot)
            pollingSuspended = false
        } catch {
            guard token == generation else { return }
            // Stop repeating failed events after a denied permission, quit, or hung Music process.
            pollingSuspended = true
            errorMessage = error.localizedDescription
        }
    }
    private func accept(_ snapshot: MusicAppSnapshot) {
        if current != snapshot.track { current = snapshot.track }
        isPlaying = snapshot.isPlaying
        progress = max(0, snapshot.position); shuffle = snapshot.shuffle
        repeatAll = snapshot.repeatAll; volume = snapshot.volume
        upcoming = []
    }
}
