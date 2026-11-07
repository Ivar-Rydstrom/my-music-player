import SwiftUI
#if SWIFT_PACKAGE
import PlayerCore
#endif

/// One floating object at the bottom of the content card. It is the player pill; selecting two or more
/// songs morphs it into the selection action bar (a hairline of progress keeps playback visible); clicking
/// it (or ⇧⌘U) grows it into the fuller panel with volume, sleep timer, favorite and, where real, the queue.
struct FloatingPlayer: View {
    @Environment(\.playerTheme) private var theme
    @ObservedObject var model: AppModel
    @ObservedObject var player: PlaybackController
    @ObservedObject var workspace: Workspace
    @Namespace private var space
    @State private var seekDraft = 0.0
    @State private var seeking = false
    @State private var volumeDraft = 50.0
    @State private var changingVolume = false
    /// The debug Music.app layout shows the real volume slider and no queue, as Music.app mode does.
    private var isMusicApp: Bool { player.isMusicApp || workspace.debugMusicAppLayout }
    private var showsQueue: Bool { workspace.queueSupported && player.canEditQueue }

    enum Shape: Equatable { case pill, selection, expanded }
    private var shape: Shape {
        if workspace.pillExpanded { return .expanded }
        if workspace.selection.count > 1 { return .selection }
        return .pill
    }
    static let morph = Animation.spring(response: 0.42, dampingFraction: 0.82)

    var body: some View {
        ZStack(alignment: .bottom) {
            if shape == .expanded {
                Color.black.opacity(theme.isDark ? 0.28 : 0.10)
                    .contentShape(Rectangle())
                    .onTapGesture { toggle() }
                    .padding(.bottom, -16)
                    .transition(.opacity)
            }
            // The glass is one matched shape, so it stretches between the three forms while the
            // contents cross-fade inside it.
            switch shape {
            case .expanded:
                panel
                    .background(chrome(radius: 26))
                    .transition(.asymmetric(insertion: .opacity.animation(.easeOut(duration: 0.2).delay(0.08)), removal: .opacity.animation(.easeOut(duration: 0.1))))
            case .selection:
                selectionBar
                    .background(chrome(radius: 28))
                    .padding(.horizontal, 24)
                    .transition(.asymmetric(insertion: .opacity.animation(.easeOut(duration: 0.18).delay(0.1)), removal: .opacity.animation(.easeOut(duration: 0.1))))
            case .pill:
                pill
                    .background(chrome(radius: 31))
                    .frame(maxWidth: 660)
                    .padding(.horizontal, 24)
                    .transition(.asymmetric(insertion: .opacity.animation(.easeOut(duration: 0.18).delay(0.1)), removal: .opacity.animation(.easeOut(duration: 0.1))))
            }
        }
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .animation(Self.morph, value: shape)
        .onAppear { seekDraft = player.progress; volumeDraft = player.volume }
        .onChange(of: player.current?.id) { _, _ in seekDraft = min(player.progress, max(player.current?.duration ?? 0, 1)) }
        .onChange(of: player.progress) { _, value in if !seeking { seekDraft = min(value, max(player.current?.duration ?? 0, 1)) } }
        .onChange(of: player.volume) { _, value in if !changingVolume { volumeDraft = value } }
    }

    private func toggle() { withAnimation(Self.morph) { workspace.pillExpanded.toggle() } }

    private func chrome(radius: CGFloat) -> some View {
        glassChrome(RoundedRectangle(cornerRadius: radius, style: .continuous), theme: theme)
            .matchedGeometryEffect(id: "chrome", in: space)
    }

    // MARK: Collapsed pill

