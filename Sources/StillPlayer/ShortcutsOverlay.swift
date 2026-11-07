import SwiftUI

struct ShortcutsOverlay: View {
    @Environment(\.playerTheme) private var theme
    @ObservedObject var workspace: Workspace
    var queueSupported: Bool
    var musicVolume: Bool
    @AppStorage(PaletteShortcut.storageKey) private var paletteShortcut = PaletteShortcut.standard.storage
    private var paletteKey: String? { PaletteShortcut.stored(paletteShortcut)?.display }

    private var groups: [(String, [(String, String)])] {
        var playback = [("Play / pause", "Space  ⌘P"), ("Next / previous song", "⌘→  ⌘←"), ("Play playlist", "⌘↩"),
                        ("Shuffle playlist", "⇧⌘↩"), ("Favorite current song", "⌘L")]
        if musicVolume { playback.append(("Music volume", "⌘↑  ⌘↓")) }
        return [
            ("Palette", [("Search and commands", paletteKey ?? "none"), ("Move / run", "↑  ↓  ↩"), ("Actions for a result", "⌘K  →"),
                         ("Play next / shuffle", "⌘↩"), ("Back a step, then close", "⌫  esc")]),
            ("Go", [("Back / forward", "⌘[  ⌘]"), ("Next / previous playlist", "⌥⌘↓  ⌥⌘↑"), ("Filter this playlist", "⌘F"),
                    ("Search whole library", "⇧⌘F"),
                    ("Reveal current song", "⌘J")]),
            ("Songs", [("Play selected", "↩"), ("Actions for selected song", "⌘K"), ("Extend selection", "⇧↑  ⇧↓"),
                       ("Select all", "⌘A"), ("Clear selection", "esc")]),
            ("Playback", playback),
            ("Window", [("Hide / show sidebar", "⌘S"), (queueSupported ? "Expand player and queue" : "Expand player", "⇧⌘U"),
                        ("Keyboard shortcuts", "⌘/"), ("Settings", "⌘,"), ("Refresh library", "⌘R")])
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
                Text(paletteKey.map { "Every command is also in the palette (\($0)), with its shortcut beside it. Change or remove that key in Settings › Keyboard." }
                     ?? "The palette has no shortcut; open it from the sidebar's address bar. Set one in Settings › Keyboard.").font(.system(size: 12)).foregroundStyle(theme.muted)
            }
            .padding(24)
            .frame(width: 640)
            .background(theme.background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(theme.text.opacity(0.08)))
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
