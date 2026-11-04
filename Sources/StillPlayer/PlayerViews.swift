import SwiftUI
#if SWIFT_PACKAGE
import PlayerCore
#endif

struct PlayerBar: View {
    @ObservedObject var model: AppModel
    @ObservedObject var player: PlaybackController
    @Binding var showQueue: Bool
    @State private var seekDraft = 0.0
    @State private var seeking = false
    @State private var volumeDraft = 50.0
    @State private var changingVolume = false
    var body: some View {
        HStack(spacing: 24) {
            HStack(spacing: 12) {
                Artwork(url: player.current?.artwork, seed: player.current?.album ?? "Still", size: 46)
                VStack(alignment: .leading, spacing: 5) {
                    Text(player.current?.title ?? "Make room for music").font(.system(size: 12, weight: .medium)).lineLimit(1)
                    Text(player.current?.artist ?? "Choose something to play").font(.system(size: 11)).foregroundStyle(Palette.muted).lineLimit(1)
                }
                Spacer(minLength: 3)
                if let current = player.current {
                    Button { model.perform { try await model.favorite(current) } } label: {
                        Image(systemName: model.favorites.contains(current.id) ? "star.fill" : "star")
                    }.buttonStyle(.plain).foregroundStyle(Palette.accent).help("Favorite song")
                }
            }.frame(width: 250)
            VStack(spacing: 8) {
                HStack(spacing: 23) {
                    Button { player.shuffle.toggle(); player.applyModes() } label: {
                        Image(systemName: "shuffle").foregroundStyle(player.shuffle ? Palette.accent : Palette.muted)
                    }.help("Shuffle").accessibilityLabel("Shuffle")
                    Button { model.perform { try await player.previous() } } label: { Image(systemName: "backward.end.fill") }
                        .accessibilityLabel("Previous track")
                    Button { model.perform { try await player.toggle() } } label: {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 15)).foregroundStyle(Palette.background)
                            .frame(width: 34, height: 34).background(Palette.accent, in: Circle())
                    }.keyboardShortcut(.space, modifiers: []).accessibilityLabel(player.isPlaying ? "Pause" : "Play")
                    Button { model.perform { try await player.next() } } label: { Image(systemName: "forward.end.fill") }
                        .accessibilityLabel("Next track")
                    Button { player.repeatAll.toggle(); player.applyModes() } label: {
                        Image(systemName: "repeat").foregroundStyle(player.repeatAll ? Palette.accent : Palette.muted)
                    }.help("Repeat queue").accessibilityLabel("Repeat queue")
                }.buttonStyle(.plain).disabled(player.current == nil)
                HStack(spacing: 10) {
                    Text(clockText(player.progress)).frame(width: 30, alignment: .trailing)
                    Slider(value: $seekDraft, in: 0...max(player.current?.duration ?? 0, 1)) { editing in
                        seeking = editing
                        if !editing { player.seek(seekDraft) }
                    }
                        .controlSize(.mini).disabled(player.current == nil).accessibilityLabel("Playback position")
                    Text(clockText(player.current?.duration ?? 0)).frame(width: 30, alignment: .leading)
                }.font(.system(size: 9)).monospacedDigit().foregroundStyle(Palette.muted)
            }.frame(maxWidth: 520).frame(maxWidth: .infinity)
            HStack(spacing: 19) {
                if player.isMusicApp {
                    Image(systemName: "speaker.wave.2").foregroundStyle(Palette.muted)
                    Slider(value: $volumeDraft, in: 0...100) { editing in
                        changingVolume = editing
                        if !editing { player.setVolume(volumeDraft) }
                    }.frame(width: 78).controlSize(.small).accessibilityLabel("Music volume")
                } else {
                Text(model.isLive ? "MUSICKIT" : "NO AUDIO · DEMO")
                    .font(.system(size: 8, weight: .medium)).tracking(1).foregroundStyle(Palette.muted)
                Button {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Sound-Settings.extension")!)
                } label: { Image(systemName: "speaker.wave.2") }.help("Open system sound settings").accessibilityLabel("System sound settings")
                }
                Button { showQueue.toggle() } label: {
                    Image(systemName: "list.bullet").foregroundStyle(showQueue ? Palette.accent : Palette.muted)
                }.keyboardShortcut("u", modifiers: [.command, .shift]).help("Show queue").accessibilityLabel("Toggle queue")
            }.buttonStyle(.plain).frame(width: 215, alignment: .trailing)
        }.padding(.horizontal, 24).padding(.vertical, 16).background(Palette.surface)
            .onChange(of: player.progress) { _, value in if !seeking { seekDraft = min(value, max(player.current?.duration ?? 0, 1)) } }
            .onChange(of: player.volume) { _, value in if !changingVolume { volumeDraft = value } }
    }
}

