import SwiftUI
import AppKit

// Every app command's keyboard shortcut is the user's to change or remove (Settings › Keyboard).
// `ShortcutAction` lists the commands and their defaults, `KeyBinding` is one key combination, and
// `ShortcutStore` holds the current bindings. The main window's key monitor dispatches through the
// store, so a binding works even where a menu can't display it (F-keys); menus show it where they can.

/// One key combination, e.g. ⇧⌘P.
struct KeyBinding: Equatable {
    static let relevantModifiers: NSEvent.ModifierFlags = [.command, .option, .control, .shift]

    var keyCode: UInt16
    /// What the key prints, upper-cased ("P", "[", "Space", "↩", "F5").
    var key: String
    var modifiers: NSEvent.ModifierFlags

    init(_ keyCode: UInt16, _ key: String, _ modifiers: NSEvent.ModifierFlags) {
        self.keyCode = keyCode
        self.key = key
        self.modifiers = modifiers.intersection(Self.relevantModifiers)
    }

    /// Parses "<modifier flags>:<key code>:<key label>".
    init?(storage: String) {
        let parts = storage.split(separator: ":", maxSplits: 2, omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 3, let flags = UInt(parts[0]), let code = UInt16(parts[1]), !parts[2].isEmpty else { return nil }
        self.init(code, parts[2], NSEvent.ModifierFlags(rawValue: flags))
    }

    /// Builds a binding from a key press, or nil for a press that can't name one.
    init?(event: NSEvent) {
        let label: String
        if let name = Self.named[event.keyCode] {
            label = name
        } else if let typed = event.characters(byApplyingModifiers: []), let first = typed.first, !first.isWhitespace, !first.isNewline {
            label = String(first).uppercased()
        } else {
            return nil
        }
        self.init(event.keyCode, label, event.modifierFlags)
    }

    private static let named: [UInt16: String] = [
        49: "Space", 36: "↩", 76: "↩", 48: "⇥", 51: "⌫", 117: "⌦", 53: "esc", 123: "←", 124: "→", 125: "↓", 126: "↑",
        115: "↖", 119: "↘", 116: "⇞", 121: "⇟",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8", 101: "F9", 109: "F10",
        103: "F11", 111: "F12", 105: "F13", 107: "F14", 113: "F15",
    ]

    var storage: String { "\(modifiers.rawValue):\(keyCode):\(key)" }

    var display: String {
        var text = ""
        if modifiers.contains(.control) { text += "⌃" }
        if modifiers.contains(.option) { text += "⌥" }
        if modifiers.contains(.shift) { text += "⇧" }
        if modifiers.contains(.command) { text += "⌘" }
        return text + key
    }

    func matches(_ event: NSEvent) -> Bool {
        event.keyCode == keyCode && event.modifierFlags.intersection(Self.relevantModifiers) == modifiers
    }

    var isFunctionKey: Bool { key.count > 1 && key.hasPrefix("F") && key.dropFirst().allSatisfy(\.isNumber) }
    /// Bindings with ⌘, ⌃ or ⌥ (or F-keys) also work while a text field is focused; plain keys don't.
    var worksWhileTyping: Bool { isFunctionKey || !modifiers.isDisjoint(with: [.command, .control]) }

    /// Why this combination can't be a shortcut at all, or nil if it can.
    var problem: String? {
        if let owner = Self.system[display] { return "\(display) belongs to \(owner)." }
        if key == "Space" && modifiers.isEmpty { return nil }
        if isFunctionKey { return nil }
        if modifiers.isDisjoint(with: [.command, .control, .option]) {
            return "Add ⌘, ⌃ or ⌥ (plain keys are for typing and moving around). Space and F-keys may stand alone."
        }
        if modifiers.isDisjoint(with: [.command, .control]) && key.count == 1 {
            return "⌥ on its own types special characters. Add ⌘ or ⌃."
        }
        return nil
    }

    /// Combinations macOS or text editing owns; no app command may take them.
    static let system: [String: String] = [
        "⌘Q": "Quit", "⌘W": "Close Window", "⌘H": "Hide", "⌥⌘H": "Hide Others", "⌘M": "Minimize",
        "⌘C": "Copy", "⌘V": "Paste", "⌘X": "Cut", "⌘Z": "Undo", "⇧⌘Z": "Redo", "⌃⌘F": "Full Screen",
        "⌘Space": "Spotlight", "⌃Space": "Input Sources", "⌘⇥": "the app switcher", "⌘`": "window cycling",
        "⌃⌘Q": "Lock Screen", "⌘esc": "the system",
    ]

    /// The SwiftUI form, for showing the binding on a menu item. Nil for keys SwiftUI can't express.
    var keyboardShortcut: KeyboardShortcut? {
        var flags: SwiftUI.EventModifiers = []
        if modifiers.contains(.command) { flags.insert(.command) }
        if modifiers.contains(.shift) { flags.insert(.shift) }
        if modifiers.contains(.option) { flags.insert(.option) }
        if modifiers.contains(.control) { flags.insert(.control) }
        let special: [String: KeyEquivalent] = ["Space": .space, "↩": .return, "⇥": .tab, "⌫": .delete, "⌦": .deleteForward,
                                                "esc": .escape, "←": .leftArrow, "→": .rightArrow, "↑": .upArrow, "↓": .downArrow,
                                                "↖": .home, "↘": .end, "⇞": .pageUp, "⇟": .pageDown]
        if let equivalent = special[key] { return KeyboardShortcut(equivalent, modifiers: flags) }
        guard key.count == 1, let character = key.lowercased().first else { return nil }
        return KeyboardShortcut(KeyEquivalent(character), modifiers: flags)
    }
}

/// Every app command that has a keyboard shortcut.
enum ShortcutAction: String, CaseIterable, Identifiable {
    case palette, songActions, filter, searchLibrary
    case back, forward, previousList, nextList, revealCurrent
    case playPause, playPauseQuick, nextSong, previousSong, playPlaylist, shufflePlaylist, favoriteCurrent, volumeUp, volumeDown
    case selectAll
    case toggleSidebar, expandPlayer, refresh, settings, shortcutsHelp

