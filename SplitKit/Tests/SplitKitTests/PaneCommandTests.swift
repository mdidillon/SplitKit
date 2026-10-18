import AppKit
import SwiftUI
import Testing
import SplitKitContent
import SplitKitModel
@testable import SplitKit

/// The command model behind the pane menu and the menu bar (spec §7.3–§7.5): dynamic close labels, focus
/// mode, enabled states, and the content's toolbar items under Pane ▸ ‹Content name› ▸.
@MainActor @Suite struct PaneCommandTests {
    let workspace: SplitKitWorkspace
    let main: WindowID

    init() throws {
        workspace = try makeWorkspace()
        main = workspace.mainLayout.id
    }

    var model: PaneMenuModel { workspace.activePaneMenuModel(in: main) }

    func object(_ content: ContentID?) -> TestContent? { content.flatMap { workspace.store[$0] as? TestContent } }

    /// Detaches the second of two panes into a new detached window and makes its pane active there.
    func detachedWindow() async throws -> (window: WindowID, pane: PaneID) {
        await workspace.addContentByKeyboard(in: main)
        await workspace.addContentByKeyboard(in: main)
        let second = try #require(workspace.mainLeaves.last?.pane)
        let window = WindowID(raw: UUID())
        try workspace.commit(.detach(second, to: window, placement: .defaultMainWindow))
        let pane = try #require(workspace.windowLayout(window)?.root?.leaves.first?.pane)
        try await workspace.perform(.setActive(pane, in: window))
        return (window, pane)
    }

    // MARK: Close labels and semantics (§7.5)

    @Test func noKeyWindowDisablesEverything() {
        let none = workspace.activePaneMenuModel(in: nil)
        #expect(none.title(.closePane) == "Close Pane")
        #expect(none.pane == nil && !none.canAdd)
        let actions: [PaneMenuModel.Action] = [.chooseContent, .split(.right), .toggleFocusMode, .focusNeighbour(.left),
                                               .moveToEdge(.left), .detach, .closePane, .closeWindow]
        #expect(actions.allSatisfy { !none.isEnabled($0) })
        #expect(!workspace.activePaneMenuModel(in: WindowID(raw: UUID())).isEnabled(.closePane))
    }

    @Test func inAnEmptyMainWindowCommandWClosesTheWindow() async throws {
        #expect(model.title(.closePane) == "Close Window")
        #expect(model.isEnabled(.closePane) && model.isEnabled(.closeWindow))
        #expect(model.isEnabled(.chooseContent), "Add Content… works in the empty window")
        #expect(!model.isEnabled(.split(.right)) && !model.isEnabled(.toggleFocusMode))
        await workspace.key(.closePane, in: main)
        #expect(workspace.session.windows.isEmpty, "the window is gone; the app stays alive (zero windows is valid)")
    }

    @Test func theLastPaneOfTheMainWindowReadsClosePaneAndLeavesTheEmptyState() async throws {
        await workspace.addContentByKeyboard(in: main)
        #expect(model.title(.closePane) == "Close Pane")
        await workspace.key(.closePane, in: main)
        #expect(workspace.session.windows.map(\.id) == [main])
        #expect(workspace.mainLayout.root == nil)
        #expect(model.title(.closePane) == "Close Window", "now ⌘W would close the empty window")
    }

    @Test func aMainWindowWithSeveralPanesReadsClosePane() async throws {
        await workspace.addContentByKeyboard(in: main)
        await workspace.addContentByKeyboard(in: main)
        #expect(model.title(.closePane) == "Close Pane")
        await workspace.key(.closePane, in: main)
        #expect(workspace.mainLeaves.count == 1)
    }

    @Test func theOnlyPaneOfADetachedWindowReadsClosePaneAndWindowAndClosesBoth() async throws {
        let (window, _) = try await detachedWindow()
        let detached = workspace.activePaneMenuModel(in: window)
        #expect(detached.title(.closePane) == "Close Pane and Window")
        #expect(detached.title(.closeWindow) == "Close Window")
        await workspace.key(.closePane, in: window)
        #expect(workspace.windowLayout(window) == nil)
        #expect(workspace.session.windows.map(\.id) == [main])
    }