    private var pill: some View {
        HStack(spacing: 14) {
            Artwork(url: player.current?.artwork, seed: player.current?.album ?? "Still", size: 44, cornerRadius: 22)
                .matchedGeometryEffect(id: "art", in: space)
            VStack(alignment: .leading, spacing: 3) {
                Text(player.current?.title ?? "Nothing playing").font(.system(size: 13, weight: .semibold)).lineLimit(1)
                Text(player.current?.artist ?? "Pick a playlist to begin").font(.system(size: 12)).foregroundStyle(theme.muted).lineLimit(1)
            }
            .frame(width: 150, alignment: .leading)
            HStack(spacing: 16) {
                Button { model.perform { try await player.previous() } } label: { Image(systemName: "backward.fill") }
                    .accessibilityLabel("Previous track")
                playButton(size: 36)
                Button { model.perform { try await player.next() } } label: { Image(systemName: "forward.fill") }
                    .accessibilityLabel("Next track")
            }
            .font(.system(size: 14)).disabled(player.current == nil)
            seekBar.frame(minWidth: 150, maxWidth: 230)
            Button(action: toggle) { Image(systemName: "chevron.up").font(.system(size: 12, weight: .semibold)) }
                .foregroundStyle(theme.muted)
                .help(showsQueue ? "Show player and queue (⇧⌘U)" : "Show player (⇧⌘U)")
                .accessibilityLabel("Expand player")
        }
        .buttonStyle(.plain)
        .padding(.leading, 9).padding(.trailing, 20).frame(height: 62)
        .contentShape(Capsule())
        .onTapGesture(perform: toggle)
    }

    // MARK: Selection bar (the pill, morphed)

    private var selectionBar: some View {
        let tracks = workspace.selectedTracks()
        return ViewThatFits(in: .horizontal) {
            selectionContent(tracks, compact: false)
            selectionContent(tracks, compact: true)
        }
    }

