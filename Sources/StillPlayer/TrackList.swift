import SwiftUI
#if SWIFT_PACKAGE
import PlayerCore
#endif

/// Fixed columns keep their own width; weighted columns share what's left. Header and rows use the
/// same layout so they always line up.
struct TrackColumns: Layout {
    static let weights: [CGFloat] = [0, 1.5, 1, 1, 0, 0]
    var spacing: CGFloat = 12
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        CGSize(width: proposal.width ?? 640, height: subviews.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let weights = Self.weights
        let fixed = zip(subviews, weights).filter { $0.1 == 0 }.map { $0.0.sizeThatFits(.unspecified).width }.reduce(0, +)
        let free = max(0, bounds.width - fixed - spacing * CGFloat(subviews.count - 1))
        let total = weights.reduce(0, +)
        var x = bounds.minX
        for (subview, weight) in zip(subviews, weights) {
            let width = weight == 0 ? subview.sizeThatFits(.unspecified).width : free * weight / total
            subview.place(at: CGPoint(x: x, y: bounds.midY), anchor: .leading, proposal: ProposedViewSize(width: width, height: bounds.height))
            x += width + spacing
        }
    }
}

enum TrackMetrics {
    static let numberWidth: CGFloat = 26
    static let actionsWidth: CGFloat = 78
    static let durationWidth: CGFloat = 40
    static let rowHeight: CGFloat = 30
    static let horizontalInset: CGFloat = 12
    /// Room under the last row so it clears the floating player.
    static let bottomInset: CGFloat = 104
}

struct TrackListHeader: View {
    @Environment(\.playerTheme) private var theme
    @ObservedObject var workspace: Workspace
    var body: some View {
        TrackColumns {
            header("#", key: .number, alignment: .trailing).frame(width: TrackMetrics.numberWidth, alignment: .trailing)
            header("Title", key: .title).padding(.leading, 31)
            header("Artist", key: .artist)
            header("Album", key: .album)
            Color.clear.frame(width: TrackMetrics.actionsWidth, height: 1)
            header("Time", key: .duration, alignment: .trailing).frame(width: TrackMetrics.durationWidth, alignment: .trailing)
        }
        .padding(.horizontal, 10)
        .frame(height: 26)
    }

    private func header(_ title: String, key: SortKey, alignment: Alignment = .leading) -> some View {
        let active = workspace.sort.key == key && key != .number
        return Button { workspace.toggleSort(key) } label: {
            HStack(spacing: 3) {
                Text(title)
                if active { Image(systemName: workspace.sort.ascending ? "chevron.up" : "chevron.down").font(.system(size: 8, weight: .bold)) }
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(active ? theme.text : theme.muted.opacity(0.85))
            .frame(maxWidth: .infinity, alignment: alignment)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(key == .number ? "Playlist order" : "Sort by \(title.lowercased())")
    }
}

/// A plain scrolling stack instead of `List`, so selection can be a theme-tinted rounded fill rather
/// than the system's grey bar. Click, ⌘-click, ⇧-click, double-click and right-click behave like Finder.
struct TrackList: View {
    @Environment(\.playerTheme) private var theme
    @ObservedObject var model: AppModel
    @ObservedObject var workspace: Workspace
    var rows: [TrackRowItem]

    var body: some View {
        let selection = workspace.selection
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { offset, row in
                        let selected = selection.contains(row.id)
                        TrackRow(model: model, workspace: workspace, row: row, selected: selected,
                                 joinsAbove: selected && offset > 0 && selection.contains(rows[offset - 1].id),
                                 joinsBelow: selected && offset + 1 < rows.count && selection.contains(rows[offset + 1].id))
                            .id(row.id)
                            .contextMenu {
                                let targets = selection.contains(row.id) ? rows.filter { selection.contains($0.id) } : [row]
                                TrackActionsMenu(model: model, tracks: targets.map(\.track)) { workspace.play(row: targets[0]) }
                            }
                    }
                }
                .padding(.horizontal, TrackMetrics.horizontalInset)
                .padding(.bottom, TrackMetrics.bottomInset)
            }
            .scrollIndicators(.automatic)
            .onChange(of: workspace.scrollRequest) { _, target in
                guard let target else { return }
                withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(target) }
                workspace.scrollRequest = nil
            }
        }
    }
}

