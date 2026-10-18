import SwiftUI
import Testing
@testable import SplitKit

/// `ShortcutMap` (spec §7.5): the default table, collision testing against the standard macOS menu
/// shortcuts SplitKit doesn't own, host maps with conflicts, and content shortcuts that lose to SplitKit's.
@MainActor @Suite struct ShortcutMapTests {
    func shortcut(_ key: KeyEquivalent, _ modifiers: EventModifiers) -> KeyboardShortcut {
        KeyboardShortcut(key, modifiers: modifiers)
    }

    // MARK: The default table

    @Test func defaultMapIsTheSpecTable() {
        let map = ShortcutMap.default
        #expect(map[.addContent] == shortcut("n", [.command, .shift]))
        #expect(map[.splitRight] == shortcut("d", .command))
        #expect(map[.splitDown] == shortcut("d", [.command, .shift]))
        let focus: [(ShortcutCommand, KeyEquivalent)] = [(.focusLeft, .leftArrow), (.focusRight, .rightArrow), (.focusUp, .upArrow), (.focusDown, .downArrow)]
        for (command, key) in focus { #expect(map[command] == shortcut(key, [.command, .option])) }
        let move: [(ShortcutCommand, KeyEquivalent)] = [(.moveLeft, .leftArrow), (.moveRight, .rightArrow), (.moveUp, .upArrow), (.moveDown, .downArrow)]
        for (command, key) in move { #expect(map[command] == shortcut(key, [.control, .option, .command])) }
        #expect(map[.focusPane] == shortcut("f", [.control, .command]))
        #expect(map[.detach] == shortcut("d", [.option, .command]))
        #expect(map[.closePane] == shortcut("w", .command))
        #expect(map[.closeWindow] == shortcut("w", [.command, .shift]))
        #expect(ShortcutCommand.allCases.allSatisfy { map[$0] != nil }, "every command has a default")
    }

    @Test func defaultMapHasNoDuplicates() {
        let shortcuts = ShortcutCommand.allCases.compactMap { ShortcutMap.default[$0] }
        for (index, value) in shortcuts.enumerated() {
            #expect(!shortcuts[(index + 1)...].contains(value), "duplicate \(value)")
        }
        #expect(ShortcutMap.default.conflicts().filter { if case .duplicate = $0 { true } else { false } }.isEmpty)
    }

    /// The listed standard shortcuts (`ShortcutMap.standardMacOS`): Quit, Hide, Hide Others, Minimize, Settings,
    /// New, Open, Save, Save As, Print, Page Setup, Undo, Redo, Cut, Copy, Paste, Paste and Match Style,
    /// Select All, Find, Find Next/Previous, Use Selection for Find, Jump to Selection, Show Fonts, Bold,
    /// Italic, Underline, Close All, Cycle Through Windows (both ways), Help.
    @Test func defaultMapCollidesWithNoStandardShortcut() {
        #expect(ShortcutMap.default.conflicts() == [])
        #expect(ShortcutMap.default.conflicts(reserved: ShortcutMap.standardMacOS) == [])
        #expect(throws: Never.self) { try ShortcutMap.default.validate() }
        let listed = ShortcutMap.standardMacOS.map(\.name)
        for name in ["Quit", "Hide", "Minimize", "Settings", "New", "Open", "Save", "Print", "Undo", "Redo", "Cut", "Copy",
                     "Paste", "Select All", "Find", "Cycle Through Windows"] {
            #expect(listed.contains(name), "\(name) is not in the standard list")
        }
        #expect(ShortcutMap.standardMacOS.map(\.shortcut).count == Set(ShortcutMap.standardMacOS.map(\.shortcut)).count,
                "the list itself has no duplicates")
    }

    /// Deviation candidate: the spec's own table overlaps two system shortcuts. The test pins them so they
    /// stay visible.
    @Test func theSpecTableOverlapsExactlyTwoSystemShortcuts() {
        let overlaps = ShortcutMap.default.conflicts(reserved: ShortcutMap.systemOverlaps)
        #expect(overlaps == [
            .reserved(.focusPane, shortcut("f", [.control, .command]), name: "Enter Full Screen"),
            .reserved(.detach, shortcut("d", [.option, .command]), name: "Turn Dock Hiding On/Off"),
        ])
    }

    // MARK: Host maps

    @Test func aRemappedMapWithoutConflictsIsValid() throws {
        var map = ShortcutMap.default
        map[.splitRight] = shortcut("r", [.command, .option])
        map[.detach] = nil
        try map.validate()
        #expect(map[.splitRight] == shortcut("r", [.command, .option]) && map[.detach] == nil)
    }

    @Test func duplicatesInAHostMapAreReported() {
        var map = ShortcutMap.default
        map[.splitDown] = map[.splitRight]
        #expect(map.conflicts() == [.duplicate(shortcut("d", .command), [.splitRight, .splitDown])])
        #expect(throws: ShortcutMapError(conflicts: map.conflicts())) { try map.validate() }
    }

    @Test func collisionsWithStandardShortcutsAreReported() {
        var map = ShortcutMap.default
        map[.splitRight] = shortcut("q", .command)
        map[.focusUp] = shortcut("c", .command)
        #expect(map.conflicts() == [
            .reserved(.splitRight, shortcut("q", .command), name: "Quit"),
            .reserved(.focusUp, shortcut("c", .command), name: "Copy"),
        ])
    }

    @Test func aHostMayAllowAShortcutByPassingItsOwnReservedList() throws {
        var map = ShortcutMap.default
        map[.splitRight] = shortcut("q", .command)
        try map.validate(reserved: [])
    }

    @Test func conflictingCommandsGetNoShortcutAndTheRestIsKept() {
        var map = ShortcutMap.default
        map[.splitDown] = map[.splitRight]
        map[.focusUp] = shortcut("c", .command)
        let commands = SplitKitCommands(try! SplitKitWorkspace(registry: .init(), configuration: SplitKitConfiguration()), shortcuts: map)
        #expect(commands.shortcutError?.conflicts == map.conflicts())
        #expect(commands.shortcuts[.splitRight] == nil && commands.shortcuts[.splitDown] == nil)
        #expect(commands.shortcuts[.focusUp] == nil)
        #expect(commands.shortcuts[.closePane] == ShortcutMap.default[.closePane])
        #expect(commands.shortcuts[.addContent] == ShortcutMap.default[.addContent])
    }

    @Test func aValidMapIsKeptAsGiven() throws {
        let commands = SplitKitCommands(try SplitKitWorkspace(registry: .init(), configuration: SplitKitConfiguration()))
        #expect(commands.shortcutError == nil)
        #expect(commands.shortcuts == .default)
    }

    // MARK: Content shortcuts (spec §7.4)

    @Test func aContentShortcutWithoutConflictIsKept() {
        #expect(ShortcutMap.default.contentShortcut(KeyboardShortcut("0")) == KeyboardShortcut("0"))
        #expect(ShortcutMap.default.contentShortcut(nil) == nil)
    }

    @Test func aContentShortcutThatCollidesWithASplitKitShortcutLoses() {
        #expect(ShortcutMap.default.contentShortcut(shortcut("d", .command), itemTitle: "Duplicate") == nil)
        #expect(ShortcutMap.default.contentShortcut(shortcut("w", [.command, .shift])) == nil)
    }

    @Test func aRemappedShortcutFreesTheOldOneForContent() {
        var map = ShortcutMap.default
        map[.splitRight] = shortcut("r", [.command, .option])
        #expect(map.contentShortcut(shortcut("d", .command)) == shortcut("d", .command))
        #expect(map.contentShortcut(shortcut("r", [.command, .option])) == nil)
    }
}