    enum Group: String, CaseIterable { case search = "Search and palette", go = "Go", playback = "Playback", songs = "Songs", window = "Window" }

    var id: String { rawValue }

    var title: String {
        switch self {
        case .palette: "Command palette"
        case .songActions: "Actions for selected song"
        case .filter: "Filter this playlist"
        case .searchLibrary: "Search whole library"
        case .back: "Back"
        case .forward: "Forward"
        case .previousList: "Previous playlist"
        case .nextList: "Next playlist"
        case .revealCurrent: "Reveal current song"
        case .playPause: "Play / pause"
        case .playPauseQuick: "Play / pause (second key)"
        case .nextSong: "Next song"
        case .previousSong: "Previous song"
        case .playPlaylist: "Play playlist"
        case .shufflePlaylist: "Shuffle playlist"
        case .favoriteCurrent: "Favorite current song"
        case .volumeUp: "Music volume up"
        case .volumeDown: "Music volume down"
        case .selectAll: "Select all songs"
        case .toggleSidebar: "Hide / show sidebar"
        case .expandPlayer: "Expand player"
        case .refresh: "Refresh library"
        case .settings: "Settings"
        case .shortcutsHelp: "Keyboard shortcuts"
        }
    }

    var group: Group {
        switch self {
        case .palette, .songActions, .filter, .searchLibrary: .search
        case .back, .forward, .previousList, .nextList, .revealCurrent: .go
        case .playPause, .playPauseQuick, .nextSong, .previousSong, .playPlaylist, .shufflePlaylist, .favoriteCurrent, .volumeUp, .volumeDown: .playback
        case .selectAll: .songs
        case .toggleSidebar, .expandPlayer, .refresh, .settings, .shortcutsHelp: .window
        }
    }