    @Test func aDetachedWindowWithTwoPanesReadsClosePane() async throws {
        let (window, pane) = try await detachedWindow()
        try await workspace.perform(.split(pane, edge: .right))
        #expect(workspace.activePaneMenuModel(in: window).title(.closePane) == "Close Pane")
    }

    @Test func closeWindowAsksOncePerWindowAndCancelClosesNothing() async throws {
        await workspace.addContentByKeyboard(in: main)
        await workspace.addContentByKeyboard(in: main)
        let task = Task { await self.model.run(.closeWindow, in: self.workspace) }
        try await waitUntil { workspace.closePrompt != nil }
        let prompt = try #require(workspace.closePrompt)
        #expect(prompt.title == "Close window with 2 panes?")
        workspace.answer(prompt, confirmed: false)
        await task.value
        #expect(workspace.mainLeaves.count == 2)
    }

    @Test func detachNeedsAPaneWithContent() async throws {
        #expect(!model.isEnabled(.detach), "no pane in the empty window")
        await workspace.addContentByKeyboard(in: main)
        #expect(model.isEnabled(.detach) && model.isEnabled(.replaceContent))
        try await workspace.perform(.split(try #require(workspace.mainLeaves.first?.pane), edge: .right))
        try await workspace.perform(.setActive(workspace.mainLeaves[1].pane, in: main))
        #expect(!model.isEnabled(.detach) && !model.isEnabled(.replaceContent), "an empty pane has nothing to detach or replace")
        let before = try Migrator.encode(workspace.session)
        await workspace.key(.detach, in: main)
        #expect(try Migrator.encode(workspace.session) == before)
    }

    @Test func aPendingCloseDisablesTheMenuBarActions() async throws {
        await workspace.addContentByKeyboard(in: main)
        await workspace.addContentByKeyboard(in: main)
        try await workspace.perform(.setActive(workspace.mainLeaves[0].pane, in: main))
        _ = try workspace.commit(.beginClose(workspace.mainLeaves[0].pane))
        let pending = model
        #expect(pending.isPending)
        #expect(!pending.isEnabled(.closePane) && !pending.isEnabled(.split(.right)) && !pending.isEnabled(.toggleFocusMode))
        #expect(!pending.isEnabled(.focusNeighbour(.right)) && !pending.isEnabled(.moveToEdge(.right)))
        #expect(!pending.isEnabled(.chooseContent))
    }

    @Test func aNeighbourThatIsClosingCannotBeFocused() async throws {
        await workspace.addContentByKeyboard(in: main)
        await workspace.addContentByKeyboard(in: main)
        try await workspace.perform(.setActive(workspace.mainLeaves[0].pane, in: main))
        #expect(model.isEnabled(.focusNeighbour(.right)))
        _ = try workspace.commit(.beginClose(workspace.mainLeaves[1].pane))
        #expect(!model.isEnabled(.focusNeighbour(.right)))
    }

    // MARK: Focus mode (§7.3)

    @Test func focusPaneEntersAndLeavesFocusModeAndMakesThePaneActive() async throws {
        await workspace.addContentByKeyboard(in: main)
        await workspace.addContentByKeyboard(in: main)
        let first = workspace.mainLeaves[0].pane
        try await workspace.perform(.setActive(first, in: main))
        await workspace.key(.toggleFocusMode, in: main)     // ⇧⌘↩
        #expect(workspace.mainLayout.focusModePane == first && workspace.mainLayout.activePane == first)
        #expect(workspace.mainLeaves.count == 2, "the tree is untouched")
        await workspace.key(.toggleFocusMode, in: main)
        #expect(workspace.mainLayout.focusModePane == nil)
    }

    @Test func entersFocusModeFromTheHeaderToggleOfAnotherPaneAndSetsItActive() async throws {
        await workspace.addContentByKeyboard(in: main)
        await workspace.addContentByKeyboard(in: main)
        let (first, second) = (workspace.mainLeaves[0].pane, workspace.mainLeaves[1].pane)
        try await workspace.perform(.setActive(first, in: main))
        try await workspace.perform(.toggleFocusMode(second))
        #expect(workspace.mainLayout.focusModePane == second && workspace.mainLayout.activePane == second)
    }

    @Test func escLeavesFocusModeOnlyInFocusMode() async throws {
        await workspace.addContentByKeyboard(in: main)
        #expect(workspace.exitFocusModeAction(in: main) == nil, "no handler outside focus mode: Esc stays with others")
        await workspace.key(.toggleFocusMode, in: main)
        let action = try #require(workspace.exitFocusModeAction(in: main))
        action()
        try await waitUntil { workspace.mainLayout.focusModePane == nil }
        #expect(workspace.mainLayout.activePane == workspace.mainLeaves.first?.pane)
        #expect(workspace.exitFocusModeAction(in: main) == nil)
    }

    @Test func focusModeIsOffWhenDisabledInTheConfiguration() async throws {
        let workspace = try makeWorkspace(focusModeEnabled: false)
        await workspace.addContentByKeyboard(in: workspace.mainLayout.id)
        #expect(!workspace.activePaneMenuModel(in: workspace.mainLayout.id).isEnabled(.toggleFocusMode))
    }

    @Test func movingFocusIsOffWhileAPaneFillsTheWindow() async throws {
        await workspace.addContentByKeyboard(in: main)
        await workspace.addContentByKeyboard(in: main)
        try await workspace.perform(.setActive(workspace.mainLeaves[0].pane, in: main))
        #expect(model.isEnabled(.focusNeighbour(.right)))
        await workspace.key(.toggleFocusMode, in: main)
        #expect(!model.isEnabled(.focusNeighbour(.right)))
    }

    @Test(arguments: ["split", "add", "close", "move", "insert"])
    func structuralChangesClearFocusMode(_ change: String) async throws {
        await workspace.addContentByKeyboard(in: main)
        await workspace.addContentByKeyboard(in: main)
        let (first, second) = (workspace.mainLeaves[0].pane, workspace.mainLeaves[1].pane)
        try await workspace.perform(.setActive(first, in: main))
        await workspace.key(.toggleFocusMode, in: main)
        #expect(workspace.mainLayout.focusModePane == first)
        switch change {
        case "split": try await workspace.perform(.split(second, edge: .bottom))
        case "add": try await workspace.addContent(TestContent.type, besides: second, edge: .right)
        case "close": try await workspace.perform(.closePane(second))
        case "move": try await workspace.perform(.move(try #require(workspace.mainLeaves[1].content), to: first, edge: .top))
        default: try workspace.commit(.insert(nil, at: second, edge: .left, in: main))
        }
        #expect(workspace.mainLayout.focusModePane == nil, "\(change) leaves focus mode")
    }

    @Test func closingTheFocusedPaneClearsBothFieldsAndActivatesTheNearestSibling() async throws {
        await workspace.addContentByKeyboard(in: main)
        await workspace.addContentByKeyboard(in: main)
        let (first, second) = (workspace.mainLeaves[0].pane, workspace.mainLeaves[1].pane)
        try await workspace.perform(.setActive(first, in: main))
        await workspace.key(.toggleFocusMode, in: main)
        await workspace.key(.closePane, in: main)
        #expect(workspace.mainLayout.focusModePane == nil)
        #expect(workspace.mainLayout.activePane == second)
        #expect(workspace.mainLeaves.map(\.pane) == [second])
    }

    // MARK: Content submenu (§7.4)

    func toolbarItems() -> [PaneToolbarItem] {
        [
            PaneToolbarItem(id: "reset", title: "Reset Camera", systemImage: "camera", kind: .button(action: {}),
                            priority: .high, keyboardShortcut: KeyboardShortcut("0")),
            PaneToolbarItem(id: "grid", title: "Grid", kind: .toggle(isOn: .constant(true)), priority: .low),
            PaneToolbarItem(id: "mode", title: "Mode", kind: .menu(items: [
                PaneToolbarItem(id: "wire", title: "Wireframe", kind: .button(action: {})),
            ])),
            PaneToolbarItem(id: "custom", title: "Slider", kind: .custom(minWidth: 40, view: AnyView(Color.clear)), fallbackAction: {}),
        ]
    }

    @Test func everyToolbarItemAppearsUnderTheContentSubmenu() async throws {
        await workspace.addContentByKeyboard(in: main)
        let content = try #require(workspace.mainLeaves.first?.content)
        object(content)?.toolbarItems = toolbarItems()
        let menu = try #require(model.contentMenu)
        #expect(menu.title == "Test")
        #expect(menu.items.map(\.id) == ["reset", "grid", "mode", "custom"], "declaration order, including low priority")
        if case let .menu(nested) = menu.items[2].kind { #expect(nested.map(\.id) == ["wire"]) } else { Issue.record("menu item lost") }
        #expect(menu.items[3].isEnabledInOverflow, "a custom item acts through its fallback")
    }

    @Test func theContentSubmenuFollowsTheActivePaneAndIsAbsentWithoutItems() async throws {
        await workspace.addContentByKeyboard(in: main)
        await workspace.addContentByKeyboard(in: main)
        let (first, second) = (workspace.mainLeaves[0], workspace.mainLeaves[1])
        object(first.content)?.toolbarItems = toolbarItems()
        try await workspace.perform(.setActive(first.pane, in: main))
        #expect(model.contentMenu?.items.count == 4)
        try await workspace.perform(.setActive(second.pane, in: main))
        #expect(model.contentMenu == nil, "ImageViewer-style content has no items")
    }

    @Test func theMenuBarAndTheHeaderRenderTheSameModel() async throws {
        await workspace.addContentByKeyboard(in: main)
        let content = try #require(workspace.mainLeaves.first?.content)
        object(content)?.toolbarItems = toolbarItems()
        host(PaneMenu(workspace: workspace, model: model, scope: .menuBar(.default)))
        host(PaneMenu(workspace: workspace, model: model))
        host(PaneMenuEntry(workspace: workspace, model: model, action: .closePane, shortcuts: .default))
        let pane = try #require(workspace.mainLeaves.first?.pane)
        let header = workspace.paneMenuModel(for: pane, content: content)
        for action in [PaneMenuModel.Action.split(.right), .split(.bottom), .closePane, .detach, .toggleFocusMode] {
            #expect(header.title(action) == model.title(action))
            #expect(header.isEnabled(action) == model.isEnabled(action))
        }
    }

    @Test func everyActionHasItsShortcutCommand() {
        let mapped: [(PaneMenuModel.Action, ShortcutCommand)] = [
            (.chooseContent, .addContent), (.split(.right), .splitRight), (.split(.bottom), .splitDown),
            (.focusNeighbour(.left), .focusLeft), (.focusNeighbour(.right), .focusRight),
            (.focusNeighbour(.up), .focusUp), (.focusNeighbour(.down), .focusDown),
            (.moveToEdge(.left), .moveLeft), (.moveToEdge(.right), .moveRight),
            (.moveToEdge(.up), .moveUp), (.moveToEdge(.down), .moveDown),
            (.toggleFocusMode, .focusPane), (.detach, .detach), (.closePane, .closePane), (.closeWindow, .closeWindow),
        ]
        #expect(Set(mapped.map(\.1)) == Set(ShortcutCommand.allCases), "no command without an action")
        for (action, command) in mapped { #expect(action.shortcutCommand == command) }
        #expect(PaneMenuModel.Action.split(.left).shortcutCommand == nil)
    }
}