/// The one menu used for right-click, the ⋯ button, and nothing else drifting out of sync.
struct TrackActionsMenu: View {
    @ObservedObject var model: AppModel
    var tracks: [LibraryTrack]
    var onPlay: () -> Void
    var body: some View {
        if !tracks.isEmpty {
            Button(tracks.count == 1 ? "Play" : "Play \(tracks.count) songs", action: onPlay)
            if model.playback.canEditQueue {
                Button("Play next") { model.perform { try await model.playback.enqueue(tracks, next: true) } }
                Button("Add to queue") { model.perform { try await model.playback.enqueue(tracks, next: false) } }
            }
            Divider()
            if let track = tracks.first, tracks.count == 1 {
                Button(model.favorites.contains(track.id) && (!model.isLive || model.usesMusicApp) ? "Remove from favorites" : "Favorite") {
                    model.perform { try await model.favorite(track) }
                }
            } else {
                Button("Favorite \(tracks.count) songs") { favoriteAll(model: model, tracks: tracks) }
            }
            AddToPlaylistMenu(model: model, tracks: tracks)
        }
    }
}

@MainActor func favoriteAll(model: AppModel, tracks: [LibraryTrack]) {
    let pending = tracks.filter { !model.favorites.contains($0.id) }
    model.perform { for track in pending { try await model.favorite(track) } }
}

struct AddToPlaylistMenu: View {
    @ObservedObject var model: AppModel
    var tracks: [LibraryTrack]
    var title = "Add to playlist"
    var body: some View {
        Menu(title) { playlistButtons }
    }
    @ViewBuilder var playlistButtons: some View {
        let targets = Workspace.alphabetical(model.playlists).filter(\.canAddTracks)
        if targets.isEmpty { Text("No editable playlists") }
        ForEach(targets) { playlist in
            Button(playlist.name) { model.perform { try await model.add(tracks, to: playlist) } }
        }
    }
}

struct TrackRow: View {
    @Environment(\.playerTheme) private var theme
    @ObservedObject var model: AppModel
    @ObservedObject var workspace: Workspace
    var row: TrackRowItem
    var selected: Bool
    var joinsAbove: Bool
    var joinsBelow: Bool
    @State private var hovering = false

    private var track: LibraryTrack { row.track }
    private var isCurrent: Bool { model.playback.current?.id == track.id }
    private var isFavorite: Bool { model.favorites.contains(track.id) }
    private var revealed: Bool { workspace.debugHoverRow.map { $0 == row.number } ?? hovering }

    var body: some View {
        TrackColumns {
            numberCell.frame(width: TrackMetrics.numberWidth, alignment: .trailing)
            HStack(spacing: 9) {
                Artwork(url: track.artwork, seed: track.album, size: 22, cornerRadius: 4)
                Text(track.title).font(.system(size: 13, weight: isCurrent ? .semibold : .regular))
                    .foregroundStyle(isCurrent ? theme.accent : theme.text).lineLimit(1)
            }.frame(maxWidth: .infinity, alignment: .leading)
            Text(track.artist).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
            Text(track.album).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
            actions.frame(width: TrackMetrics.actionsWidth, alignment: .trailing)
            Text(clockText(track.duration)).monospacedDigit().frame(width: TrackMetrics.durationWidth, alignment: .trailing)
        }
        .font(.system(size: 13))
        .foregroundStyle(theme.muted)
        .padding(.horizontal, 10)
        .frame(height: TrackMetrics.rowHeight)
        .background { rowBackground }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { workspace.play(row: row) }
        .simultaneousGesture(TapGesture().onEnded {
            let flags = NSEvent.modifierFlags
            workspace.click(row: row, command: flags.contains(.command), shift: flags.contains(.shift))
        })
        .onHover { hovering = $0 }
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(track.title), \(track.artist), \(track.album)\(isCurrent ? ", now playing" : "")")
    }

