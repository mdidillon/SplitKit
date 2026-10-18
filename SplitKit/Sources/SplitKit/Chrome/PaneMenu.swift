import SwiftUI
import SplitKitContent
import SplitKitModel

/// What the pane commands offer for one pane (or for an empty window) and what each does (spec §7.1,
/// §7.5). The title ▾ and the right-click menu, and the menu bar's Pane, File and Window items, all render
/// this one model through `PaneMenu` and `PaneMenuEntry`; the actions only call existing workspace commands.
struct PaneMenuModel {
    enum Action: Equatable {
        /// A new content of this type, through the content picker.
        case addContent(ContentType)
        /// Opens the keyboard-navigable type list (File ▸ Add Content…, ⇧⌘N).
        case chooseContent
        case split(DropEdge)
        /// Makes the geometric neighbour in this direction the active pane (⌥⌘-arrows).
        case focusNeighbour(FocusDirection)
        /// Moves the pane's content to the near edge of its neighbour in this direction (⌃⌥⌘-arrows).
        case moveToEdge(FocusDirection)
        case toggleFocusMode
        /// Opens the type list in replace mode for the pane (spec §6.3.6).
        case replaceContent
        case detach
        /// Moves the pane's content into this other window (spec §9).
        case moveToWindow(WindowID)
        /// Moves every content of the detached window into the main window (spec §9).
        case dockBack
        /// The pane, or the empty main window when there is no pane (⌘W, spec §7.5).
        case closePane
        case closeWindow

        /// The shortcut this action has in a `ShortcutMap`.
        var shortcutCommand: ShortcutCommand? {
            switch self {
            case .chooseContent: .addContent
            case let .split(edge): edge == .right ? .splitRight : edge == .bottom ? .splitDown : nil
            case let .focusNeighbour(direction):
                switch direction {
                case .left: .focusLeft
                case .right: .focusRight
                case .up: .focusUp
                case .down: .focusDown
                }
            case let .moveToEdge(direction):
                switch direction {
                case .left: .moveLeft
                case .right: .moveRight
                case .up: .moveUp
                case .down: .moveDown
                }
            case .toggleFocusMode: .focusPane
            case .detach: .detach
            case .closePane: .closePane
            case .closeWindow: .closeWindow
            case .addContent, .replaceContent, .moveToWindow, .dockBack: nil
            }
        }
    }

    /// The content submenu Pane ▸ ‹Content name› ▸ (spec §7.4): every toolbar item of the pane's content.
    struct ContentMenu {
        let title: String
        let items: [PaneToolbarItem]
    }

    /// The window the commands act in; nil when no SplitKit window is key.
    let window: WindowID?
    let windowKind: WindowLayout.Kind?
    /// The panes in the window.
    let paneCount: Int
    /// The pane the commands act on; nil in an empty window or a window without an active pane.
    let pane: PaneID?
    let isEmpty: Bool
    /// A two-stage close is waiting for this pane (or window): every action that touches it is disabled
    /// (spec §6.3).
    let isPending: Bool
    /// The window is in focus mode: only the focused pane is shown, so moving focus is off.
    let isWindowInFocusMode: Bool
    let focusModeEnabled: Bool
    /// The pane's content, if any.
    let content: ContentID?
    /// The geometric neighbour per direction that can be moved to (not closing).
    let neighbours: [FocusDirection: PaneID]
    /// The other windows Move to Window ▸ lists, main first (spec §9).
    let windowChoices: [SplitKitWorkspace.WindowChoice]
    /// `.disabled` hides Detach and Move to Window (spec §9).
    let detach: SplitKitConfiguration.Detach
    /// Add: in the pane when it is empty, otherwise in a new pane to its right.
    let picker: ContentPicker
    let contentMenu: ContentMenu?

    var canAdd: Bool { picker.isEnabled }

    /// Detach and Move to Window are offered at all (spec §9: `Detach.disabled` hides them).
    var offersDetach: Bool { detach != .disabled }

    /// The pane's content can leave its window.
    private var canLeaveWindow: Bool { pane != nil && !isPending && content != nil && offersDetach }

    /// The Move to Window ▸ submenu has something to choose.
    var canMoveToWindow: Bool { canLeaveWindow && !windowChoices.isEmpty }

    func isEnabled(_ action: Action) -> Bool {
        switch action {
        case .detach: canLeaveWindow
        case let .moveToWindow(window): canLeaveWindow && windowChoices.contains { $0.id == window }
        case .replaceContent: pane != nil && !isPending && content != nil && !picker.entries.isEmpty
        case .dockBack: windowKind == .detached && !isPending
        case .addContent, .chooseContent: canAdd
        case .split: pane != nil && !isPending
        case .toggleFocusMode: pane != nil && !isPending && focusModeEnabled
        case let .focusNeighbour(direction): pane != nil && !isPending && !isWindowInFocusMode && neighbours[direction] != nil
        case let .moveToEdge(direction): pane != nil && !isPending && content != nil && neighbours[direction] != nil
        case .closePane: !isPending && (pane != nil || windowKind == .main)
        case .closeWindow: window != nil && !isPending
        }
    }