    var standard: KeyBinding? {
        switch self {
        case .palette: KeyBinding(35, "P", [.command, .shift])
        case .songActions: KeyBinding(40, "K", [.command])
        case .filter: KeyBinding(3, "F", [.command])
        case .searchLibrary: KeyBinding(3, "F", [.command, .shift])
        case .back: KeyBinding(33, "[", [.command])
        case .forward: KeyBinding(30, "]", [.command])
        case .previousList: KeyBinding(126, "↑", [.command, .option])
        case .nextList: KeyBinding(125, "↓", [.command, .option])
        case .revealCurrent: KeyBinding(38, "J", [.command])
        case .playPause: KeyBinding(35, "P", [.command])
        case .playPauseQuick: KeyBinding(49, "Space", [])
        case .nextSong: KeyBinding(124, "→", [.command])
        case .previousSong: KeyBinding(123, "←", [.command])
        case .playPlaylist: KeyBinding(36, "↩", [.command])
        case .shufflePlaylist: KeyBinding(36, "↩", [.command, .shift])
        case .favoriteCurrent: KeyBinding(37, "L", [.command])
        case .volumeUp: KeyBinding(126, "↑", [.command])
        case .volumeDown: KeyBinding(125, "↓", [.command])
        case .selectAll: KeyBinding(0, "A", [.command])
        case .toggleSidebar: KeyBinding(1, "S", [.command])
        case .expandPlayer: KeyBinding(32, "U", [.command, .shift])
        case .refresh: KeyBinding(15, "R", [.command])
        case .settings: KeyBinding(43, ",", [.command])
        case .shortcutsHelp: KeyBinding(44, "/", [.command])
        }
    }

    /// The palette keeps its original key so earlier settings carry over.
    var storageKey: String { self == .palette ? "palette.shortcut" : "shortcut." + rawValue }

    /// Shown in Settings while the binding is removed: how to reach the command without a key.
    var withoutKey: String? {
        switch self {
        case .palette: "Open it from the address bar at the top of the sidebar, or Edit › Command Palette."
        case .songActions: "Right-click a song, or use its ⋯ button."
        case .playPause, .playPauseQuick: "Use the play button in the player, or Playback › Play / Pause."
        case .settings: "Use the gear at the bottom of the sidebar, or Still › Settings."
        case .shortcutsHelp: "Use the keyboard button at the bottom of the sidebar, or Help › Keyboard Shortcuts."
        default: nil
        }
    }
}

/// The user's current bindings. A removed binding is stored as "none" and stays removed; a binding the
/// user never touched follows the default.
@MainActor
final class ShortcutStore: ObservableObject {
    static let shared = ShortcutStore()
    static let unboundStorage = "none"

    @Published private(set) var bindings: [ShortcutAction: KeyBinding] = [:]
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        reload()
    }

    func reload() {
        var loaded: [ShortcutAction: KeyBinding] = [:]
        for action in ShortcutAction.allCases {
            switch defaults.string(forKey: action.storageKey) {
            case Self.unboundStorage?: continue
            case let stored?: if let binding = KeyBinding(storage: stored) ?? action.standard { loaded[action] = binding }
            case nil: if let standard = action.standard { loaded[action] = standard }
            }
        }
        bindings = loaded
    }

    func binding(_ action: ShortcutAction) -> KeyBinding? { bindings[action] }
    func display(_ action: ShortcutAction) -> String? { bindings[action]?.display }
    func isDefault(_ action: ShortcutAction) -> Bool { bindings[action] == action.standard }

    /// "Filter this playlist (⌘F)", or just the text when the command has no key.
    func hint(_ text: String, _ action: ShortcutAction) -> String { display(action).map { "\(text) (\($0))" } ?? text }

    /// The command already using this combination, if any.
    func owner(of binding: KeyBinding, except action: ShortcutAction? = nil) -> ShortcutAction? {
        bindings.first { $0.key != action && $0.value == binding }?.key
    }

