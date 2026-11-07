import SwiftUI
import AppKit
#if SWIFT_PACKAGE
import PlayerCore
#endif

/// Palette state and keyboard routing. The data model and ranking live in `PaletteModel.swift`.
@MainActor
final class PaletteController: ObservableObject {
    struct Frame: Equatable {
        var step: PaletteStep
        var parentQuery: String
        var parentHighlight: Int
    }

    weak var workspace: Workspace?
    @Published var isOpen = false
    @Published var query = "" { didSet { if query != oldValue { highlighted = 0 } } }
    @Published private(set) var stack: [Frame] = []
    @Published var highlighted = 0
    /// The result whose action panel is open (→ or ⌘K).
    @Published var actionsItem: PaletteItem?
    @Published var actionsQuery = "" { didSet { if actionsQuery != oldValue { actionsHighlighted = 0 } } }
    @Published var actionsHighlighted = 0
    @Published var focusRequest = 0
    @Published private(set) var recents: [String] = UserDefaults.standard.stringArray(forKey: "palette.recents") ?? []

    var perform: (PaletteCommand) -> Void = { _ in }
    var contextProvider: () -> PaletteContext = { PaletteContext() }
    var songProvider: () -> [LibraryTrack] = { [] }
    /// Song ids already in a playlist, read only while choosing where to add songs.
    var contentsProvider: (String) -> Set<String> = { _ in [] }

    var step: PaletteStep? { stack.last?.step }

    var sections: [PaletteSection] {
        let context = contextProvider()
        if case .addToPlaylist(let tracks, _)? = step {
            return PaletteSearch.playlistChoices(query: query, tracks: tracks, context: context, contents: contentsProvider)
        }
        return PaletteSearch.results(query: query, context: context, songs: songProvider(), recents: recents)
    }
    var items: [PaletteItem] { sections.flatMap(\.items) }
    var highlightedItem: PaletteItem? {
        let items = items
        return items.indices.contains(highlighted) ? items[highlighted] : items.first
    }
    var actions: [PaletteItem] {
        guard let actionsItem else { return [] }
        return PaletteSearch.filterActions(PaletteCatalog.actions(for: actionsItem, context: contextProvider()), query: actionsQuery)
    }

    // MARK: Opening and closing

    func open(query: String = "") {
        stack = []; actionsItem = nil; actionsQuery = ""
        self.query = query; highlighted = 0
        isOpen = true
        focusRequest += 1
    }

    /// Opens straight into a result's action panel (⌘K on a selected song).
    func open(actionsFor item: PaletteItem) {
        open(query: item.title)
        actionsItem = item
        focusRequest += 1
    }

    func open(step: PaletteStep) {
        open()
        stack = [Frame(step: step, parentQuery: "", parentHighlight: 0)]
    }

    func close() {
        isOpen = false
        actionsItem = nil
        stack = []
        query = ""
    }

    // MARK: Running

    func run(_ item: PaletteItem) { execute(item.action, record: item.id) }

    func runSecondary(_ item: PaletteItem) {
        if let action = PaletteCatalog.secondary(for: item, context: contextProvider()) { execute(action, record: nil) }
    }

    func runAction(_ action: PaletteItem) { execute(action.action, record: nil) }

    func showActions(for item: PaletteItem? = nil) {
        guard let item = item ?? highlightedItem else { return }
        actionsQuery = ""; actionsHighlighted = 0
        actionsItem = item
        focusRequest += 1
    }

    private func execute(_ action: PaletteAction, record: String?) {
        switch action {
        case .push(let step):
            actionsItem = nil
            stack.append(Frame(step: step, parentQuery: query, parentHighlight: highlighted))
            query = ""; highlighted = 0
            focusRequest += 1
        case .run(let command):
            if let record, record.hasPrefix("cmd.") { remember(record) }
            close()
            perform(command)
        }
    }

    private func remember(_ id: String) {
        recents.removeAll { $0 == id }
        recents.insert(id, at: 0)
        recents = Array(recents.prefix(8))
        UserDefaults.standard.set(recents, forKey: "palette.recents")
    }

    /// Esc and ⌫ on an empty input step back one layer: action panel, then nested step.
    @discardableResult func back() -> Bool {
        if actionsItem != nil { actionsItem = nil; focusRequest += 1; return true }
        guard let frame = stack.popLast() else { return false }
        query = frame.parentQuery
        highlighted = frame.parentHighlight
        focusRequest += 1
        return true
    }

    func move(_ delta: Int) {
        let count = items.count
        guard count > 0 else { return }
        highlighted = min(max(highlighted + delta, 0), count - 1)
    }

    // MARK: Keyboard

