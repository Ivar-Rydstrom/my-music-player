import SwiftUI
import Combine
#if SWIFT_PACKAGE
import PlayerCore
#endif

struct ContentView: View {
    @Environment(\.playerTheme) private var theme
    @ObservedObject var model: AppModel
    @AppStorage("queue.visible") private var showQueue = true
    @State private var showSearch = false
    @Environment(\.openSettings) private var openSettings
    @State private var sidebarFilter = ""
    @State private var filters: [String: String] = [:]
    @State private var selections: [String: Set<String>] = [:]

    private var viewID: String { model.selectedID ?? "none" }
    private var filter: Binding<String> { Binding(get: { filters[viewID] ?? "" }, set: { filters[viewID] = $0 }) }
    private var selection: Binding<Set<String>> { Binding(get: { selections[viewID] ?? [] }, set: { selections[viewID] = $0 }) }
    private var visible: [LibraryTrack] { model.tracks.filter { $0.matches(filter.wrappedValue) } }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                sidebar.frame(width: 225)
                Divider()
                mainContent.frame(maxWidth: .infinity, maxHeight: .infinity)
                if showQueue && !model.usesMusicApp {
                    Divider()
                    QueuePanel(player: model.playback).frame(width: 270)
                }
            }
            Divider()
            PlayerBar(model: model, player: model.playback, showQueue: $showQueue)
        }
        .background(theme.background)
        .task {
            if ProcessInfo.processInfo.arguments.contains("--sample-library") { model.useSamples() }
            await model.select(model.selectedID)
            if ProcessInfo.processInfo.arguments.contains("--connect-music") {
                await model.connect()
                let report = "Music.app connection: \(model.usesMusicApp ? "connected" : "failed"); playlist count: \(model.usesMusicApp ? model.playlists.count : 0); \(model.error ?? "no error")\n"
                FileHandle.standardOutput.write(Data(report.utf8))
            } else if !ProcessInfo.processInfo.arguments.contains("--sample-library") { await model.restoreConnectionIfNeeded() }
            if ProcessInfo.processInfo.arguments.contains("--show-settings") || ProcessInfo.processInfo.arguments.contains("--connect-music") { openSettings() }
        }
        .task(id: model.tracks.compactMap(\.artwork)) {
            await MusicArtworkLoader.shared.prefetchTracks(model.tracks.compactMap(\.artwork))
        }
        .task(id: model.playlists.compactMap(\.artwork)) {
            await MusicArtworkLoader.shared.prefetchPlaylists(model.playlists.compactMap(\.artwork))
        }
        .sheet(isPresented: $showSearch) { SearchView(model: model) }

        .alert("Couldn't complete that action", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("OK") { model.error = nil }
        } message: { Text(model.error ?? "") }
        .overlay(alignment: .top) {
            if let notice = model.notice {
                HStack {
                    Text(notice).font(.callout)
                    Button { model.notice = nil } label: { Image(systemName: "xmark") }.buttonStyle(.plain)
                }
                .padding(12).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                .padding(.top, 36)
                .task(id: notice) { try? await Task.sleep(for: .seconds(6)); if model.notice == notice { model.notice = nil } }
            }
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 9) {
                Image(systemName: "waveform").foregroundStyle(theme.accent)
                Text("still").font(.system(size: 25, weight: .semibold, design: .rounded))
            }.padding(.top, 44).padding(.bottom, 30).padding(.horizontal, 23)
            Button { showSearch = true } label: {
                HStack {
                    Label("Search", systemImage: "magnifyingglass")
                    Spacer()
                    Text("⌘K").foregroundStyle(theme.muted)
                }.padding(10).background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 7))
            }.buttonStyle(.plain).keyboardShortcut("k").padding(.horizontal, 14)
            Text("YOUR MUSIC").font(.system(size: 10, weight: .semibold)).tracking(1.6)
                .foregroundStyle(theme.muted).padding(.horizontal, 24).padding(.top, 30).padding(.bottom, 12)
            sidebarItem("Recently played", icon: "clock.arrow.circlepath", id: "recent")
            sidebarItem(model.isLive && !model.usesMusicApp ? "Favorites this session" : "Favorite songs", icon: "star", id: "favorites")
            HStack {
                Text("PLAYLISTS").font(.system(size: 10, weight: .semibold)).tracking(1.6)
                Spacer()
                Button { model.perform { await model.refresh() } } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.plain).help("Refresh library")
            }.foregroundStyle(theme.muted).padding(.horizontal, 24).padding(.top, 30).padding(.bottom, 12)
            TextField("Filter playlists", text: $sidebarFilter).textFieldStyle(.plain)
                .font(.caption).padding(.horizontal, 24).padding(.bottom, 12)
            ScrollView {
                LazyVStack(spacing: 3) {
                    ForEach(model.sortedPlaylists.filter { sidebarFilter.isEmpty || $0.name.localizedStandardContains(sidebarFilter) }) { playlist in
                        sidebarItem(playlist.name, icon: model.pinned.contains(playlist.id) ? "pin.fill" : "music.note.list", id: playlist.id, artwork: playlist.artwork)
                            .contextMenu {
                                Button(model.pinned.contains(playlist.id) ? "Unpin playlist" : "Pin playlist") { model.pin(playlist) }
                            }
                    }
                }
            }
            Spacer(minLength: 15)
            Button { openSettings() } label: {
                HStack(spacing: 8) {
                    Circle().fill(model.isLive ? theme.accent : .orange).frame(width: 6, height: 6)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(model.isLive ? "Library connected" : "Sample library").font(.caption.weight(.medium))
                        Text(model.isLive ? "Settings & appearance" : "Settings · Demo has no audio").font(.system(size: 10)).foregroundStyle(theme.muted)
                    }
                    Spacer()
                    Image(systemName: "slider.horizontal.3").foregroundStyle(theme.muted)
                }.padding(14)
            }.buttonStyle(.plain)
        }.background(theme.surface.opacity(0.6))
    }

    private func sidebarItem(_ title: String, icon: String, id: String, artwork: URL? = nil) -> some View {
        Button { Task { await model.select(id) } } label: {
            HStack(spacing: 11) {
                if let artwork {
                    Artwork(url: artwork, seed: title, size: 28)
                } else {
                    Image(systemName: icon).frame(width: 16).foregroundStyle(model.selectedID == id ? theme.accent : theme.muted)
                }
                Text(title).lineLimit(1).font(.system(size: 12))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 11).padding(.vertical, 10)
            .background(model.selectedID == id ? theme.accent.opacity(0.10) : .clear, in: RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }.buttonStyle(.plain).padding(.horizontal, 12)
    }

    private var mainContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(model.isLive ? "YOUR LIBRARY" : "SAMPLE LIBRARY")
                    .font(.system(size: 10, weight: .medium)).tracking(1.7).foregroundStyle(theme.muted)
                Spacer()
                Button { openSettings() } label: { Image(systemName: "gearshape") }.buttonStyle(.plain).help("Settings").accessibilityLabel("Settings")
            }.padding(.horizontal, 30).padding(.top, 43)
            HStack(alignment: .bottom, spacing: 24) {
                Artwork(url: model.playlist?.artwork, seed: model.selectedID == "recent" ? "Recently played" : model.playlist?.name ?? "Favorites", size: 124)
                VStack(alignment: .leading, spacing: 10) {
                    Text(model.selectedID == "recent" ? "LISTENING HISTORY" : model.selectedID == "favorites" ? "FAVORITES" : "PLAYLIST")
                        .font(.system(size: 9, weight: .semibold)).tracking(2).foregroundStyle(theme.accent)
                    Text(model.selectedID == "recent" ? "Recently played" : model.selectedID == "favorites" ? "Your favorites" : model.playlist?.name ?? "Your music")
                        .font(.system(size: 32, weight: .semibold, design: .rounded)).lineLimit(2)
                    Text(model.selectedID == "recent" ? "The songs you come back to. From this session." : model.selectedID == "favorites" ? model.usesMusicApp ? "Your most-loved songs, all together." : model.isLive ? "Favorite requests accepted in this session. Account favorites are not imported yet." : "Always worth another listen." : model.playlist?.subtitle ?? "Choose a playlist to get started.")
                        .font(.system(size: 12)).foregroundStyle(theme.muted)
                    Text("\(model.tracks.count) songs · \(Int(model.tracks.reduce(0) { $0 + $1.duration } / 60)) min")
                        .font(.system(size: 11)).foregroundStyle(theme.muted)
                }
                Spacer(minLength: 0)
            }.padding(30).frame(maxWidth: .infinity, alignment: .leading).background(theme.wash)
            HStack(spacing: 12) {
                Button {
                    model.perform { try await model.playback.play(model.tracks) }
                } label: { Label("Play", systemImage: "play.fill").padding(.horizontal, 13).padding(.vertical, 4) }
                    .buttonStyle(.borderedProminent).foregroundStyle(theme.buttonInk).disabled(model.tracks.isEmpty)
                Button {
                    model.perform {
                        model.playback.shuffle = true
                        try await model.playback.play(model.tracks)
                    }
                } label: { Image(systemName: "shuffle") }.buttonStyle(.borderless).help("Shuffle playlist").disabled(model.tracks.isEmpty)
                if model.selectedID == "recent", !model.recentTracks.isEmpty {
                    Button("Clear history") { model.recentTracks = [] }.buttonStyle(.plain).font(.caption).foregroundStyle(theme.muted)
                }
                Spacer()
                Image(systemName: "line.3.horizontal.decrease").foregroundStyle(theme.muted)
                TextField("Find in playlist", text: filter).textFieldStyle(.plain).frame(width: 155)
            }.padding(.horizontal, 30).padding(.bottom, 20)
            Divider().padding(.horizontal, 30)
            if model.loadingPlaylistID == model.selectedID {
                ProgressView("Loading songs…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if visible.isEmpty {
                ContentUnavailableView(filter.wrappedValue.isEmpty ? "No songs here yet" : "No matching songs",
                    systemImage: "music.note", description: Text("Choose another playlist or search your library."))
            } else {
                TrackTable(model: model, tracks: visible, selection: selection).id(viewID)
                    .padding(.horizontal, 18)
            }
            HStack {
                Text("Double-click to play · Right-click for more")
                Spacer()
                Text(model.isLive ? "Connected" : "Sample mode")
            }.font(.system(size: 10)).foregroundStyle(theme.muted).padding(.horizontal, 30).padding(.vertical, 13)
        }
    }
}