    /// Why `binding` can't be given to `action`, or nil if it can.
    func problem(_ binding: KeyBinding, for action: ShortcutAction) -> String? {
        if let problem = binding.problem { return problem }
        if let owner = owner(of: binding, except: action) {
            return "\(binding.display) is already used for “\(owner.title)”. Remove or change it there first."
        }
        return nil
    }

    /// Sets a binding, or removes it with nil.
    func set(_ binding: KeyBinding?, for action: ShortcutAction) {
        defaults.set(binding?.storage ?? Self.unboundStorage, forKey: action.storageKey)
        bindings[action] = binding
    }

    func reset(_ action: ShortcutAction) {
        // Taking back a default another command now uses would make two commands share a key.
        if let standard = action.standard, let owner = owner(of: standard, except: action) {
            set(nil, for: owner)
        }
        defaults.removeObject(forKey: action.storageKey)
        bindings[action] = action.standard
    }

    func resetAll() {
        for action in ShortcutAction.allCases { defaults.removeObject(forKey: action.storageKey) }
        reload()
    }

    /// The command a key press triggers. While typing in a text field only bindings with ⌘ or ⌃ (or
    /// F-keys) count, and Select All stays with the text field.
    func action(for event: NSEvent, typing: Bool) -> ShortcutAction? {
        guard let match = bindings.first(where: { $0.value.matches(event) }) else { return nil }
        if typing && (!match.value.worksWhileTyping || match.key == .selectAll) { return nil }
        return match.key
    }
}

extension View {
    /// Shows a binding on its menu item, or nothing when it's removed or SwiftUI can't express it.
    @ViewBuilder func shortcut(_ binding: KeyBinding?) -> some View {
        if let keyboardShortcut = binding?.keyboardShortcut { self.keyboardShortcut(keyboardShortcut) } else { self }
    }
}

// MARK: - Settings › Keyboard

/// Records one binding at a time: the next key press becomes the binding, ⌫ removes it, Esc cancels.
@MainActor
final class ShortcutRecorder: ObservableObject {
    @Published private(set) var recording: ShortcutAction?
    @Published var message: (action: ShortcutAction, text: String)?
    private var monitor: Any?

    func start(_ action: ShortcutAction, store: ShortcutStore) {
        stop()
        message = nil
        recording = action
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            nonisolated(unsafe) let event = event
            MainActor.assumeIsolated {
                guard let self else { return }
                let bare = event.modifierFlags.intersection(KeyBinding.relevantModifiers).isEmpty
                if event.keyCode == 53 && bare { self.stop(); return }
                if (event.keyCode == 51 || event.keyCode == 117) && bare { store.set(nil, for: action); self.stop(); return }
                guard let binding = KeyBinding(event: event) else { return }
                if let problem = store.problem(binding, for: action) { self.message = (action, problem); return }
                store.set(binding, for: action)
                self.stop()
            }
            return nil
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        recording = nil
    }
}

