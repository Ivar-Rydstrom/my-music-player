import SwiftUI
#if SWIFT_PACKAGE
import PlayerCore
#endif

/// One row: now playing, transport, scrubber, and the few secondary controls.
struct PlayerBar: View {
    @Environment(\.playerTheme) private var theme
    @ObservedObject var model: AppModel
    @ObservedObject var player: PlaybackController
    @ObservedObject var workspace: Workspace
    @State private var seekDraft = 0.0
    @State private var seeking = false
    @State private var volumeDraft = 50.0
    @State private var changingVolume = false

    var body: some View {
        HStack(spacing: 18) {
            nowPlaying.frame(width: 236, alignment: .leading)
            transport
            scrubber
            trailing
        }
        .padding(.horizontal, 16).frame(height: 54)
        .background(theme.surface)
        .onAppear { seekDraft = player.progress; volumeDraft = player.volume }
        .onChange(of: player.current?.id) { _, _ in seekDraft = min(player.progress, max(player.current?.duration ?? 0, 1)) }
        .onChange(of: player.progress) { _, value in if !seeking { seekDraft = min(value, max(player.current?.duration ?? 0, 1)) } }
        .onChange(of: player.volume) { _, value in if !changingVolume { volumeDraft = value } }
    }

    private var nowPlaying: some View {
        HStack(spacing: 10) {
            Artwork(url: player.current?.artwork, seed: player.current?.album ?? "Still", size: 36, cornerRadius: 5)
            VStack(alignment: .leading, spacing: 1) {
                Text(player.current?.title ?? "Nothing playing").font(.system(size: 13, weight: .medium)).lineLimit(1)
                Text(player.current.map { "\($0.artist) — \($0.album)" } ?? "Double-click a song, or press Return")
                    .font(.system(size: 12)).foregroundStyle(theme.muted).lineLimit(1)
            }
            Spacer(minLength: 0)
            if let current = player.current {
                let favorite = model.favorites.contains(current.id)
                RowIconButton(symbol: favorite ? "star.fill" : "star", tint: favorite ? theme.accent : theme.muted,
                              help: favorite ? "Remove from favorites (⌘L)" : "Favorite current song (⌘L)") {
                    model.perform { try await model.favorite(current) }
                }
            }
        }
    }

    private var transport: some View {
        HStack(spacing: 4) {
            BarButton(symbol: "shuffle", active: player.shuffle, help: "Shuffle") { player.shuffle.toggle(); player.applyModes() }
            BarButton(symbol: "backward.fill", help: "Previous (⌘←)") { model.perform { try await player.previous() } }
            Button { model.perform { try await player.toggle() } } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 13)).foregroundStyle(theme.buttonInk)
                    .frame(width: 30, height: 30).background(theme.accent, in: Circle())
            }
            .buttonStyle(.plain)
            .help(player.isPlaying ? "Pause (Space)" : "Play (Space)").accessibilityLabel(player.isPlaying ? "Pause" : "Play")
            .padding(.horizontal, 4)
            BarButton(symbol: "forward.fill", help: "Next (⌘→)") { model.perform { try await player.next() } }
            BarButton(symbol: "repeat", active: player.repeatAll, help: "Repeat") { player.repeatAll.toggle(); player.applyModes() }
        }.disabled(player.current == nil)
    }

    private var scrubber: some View {
        HStack(spacing: 8) {
            Text(clockText(seeking ? seekDraft : player.progress)).frame(width: 36, alignment: .trailing)
            Slider(value: $seekDraft, in: 0...max(player.current?.duration ?? 0, 1)) { editing in
                seeking = editing
                if !editing { player.seek(seekDraft) }
            }
            .controlSize(.small).disabled(player.current == nil).accessibilityLabel("Playback position")
            Text(clockText(player.current?.duration ?? 0)).frame(width: 36, alignment: .leading)
        }
        .font(.system(size: 11)).monospacedDigit().foregroundStyle(theme.muted)
        .frame(minWidth: 160, maxWidth: .infinity)
    }

    private var trailing: some View {
        HStack(spacing: 4) {
            if player.isMusicApp {
                Image(systemName: "speaker.wave.2").font(.system(size: 12)).foregroundStyle(theme.muted)
                Slider(value: $volumeDraft, in: 0...100) { editing in
                    changingVolume = editing
                    if !editing { player.setVolume(volumeDraft) }
                }.frame(width: 76).controlSize(.small).accessibilityLabel("Music volume").help("Music volume (⌘↑ ⌘↓)")
                    .padding(.trailing, 4)
            } else {
                BarButton(symbol: "speaker.wave.2", help: "Open system sound settings") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Sound-Settings.extension")!)
                }
            }
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
                Image(systemName: player.sleepUntil == nil ? "moon" : "moon.zzz.fill")
                    .foregroundStyle(player.sleepUntil == nil ? theme.muted : theme.accent)
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().frame(width: 28, height: 28)
            .help(player.sleepUntil.map { "Sleep timer: pauses at \($0.formatted(date: .omitted, time: .shortened))" } ?? "Sleep timer")
            .accessibilityLabel("Sleep timer")
            if workspace.queueSupported {
                BarButton(symbol: "list.bullet", active: workspace.showQueue, help: workspace.showQueue ? "Hide queue (⇧⌘U)" : "Show queue (⇧⌘U)") {
                    workspace.showQueue.toggle()
                }
            }
            BarButton(symbol: "keyboard", help: "Keyboard shortcuts (?)") { workspace.showShortcuts.toggle() }
        }
    }
}