struct QueuePanel: View {
    @ObservedObject var player: PlaybackController
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Queue").font(.system(size: 17, weight: .semibold, design: .rounded))
                Spacer()
                if !player.isMusicApp { Text("\(player.upcoming.count) next").font(.caption).foregroundStyle(Palette.muted) }
            }.padding(.horizontal, 22).padding(.top, 44).padding(.bottom, 30)
            if let current = player.current {
                Text("NOW PLAYING").font(.system(size: 9, weight: .semibold)).tracking(1.6)
                    .foregroundStyle(Palette.accent).padding(.horizontal, 22).padding(.bottom, 14)
                HStack(spacing: 12) {
                    Artwork(url: current.artwork, seed: current.album, size: 42)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(current.title).font(.system(size: 12, weight: .medium)).lineLimit(1)
                        Text(current.artist).font(.system(size: 11)).foregroundStyle(Palette.muted).lineLimit(1)
                    }
                }.padding(.horizontal, 22).padding(.bottom, 25)
                Divider().padding(.horizontal, 22)
            }
            Text("UP NEXT").font(.system(size: 9, weight: .semibold)).tracking(1.6)
                .foregroundStyle(Palette.muted).padding(.horizontal, 22).padding(.top, 22).padding(.bottom, 12)
            if player.isMusicApp {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Managed by Music").font(.system(size: 12, weight: .medium))
                    Text("Music's Up Next queue isn't available through its scripting interface. View and edit it in Music.")
                        .font(.system(size: 11)).foregroundStyle(Palette.muted)
                    Button("Open Music") { NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Music.app")) }
                }.padding(.horizontal, 22).padding(.top, 14)
            } else if player.upcoming.isEmpty {
                VStack(alignment: .leading, spacing: 9) {
                    Text("A little breathing room.").font(.system(size: 12))
                    Text("Play a playlist, or right-click a song to queue it.").font(.system(size: 11)).foregroundStyle(Palette.muted)
                }.padding(.horizontal, 22).padding(.top, 14)
            }
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(player.upcoming.enumerated()), id: \.element.id) { offset, entry in
                        HStack(spacing: 10) {
                            Text("\(offset + 1)").font(.system(size: 10)).foregroundStyle(Palette.muted).frame(width: 16)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(entry.track.title).font(.system(size: 11)).lineLimit(1)
                                Text(entry.track.artist).font(.system(size: 10)).foregroundStyle(Palette.muted).lineLimit(1)
                            }
                            Spacer(minLength: 0)
                            Menu {
                                Button("Move up") { player.move(entry.id, by: -1) }.disabled(offset == 0)
                                Button("Move down") { player.move(entry.id, by: 1) }.disabled(offset == player.upcoming.count - 1)
                                Divider()
                                Button("Remove from queue") { player.remove(entry.id) }
                            } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).frame(width: 20)
                                .accessibilityLabel("Queue actions for \(entry.track.title)")
                        }.padding(.horizontal, 18).padding(.vertical, 11)
                    }
                }
            }
            Spacer(minLength: 0)
        }.frame(maxHeight: .infinity).background(Palette.surface.opacity(0.35))
    }
}