struct Artwork: View {
    @Environment(\.playerTheme) private var theme
    var url: URL?
    var seed: String
    var size: CGFloat
    @State private var localImage: NSImage?
    private var hue: Double { Double(seed.utf8.reduce(0) { $0 + Int($1) } % 100) / 100 }
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8).fill(Color(hue: hue, saturation: 0.27, brightness: 0.32).gradient)
            GeometryReader { proxy in
                ZStack {
                    ForEach(0..<7) { index in
                        Circle().stroke(.white.opacity(0.14), lineWidth: max(1, size / 90))
                            .frame(width: proxy.size.width * (0.3 + Double(index) * 0.2))
                    }
                }.position(x: proxy.size.width * 0.75, y: proxy.size.height * 0.7)
            }.clipped()
            if url?.scheme == "music-artwork" {
                if let localImage {
                    Image(nsImage: localImage).resizable().scaledToFill()
                }
            } else if let url {
                AsyncImage(url: url) { image in image.resizable().scaledToFill() } placeholder: { Color.clear }
            }
        }.frame(width: size, height: size).clipShape(RoundedRectangle(cornerRadius: 8)).accessibilityHidden(true)
        .task(id: url) {
            localImage = nil
            guard let url, url.scheme == "music-artwork" else { return }
            let data = await MusicArtworkLoader.shared.thumbnail(for: url, pixels: size > 48 ? 320 : 96)
            guard !Task.isCancelled else { return }
            localImage = data.flatMap { NSImage(data: $0) }
        }
    }
}