    /// The menu title of `action`. Closing is dynamic (spec §7.5): "Close Pane and Window" for the only pane
    /// of a detached window, "Close Window" where ⌘W closes the empty main window, else "Close Pane".
    func title(_ action: Action) -> String {
        switch action {
        case let .addContent(type): picker.entries.first { $0.type == type }?.displayName ?? type.raw
        case .chooseContent: ChromeText.addContentCommand
        case let .split(edge): edge == .bottom ? ChromeText.splitDown : edge == .right ? ChromeText.splitRight : ChromeText.split
        case let .focusNeighbour(direction), let .moveToEdge(direction): ChromeText.direction(direction)
        case .toggleFocusMode: SplitKitStyleConstants.Accessibility.focusToggleLabel
        case .replaceContent: ChromeText.replaceContent
        case .detach: ChromeText.detach
        case let .moveToWindow(window): windowChoices.first { $0.id == window }?.title ?? ChromeText.moveToWindow
        case .dockBack: ChromeText.dockBack
        case .closePane:
            if pane == nil, windowKind == .main { ChromeText.closeWindow }
            else if windowKind == .detached, paneCount == 1 { ChromeText.closePaneAndWindow }
            else { SplitKitStyleConstants.Accessibility.closeLabel }
        case .closeWindow: ChromeText.closeWindow
        }
    }

    /// Runs `action` if it is enabled. Failures leave the workspace unchanged (spec §6.2).
    @MainActor func run(_ action: Action, in workspace: SplitKitWorkspace) async {
        guard isEnabled(action) else { return }
        switch action {
        case let .addContent(type):
            await picker.choose(type, in: workspace)
        case .chooseContent:
            if let window { workspace.requestAddContent(in: window) }
        case let .split(edge):
            if let pane { try? await workspace.perform(.split(pane, edge: edge)) }
        case let .focusNeighbour(direction):
            if let window, let target = neighbours[direction] { try? await workspace.perform(.setActive(target, in: window)) }
        case let .moveToEdge(direction):
            guard let content, let target = neighbours[direction] else { return }
            do {
                try await workspace.perform(.move(content, to: target, edge: direction.edge))
            } catch {
                return
            }
            // The move gives the content a new pane; the active pane follows it.
            if let host = workspace.host(of: content) { try? await workspace.perform(.setActive(host.pane, in: host.window)) }
        case .toggleFocusMode:
            if let pane { try? await workspace.perform(.toggleFocusMode(pane)) }
        case .closePane:
            if let pane {
                try? await workspace.perform(.closePane(pane))
            } else if let window {
                try? await workspace.perform(.closeWindow(window))
            }
        case .closeWindow:
            if let window { try? await workspace.perform(.closeWindow(window)) }
        case .replaceContent:
            if let pane { workspace.requestReplaceContent(of: pane) }
        case .detach:
            if let pane { try? await workspace.perform(.detach(pane)) }
        case let .moveToWindow(target):
            if let pane { try? await workspace.perform(.moveToWindow(pane, target)) }
        case .dockBack:
            if let window { try? await workspace.perform(.dockBack(window)) }
        }
    }
}

extension SplitKitWorkspace {
    /// The model of the header's pane menu for `pane` hosting `content`.
    func paneMenuModel(for pane: PaneID, content: ContentID?) -> PaneMenuModel {
        menuModel(pane: pane, content: content, window: try? window(containing: pane))
    }

    /// The model of the menu bar: the active pane of `window` (nil: no SplitKit window is key), or the
    /// empty window.
    func activePaneMenuModel(in window: WindowID?) -> PaneMenuModel {
        guard let window, let layout = windowLayout(window) else { return menuModel(pane: nil, content: nil, window: nil) }
        let leaf = layout.root?.leaves.first { $0.pane == layout.activePane }
        return menuModel(pane: leaf?.pane, content: leaf?.content, window: window)
    }