    /// Adjacent selected rows merge into one rounded block, like Finder's selection.
    @ViewBuilder private var rowBackground: some View {
        if selected {
            UnevenRoundedRectangle(topLeadingRadius: joinsAbove ? 0 : 7, bottomLeadingRadius: joinsBelow ? 0 : 7,
                                   bottomTrailingRadius: joinsBelow ? 0 : 7, topTrailingRadius: joinsAbove ? 0 : 7, style: .continuous)
                .fill(theme.rowSelection)
        } else if revealed {
            RoundedRectangle(cornerRadius: 7, style: .continuous).fill(theme.rowHover)
        }
    }

    @ViewBuilder private var numberCell: some View {
        if revealed {
            Button { workspace.play(row: row) } label: {
                Image(systemName: isCurrent && model.playback.isPlaying ? "speaker.wave.2.fill" : "play.fill").font(.system(size: 11))
                    .foregroundStyle(theme.text)
                    .frame(width: TrackMetrics.numberWidth, height: 22, alignment: .trailing)
                    .contentShape(Rectangle())
            }.buttonStyle(.plain).help("Play (Return)").accessibilityLabel("Play \(track.title)")
        } else if isCurrent {
            Image(systemName: model.playback.isPlaying ? "speaker.wave.2.fill" : "speaker.fill")
                .font(.system(size: 11, weight: .semibold)).foregroundStyle(theme.accent)
                .accessibilityLabel(model.playback.isPlaying ? "Now playing" : "Paused")
        } else {
            Text("\(row.number)").font(.system(size: 12)).monospacedDigit()
        }
    }

    private var actions: some View {
        HStack(spacing: 2) {
            if revealed {
                RowIconButton(symbol: isFavorite ? "star.fill" : "star", tint: isFavorite ? theme.accent : theme.text,
                              help: isFavorite ? "Remove from favorites" : "Favorite") {
                    model.perform { try await model.favorite(track) }
                }
                Menu {
                    AddToPlaylistMenu(model: model, tracks: [track]).playlistButtons
                } label: { Image(systemName: "plus") }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                    .frame(width: 24, height: 22).help("Add to playlist")
                    .accessibilityLabel("Add \(track.title) to playlist")
                Menu {
                    TrackActionsMenu(model: model, tracks: [track]) { workspace.play(row: row) }
                } label: { Image(systemName: "ellipsis") }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                    .frame(width: 24, height: 22).help("More actions")
                    .accessibilityLabel("More actions for \(track.title)")
            } else if isFavorite {
                Image(systemName: "star.fill").font(.system(size: 11)).foregroundStyle(theme.accent)
                    .frame(width: 24).padding(.trailing, 48).accessibilityLabel("Favorite")
            }
        }.foregroundStyle(theme.text)
    }
}

struct RowIconButton: View {
    @Environment(\.playerTheme) private var theme
    var symbol: String
    var tint: Color? = nil
    var help: String
    var action: () -> Void
    @State private var hovering = false
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 12))
                .foregroundStyle(tint ?? theme.text)
                .frame(width: 24, height: 22)
                .background(hovering ? theme.text.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 5))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain).help(help).accessibilityLabel(help)
        .onHover { hovering = $0 }
    }
}

/// Appears when two or more songs are selected: a glass capsule that drops in from the top of the
/// content card, mirroring the player pill at the bottom. Icon-only when the card is narrow.
struct SelectionBar: View {
    @Environment(\.playerTheme) private var theme
    @ObservedObject var model: AppModel
    @ObservedObject var workspace: Workspace
    var body: some View {
        let tracks = workspace.selectedTracks()
        ViewThatFits(in: .horizontal) {
            bar(tracks, compact: false)
            bar(tracks, compact: true)
        }.padding(.horizontal, 16)
    }

