import SwiftUI
#if SWIFT_PACKAGE
import PlayerCore
#endif

/// One field for both "find in this playlist" and "search the library". Typing filters the open
/// playlist instantly; Tab (or the scope control) widens it to the library or catalog.
struct CommandBar: View {
    @Environment(\.playerTheme) private var theme
    @ObservedObject var model: AppModel
    @ObservedObject var workspace: Workspace
    var focus: FocusState<Bool>.Binding

    private var text: Binding<String> {
        Binding(get: { workspace.queryText }, set: { workspace.queryText = $0 })
    }
    private var placeholder: String {
        switch workspace.scope {
        case .playlist: "Filter \(listName) · Tab for library"
        case .library: "Search your library"
        case .catalog: "Search the Apple Music catalog"
        }
    }
    private var listName: String {
        model.selectedID == "recent" ? "Recently played" : model.selectedID == "favorites" ? "Favorites" : model.playlist?.name ?? "this playlist"
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: workspace.isSearching ? "magnifyingglass" : "line.3.horizontal.decrease")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(focus.wrappedValue ? theme.accent : theme.muted)
                .frame(width: 16)
            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .focused(focus)
                .accessibilityLabel(workspace.isSearching ? "Search" : "Filter playlist")
            if model.searching && workspace.isSearching { ProgressView().controlSize(.small) }
            if !workspace.queryText.isEmpty {
                Button { workspace.queryText = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain).foregroundStyle(theme.muted).help("Clear (Esc)").accessibilityLabel("Clear")
            }
            Picker("Scope", selection: Binding(get: { workspace.scope }, set: { workspace.setScope($0); workspace.focusCommandBar() })) {
                ForEach(workspace.availableScopes) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented).labelsHidden().controlSize(.small).fixedSize()
            .help("Where to look (Tab switches)")
            if !focus.wrappedValue { KeyCap("⌘K") }
        }
        .padding(.leading, 10).padding(.trailing, 6)
        .frame(height: 32)
        .background(theme.surface.opacity(theme.isDark ? 0.9 : 0.7), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(focus.wrappedValue ? theme.accent.opacity(0.7) : theme.text.opacity(0.12), lineWidth: focus.wrappedValue ? 1.5 : 1))
        .contentShape(Rectangle())
        .onTapGesture { workspace.focusCommandBar() }
    }
}

/// Header for the content area while searching the library or catalog.
struct SearchHeader: View {
    @Environment(\.playerTheme) private var theme
    @ObservedObject var model: AppModel
    @ObservedObject var workspace: Workspace
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(workspace.scope == .catalog ? "Catalog" : "Library").font(.system(size: 17, weight: .semibold))
            if workspace.libraryQuery.isEmpty {
                Text(model.usesMusicApp ? "Songs in your Music library" : model.isLive ? "Up to 25 songs per search" : "Sample songs").font(.system(size: 12)).foregroundStyle(theme.muted)
            } else {
                Text("\(model.searchResults.count) songs for “\(workspace.libraryQuery)”").font(.system(size: 12)).foregroundStyle(theme.muted).lineLimit(1)
            }
            Spacer()
            if model.usesMusicApp {
                Button("Open Music for catalog") { NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Music.app")) }
                    .buttonStyle(.borderless).font(.system(size: 12))
            }
            Button { workspace.setScope(.playlist) } label: {
                HStack(spacing: 5) { Text("Back to playlist"); KeyCap("esc") }
            }.buttonStyle(.borderless).font(.system(size: 12)).help("Return to the open playlist (Esc)")
        }
    }
}

struct KeyCap: View {
    @Environment(\.playerTheme) private var theme
    var label: String
    init(_ label: String) { self.label = label }
    var body: some View {
        Text(label)
            .font(.system(size: 11, weight: .medium, design: .rounded))
            .foregroundStyle(theme.muted)
            .padding(.horizontal, 5).frame(minWidth: 20, minHeight: 18)
            .background(theme.text.opacity(0.06), in: RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(theme.text.opacity(0.12)))
    }
}