struct BarButton: View {
    @Environment(\.playerTheme) private var theme
    @Environment(\.isEnabled) private var enabled
    var symbol: String
    var active = false
    var help: String
    var action: () -> Void
    @State private var hovering = false
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 13, weight: .medium))
                .foregroundStyle(active ? theme.accent : hovering ? theme.text : theme.muted)
                .frame(width: 28, height: 28)
                .background(hovering && enabled ? theme.text.opacity(0.07) : .clear, in: RoundedRectangle(cornerRadius: 6))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain).help(help).accessibilityLabel(help)
        .onHover { hovering = $0 }
    }
}

/// Slim, toggleable Up Next column. Only exists where the queue is real (sample and MusicKit modes).
struct QueueColumn: View {
    @Environment(\.playerTheme) private var theme
    @ObservedObject var player: PlaybackController
    @ObservedObject var workspace: Workspace
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Text("Up next").font(.system(size: 13, weight: .semibold))
                if !player.upcoming.isEmpty {
                    Text("\(player.upcoming.count)").font(.system(size: 12)).foregroundStyle(theme.muted).monospacedDigit()
                }
                Spacer()
                if !player.upcoming.isEmpty {
                    Button("Clear") { player.clearUpcoming() }.buttonStyle(.borderless).font(.system(size: 12)).help("Clear upcoming songs")
                }
                BarButton(symbol: "sidebar.right", help: "Hide queue (⇧⌘U)") { workspace.showQueue = false }
            }
            .padding(.leading, 14).padding(.trailing, 6).frame(height: 48).padding(.top, 0)
            if player.upcoming.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Nothing queued").font(.system(size: 13))
                    Text("Play a playlist, or use Play next on any song.").font(.system(size: 12)).foregroundStyle(theme.muted)
                }.padding(.horizontal, 14).padding(.top, 6)
            }
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(player.upcoming.enumerated()), id: \.element.id) { offset, entry in
                        QueueRow(player: player, entry: entry, offset: offset)
                    }
                }.padding(.horizontal, 6)
            }
            if !player.upcoming.isEmpty {
                Divider()
                Text("\(Int(player.upcoming.reduce(0) { $0 + $1.track.duration } / 60)) min remaining")
                    .font(.system(size: 11)).foregroundStyle(theme.muted).padding(.horizontal, 14).padding(.vertical, 9)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(theme.surface.opacity(theme.isDark ? 0.45 : 0.35))
    }
}

struct QueueRow: View {
    @Environment(\.playerTheme) private var theme
    @ObservedObject var player: PlaybackController
    var entry: PlaybackRow
    var offset: Int
    @State private var hovering = false
    var body: some View {
        HStack(spacing: 8) {
            Text("\(offset + 1)").font(.system(size: 11)).monospacedDigit().foregroundStyle(theme.muted).frame(width: 18, alignment: .trailing)
            VStack(alignment: .leading, spacing: 0) {
                Text(entry.track.title).font(.system(size: 12)).lineLimit(1)
                Text(entry.track.artist).font(.system(size: 11)).foregroundStyle(theme.muted).lineLimit(1)
            }
            Spacer(minLength: 0)
            if hovering {
                HStack(spacing: 0) {
                    RowIconButton(symbol: "chevron.up", help: "Move up") { player.move(entry.id, by: -1) }.disabled(offset == 0)
                    RowIconButton(symbol: "chevron.down", help: "Move down") { player.move(entry.id, by: 1) }.disabled(offset == player.upcoming.count - 1)
                    RowIconButton(symbol: "xmark", help: "Remove from queue") { player.remove(entry.id) }
                }
            }
        }
        .padding(.horizontal, 8).frame(height: 34)
        .background(hovering ? theme.text.opacity(0.05) : .clear, in: RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .contextMenu {
            Button("Move up") { player.move(entry.id, by: -1) }.disabled(offset == 0)
            Button("Move down") { player.move(entry.id, by: 1) }.disabled(offset == player.upcoming.count - 1)
            Divider()
            Button("Remove from queue") { player.remove(entry.id) }
        }
    }
}