    private func menuModel(pane: PaneID?, content: ContentID?, window: WindowID?) -> PaneMenuModel {
        let layout = window.flatMap(windowLayout)
        let target: ContentPicker.Target = if let pane {
            .adding(to: pane, hosting: content)
        } else if let window, layout?.root == nil {
            addContentTarget(in: window)
        } else {
            .none
        }
        var neighbours: [FocusDirection: PaneID] = [:]
        if let pane, let root = layout?.root {
            for direction in FocusDirection.allCases {
                if let next = SplitGeometry.neighbour(of: pane, toward: direction, in: root), !isClosing(pane: next) {
                    neighbours[direction] = next
                }
            }
        }
        let items = content.flatMap { store[$0] }?.toolbarItems ?? []
        return PaneMenuModel(
            window: window, windowKind: layout?.kind, paneCount: layout?.root?.leaves.count ?? 0,
            pane: pane, isEmpty: content == nil,
            isPending: pane.map(isClosing(pane:)) ?? window.map(isClosing(window:)) ?? false,
            isWindowInFocusMode: layout?.focusModePane != nil, focusModeEnabled: configuration.focusModeEnabled,
            content: content, neighbours: neighbours, windowChoices: moveTargets(excluding: window),
            detach: configuration.detach, picker: contentPicker(for: target),
            contentMenu: content.flatMap { content in
                items.isEmpty ? nil : PaneMenuModel.ContentMenu(title: typeName(of: content) ?? "", items: items)
            })
    }
}

/// One action as a menu item: the model's title, enabled state and, in the menu bar, its shortcut.
struct PaneMenuEntry: View {
    let workspace: SplitKitWorkspace
    let model: PaneMenuModel
    let action: PaneMenuModel.Action
    /// The shortcuts to register; nil in the header's menus, where the menu bar owns them.
    var shortcuts: ShortcutMap?

    var body: some View {
        Button(model.title(action)) { Task { await model.run(action, in: workspace) } }
            .disabled(!model.isEnabled(action))
            .optionalKeyboardShortcut(action.shortcutCommand.flatMap { shortcuts?[$0] })
    }
}

/// The pane commands as menu items. `.header`: the title ▾ and right-click menu (content picker part, Add,
/// Split Right, Split Down, Detach, Move to Window, Close). `.menuBar`: the Pane menu (Focus Pane, splits,
/// focus and move by direction, Detach, the content's toolbar items, Close), with `ShortcutMap` shortcuts.
struct PaneMenu: View {
    enum Scope {
        case header
        case menuBar(ShortcutMap)
    }

    let workspace: SplitKitWorkspace
    let model: PaneMenuModel
    var scope: Scope = .header

    var body: some View {
        switch scope {
        case .header: header
        case let .menuBar(shortcuts): menuBar(shortcuts)
        }
    }

    @ViewBuilder private var header: some View {
        if model.isEmpty {
            // The empty pane's title is "Add Content": its menu lists the types directly.
            ContentPickerButtons(workspace: workspace, picker: model.picker)
        } else {
            Menu(ChromeText.add) { ContentPickerButtons(workspace: workspace, picker: model.picker) }
                .disabled(!model.canAdd)
        }
        if !model.isEmpty { entry(.replaceContent) }
        Divider()
        entry(.split(.right))
        entry(.split(.bottom))
        Divider()
        windowEntries()
        if model.windowKind == .detached { entry(.dockBack) }
        Divider()
        entry(.closePane)
    }

    /// Detach and the Move to Window ▸ submenu; neither exists with `Detach.disabled` (spec §9).
    @ViewBuilder private func windowEntries(_ shortcuts: ShortcutMap? = nil) -> some View {
        if model.offersDetach {
            entry(.detach, shortcuts)
            Menu(ChromeText.moveToWindow) {
                ForEach(model.windowChoices, id: \.id) { entry(.moveToWindow($0.id), shortcuts) }
            }
            .disabled(!model.canMoveToWindow)
        }
    }

    @ViewBuilder private func menuBar(_ shortcuts: ShortcutMap) -> some View {
        entry(.toggleFocusMode, shortcuts)
        Divider()
        entry(.split(.right), shortcuts)
        entry(.split(.bottom), shortcuts)
        Divider()
        Menu(ChromeText.moveFocus) {
            ForEach(FocusDirection.allCases, id: \.self) { entry(.focusNeighbour($0), shortcuts) }
        }
        Menu(ChromeText.moveToEdge) {
            ForEach(FocusDirection.allCases, id: \.self) { entry(.moveToEdge($0), shortcuts) }
        }
        Divider()
        entry(.replaceContent, shortcuts)
        windowEntries(shortcuts)
        if let contentMenu = model.contentMenu {
            Divider()
            Menu(contentMenu.title) { PaneToolbarMenuEntries(items: contentMenu.items, shortcuts: shortcuts) }
        }
        Divider()
        entry(.closePane, shortcuts)
    }

    private func entry(_ action: PaneMenuModel.Action, _ shortcuts: ShortcutMap? = nil) -> some View {
        PaneMenuEntry(workspace: workspace, model: model, action: action, shortcuts: shortcuts)
    }
}