    func handle(key: UInt16, flags: NSEvent.ModifierFlags, characters: String?) -> Bool {
        if actionsItem != nil {
            let list = actions
            switch key {
            case 125: actionsHighlighted = min(actionsHighlighted + 1, max(list.count - 1, 0)); return true
            case 126: actionsHighlighted = max(actionsHighlighted - 1, 0); return true
            case 36, 76:
                if list.indices.contains(actionsHighlighted) { runAction(list[actionsHighlighted]) }
                return true
            case 53: back(); return true
            case 40 where flags == .command: back(); return true
            case 123 where actionsQuery.isEmpty, 51 where actionsQuery.isEmpty: back(); return true
            case 48: return true
            default: return false
            }
        }
        switch key {
        case 125 where flags.isEmpty: move(1); return true
        case 126 where flags.isEmpty: move(-1); return true
        case 36 where flags == .command, 76 where flags == .command:
            if let item = highlightedItem { runSecondary(item) }
            return true
        case 36, 76:
            if let item = highlightedItem { run(item) }
            return true
        case 53:
            if !back() { close() }
            return true
        case 40 where flags == .command:
            showActions(); return true
        case 124 where flags.isEmpty:
            // → opens actions when the caret is already at the end of the input.
            if let editor = workspace?.window?.firstResponder as? NSTextView, editor.selectedRange().location < (editor.string as NSString).length { return false }
            showActions(); return true
        case 51 where flags.isEmpty && query.isEmpty:
            return back()
        case 37 where flags == .command:
            if let track = highlightedItem?.track { close(); perform(.favorite(track)) ; return true }
            return false
        case 48: return true
        default: return false
        }
    }
}

// MARK: - View

struct CommandPalette: View {
    @Environment(\.playerTheme) private var theme
    @ObservedObject var palette: PaletteController
    @ObservedObject var model: AppModel
    @FocusState private var focus: Field?
    private enum Field { case query, actions }

    var body: some View {
        let sections = palette.sections
        let items = sections.flatMap(\.items)
        let highlightedID = items.indices.contains(palette.highlighted) ? items[palette.highlighted].id : items.first?.id
        ZStack(alignment: .top) {
            Color.black.opacity(theme.isDark ? 0.28 : 0.08)
                .contentShape(Rectangle())
                .onTapGesture { palette.close() }
            VStack(spacing: 0) {
                input
                Rectangle().fill(theme.text.opacity(0.07)).frame(height: 1)
                results(sections, highlightedID: highlightedID)
                footer(items.first { $0.id == highlightedID })
            }
            .frame(width: 680)
            .background(PaletteChrome(radius: 14))
            .overlay(alignment: .bottomTrailing) {
                if let item = palette.actionsItem {
                    actionPanel(item)
                        .padding(.trailing, 10).padding(.bottom, 46)
                        .transition(.asymmetric(insertion: .scale(scale: 0.96, anchor: .bottomTrailing).combined(with: .opacity), removal: .opacity))
                }
            }
            .animation(.spring(response: 0.26, dampingFraction: 0.86), value: palette.actionsItem?.id)
            .padding(.top, 92)
        }
        .onAppear { focus = .query }
        .onChange(of: palette.focusRequest) { _, _ in
            focus = palette.actionsItem == nil ? .query : .actions
            DispatchQueue.main.async { (NSApp.keyWindow?.firstResponder as? NSTextView)?.moveToEndOfDocument(nil) }
        }
        .task(id: palette.step == nil ? palette.query : "") {
            guard palette.step == nil else { return }
            await model.search(palette.query, catalog: false)
        }
        .accessibilityAddTraits(.isModal)
    }

    // MARK: Input

    private var input: some View {
        HStack(spacing: 10) {
            if let step = palette.step {
                HStack(spacing: 6) {
                    Crumb(text: step.subject, muted: true)
                    Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(theme.muted)
                    Crumb(text: step.breadcrumb, muted: false)
                }
                .fixedSize()
                .onTapGesture { palette.back() }
                .help("Back (⌫ or Esc)")
            } else {
                Image(systemName: "magnifyingglass").font(.system(size: 16, weight: .medium)).foregroundStyle(theme.muted)
            }
            TextField(palette.step?.placeholder ?? "Search songs, playlists and commands…", text: $palette.query)
                .textFieldStyle(.plain)
                .font(.system(size: 18))
                .focused($focus, equals: .query)
                .accessibilityLabel("Command palette")
            if model.searching && palette.step == nil && !palette.query.isEmpty {
                ProgressView().controlSize(.small)
            }
        }
        .padding(.horizontal, 18).frame(height: 56)
    }

    // MARK: Results

