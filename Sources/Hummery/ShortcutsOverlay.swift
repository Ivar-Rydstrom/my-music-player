import SwiftUI

struct ShortcutsOverlay: View {
    @Environment(\.playerTheme) private var theme
    @ObservedObject var workspace: Workspace
    var queueSupported: Bool
    var musicVolume: Bool
    @ObservedObject private var shortcuts = ShortcutStore.shared

    /// Each command's current key ("none" if removed), plus the fixed keys for moving around.
    private var groups: [(String, [(String, String)])] {
        var result: [(String, [(String, String)])] = []
        for group in ShortcutAction.Group.allCases {
            var rows = ShortcutAction.allCases.filter { $0.group == group }
                .filter { musicVolume || ($0 != .volumeUp && $0 != .volumeDown) }
                .map { action in (action == .expandPlayer && queueSupported ? "Expand player and queue" : action.title, shortcuts.display(action) ?? "none") }
            if group == .songs {
                rows = [("Play selected", "↩"), ("Extend selection", "⇧↑  ⇧↓"), ("Clear selection", "esc")] + rows
            }
            result.append((group.rawValue, rows))
        }
        let palette = ("Inside the palette", [("Move / run", "↑  ↓  ↩"), ("Actions for a result", "⌘K  →"),
                                              ("Play next / shuffle", "⌘↩"), ("Back a step, then close", "⌫  esc")])
        // Left column: search, go, songs, palette. Right column: playback, window.
        return [result[0], result[1], result[3], palette, result[2], result[4]]
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
                    column(Array(groups.prefix(4)))
                    column(Array(groups.dropFirst(4)))
                }
                Text("Change or remove any of these in Settings › Keyboard.").font(.system(size: 12)).foregroundStyle(theme.muted)
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
