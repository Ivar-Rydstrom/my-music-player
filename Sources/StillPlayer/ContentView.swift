import SwiftUI
import Combine
#if SWIFT_PACKAGE
import PlayerCore
#endif

struct ContentView: View {
    @ObservedObject var model: AppModel
    @AppStorage("queue.visible") private var showQueue = true
    @State private var showSearch = false
    @State private var showDiagnostics = ProcessInfo.processInfo.arguments.contains("--connect-music")
    @State private var sidebarFilter = ""
    @State private var filters: [String: String] = [:]
    @State private var selections: [String: Set<String>] = [:]
    private let timer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

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
                if showQueue {
                    Divider()
                    QueuePanel(player: model.playback).frame(width: 270)
                }
            }
            Divider()
            PlayerBar(model: model, player: model.playback, showQueue: $showQueue)
        }
        .background(Palette.background)
        .onReceive(timer) { _ in model.playback.tick() }
        .task {
            await model.select(model.selectedID)
            if ProcessInfo.processInfo.arguments.contains("--connect-music") {
                await model.connect()
                let report = "Music.app connection: \(model.usesMusicApp ? "connected" : "failed"); playlist count: \(model.usesMusicApp ? model.playlists.count : 0); \(model.error ?? "no error")\n"
                FileHandle.standardOutput.write(Data(report.utf8))
            } else { await model.restoreConnectionIfNeeded() }
        }
        .sheet(isPresented: $showSearch) { SearchView(model: model) }
        .sheet(isPresented: $showDiagnostics) { DiagnosticsView(model: model) }
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
                Image(systemName: "waveform").foregroundStyle(Palette.accent)
                Text("still").font(.system(size: 25, weight: .semibold, design: .rounded))
            }.padding(.top, 44).padding(.bottom, 30).padding(.horizontal, 23)
            Button { showSearch = true } label: {
                HStack {
                    Label("Search", systemImage: "magnifyingglass")
                    Spacer()
                    Text("⌘K").foregroundStyle(Palette.muted)
                }.padding(10).background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 7))
            }.buttonStyle(.plain).keyboardShortcut("k").padding(.horizontal, 14)
            Text("YOUR MUSIC").font(.system(size: 10, weight: .semibold)).tracking(1.6)
                .foregroundStyle(Palette.muted).padding(.horizontal, 24).padding(.top, 30).padding(.bottom, 12)
            sidebarItem(model.isLive && !model.usesMusicApp ? "Favorites this session" : "Favorite songs", icon: "star", id: "favorites")
            HStack {
                Text("PLAYLISTS").font(.system(size: 10, weight: .semibold)).tracking(1.6)
                Spacer()
                Button { model.perform { await model.refresh() } } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.plain).help("Refresh library")
            }.foregroundStyle(Palette.muted).padding(.horizontal, 24).padding(.top, 30).padding(.bottom, 12)
            TextField("Filter playlists", text: $sidebarFilter).textFieldStyle(.plain)
                .font(.caption).padding(.horizontal, 24).padding(.bottom, 12)
            ScrollView {
                VStack(spacing: 3) {
                    ForEach(model.sortedPlaylists.filter { sidebarFilter.isEmpty || $0.name.localizedStandardContains(sidebarFilter) }) { playlist in
                        sidebarItem(playlist.name, icon: model.pinned.contains(playlist.id) ? "pin.fill" : "music.note.list", id: playlist.id)
                            .contextMenu {
                                Button(model.pinned.contains(playlist.id) ? "Unpin playlist" : "Pin playlist") { model.pin(playlist) }
                            }
                    }
                }
            }
            Spacer(minLength: 15)
            Button { showDiagnostics = true } label: {
                HStack(spacing: 8) {
                    Circle().fill(model.isLive ? Palette.accent : .orange).frame(width: 6, height: 6)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(model.usesMusicApp ? "Music.app connected" : model.isLive ? "MusicKit connected" : "Sample library").font(.caption.weight(.medium))
                        Text(model.isLive ? "Account & diagnostics" : "Simulated playback · no audio").font(.system(size: 10)).foregroundStyle(Palette.muted)
                    }
                    Spacer()
                    Image(systemName: "slider.horizontal.3").foregroundStyle(Palette.muted)
                }.padding(14)
            }.buttonStyle(.plain)
        }.background(Palette.surface.opacity(0.6))
    }

    private func sidebarItem(_ title: String, icon: String, id: String) -> some View {
        Button { Task { await model.select(id) } } label: {
            HStack(spacing: 11) {
                Image(systemName: icon).frame(width: 16).foregroundStyle(model.selectedID == id ? Palette.accent : Palette.muted)
                Text(title).lineLimit(1).font(.system(size: 12))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 11).padding(.vertical, 10)
            .background(model.selectedID == id ? Palette.accent.opacity(0.10) : .clear, in: RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }.buttonStyle(.plain).padding(.horizontal, 12)
    }

    private var mainContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(model.isLive ? "LIBRARY" : "PROTOTYPE / SAMPLE LIBRARY")
                    .font(.system(size: 10, weight: .medium)).tracking(1.7).foregroundStyle(Palette.muted)
                Spacer()
                Button { showDiagnostics = true } label: { Image(systemName: "gearshape") }.buttonStyle(.plain).help("Account and integration experiment")
            }.padding(.horizontal, 30).padding(.top, 43)
            HStack(alignment: .bottom, spacing: 24) {
                Artwork(url: model.playlist?.artwork, seed: model.playlist?.name ?? "Favorites", size: 124)
                VStack(alignment: .leading, spacing: 10) {
                    Text(model.selectedID == "favorites" ? "FAVORITES" : "PLAYLIST")
                        .font(.system(size: 9, weight: .semibold)).tracking(2).foregroundStyle(Palette.accent)
                    Text(model.selectedID == "favorites" ? "Your favorites" : model.playlist?.name ?? "Your music")
                        .font(.system(size: 32, weight: .semibold, design: .rounded)).lineLimit(2)
                    Text(model.selectedID == "favorites" ? model.usesMusicApp ? "Favorite songs in your Music library." : model.isLive ? "Favorite requests accepted in this session. Account favorites are not imported yet." : "Always worth another listen." : model.playlist?.subtitle ?? "Choose a playlist to get started.")
                        .font(.system(size: 12)).foregroundStyle(Palette.muted)
                    Text("\(model.tracks.count) songs · \(Int(model.tracks.reduce(0) { $0 + $1.duration } / 60)) min")
                        .font(.system(size: 11)).foregroundStyle(Palette.muted)
                }
                Spacer(minLength: 0)
            }.padding(30)
            HStack(spacing: 12) {
                Button {
                    model.perform { try await model.playback.play(model.tracks) }
                } label: { Label("Play", systemImage: "play.fill").padding(.horizontal, 13).padding(.vertical, 4) }
                    .buttonStyle(.borderedProminent).foregroundStyle(Palette.background).disabled(model.tracks.isEmpty)
                Button {
                    model.perform {
                        model.playback.shuffle = true
                        try await model.playback.play(model.tracks.shuffled())
                    }
                } label: { Image(systemName: "shuffle") }.buttonStyle(.borderless).help("Shuffle playlist").disabled(model.tracks.isEmpty)
                Spacer()
                Image(systemName: "line.3.horizontal.decrease").foregroundStyle(Palette.muted)
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
                Text(model.usesMusicApp ? "Double-click to play in Music · Playlist order follows Music" : "Double-click to play · Right-click for more")
                Spacer()
                Text(model.usesMusicApp ? "Music.app" : model.isLive ? "MusicKit" : "Sample mode")
            }.font(.system(size: 10)).foregroundStyle(Palette.muted).padding(.horizontal, 30).padding(.vertical, 13)
        }
    }
}

