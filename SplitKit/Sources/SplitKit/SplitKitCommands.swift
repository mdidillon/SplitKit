import OSLog
import SwiftUI
import SplitKitModel

extension FocusedValues {
    /// The window of the key `SplitKitView`; `SplitKitCommands` acts in it.
    @Entry var splitKitWindow: WindowID?
}

/// The menu bar commands of SplitKit (spec §5, §7.5): File ▸ Add Content…, the Pane menu and Window ▸ Close
/// Window. Every item renders the same `PaneMenuModel` as the pane menu, for the active pane of the key
/// window (the `splitKitWindow` focused value), so titles, enabled states and actions cannot differ.
///
/// It replaces File ▸ Close (⌘W) and, with it, whatever else SwiftUI places in `CommandGroupPlacement.saveItem`:
/// a host that needs Save re-adds it in its own commands.
///
/// `shortcuts` is validated here. A conflicting map is not applied silently: `shortcutError` lists the
/// conflicts, the conflicting commands get no shortcut (they stay in the menus) and every other shortcut
/// of the map is kept.
public struct SplitKitCommands: Commands {
    private let workspace: SplitKitWorkspace
    /// The shortcuts in force: the given map minus the commands in conflict.
    public let shortcuts: ShortcutMap
    /// The conflicts of the given map, or nil when it is valid (spec §7.5).
    public let shortcutError: ShortcutMapError?
    @FocusedValue(\.splitKitWindow) private var window

    public init(_ ws: SplitKitWorkspace, shortcuts: ShortcutMap = .default) {
        workspace = ws
        do {
            try shortcuts.validate()
            self.shortcuts = shortcuts
            shortcutError = nil
        } catch {
            Logger.shortcuts.error("Invalid ShortcutMap, conflicting commands get no shortcut: \(String(describing: error.conflicts))")
            self.shortcuts = shortcuts.removing(error)
            shortcutError = error
        }
    }

    /// The key window's `SplitKitView`, or else the key coordinator window (`.splitKit` mode).
    private var model: PaneMenuModel { workspace.activePaneMenuModel(in: window ?? workspace.keyWindow) }

    public var body: some Commands {
        CommandGroup(replacing: .saveItem) {}
        CommandGroup(after: .newItem) {
            if case .splitKit = workspace.configuration.windowManagement {
                // SplitKit owns the windows here, so it owns File ▸ New Window and its standard shortcut.
                Button(ChromeText.newWindow) { workspace.send(.newWindow) }
                    .keyboardShortcut(ShortcutMap.newWindow)
            }
            PaneMenuEntry(workspace: workspace, model: model, action: .chooseContent, shortcuts: shortcuts)
        }
        CommandMenu(ChromeText.paneMenu) {
            PaneMenu(workspace: workspace, model: model, scope: .menuBar(shortcuts))
        }
        CommandGroup(after: .windowArrangement) {
            PaneMenuEntry(workspace: workspace, model: model, action: .closeWindow, shortcuts: shortcuts)
        }
    }
}
