import OSLog
import SwiftUI

/// The commands that have a keyboard shortcut (spec §7.5). One case per row of the table; the four
/// directional rows are split per direction.
public enum ShortcutCommand: CaseIterable, Hashable, Sendable {
    case addContent
    case splitRight, splitDown
    case focusLeft, focusRight, focusUp, focusDown
    case moveLeft, moveRight, moveUp, moveDown
    case focusPane
    case detach
    case closePane
    case closeWindow
}

/// A standard macOS shortcut that SplitKit does not own, with the name of the menu item that has it.
public struct ReservedShortcut: Equatable, Sendable {
    public var name: String
    public var shortcut: KeyboardShortcut

    public init(_ name: String, _ shortcut: KeyboardShortcut) {
        self.name = name
        self.shortcut = shortcut
    }
}

/// A problem in a `ShortcutMap` (spec §7.5 collision testing).
public enum ShortcutConflict: Equatable, Sendable {
    /// Two or more commands have the same shortcut.
    case duplicate(KeyboardShortcut, [ShortcutCommand])
    /// A command has a standard macOS shortcut that SplitKit does not own.
    case reserved(ShortcutCommand, KeyboardShortcut, name: String)

    /// The commands this conflict involves.
    var commands: [ShortcutCommand] {
        switch self {
        case let .duplicate(_, commands): commands
        case let .reserved(command, _, _): [command]
        }
    }
}

/// The recoverable error of a host-supplied map with conflicts (spec §7.5). Never thrown by the commands
/// themselves: `SplitKitCommands` reports it and leaves the conflicting commands without a shortcut.
public struct ShortcutMapError: Error, Equatable, Sendable {
    public var conflicts: [ShortcutConflict]
}

/// The keyboard shortcuts of the SplitKit commands (spec §5, §7.5). A command without an entry has no
/// shortcut; it stays reachable in the menus.
///
/// §5 references `ShortcutMap` without declaring it: this is the minimal public type (deviation
/// candidate, pending Marc's approval).
public struct ShortcutMap: Equatable, Sendable {
    public var shortcuts: [ShortcutCommand: KeyboardShortcut]

    public init(_ shortcuts: [ShortcutCommand: KeyboardShortcut]) {
        self.shortcuts = shortcuts
    }

    public subscript(_ command: ShortcutCommand) -> KeyboardShortcut? {
        get { shortcuts[command] }
        set { shortcuts[command] = newValue }
    }

    /// The §7.5 table.
    public static let `default` = ShortcutMap([
        .addContent: KeyboardShortcut("n", modifiers: [.command, .shift]),
        .splitRight: KeyboardShortcut("d", modifiers: .command),
        .splitDown: KeyboardShortcut("d", modifiers: [.command, .shift]),
        .focusLeft: KeyboardShortcut(.leftArrow, modifiers: [.command, .option]),
        .focusRight: KeyboardShortcut(.rightArrow, modifiers: [.command, .option]),
        .focusUp: KeyboardShortcut(.upArrow, modifiers: [.command, .option]),
        .focusDown: KeyboardShortcut(.downArrow, modifiers: [.command, .option]),
        .moveLeft: KeyboardShortcut(.leftArrow, modifiers: [.control, .option, .command]),
        .moveRight: KeyboardShortcut(.rightArrow, modifiers: [.control, .option, .command]),
        .moveUp: KeyboardShortcut(.upArrow, modifiers: [.control, .option, .command]),
        .moveDown: KeyboardShortcut(.downArrow, modifiers: [.control, .option, .command]),
        .focusPane: KeyboardShortcut("f", modifiers: [.control, .command]),
        .detach: KeyboardShortcut("d", modifiers: [.option, .command]),
        .closePane: KeyboardShortcut("w", modifiers: .command),
        .closeWindow: KeyboardShortcut("w", modifiers: [.command, .shift]),
    ])

    // MARK: Standard macOS shortcuts