    private func results(_ sections: [PaletteSection], highlightedID: String?) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    if sections.allSatisfy(\.items.isEmpty) {
                        VStack(spacing: 6) {
                            Text(palette.step == nil ? "No results for “\(palette.query)”" : "No playlists match")
                                .font(.system(size: 13, weight: .medium))
                            Text(palette.step == nil ? "Try a song, an artist, a playlist, or a command like “sleep”." : "Only playlists that accept songs are listed.")
                                .font(.system(size: 12)).foregroundStyle(theme.muted)
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 40)
                    }
                    ForEach(sections) { section in
                        if let title = section.title, !section.items.isEmpty {
                            Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(theme.muted)
                                .padding(.horizontal, 12).padding(.top, 10).padding(.bottom, 4)
                        }
                        ForEach(section.items) { item in
                            PaletteRow(item: item, query: palette.query, highlighted: item.id == highlightedID,
                                       actionsOpen: palette.actionsItem?.id == item.id)
                                .id(item.id)
                                .onTapGesture { palette.run(item) }
                                .onHover { inside in
                                    if inside, palette.actionsItem == nil, let index = palette.items.firstIndex(where: { $0.id == item.id }) { palette.highlighted = index }
                                }
                                .contextMenu {
                                    ForEach(PaletteCatalog.actions(for: item, context: palette.contextProvider())) { action in
                                        Button(action.title) { palette.runAction(action) }
                                    }
                                }
                        }
                    }
                }
                .padding(8)
            }
            .scrollIndicators(.never)
            .frame(height: 392)
            .onChange(of: highlightedID) { _, id in if let id { proxy.scrollTo(id) } }
        }
    }

    private func footer(_ item: PaletteItem?) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "waveform").font(.system(size: 11, weight: .semibold)).foregroundStyle(theme.accent)
            Text(palette.step.map { "\($0.breadcrumb) · \($0.subject)" } ?? "Still").font(.system(size: 12, weight: .medium)).foregroundStyle(theme.muted)
                .lineLimit(1)
            Spacer()
            if let item {
                Button { palette.run(item) } label: {
                    HStack(spacing: 6) {
                        Text(item.hint).font(.system(size: 12, weight: .semibold)).foregroundStyle(theme.text)
                        KeyCap("↵")
                    }
                }.buttonStyle(.plain)
                Rectangle().fill(theme.text.opacity(0.12)).frame(width: 1, height: 16).padding(.horizontal, 4)
                Button { if palette.actionsItem == nil { palette.showActions() } else { palette.back() } } label: {
                    HStack(spacing: 6) {
                        Text("Actions").font(.system(size: 12, weight: .medium)).foregroundStyle(palette.actionsItem == nil ? theme.muted : theme.text)
                        KeyCap("⌘K")
                    }
                }.buttonStyle(.plain).help("Show actions for the highlighted result (⌘K or →)")
            }
        }
        .padding(.horizontal, 14).frame(height: 38)
        .background(theme.text.opacity(theme.isDark ? 0.04 : 0.025))
        .overlay(alignment: .top) { Rectangle().fill(theme.text.opacity(0.07)).frame(height: 1) }
    }

    // MARK: Action panel

    private func actionPanel(_ item: PaletteItem) -> some View {
        let actions = palette.actions
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                PaletteIconView(icon: item.icon, size: 18)
                Text(item.title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                Spacer(minLength: 0)
                Text(item.typeLabel).font(.system(size: 11)).foregroundStyle(theme.muted)
            }
            .padding(.horizontal, 12).padding(.top, 10).padding(.bottom, 6)
            VStack(spacing: 1) {
                ForEach(Array(actions.enumerated()), id: \.element.id) { offset, action in
                    let active = offset == palette.actionsHighlighted
                    HStack(spacing: 10) {
                        Image(systemName: action.icon.symbolName ?? "command").font(.system(size: 12, weight: .medium))
                            .foregroundStyle(active ? theme.accent : theme.muted).frame(width: 18)
                        Text(action.title).font(.system(size: 13))
                        Spacer(minLength: 8)
                        if action.title.hasSuffix("…") {
                            Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(theme.muted)
                        } else if let shortcut = action.shortcut {
                            KeyCap(shortcut)
                        }
                    }
                    .padding(.horizontal, 8).frame(height: 30)
                    .background(active ? theme.accent.opacity(theme.isDark ? 0.22 : 0.15) : .clear, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .contentShape(Rectangle())
                    .onTapGesture { palette.runAction(action) }
                    .onHover { if $0 { palette.actionsHighlighted = offset } }
                }
                if actions.isEmpty {
                    Text("No matching actions").font(.system(size: 12)).foregroundStyle(theme.muted).padding(.vertical, 8)
                }
            }
            .padding(.horizontal, 6).padding(.bottom, 6)
            Rectangle().fill(theme.text.opacity(0.08)).frame(height: 1)
            TextField("Search for actions…", text: $palette.actionsQuery)
                .textFieldStyle(.plain).font(.system(size: 13))
                .focused($focus, equals: .actions)
                .padding(.horizontal, 12).frame(height: 34)
        }
        .frame(width: 300)
        .background(PaletteChrome(radius: 11, elevated: true))
    }
}