struct KeyboardSettingsView: View {
    @Environment(\.playerTheme) private var theme
    @ObservedObject private var store = ShortcutStore.shared
    @StateObject private var recorder = ShortcutRecorder()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Keyboard").font(.system(size: 28, weight: .semibold, design: .rounded))
                        Text("Click a shortcut and press new keys. ⌫ or ✕ removes it; every command still works from the menus and the mouse.")
                            .foregroundStyle(theme.muted).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Button("Reset all") { recorder.stop(); store.resetAll() }
                        .buttonStyle(.plain).foregroundStyle(theme.accent)
                        .disabled(ShortcutAction.allCases.allSatisfy(store.isDefault))
                }
                ForEach(ShortcutAction.Group.allCases, id: \.self) { group in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(group.rawValue).font(.system(size: 12, weight: .semibold)).foregroundStyle(theme.accent).padding(.leading, 4)
                        VStack(spacing: 0) {
                            let actions = ShortcutAction.allCases.filter { $0.group == group }
                            ForEach(Array(actions.enumerated()), id: \.element) { offset, action in
                                if offset > 0 { Rectangle().fill(theme.text.opacity(0.06)).frame(height: 1).padding(.leading, 14) }
                                ShortcutRow(action: action, store: store, recorder: recorder)
                            }
                        }
                        .background(theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }
                fixedKeys
            }
            .padding(28)
        }
        .onDisappear { recorder.stop() }
    }

    /// Keys that move around and edit text rather than run commands. They stay as macOS defines them.
    private var fixedKeys: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Fixed keys").font(.headline)
            Text("These move around lists and the palette, so they stay put.").font(.callout).foregroundStyle(theme.muted)
            hint("Move / extend selection", "↑  ↓  ⇧↑  ⇧↓")
            hint("Play selected song, or run palette result", "↩")
            hint("Back out: palette step, filter, selection", "esc")
            hint("Palette: actions for result, play next, back", "⌘K  →  ⌘↩  ⌫")
        }
        .padding(16)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func hint(_ title: String, _ keys: String) -> some View {
        HStack {
            Text(title).font(.callout)
            Spacer()
            HStack(spacing: 4) { ForEach(keys.components(separatedBy: "  "), id: \.self) { KeyCap($0) } }
        }
    }
}

/// One command: its name, its key (click to record), remove (✕) and reset (↺).
struct ShortcutRow: View {
    @Environment(\.playerTheme) private var theme
    var action: ShortcutAction
    @ObservedObject var store: ShortcutStore
    @ObservedObject var recorder: ShortcutRecorder

    private var binding: KeyBinding? { store.binding(action) }
    private var recording: Bool { recorder.recording == action }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Text(action.title).font(.system(size: 13))
                Spacer(minLength: 8)
                if !store.isDefault(action) && !recording {
                    Button { recorder.message = nil; store.reset(action) } label: {
                        Image(systemName: "arrow.uturn.backward").font(.system(size: 11, weight: .semibold)).frame(width: 22, height: 22)
                    }
                    .buttonStyle(.plain).foregroundStyle(theme.accent)
                    .help("Reset to \(action.standard?.display ?? "none")").accessibilityLabel("Reset \(action.title) shortcut")
                }
                field
            }
            if let message = recorder.message, message.action == action {
                Text(message.text).font(.caption).foregroundStyle(theme.accent)
            } else if recording {
                Text("Press the keys together. ⌫ removes the shortcut, Esc cancels.").font(.caption).foregroundStyle(theme.muted)
            } else if binding == nil, let note = action.withoutKey {
                Text("No shortcut. \(note)").font(.caption).foregroundStyle(theme.muted)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
    }

    private var field: some View {
        HStack(spacing: 0) {
            Button {
                if recording { recorder.stop() } else { recorder.start(action, store: store) }
            } label: {
                Text(recording ? "Type keys…" : binding?.display ?? "None")
                    .font(.system(size: 12.5, weight: .medium, design: .rounded))
                    .foregroundStyle(recording || binding == nil ? theme.muted : theme.text)
                    .frame(maxWidth: .infinity, minHeight: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(recording ? "Press the new shortcut. ⌫ removes it, Esc cancels." : "Click, then press a new shortcut")
            .accessibilityLabel("\(action.title) shortcut, \(binding?.display ?? "none"). Click to change.")
            if binding != nil && !recording {
                Button { recorder.message = nil; store.set(nil, for: action) } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 11)).foregroundStyle(theme.muted.opacity(0.8))
                        .frame(width: 22, height: 26).contentShape(Rectangle())
                }
                .buttonStyle(.plain).help("Remove shortcut").accessibilityLabel("Remove \(action.title) shortcut")
            }
        }
        .frame(width: 128)
        .background(theme.text.opacity(theme.isDark ? 0.08 : 0.05), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous)
            .strokeBorder(recording ? theme.accent : theme.text.opacity(0.1), lineWidth: recording ? 1.5 : 1))
    }
}
