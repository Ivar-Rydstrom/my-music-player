import XCTest
import SwiftUI
import AppKit
import PlayerCore
@testable import Hummery

@MainActor
final class ShortcutTests: XCTestCase {
    private var suite: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suite = "ShortcutTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    private func key(_ code: UInt16, _ chars: String, _ flags: NSEvent.ModifierFlags) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0, context: nil,
                         characters: chars, charactersIgnoringModifiers: chars, isARepeat: false, keyCode: code)!
    }

    func testEveryCommandHasADistinctDefaultThatIsAllowed() {
        var seen: [String: ShortcutAction] = [:]
        for action in ShortcutAction.allCases {
            guard let standard = action.standard else { continue }
            XCTAssertNil(standard.problem, "\(action) default \(standard.display) must be assignable")
            XCTAssertNil(seen[standard.display], "\(action) and \(seen[standard.display]!) share \(standard.display)")
            seen[standard.display] = action
        }
        XCTAssertEqual(ShortcutAction.palette.standard?.display, "⇧⌘P")
    }

    func testEveryCommandCanBeChangedAndRemovedAndThatPersists() {
        let store = ShortcutStore(defaults: defaults)
        for action in ShortcutAction.allCases {
            store.set(nil, for: action)
            XCTAssertNil(store.binding(action))
        }
        let reloaded = ShortcutStore(defaults: defaults)
        XCTAssertTrue(ShortcutAction.allCases.allSatisfy { reloaded.binding($0) == nil }, "Removed stays removed after relaunch")

        let f5 = KeyBinding(96, "F5", [])
        reloaded.set(f5, for: .playPause)
        XCTAssertEqual(ShortcutStore(defaults: defaults).binding(.playPause), f5)
        XCTAssertNil(f5.keyboardShortcut, "Menus can't show F-keys…")
        XCTAssertEqual(reloaded.action(for: key(96, "", []), typing: false), .playPause, "…but the key still works")
    }

    func testARemovedKeyTriggersNothing() {
        let store = ShortcutStore(defaults: defaults)
        let shiftCommandP = key(35, "p", [.command, .shift])
        XCTAssertEqual(store.action(for: shiftCommandP, typing: false), .palette)
        store.set(nil, for: .palette)
        XCTAssertNil(store.action(for: shiftCommandP, typing: false))
        XCTAssertNil(store.hint("Search", .palette).firstIndex(of: "("), "No key, so no key in the tooltip")
    }

    func testTheOldPaletteSettingCarriesOver() {
        defaults.set("none", forKey: "palette.shortcut")
        XCTAssertNil(ShortcutStore(defaults: defaults).binding(.palette))
        defaults.set(KeyBinding(40, "K", [.command, .option]).storage, forKey: "palette.shortcut")
        XCTAssertEqual(ShortcutStore(defaults: defaults).display(.palette), "⌥⌘K")
        defaults.set("garbage", forKey: "palette.shortcut")
        XCTAssertEqual(ShortcutStore(defaults: defaults).display(.palette), "⇧⌘P", "Unreadable data falls back to the default")
    }

    func testConflictsAreRefusedAndNamed() {
        let store = ShortcutStore(defaults: defaults)
        let commandK = KeyBinding(40, "K", [.command])
        XCTAssertEqual(store.problem(commandK, for: .palette), "⌘K is already used for “Actions for selected song”. Remove or change it there first.")
        XCTAssertNil(store.problem(commandK, for: .songActions), "Re-entering a command's own key is fine")
        store.set(nil, for: .songActions)
        XCTAssertNil(store.problem(commandK, for: .palette), "Free once removed elsewhere")
    }

    func testResettingTakesBackTheDefaultWithoutCreatingADuplicate() {
        let store = ShortcutStore(defaults: defaults)
        store.set(nil, for: .songActions)
        store.set(KeyBinding(40, "K", [.command]), for: .palette)
        store.reset(.songActions)
        XCTAssertEqual(store.display(.songActions), "⌘K")
        XCTAssertNil(store.binding(.palette), "The command that borrowed ⌘K loses it rather than sharing it")
        store.resetAll()
        XCTAssertTrue(ShortcutAction.allCases.allSatisfy(store.isDefault))
    }

    func testKeysThatWouldFireWhileTypingOrBelongToMacOSAreRefused() {
        XCTAssertNotNil(KeyBinding(35, "P", []).problem, "A bare letter would fire while typing")
        XCTAssertNotNil(KeyBinding(35, "P", [.shift]).problem)
        XCTAssertNotNil(KeyBinding(35, "P", [.option]).problem, "⌥P types π")
        XCTAssertNotNil(KeyBinding(12, "Q", [.command]).problem, "⌘Q is Quit")
        XCTAssertNotNil(KeyBinding(8, "C", [.command]).problem, "⌘C is Copy")
        XCTAssertNil(KeyBinding(49, "Space", []).problem, "Space may stand alone")
        XCTAssertNil(KeyBinding(122, "F1", []).problem, "F-keys may stand alone")
        XCTAssertNil(KeyBinding(35, "P", [.control, .option]).problem)
    }

    func testWhileTypingOnlyModifiedKeysCountAndSelectAllStaysWithTheTextField() {
        let store = ShortcutStore(defaults: defaults)
        XCTAssertEqual(store.action(for: key(49, " ", []), typing: false), .playPauseQuick)
        XCTAssertNil(store.action(for: key(49, " ", []), typing: true), "Space types a space")
        XCTAssertEqual(store.action(for: key(3, "f", [.command]), typing: true), .filter)
        XCTAssertNil(store.action(for: key(0, "a", [.command]), typing: true), "⌘A selects the text")
        XCTAssertEqual(store.action(for: key(0, "a", [.command]), typing: false), .selectAll)
    }

    func testMenuFormMatchesTheBinding() {
        XCTAssertEqual(ShortcutAction.palette.standard?.keyboardShortcut, KeyboardShortcut("p", modifiers: [.command, .shift]))
        XCTAssertEqual(ShortcutAction.playPlaylist.standard?.keyboardShortcut, KeyboardShortcut(.return, modifiers: [.command]))
        XCTAssertEqual(ShortcutAction.nextList.standard?.keyboardShortcut, KeyboardShortcut(.downArrow, modifiers: [.command, .option]))
    }

    func testPaletteRowsShowTheCurrentKeyOrNone() {
        var context = PaletteContext()
        context.current = SampleLibrary.tracks[1]
        context.keys[.nextSong] = "F9"
        context.keys[.favoriteCurrent] = nil
        let commands = PaletteCatalog.commands(context)
        XCTAssertEqual(commands.first { $0.id == "cmd.next" }?.shortcut, "F9")
        XCTAssertNil(commands.first { $0.id == "cmd.favcurrent" }?.shortcut)
    }
}