struct Artwork: View {
    var url: URL?
    var seed: String
    var size: CGFloat
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
            if let url {
                AsyncImage(url: url) { image in image.resizable().scaledToFill() } placeholder: { Color.clear }
            }
        }.frame(width: size, height: size).clipShape(RoundedRectangle(cornerRadius: 8)).accessibilityHidden(true)
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
                    Text(row.title).font(.system(size: 12, weight: .medium)).lineLimit(1)
                }.padding(.vertical, 5)
            }.width(min: 165, ideal: 230)
            TableColumn("Artist", value: \.artist) { Text($0.artist).font(.system(size: 11)).foregroundStyle(Palette.muted) }.width(min: 90, ideal: 140)
            TableColumn("Album", value: \.album) { Text($0.album).font(.system(size: 11)).foregroundStyle(Palette.muted) }.width(min: 80, ideal: 140)
            TableColumn("", value: \.duration) { row in
                HStack {
                    if model.favorites.contains(row.track.id) { Image(systemName: "star.fill").foregroundStyle(Palette.accent) }
                    Spacer()
                    Text(clockText(row.duration)).monospacedDigit().foregroundStyle(Palette.muted)
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
                    Button(model.isLive && !model.usesMusicApp ? "Favorite in Apple Music" : model.favorites.contains(track.id) ? "Remove from favorites" : "Favorite song") {
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