    private func selectionContent(_ tracks: [LibraryTrack], compact: Bool) -> some View {
        HStack(spacing: 4) {
            Artwork(url: player.current?.artwork, seed: player.current?.album ?? "Still", size: 34, cornerRadius: 17)
                .matchedGeometryEffect(id: "art", in: space)
                .overlay {
                    if player.current != nil {
                        Button { model.perform { try await player.toggle() } } label: {
                            Image(systemName: player.isPlaying ? "pause.fill" : "play.fill").font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.white).frame(width: 34, height: 34).background(.black.opacity(0.3), in: Circle())
                        }
                        .buttonStyle(.plain).help(player.isPlaying ? "Pause (Space)" : "Play (Space)")
                        .accessibilityLabel(player.isPlaying ? "Pause" : "Play")
                    }
                }
                .padding(.trailing, 6)
            Text("\(tracks.count) selected").font(.system(size: 13, weight: .semibold)).monospacedDigit().fixedSize()
                .contentTransition(.numericText()).padding(.trailing, 8)
            Button { workspace.playSelection() } label: { Label("Play", systemImage: "play.fill") }
                .buttonStyle(SoftCapsuleStyle(prominent: true, compact: true)).help("Play from the first selected song (Return)")
            if showsQueue {
                PillAction(title: "Play next", icon: "text.line.first.and.arrowtriangle.forward", compact: compact) {
                    model.perform { try await player.enqueue(tracks, next: true) }
                }
                PillAction(title: "Add to queue", icon: "text.line.last.and.arrowtriangle.forward", compact: compact) {
                    model.perform { try await player.enqueue(tracks, next: false) }
                }
            }
            PillMenu(title: "Add to playlist", icon: "text.badge.plus", compact: compact) {
                AddToPlaylistMenu(model: model, tracks: tracks).playlistButtons
            }
            PillAction(title: "Favorite", icon: "star", compact: compact) { favoriteAll(model: model, tracks: tracks) }
            Rectangle().fill(theme.text.opacity(0.12)).frame(width: 1, height: 18).padding(.horizontal, 4)
            Button { withAnimation(Self.morph) { workspace.selection = [] } } label: {
                Image(systemName: "xmark").font(.system(size: 11, weight: .bold)).frame(width: 28, height: 28)
                    .background(theme.text.opacity(0.07), in: Circle())
            }
            .buttonStyle(.plain).foregroundStyle(theme.muted).help("Clear selection (Esc)").accessibilityLabel("Clear selection")
        }
        .foregroundStyle(theme.text)
        .padding(.leading, 11).padding(.trailing, 11).frame(height: 56)
        .overlay(alignment: .bottom) { progressLine.padding(.horizontal, 28).padding(.bottom, 4) }
        .fixedSize()
    }

    /// The playback hint that survives the morph: a hairline of progress along the bottom edge.
    private var progressLine: some View {
        GeometryReader { proxy in
            let fraction = player.current.map { min(1, player.progress / max($0.duration, 1)) } ?? 0
            ZStack(alignment: .leading) {
                Capsule().fill(theme.text.opacity(0.08))
                Capsule().fill(theme.accent.opacity(0.85)).frame(width: proxy.size.width * fraction)
            }
        }
        .frame(height: 2)
        .opacity(player.current == nil ? 0 : 1)
        .accessibilityHidden(true)
    }

    // MARK: Expanded panel

    private var panel: some View {
        HStack(alignment: .top, spacing: 0) {
            nowPlaying.frame(width: 340)
            if showsQueue {
                Divider().padding(.vertical, 22)
                queue.frame(width: 320)
            }
        }
        .frame(height: showsQueue ? 470 : nil)
    }

    private var nowPlaying: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Now playing").font(.system(size: 12, weight: .semibold)).foregroundStyle(theme.muted)
                Spacer()
                Button(action: toggle) { Image(systemName: "chevron.down").font(.system(size: 12, weight: .semibold)) }
                    .buttonStyle(.plain).foregroundStyle(theme.muted)
                    .help("Collapse (Esc or ⇧⌘U)").accessibilityLabel("Collapse player")
            }
            .padding(.bottom, 14)
            Artwork(url: player.current?.artwork, seed: player.current?.album ?? "Still", size: 170, cornerRadius: 12)
                .matchedGeometryEffect(id: "art", in: space)
                .shadow(color: .black.opacity(0.22), radius: 16, y: 8)
                .padding(.bottom, 18)
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(player.current?.title ?? "Nothing playing").font(.system(size: 17, weight: .semibold)).lineLimit(1)
                    Text(player.current.map { "\($0.artist) · \($0.album)" } ?? "Pick a playlist to begin")
                        .font(.system(size: 13)).foregroundStyle(theme.muted).lineLimit(1)
                }
                Spacer(minLength: 0)
                if let current = player.current {
                    Menu { AddToPlaylistMenu(model: model, tracks: [current]).playlistButtons } label: {
                        Image(systemName: "text.badge.plus").font(.system(size: 15)).foregroundStyle(theme.accent)
                    }
                    .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
                    .help("Add to playlist").accessibilityLabel("Add current song to a playlist")
                    Button { model.perform { try await model.favorite(current) } } label: {
                        Image(systemName: model.favorites.contains(current.id) ? "star.fill" : "star").font(.system(size: 16))
                    }
                    .buttonStyle(.plain).foregroundStyle(theme.accent)
                    .help(model.favorites.contains(current.id) ? "Remove from favorites" : "Favorite song")
                    .accessibilityLabel(model.favorites.contains(current.id) ? "Remove from favorites" : "Favorite song")
                }
            }
            .padding(.bottom, 12)
            seekBar.padding(.bottom, 14)
            HStack(spacing: 0) {
                Button { player.shuffle.toggle(); player.applyModes() } label: {
                    Image(systemName: "shuffle").foregroundStyle(player.shuffle ? theme.accent : theme.muted)
                }.help("Shuffle").accessibilityLabel("Shuffle")
                Spacer()
                Button { model.perform { try await player.previous() } } label: { Image(systemName: "backward.fill").font(.system(size: 18)) }
                    .accessibilityLabel("Previous track")
                Spacer()
                playButton(size: 50)
                Spacer()
                Button { model.perform { try await player.next() } } label: { Image(systemName: "forward.fill").font(.system(size: 18)) }
                    .accessibilityLabel("Next track")
                Spacer()
                Button { player.repeatAll.toggle(); player.applyModes() } label: {
                    Image(systemName: "repeat").foregroundStyle(player.repeatAll ? theme.accent : theme.muted)
                }.help("Repeat").accessibilityLabel("Repeat")
            }
            .buttonStyle(.plain).font(.system(size: 14)).disabled(player.current == nil)
            .padding(.horizontal, 6).padding(.bottom, 18)
            HStack(spacing: 10) {
                if isMusicApp {
                    Image(systemName: "speaker.fill").foregroundStyle(theme.muted).font(.system(size: 11))
                    Slider(value: $volumeDraft, in: 0...100) { editing in
                        changingVolume = editing
                        if !editing { player.setVolume(volumeDraft) }
                    }.controlSize(.small).accessibilityLabel("Music volume")
                    Image(systemName: "speaker.wave.3.fill").foregroundStyle(theme.muted).font(.system(size: 11))
                } else {
                    Button {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Sound-Settings.extension")!)
                    } label: { Label("Sound settings", systemImage: "speaker.wave.2") }
                        .buttonStyle(.plain).foregroundStyle(theme.muted).font(.system(size: 12))
                        .help("Volume follows your Mac's output").accessibilityLabel("System sound settings")
                    Spacer()
                }
                sleepMenu.padding(.leading, 8)
            }
        }
        .padding(24)
    }

    private var queue: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Up next").font(.system(size: 12, weight: .semibold)).foregroundStyle(theme.muted)
                Spacer()
                if !player.upcoming.isEmpty {
                    Button("Clear") { player.clearUpcoming() }.buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(theme.accent)
                        .help("Clear upcoming songs")
                }
            }
            .padding(.horizontal, 24).padding(.top, 24).padding(.bottom, 10)
            if player.upcoming.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Nothing queued").font(.system(size: 13, weight: .medium))
                    Text("Play a playlist, or use a song's ⋯ menu to add it here.").font(.system(size: 12)).foregroundStyle(theme.muted)
                }
                .padding(.horizontal, 24).padding(.top, 8)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(Array(player.upcoming.enumerated()), id: \.element.id) { offset, entry in
                            PillQueueRow(player: player, entry: entry, offset: offset, count: player.upcoming.count)
                        }
                    }
                    .padding(.horizontal, 12)
                }
                Text("\(player.upcoming.count) songs · \(Int(player.upcoming.reduce(0) { $0 + $1.track.duration } / 60)) min")
                    .font(.system(size: 12)).foregroundStyle(theme.muted).padding(.horizontal, 24).padding(.vertical, 14)
            }
        }
    }

    // MARK: Pieces

    private func playButton(size: CGFloat) -> some View {
        Button { model.perform { try await player.toggle() } } label: {
            Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: size * 0.4)).foregroundStyle(theme.buttonInk)
                .frame(width: size, height: size).background(theme.accent, in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(player.current == nil)
        .accessibilityLabel(player.isPlaying ? "Pause" : "Play")
    }

    private var seekBar: some View {
        HStack(spacing: 8) {
            Text(clockText(seeking ? seekDraft : player.progress)).frame(width: 32, alignment: .trailing)
            Slider(value: $seekDraft, in: 0...max(player.current?.duration ?? 0, 1)) { editing in
                seeking = editing
                if !editing { player.seek(seekDraft) }
            }
            .controlSize(.mini).disabled(player.current == nil).accessibilityLabel("Playback position")
            Text(clockText(player.current?.duration ?? 0)).frame(width: 32, alignment: .leading)
        }
        .font(.system(size: 11)).monospacedDigit().foregroundStyle(theme.muted)
    }

    private var sleepMenu: some View {
        Menu {
            Text("Pause playback after")
            ForEach([15, 30, 45, 60], id: \.self) { minutes in
                Button("\(minutes) minutes") { player.setSleepTimer(minutes: minutes) }
            }
            if let deadline = player.sleepUntil {
                Divider()
                Text("Pauses at \(deadline.formatted(date: .omitted, time: .shortened))")
                Button("Cancel sleep timer") { player.setSleepTimer(minutes: nil) }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: player.sleepUntil == nil ? "moon" : "moon.zzz.fill")
                if let deadline = player.sleepUntil { Text(deadline.formatted(date: .omitted, time: .shortened)) }
            }
            .foregroundStyle(player.sleepUntil == nil ? theme.muted : theme.accent)
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        .help("Sleep timer").accessibilityLabel("Sleep timer")
    }
}

private struct PillQueueRow: View {
    @Environment(\.playerTheme) private var theme
    @ObservedObject var player: PlaybackController
    var entry: PlaybackRow
    var offset: Int
    var count: Int
    @State private var hovering = false
    var body: some View {
        HStack(spacing: 10) {
            Artwork(url: entry.track.artwork, seed: entry.track.album, size: 32, cornerRadius: 6)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.track.title).font(.system(size: 13)).lineLimit(1)
                Text(entry.track.artist).font(.system(size: 12)).foregroundStyle(theme.muted).lineLimit(1)
            }
            Spacer(minLength: 0)
            Menu {
                Button("Move up") { player.move(entry.id, by: -1) }.disabled(offset == 0)
                Button("Move down") { player.move(entry.id, by: 1) }.disabled(offset == count - 1)
                Divider()
                Button("Remove from queue") { player.remove(entry.id) }
            } label: { Image(systemName: "ellipsis") }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .opacity(hovering ? 1 : 0.45)
                .accessibilityLabel("Queue actions for \(entry.track.title)")
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(hovering ? theme.muted.opacity(0.10) : .clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onHover { hovering = $0 }
    }
}
