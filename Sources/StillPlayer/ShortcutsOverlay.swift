import SwiftUI

struct ShortcutsOverlay: View {
    @Environment(\.playerTheme) private var theme
    @ObservedObject var workspace: Workspace
    var queueSupported: Bool
    var musicVolume: Bool

    private var groups: [(String, [(String, String)])] {
        var playback = [("Play / pause", "Space  ⌘P"), ("Next / previous song", "⌘→  ⌘←"), ("Play playlist", "⌘↩"),
                        ("Shuffle playlist", "⇧⌘↩"), ("Favorite current song", "⌘L")]
        if musicVolume { playback.append(("Music volume", "⌘↑  ⌘↓")) }
        var view = [("Keyboard shortcuts", "?  ⌘/"), ("Settings", "⌘,"), ("Refresh library", "⌘R")]
        if queueSupported { view.insert(("Show or hide queue", "⇧⌘U"), at: 0) }
        return [
            ("Find", [("Find in playlist or library", "⌘K"), ("Search library", "⇧⌘K"), ("Switch scope", "Tab"),
                      ("Move through results", "↑  ↓"), ("Play result", "↩"), ("Clear, then go back", "esc"),
                      ("Start typing anywhere", "a–z")]),
            ("Go", [("Pinned playlist 1–9", "⌘1 … ⌘9"), ("Next / previous playlist", "⌥⌘↓  ⌥⌘↑"), ("Filter playlists", "⌥⌘F")]),
            ("Songs", [("Play selected", "↩"), ("Extend selection", "⇧↑  ⇧↓"), ("Select all", "⌘A"), ("Clear selection", "esc")]),
            ("Playback", playback),
            ("Window", view)
        ]
    }

    var body: some View {
        ZStack {
            Color.black.opacity(theme.isDark ? 0.45 : 0.18).ignoresSafeArea()
                .onTapGesture { workspace.showShortcuts = false }
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text("Keyboard shortcuts").font(.system(size: 17, weight: .semibold))
                    Spacer()
                    Button { workspace.showShortcuts = false } label: { KeyCap("esc") }.buttonStyle(.plain).help("Close")
                }
                HStack(alignment: .top, spacing: 32) {
                    column(Array(groups.prefix(3)))
                    column(Array(groups.dropFirst(3)))
                }
                Text("Buttons with a shortcut show it in their tooltip.").font(.system(size: 12)).foregroundStyle(theme.muted)
            }
            .padding(24)
            .frame(width: 640)
            .background(theme.background, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(theme.text.opacity(0.1)))
            .shadow(color: .black.opacity(0.3), radius: 30, y: 10)
        }
        .accessibilityAddTraits(.isModal)
    }

    private func column(_ groups: [(String, [(String, String)])]) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(groups, id: \.0) { group in
                VStack(alignment: .leading, spacing: 6) {
                    Text(group.0).font(.system(size: 12, weight: .semibold)).foregroundStyle(theme.accent)
                    ForEach(group.1, id: \.0) { item in
                        HStack {
                            Text(item.0).font(.system(size: 13))
                            Spacer(minLength: 12)
                            HStack(spacing: 4) {
                                ForEach(item.1.components(separatedBy: "  "), id: \.self) { KeyCap($0) }
                            }
                        }
                    }
                }
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