struct DisplayTrack: Identifiable {
    var id: String
    var track: LibraryTrack
    var title: String { track.title }
    var artist: String { track.artist }
    var album: String { track.album }
    var duration: Double { track.duration }
}

struct TrackTable: View {
    @Environment(\.playerTheme) private var theme
    @ObservedObject var model: AppModel
    var tracks: [LibraryTrack]
    @Binding var selection: Set<String>
    @State private var sortOrder = [KeyPathComparator<DisplayTrack>]()
    private var rows: [DisplayTrack] {
        tracks.enumerated().map { DisplayTrack(id: "\($0.offset):\($0.element.id)", track: $0.element) }.sorted(using: sortOrder)
    }
    private func selected(_ ids: Set<String>) -> [LibraryTrack] { rows.filter { ids.contains($0.id) }.map(\.track) }
    var body: some View {
        Table(rows, selection: $selection, sortOrder: $sortOrder) {
            TableColumn("Title", value: \.title) { row in
                HStack(spacing: 10) {
                    Artwork(url: row.track.artwork, seed: row.album, size: 31)
                    if model.playback.current?.id == row.track.id {
                        Image(systemName: model.playback.isPlaying ? "waveform" : "pause.fill").foregroundStyle(theme.accent).font(.caption).accessibilityLabel("Current song")
                    }
                    Text(row.title).font(.system(size: 12, weight: .medium)).lineLimit(1)
                }.padding(.vertical, 5)
            }.width(min: 165, ideal: 230)
            TableColumn("Artist", value: \.artist) { Text($0.artist).font(.system(size: 11)).foregroundStyle(theme.muted) }.width(min: 90, ideal: 140)
            TableColumn("Album", value: \.album) { Text($0.album).font(.system(size: 11)).foregroundStyle(theme.muted) }.width(min: 80, ideal: 140)
            TableColumn("", value: \.duration) { row in
                HStack {
                    if model.favorites.contains(row.track.id) { Image(systemName: "star.fill").foregroundStyle(theme.accent) }
                    Spacer()
                    Text(clockText(row.duration)).monospacedDigit().foregroundStyle(theme.muted)
                }.font(.system(size: 10))
            }.width(65)
        }
        .tableStyle(.inset(alternatesRowBackgrounds: false))
        .scrollContentBackground(.hidden)
        .contextMenu(forSelectionType: String.self) { ids in
            let chosen = selected(ids)
            if !chosen.isEmpty {
                if model.playback.canEditQueue {
                    Button("Play next") { model.perform { try await model.playback.enqueue(chosen, next: true) } }
                    Button("Add to queue") { model.perform { try await model.playback.enqueue(chosen, next: false) } }
                }
                if let track = chosen.first, chosen.count == 1 {
                    Button(model.favorites.contains(track.id) && (!model.isLive || model.usesMusicApp) ? "Remove from favorites" : "Favorite song") {
                        model.perform { try await model.favorite(track) }
                    }
                }
                Menu("Add to playlist") {
                    ForEach(model.playlists.filter(\.canAddTracks)) { playlist in
                        Button(playlist.name) { model.perform { try await model.add(chosen, to: playlist) } }
                    }
                }
            }
        } primaryAction: { ids in
            guard let first = rows.firstIndex(where: { ids.contains($0.id) }) else { return }
            model.perform { try await model.playback.play(rows.map(\.track), at: first) }
        }
    }
}
