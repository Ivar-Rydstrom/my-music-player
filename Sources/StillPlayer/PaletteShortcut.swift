import SwiftUI
import AppKit

/// The key that opens the command palette. ⇧⌘P by default; changed in Settings › Keyboard.
/// Stored as text so `@AppStorage` views update when it changes: "<modifier flags>:<key code>:<key label>".
struct PaletteShortcut: Equatable {
    static let storageKey = "palette.shortcut"
    static let standard = PaletteShortcut(keyCode: 35, key: "P", modifiers: [.command, .shift])
    static let relevantModifiers: NSEvent.ModifierFlags = [.command, .option, .control, .shift]

    var keyCode: UInt16
    /// What the key prints, upper-cased ("P", "K", "Space").
    var key: String
    var modifiers: NSEvent.ModifierFlags

    init(keyCode: UInt16, key: String, modifiers: NSEvent.ModifierFlags) {
        self.keyCode = keyCode
        self.key = key
        self.modifiers = modifiers.intersection(Self.relevantModifiers)
    }

    init(storage: String) {
        let parts = storage.split(separator: ":", maxSplits: 2, omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 3, let flags = UInt(parts[0]), let code = UInt16(parts[1]), !parts[2].isEmpty else { self = .standard; return }
        self.init(keyCode: code, key: parts[2], modifiers: NSEvent.ModifierFlags(rawValue: flags))
    }

    /// Builds a shortcut from a key press, or nil for a press that can't name one (a bare modifier).
    init?(event: NSEvent) {
        let named: [UInt16: String] = [49: "Space", 36: "↩", 48: "⇥", 51: "⌫", 123: "←", 124: "→", 125: "↓", 126: "↑",
                                       122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7",
                                       100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12"]
        let label: String
        if let name = named[event.keyCode] {
            label = name
        } else if let typed = event.characters(byApplyingModifiers: []), let first = typed.first, !first.isWhitespace, !first.isNewline {
            label = String(first).uppercased()
        } else {
            return nil
        }
        self.init(keyCode: event.keyCode, key: label, modifiers: event.modifierFlags)
    }

    static var current: PaletteShortcut {
        PaletteShortcut(storage: UserDefaults.standard.string(forKey: storageKey) ?? standard.storage)
    }

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

    private var isFunctionKey: Bool { key.count > 1 && key.hasPrefix("F") }

    /// Why this can't be the palette key, or nil if it's fine.
    var problem: String? {
        if !isFunctionKey && modifiers.isDisjoint(with: [.command, .control, .option]) {
            return "Include ⌘, ⌃ or ⌥ so typing never opens the palette by accident."
        }
        if modifiers == [.option] || modifiers == [.option, .shift] {
            return "⌥ on its own types special characters. Add ⌘ or ⌃."
        }
        if let owner = Self.reserved[display] { return "\(display) is already used for \(owner)." }
        return nil
    }

    /// Shortcuts the app (or macOS text editing) already uses.
    static let reserved: [String: String] = [
        "⌘P": "Play / Pause", "⌘F": "Filter this playlist", "⌘S": "the sidebar", "⌘R": "Refresh library",
        "⌘L": "Favorite current song", "⌘,": "Settings", "⌘/": "Keyboard shortcuts", "⌘[": "Back", "⌘]": "Forward",
        "⌘K": "song actions", "⌘J": "Reveal current song", "⌘A": "Select all", "⌘Q": "Quit", "⌘W": "Close window",
        "⌘H": "Hide", "⌘M": "Minimize", "⌘C": "Copy", "⌘V": "Paste", "⌘X": "Cut", "⌘Z": "Undo", "⇧⌘Z": "Redo",
        "⇧⌘U": "Expand player", "⌘↩": "Play playlist", "⇧⌘↩": "Shuffle playlist", "⌘←": "Previous song",
        "⌘→": "Next song", "⌘↑": "Volume up", "⌘↓": "Volume down", "⌥⌘↑": "Previous playlist", "⌥⌘↓": "Next playlist",
        "⌃⌘F": "Full screen", "⌘Space": "Spotlight", "⌃Space": "input sources", "⌘⇥": "the app switcher",
    ]

    /// The SwiftUI form, for showing the shortcut on the menu item. Nil for keys SwiftUI can't express.
    var keyboardShortcut: KeyboardShortcut? {
        var flags: SwiftUI.EventModifiers = []
        if modifiers.contains(.command) { flags.insert(.command) }
        if modifiers.contains(.shift) { flags.insert(.shift) }
        if modifiers.contains(.option) { flags.insert(.option) }
        if modifiers.contains(.control) { flags.insert(.control) }
        let special: [String: KeyEquivalent] = ["Space": .space, "↩": .return, "⇥": .tab, "⌫": .delete,
                                                "←": .leftArrow, "→": .rightArrow, "↑": .upArrow, "↓": .downArrow]
        if let equivalent = special[key] { return KeyboardShortcut(equivalent, modifiers: flags) }
        guard key.count == 1, let character = key.lowercased().first else { return nil }
        return KeyboardShortcut(KeyEquivalent(character), modifiers: flags)
    }
}

extension View {
    /// Shows the palette shortcut on a menu item when SwiftUI can express it.
    @ViewBuilder func paletteShortcut(_ shortcut: PaletteShortcut) -> some View {
        if let keyboardShortcut = shortcut.keyboardShortcut { self.keyboardShortcut(keyboardShortcut) } else { self }
    }
}

// MARK: - Recorder

@MainActor
final class ShortcutRecorder: ObservableObject {
    @Published var recording = false
    @Published var message: String?
    private var monitor: Any?

    func start(onRecord: @escaping (PaletteShortcut) -> Void) {
        stop()
        message = nil
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            nonisolated(unsafe) let event = event
            MainActor.assumeIsolated {
                guard let self else { return }
                if event.keyCode == 53 && event.modifierFlags.intersection(PaletteShortcut.relevantModifiers).isEmpty { self.stop(); return }
                guard let shortcut = PaletteShortcut(event: event) else { return }
                if let problem = shortcut.problem { self.message = problem; return }
                onRecord(shortcut)
                self.stop()
            }
            return nil
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        recording = false
    }
}

struct KeyboardSettingsView: View {
    @Environment(\.playerTheme) private var theme
    @AppStorage(PaletteShortcut.storageKey) private var stored = PaletteShortcut.standard.storage
    @StateObject private var recorder = ShortcutRecorder()

    private var shortcut: PaletteShortcut { PaletteShortcut(storage: stored) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Keyboard").font(.system(size: 28, weight: .semibold, design: .rounded))
                    Text("Still is built to be driven from the keyboard.").foregroundStyle(theme.muted)
                }
                HStack(alignment: .center, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Command palette").font(.headline)
                        Text("Search songs and playlists, change settings, control playback.")
                            .font(.callout).foregroundStyle(theme.muted)
                    }
                    Spacer()
                    if shortcut != .standard && !recorder.recording {
                        Button("Reset") { stored = PaletteShortcut.standard.storage; recorder.message = nil }
                            .buttonStyle(.plain).font(.callout).foregroundStyle(theme.accent)
                            .help("Back to \(PaletteShortcut.standard.display)")
                    }
                    Button {
                        if recorder.recording { recorder.stop() } else { recorder.start { stored = $0.storage } }
                    } label: {
                        Text(recorder.recording ? "Type a shortcut…" : shortcut.display)
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundStyle(recorder.recording ? theme.muted : theme.text)
                            .frame(minWidth: 150, minHeight: 34)
                            .background(theme.text.opacity(theme.isDark ? 0.08 : 0.05), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .strokeBorder(recorder.recording ? theme.accent : theme.text.opacity(0.12), lineWidth: recorder.recording ? 1.5 : 1))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(recorder.recording ? "Press the new shortcut, or Esc to cancel" : "Click, then press a new shortcut")
                    .accessibilityLabel("Command palette shortcut, \(shortcut.display). Click to change.")
                }
                .padding(16)
                .background(theme.surface, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                if let message = recorder.message {
                    Label(message, systemImage: "exclamationmark.circle").font(.callout).foregroundStyle(theme.accent)
                } else if recorder.recording {
                    Text("Press the keys together. Esc cancels.").font(.callout).foregroundStyle(theme.muted)
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("Inside the palette").font(.headline)
                    hint("Move", "↑  ↓")
                    hint("Run the highlighted result", "↩")
                    hint("Actions for the highlighted result", "⌘K  →")
                    hint("Play next or shuffle", "⌘↩")
                    hint("Back a step, then close", "⌫  esc")
                }
                .padding(16)
                .background(theme.surface, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                Text("Every other shortcut is listed in Help › Keyboard Shortcuts (⌘/).").font(.caption).foregroundStyle(theme.muted)
            }
            .padding(28)
        }
        .onDisappear { recorder.stop() }
    }

    private func hint(_ title: String, _ keys: String) -> some View {
        HStack {
            Text(title).font(.callout)
            Spacer()
            HStack(spacing: 4) { ForEach(keys.components(separatedBy: "  "), id: \.self) { KeyCap($0) } }
        }
    }
}
