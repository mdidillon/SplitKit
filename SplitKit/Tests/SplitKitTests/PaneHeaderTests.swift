import SwiftUI
import Testing
import SplitKitContent
import SplitKitModel
@testable import SplitKit

/// The header resolved from the workspace (spec §7.1), the pane menu's actions (§7.1, §6.3) and the header
/// rendered through the style at several widths.
@MainActor @Suite struct PaneHeaderTests {
    let workspace: SplitKitWorkspace

    init() throws {
        workspace = try makeWorkspace()
    }

    func configuration(_ pane: PaneID) -> PaneHeaderConfiguration {
        let content = workspace.mainLeaves.first { $0.pane == pane }?.content
        return workspace.headerConfiguration(for: pane, in: workspace.mainLayout, content: content)
    }

    func menu(_ pane: PaneID) -> PaneMenuModel {
        workspace.paneMenuModel(for: pane, content: workspace.mainLeaves.first { $0.pane == pane }?.content)
    }

    /// Adds a `TestContent` into the empty window and returns its pane.
    func addFirst() async throws -> PaneID {
        try await workspace.addContent(TestContent.type, url: nil, into: nil)
        return try #require(workspace.mainLeaves.first?.pane)
    }

    // MARK: Header configuration

    @Test func emptyPaneShowsAddContentWithoutIcon() async throws {
        let pane = try await addFirst()
        try await workspace.perform(.split(pane, edge: .right))
        let empty = try #require(workspace.mainLeaves.first { $0.content == nil }?.pane)
        let header = configuration(empty)
        #expect(header.title == "Add Content")
        #expect(header.systemImage == nil)
        #expect(header.isEmpty)
    }

    @Test func contentPaneTakesTitleFromTheObjectAndIconFromTheRegistry() async throws {
        let pane = try await addFirst()
        let content = try #require(workspace.mainLeaves.first?.content)
        let header = configuration(pane)
        #expect(header.title == workspace.store[content]?.title)
        #expect(header.systemImage == TestContent.systemImage)
        #expect(!header.isEmpty)
        #expect(header.showsFocusToggle)
    }

    @Test func stateFlagsFollowTheWorkspace() async throws {
        let pane = try await addFirst()
        try await workspace.perform(.split(pane, edge: .right))
        let other = try #require(workspace.mainLeaves.first { $0.pane != pane }?.pane)

        try await workspace.perform(.setActive(pane, in: workspace.mainLayout.id))
        #expect(configuration(pane).isActive)
        #expect(!configuration(other).isActive)
        #expect(!configuration(pane).isFocusMode)

        try await workspace.perform(.toggleFocusMode(pane))
        #expect(configuration(pane).isFocusMode)
        #expect(!configuration(other).isFocusMode)

        _ = try workspace.commit(.beginClose(pane))
        #expect(configuration(pane).isPendingClose)
        #expect(!configuration(other).isPendingClose)
    }

    @Test func focusToggleFollowsTheConfiguration() async throws {
        let workspace = try makeWorkspace(focusModeEnabled: false)
        try await workspace.addContent(TestContent.type, url: nil, into: nil)
        let pane = try #require(workspace.mainLeaves.first?.pane)
        let header = workspace.headerConfiguration(for: pane, in: workspace.mainLayout, content: workspace.mainLeaves.first?.content)
        #expect(!header.showsFocusToggle)
    }

    @Test func headerButtonsRunWorkspaceCommands() async throws {
        let pane = try await addFirst()
        configuration(pane).toggleFocusMode()
        try await waitUntil { workspace.mainLayout.focusModePane == pane }
        configuration(pane).close()
        try await waitUntil { workspace.mainLeaves.isEmpty }
    }

    // MARK: Pane menu

    @Test func menuListsRegisteredTypesInRegistrationOrder() async throws {
        let pane = try await addFirst()
        #expect(menu(pane).types.map(\.type) == [TestContent.type, FailingContent.type])
        #expect(menu(pane).types.first?.displayName == "Test")
        #expect(menu(pane).types.first?.systemImage == "square")
    }

    @Test func addOnAnOccupiedPaneCreatesANewContentInANewPane() async throws {
        let pane = try await addFirst()
        let first = try #require(workspace.mainLeaves.first?.content)
        await menu(pane).run(.addContent(TestContent.type), in: workspace)
        #expect(workspace.mainLeaves.count == 2)
        #expect(workspace.mainLeaves.first?.pane == pane && workspace.mainLeaves.first?.content == first)
        let added = try #require(workspace.mainLeaves.last?.content)
        #expect(added != first && workspace.store[added] is TestContent)
    }