    /// The standard macOS menu shortcuts SplitKit does not own (the default list for `conflicts(reserved:)`).
    /// ⌘W and ⇧⌘W are not here: SplitKit owns them and replaces File ▸ Close. ⌘N (New Window) is the host's.
    public static let standardMacOS: [ReservedShortcut] = [
        ReservedShortcut("Quit", KeyboardShortcut("q", modifiers: .command)),
        ReservedShortcut("Hide", KeyboardShortcut("h", modifiers: .command)),
        ReservedShortcut("Hide Others", KeyboardShortcut("h", modifiers: [.option, .command])),
        ReservedShortcut("Minimize", KeyboardShortcut("m", modifiers: .command)),
        ReservedShortcut("Settings", KeyboardShortcut(",", modifiers: .command)),
        ReservedShortcut("New", KeyboardShortcut("n", modifiers: .command)),
        ReservedShortcut("Open", KeyboardShortcut("o", modifiers: .command)),
        ReservedShortcut("Save", KeyboardShortcut("s", modifiers: .command)),
        ReservedShortcut("Save As", KeyboardShortcut("s", modifiers: [.shift, .command])),
        ReservedShortcut("Print", KeyboardShortcut("p", modifiers: .command)),
        ReservedShortcut("Page Setup", KeyboardShortcut("p", modifiers: [.shift, .command])),
        ReservedShortcut("Undo", KeyboardShortcut("z", modifiers: .command)),
        ReservedShortcut("Redo", KeyboardShortcut("z", modifiers: [.shift, .command])),
        ReservedShortcut("Cut", KeyboardShortcut("x", modifiers: .command)),
        ReservedShortcut("Copy", KeyboardShortcut("c", modifiers: .command)),
        ReservedShortcut("Paste", KeyboardShortcut("v", modifiers: .command)),
        ReservedShortcut("Paste and Match Style", KeyboardShortcut("v", modifiers: [.option, .shift, .command])),
        ReservedShortcut("Select All", KeyboardShortcut("a", modifiers: .command)),
        ReservedShortcut("Find", KeyboardShortcut("f", modifiers: .command)),
        ReservedShortcut("Find Next", KeyboardShortcut("g", modifiers: .command)),
        ReservedShortcut("Find Previous", KeyboardShortcut("g", modifiers: [.shift, .command])),
        ReservedShortcut("Use Selection for Find", KeyboardShortcut("e", modifiers: .command)),
        ReservedShortcut("Jump to Selection", KeyboardShortcut("j", modifiers: .command)),
        ReservedShortcut("Show Fonts", KeyboardShortcut("t", modifiers: .command)),
        ReservedShortcut("Bold", KeyboardShortcut("b", modifiers: .command)),
        ReservedShortcut("Italic", KeyboardShortcut("i", modifiers: .command)),
        ReservedShortcut("Underline", KeyboardShortcut("u", modifiers: .command)),
        ReservedShortcut("Close All", KeyboardShortcut("w", modifiers: [.option, .command])),
        ReservedShortcut("Cycle Through Windows", KeyboardShortcut("`", modifiers: .command)),
        ReservedShortcut("Cycle Through Windows Backwards", KeyboardShortcut("`", modifiers: [.shift, .command])),
        ReservedShortcut("Help", KeyboardShortcut("/", modifiers: [.shift, .command])),
    ]

    /// System shortcuts that the §7.5 table itself overlaps (a deviation candidate for Marc, not part of
    /// `standardMacOS`): ⌃⌘F is View ▸ Enter Full Screen and ⌥⌘D is the system-wide Dock hiding toggle.
    public static let systemOverlaps: [ReservedShortcut] = [
        ReservedShortcut("Enter Full Screen", KeyboardShortcut("f", modifiers: [.control, .command])),
        ReservedShortcut("Turn Dock Hiding On/Off", KeyboardShortcut("d", modifiers: [.option, .command])),
    ]

    // MARK: Validation

    /// Every duplicate inside the map, then every collision with `reserved`, each in `ShortcutCommand`
    /// declaration order. Empty means valid.
    public func conflicts(reserved: [ReservedShortcut] = ShortcutMap.standardMacOS) -> [ShortcutConflict] {
        var found: [ShortcutConflict] = []
        var seen: [KeyboardShortcut] = []
        for command in ShortcutCommand.allCases {
            guard let shortcut = self[command], !seen.contains(shortcut) else { continue }
            seen.append(shortcut)
            let commands = ShortcutCommand.allCases.filter { self[$0] == shortcut }
            if commands.count > 1 { found.append(.duplicate(shortcut, commands)) }
        }
        for command in ShortcutCommand.allCases {
            guard let shortcut = self[command], let match = reserved.first(where: { $0.shortcut == shortcut }) else { continue }
            found.append(.reserved(command, shortcut, name: match.name))
        }
        return found
    }

    /// The host's startup check: throws the conflicts, changes nothing.
    public func validate(reserved: [ReservedShortcut] = ShortcutMap.standardMacOS) throws(ShortcutMapError) {
        let found = conflicts(reserved: reserved)
        if !found.isEmpty { throw ShortcutMapError(conflicts: found) }
    }

    /// This map without the commands that `error` names. They stay reachable in the menus.
    func removing(_ error: ShortcutMapError) -> ShortcutMap {
        var map = self
        for command in error.conflicts.flatMap(\.commands) { map[command] = nil }
        return map
    }

    // MARK: Content shortcuts

    /// A content's shortcut (spec §7.4): `shortcut` itself, or nil when it collides with a shortcut of
    /// this map. SplitKit wins; a debug build logs a warning.
    func contentShortcut(_ shortcut: KeyboardShortcut?, itemTitle: String = "") -> KeyboardShortcut? {
        guard let shortcut else { return nil }
        guard let command = ShortcutCommand.allCases.first(where: { self[$0] == shortcut }) else { return shortcut }
        #if DEBUG
        Logger.shortcuts.warning("Content shortcut of “\(itemTitle)” dropped: it is the SplitKit shortcut of \(String(describing: command))")
        #endif
        return nil
    }
}

extension Logger {
    static let shortcuts = Logger(subsystem: "SplitKit", category: "shortcuts")
}