    private func bar(_ tracks: [LibraryTrack], compact: Bool) -> some View {
        HStack(spacing: 4) {
            Text("\(tracks.count) selected").font(.system(size: 12.5, weight: .semibold)).monospacedDigit().fixedSize()
                .padding(.leading, 6).padding(.trailing, 8)
            Button { workspace.playSelection() } label: { Label("Play", systemImage: "play.fill") }
                .buttonStyle(SoftCapsuleStyle(prominent: true, compact: true)).help("Play selection (Return)")
            if model.playback.canEditQueue && workspace.queueSupported {
                PillAction(title: "Play next", icon: "text.line.first.and.arrowtriangle.forward", compact: compact) {
                    model.perform { try await model.playback.enqueue(tracks, next: true) }
                }
                PillAction(title: "Add to queue", icon: "text.line.last.and.arrowtriangle.forward", compact: compact) {
                    model.perform { try await model.playback.enqueue(tracks, next: false) }
                }
            }
            PillAction(title: "Add to playlist…", icon: "text.badge.plus", compact: compact) {
                workspace.openPalette()
                workspace.palette.step = .addToPlaylist(tracks: tracks, label: tracks.count == 1 ? "“\(tracks[0].title)”" : "\(tracks.count) songs")
            }
            PillAction(title: "Favorite", icon: "star", compact: compact) { favoriteAll(model: model, tracks: tracks) }
            Rectangle().fill(theme.text.opacity(0.12)).frame(width: 1, height: 18).padding(.horizontal, 4)
            Button { workspace.selection = [] } label: {
                Image(systemName: "xmark").font(.system(size: 11, weight: .bold)).frame(width: 26, height: 26)
                    .background(theme.text.opacity(0.07), in: Circle())
            }
            .buttonStyle(.plain).foregroundStyle(theme.muted).help("Clear selection (Esc)").accessibilityLabel("Clear selection")
        }
        .foregroundStyle(theme.text)
        .padding(.leading, 8).padding(.trailing, 7).frame(height: 44)
        .background(glassChrome(Capsule(), theme: theme))
        .fixedSize()
    }
}

struct PillAction: View {
    @Environment(\.playerTheme) private var theme
    var title: String
    var icon: String
    var compact: Bool
    var action: () -> Void
    @State private var hovering = false
    var body: some View {
        Button(action: action) {
            Group {
                if compact { Image(systemName: icon) } else { Label(title, systemImage: icon) }
            }
            .font(.system(size: 12.5, weight: .medium))
            .padding(.horizontal, compact ? 8 : 10).frame(height: 28)
            .background(hovering ? theme.text.opacity(0.07) : .clear, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain).help(title).accessibilityLabel(title)
        .onHover { hovering = $0 }
    }
}

/// The frosted chrome shared by the player pill and the selection capsule.
func glassChrome<S: InsettableShape>(_ shape: S, theme: PlayerTheme) -> some View {
    shape.fill(.regularMaterial)
        .overlay(shape.fill(theme.surface.opacity(theme.isDark ? 0.55 : 0.5)))
        .overlay(shape.strokeBorder(theme.text.opacity(theme.isDark ? 0.10 : 0.07), lineWidth: 1))
        .shadow(color: .black.opacity(theme.isDark ? 0.42 : 0.14), radius: 20, y: 8)
}

/// Accent-filled button that keeps its colour when the window is inactive, so Play never reads as disabled.
struct AccentButtonStyle: ButtonStyle {
    @Environment(\.playerTheme) private var theme
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(theme.buttonInk)
            .padding(.horizontal, 12).frame(height: 24)
            .background(theme.accent.opacity(configuration.isPressed ? 0.8 : 1), in: RoundedRectangle(cornerRadius: 6))
            .opacity(enabled ? 1 : 0.45)
    }
}