    @Test func addOnAnEmptyPaneFillsIt() async throws {
        let pane = try await addFirst()
        try await workspace.perform(.split(pane, edge: .right))
        let empty = try #require(workspace.mainLeaves.first { $0.content == nil }?.pane)
        await menu(empty).run(.addContent(TestContent.type), in: workspace)
        #expect(workspace.mainLeaves.count == 2)
        #expect(workspace.mainLeaves.allSatisfy { $0.content != nil })
    }

    @Test func splitRightAndDownAddEmptyPanes() async throws {
        let pane = try await addFirst()
        await menu(pane).run(.split(.right), in: workspace)
        #expect(workspace.mainLeaves.count == 2)
        await menu(pane).run(.split(.bottom), in: workspace)
        #expect(workspace.mainLeaves.count == 3)
        #expect(workspace.mainLeaves.filter { $0.content == nil }.count == 2)
    }

    @Test func closeRemovesThePane() async throws {
        let pane = try await addFirst()
        await menu(pane).run(.close, in: workspace)
        #expect(workspace.mainLeaves.isEmpty)
    }

    @Test func detachAndMoveToWindowAreDisabledUntilPhase3() async throws {
        let pane = try await addFirst()
        let model = menu(pane)
        let before = try Migrator.encode(workspace.session)
        #expect(!model.isEnabled(.detach) && !model.isEnabled(.moveToWindow))
        await model.run(.detach, in: workspace)
        await model.run(.moveToWindow, in: workspace)
        #expect(try Migrator.encode(workspace.session) == before)
    }

    @Test func aPendingCloseDisablesEveryActionAndChangesNothing() async throws {
        let pane = try await addFirst()
        _ = try workspace.commit(.beginClose(pane))
        let model = menu(pane)
        #expect(model.isPending)
        let actions: [PaneMenuModel.Action] = [.addContent(TestContent.type), .split(.right), .split(.bottom), .detach, .moveToWindow, .close]
        #expect(actions.allSatisfy { !model.isEnabled($0) })
        let session = try Migrator.encode(workspace.session)
        let runtime = workspace.runtime
        for action in actions { await model.run(action, in: workspace) }
        #expect(try Migrator.encode(workspace.session) == session)
        #expect(workspace.runtime == runtime)
    }

    @Test func addIsDisabledWithoutRegisteredTypes() throws {
        let empty = SplitKitWorkspace(registry: ContentRegistry(), configuration: SplitKitConfiguration(persistence: .disabled),
                                      ids: SeededIDGenerator(seed: 1))
        _ = empty.restoreOrOpenDefault()
        let model = empty.paneMenuModel(for: PaneID(raw: UUID()), content: nil)
        #expect(model.types.isEmpty)
        #expect(!model.canAdd)
    }

    // MARK: Rendering

    @Test(arguments: [900, 320, 120, 60] as [CGFloat])
    func headerRendersAtEveryWidth(width: CGFloat) async throws {
        let pane = try await addFirst()
        let content = try #require(workspace.mainLeaves.first?.content)
        let object = try #require(workspace.store[content] as? TestContent)
        object.toolbarItems = [
            PaneToolbarItem(id: "low", title: "Low", systemImage: "star", kind: .button(action: {}), priority: .low),
            PaneToolbarItem(id: "high", title: "Reset Camera", systemImage: "camera", kind: .button(action: {}),
                            priority: .high, keyboardShortcut: KeyboardShortcut("0")),
            PaneToolbarItem(id: "custom", title: "Custom", kind: .custom(minWidth: 40, view: AnyView(Color.clear)),
                            fallbackAction: {}),
        ]
        let view = SplitKitView(workspace: workspace, window: workspace.mainLayout.id)
        let hosting = host(view, size: CGSize(width: width, height: 240))
        #expect(hosting.fittingSize.width >= 0)
        #expect(configuration(pane).title == object.title)
    }
}

/// Polls `condition` on the main actor for up to a second; the chrome's `send` runs commands in a `Task`.
@MainActor
func waitUntil(_ condition: @MainActor () -> Bool) async throws {
    for _ in 0..<100 where !condition() { try await Task.sleep(for: .milliseconds(10)) }
    #expect(condition(), "condition not reached")
}