/// Theme-tinted glass for the palette and its action panel.
struct PaletteChrome: View {
    @Environment(\.playerTheme) private var theme
    var radius: CGFloat
    var elevated = false
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        shape.fill(.regularMaterial)
            .overlay(shape.fill((elevated ? theme.surface : theme.background).opacity(theme.isDark ? 0.82 : 0.86)))
            .overlay(shape.strokeBorder(theme.text.opacity(theme.isDark ? 0.12 : 0.09), lineWidth: 1))
            .shadow(color: .black.opacity(theme.isDark ? 0.5 : 0.18), radius: elevated ? 18 : 40, y: elevated ? 8 : 18)
    }
}

private struct Crumb: View {
    @Environment(\.playerTheme) private var theme
    var text: String
    var muted: Bool
    var body: some View {
        Text(text).font(.system(size: 13, weight: .medium)).lineLimit(1).frame(maxWidth: 180)
            .foregroundStyle(muted ? theme.muted : theme.accent)
            .padding(.horizontal, 9).frame(height: 26)
            .background((muted ? theme.text.opacity(0.06) : theme.accent.opacity(0.14)), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}

struct PaletteRow: View {
    @Environment(\.playerTheme) private var theme
    var item: PaletteItem
    var query: String
    var highlighted: Bool
    var actionsOpen: Bool

    var body: some View {
        HStack(spacing: 11) {
            PaletteIconView(icon: item.icon, size: 24)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                title.font(.system(size: 13)).lineLimit(1).layoutPriority(1)
                if !item.subtitle.isEmpty {
                    Text(item.subtitle).font(.system(size: 12)).foregroundStyle(theme.muted).lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if highlighted {
                HStack(spacing: 6) {
                    Text(item.hint).font(.system(size: 12, weight: .medium)).foregroundStyle(theme.text.opacity(0.75))
                    KeyCap("↵")
                }
            } else if let shortcut = item.shortcut {
                HStack(spacing: 3) { ForEach(shortcut.components(separatedBy: " "), id: \.self) { KeyCap($0) } }
            } else {
                Text(item.typeLabel).font(.system(size: 12)).foregroundStyle(theme.muted.opacity(0.8))
            }
        }
        .padding(.horizontal, 10).frame(height: 40)
        .background {
            if highlighted {
                RoundedRectangle(cornerRadius: 9, style: .continuous).fill(theme.accent.opacity(theme.isDark ? 0.2 : 0.15))
                    .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(theme.accent.opacity(actionsOpen ? 0.35 : 0.12)))
            }
        }
        .contentShape(Rectangle())
    }

    /// The title with the matched letters emphasized.
    private var title: Text {
        let indices = Set(Fuzzy.match(query, in: item.title)?.indices ?? [])
        let characters = Array(item.title)
        guard !indices.isEmpty, Fuzzy.fold(item.title).count == characters.count else { return Text(item.title).foregroundColor(theme.text) }
        var attributed = AttributedString()
        for (offset, character) in characters.enumerated() {
            var piece = AttributedString(String(character))
            if indices.contains(offset) {
                piece.foregroundColor = theme.accent
                piece.font = .system(size: 13, weight: .bold)
            } else {
                piece.foregroundColor = theme.text
            }
            attributed += piece
        }
        return Text(attributed)
    }
}

struct PaletteIconView: View {
    @Environment(\.playerTheme) private var theme
    var icon: PaletteIcon
    var size: CGFloat
    var body: some View {
        switch icon {
        case .artwork(let url, let seed):
            Artwork(url: url, seed: seed, size: size, cornerRadius: size * 0.22)
        case .symbol(let name):
            Image(systemName: name).font(.system(size: size * 0.5, weight: .medium))
                .foregroundStyle(theme.text.opacity(0.8))
                .frame(width: size, height: size)
                .background(theme.text.opacity(theme.isDark ? 0.09 : 0.06), in: RoundedRectangle(cornerRadius: size * 0.26, style: .continuous))
        case .swatch(let id):
            let preset = ThemePreset.all.first { $0.id == id }?.theme ?? theme
            ZStack {
                Circle().fill(preset.background)
                Circle().fill(preset.accent).padding(size * 0.22)
            }
            .overlay(Circle().strokeBorder(theme.text.opacity(0.15)))
            .frame(width: size * 0.82, height: size * 0.82).frame(width: size, height: size)
        }
    }
}
