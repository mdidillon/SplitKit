import SwiftUI
import Testing
import SplitKitContent
import SplitKitModel
@testable import SplitKit

/// The two-stage close as the chrome shows it (spec §6.3, §7.5, §8): the pending state while `shouldClose()`
/// is awaited, declined and accepted closes, the window prompt and the placeholder confirmation.
@MainActor @Suite struct CloseUITests {
    let workspace: SplitKitWorkspace
    /// The main window, which a test may close.
    let main: WindowID

    init() throws {
        workspace = try makeWorkspace()
        main = workspace.mainLayout.id
    }

    func object(_ content: ContentID?) -> TestContent? { content.flatMap { workspace.store[$0] as? TestContent } }

    /// Adds a `TestContent` in a new pane to the right of `pane`, or into the empty window.
    @discardableResult
    func add(besides pane: PaneID? = nil) async throws -> (pane: PaneID, content: TestContent) {
        let before = Set(workspace.mainLeaves.map(\.pane))
        if let pane {
            await workspace.contentPicker(for: .besides(pane, .right)).choose(TestContent.type, in: workspace)
        } else {
            await workspace.contentPicker(for: .emptyWindow).choose(TestContent.type, in: workspace)
        }
        let leaf = try #require(workspace.mainLeaves.first { !before.contains($0.pane) })
        return (leaf.pane, try #require(object(leaf.content)))
    }

    func header(_ pane: PaneID) -> PaneHeaderConfiguration {
        workspace.headerConfiguration(for: pane, in: workspace.mainLayout,
                                      content: workspace.mainLeaves.first { $0.pane == pane }?.content)
    }

    func menu(_ pane: PaneID) -> PaneMenuModel {
        workspace.paneMenuModel(for: pane, content: workspace.mainLeaves.first { $0.pane == pane }?.content)
    }

    /// Starts closing `pane` and waits until its content is asked.
    func startClose(_ pane: PaneID, of content: TestContent) async throws -> Task<Void, any Error> {
        content.suspendsClose = true
        let task = Task { try await self.workspace.perform(.closePane(pane)) }
        try await waitUntil { content.isAskingToClose }
        return task
    }

    // MARK: Pending state

    @Test func whilePendingTheHeaderAndEveryTouchingActionAreDisabled() async throws {
        let (pane, content) = try await add()
        let other = try await add(besides: pane)
        let task = try await startClose(pane, of: content)

        #expect(workspace.runtime.pendingCloses == [pane])
        #expect(header(pane).isPendingClose && !header(other.pane).isPendingClose)
        let model = menu(pane)
        let actions: [PaneMenuModel.Action] = [.addContent(TestContent.type), .split(.right), .split(.bottom), .detach, .moveToWindow, .closePane]
        #expect(actions.allSatisfy { !model.isEnabled($0) })
        #expect(!model.picker.isEnabled)
        #expect(header(pane).controlsDisabled)

        content.answerClose(false)
        try await task.value
    }

    @Test func aWindowCloseMarksEveryPaneOfTheWindowPending() async throws {
        let (pane, _) = try await add()
        try workspace.commit(.beginCloseWindow(main))
        #expect(header(pane).isPendingClose)
        #expect(!workspace.contentPicker(for: .besides(pane, .right)).isEnabled)
        let canAdd = menu(pane).canAdd
        #expect(!canAdd)
    }

    // MARK: Declined and accepted

    @Test func declineLeavesSessionAndRuntimeByteIdentical() async throws {
        let (pane, content) = try await add()
        try await add(besides: pane)
        let session = try Migrator.encode(workspace.session)
        let runtime = workspace.runtime
        let task = try await startClose(pane, of: content)
        content.answerClose(false)
        try await task.value
        #expect(try Migrator.encode(workspace.session) == session)
        #expect(workspace.runtime == runtime)
        #expect(content.shouldCloseCalls == 1 && content.willReleaseCalls == 0)
        #expect(!header(pane).isPendingClose)
    }

    @Test func acceptRemovesThePaneAndReleasesOnce() async throws {
        let (pane, content) = try await add()
        let (kept, _) = try await add(besides: pane)
        let id = try #require(workspace.mainLeaves.first?.content)
        let task = try await startClose(pane, of: content)
        #expect(content.willReleaseCalls == 0, "released only after the answer")
        content.answerClose(true)
        try await task.value
        #expect(workspace.mainLeaves.map(\.pane) == [kept])
        #expect(content.shouldCloseCalls == 1 && content.willReleaseCalls == 1)
        #expect(workspace.store[id] == nil && workspace.record(id) == nil)
        #expect(workspace.runtime == WorkspaceRuntime())
    }

    @Test func aSecondCloseWhilePendingSurfacesPaneClosePendingWithoutChange() async throws {
        let (pane, content) = try await add()
        let task = try await startClose(pane, of: content)
        let session = try Migrator.encode(workspace.session)
        let runtime = workspace.runtime

        await #expect(throws: LayoutError.paneClosePending(pane)) { try await workspace.perform(.closePane(pane)) }
        await #expect(throws: LayoutError.paneClosePending(pane)) { try await workspace.perform(.split(pane, edge: .right)) }
        #expect(try Migrator.encode(workspace.session) == session)
        #expect(workspace.runtime == runtime)
        #expect(content.shouldCloseCalls == 1)

        content.answerClose(true)
        try await task.value
        #expect(content.willReleaseCalls == 1)
    }

    @Test func closingTheLastPaneLeavesTheEmptyStateAndTheWindowStays() async throws {
        let (pane, content) = try await add()
        await menu(pane).run(.closePane, in: workspace)
        #expect(workspace.mainLayout.root == nil)
        #expect(workspace.session.windows.count == 1 && workspace.session.contents.isEmpty)
        #expect(content.willReleaseCalls == 1)
        host(SplitKitView(workspace: workspace, window: main))
        // Add Content works again from the empty state.
        try await add()
        #expect(workspace.mainLeaves.count == 1)
    }

    // MARK: Unavailable placeholder

    @Test func placeholderCloseAsksSplitKitsOwnConfirmationAndReleasesNothing() async throws {
        let (pane, content) = try await add()
        let placeholder = try workspace.addPlaceholder(besides: pane)
        #expect(workspace.store[placeholder.content] == nil)

        let prompt = try await workspace.perform(.closePane(placeholder.pane), answering: true)
        #expect(prompt?.kind == .placeholder(typeName: "test.missing"))
        #expect(prompt?.title == "Close test.missing?" && prompt?.confirmTitle == "Close")
        #expect(workspace.mainLeaves.map(\.pane) == [pane])
        #expect(workspace.record(placeholder.content) == nil)
        #expect(content.shouldCloseCalls == 0 && content.willReleaseCalls == 0)
        #expect(workspace.store.objects.count == 1)
    }

    @Test func placeholderCloseCanBeDeclined() async throws {
        let (pane, content) = try await add()
        let placeholder = try workspace.addPlaceholder(besides: pane)
        let session = try Migrator.encode(workspace.session)
        let prompt = try await workspace.perform(.closePane(placeholder.pane), answering: false)
        #expect(prompt != nil)
        #expect(try Migrator.encode(workspace.session) == session)
        #expect(workspace.runtime == WorkspaceRuntime())
        #expect(content.shouldCloseCalls == 0 && content.willReleaseCalls == 0)
    }

    @Test func thePlaceholderIsPendingWhileItsPromptIsShown() async throws {
        let placeholder = try workspace.addPlaceholder()
        let task = Task { try await self.workspace.perform(.closePane(placeholder.pane)) }
        try await waitUntil { workspace.closePrompt != nil }
        #expect(header(placeholder.pane).isPendingClose)
        #expect(workspace.closePrompt?.window == main)
        let shown = try #require(workspace.closePrompt)
        workspace.answer(shown, confirmed: false)
        try await task.value
        #expect(workspace.closePrompt == nil)
        #expect(workspace.record(placeholder.content) != nil)
    }

    @Test func aStaleAnswerIsIgnored() async throws {
        let placeholder = try workspace.addPlaceholder()
        let task = Task { try await self.workspace.perform(.closePane(placeholder.pane)) }
        try await waitUntil { workspace.closePrompt != nil }
        let shown = try #require(workspace.closePrompt)
        workspace.answer(ClosePrompt(id: shown.id + 1, window: shown.window, kind: shown.kind), confirmed: true)
        #expect(workspace.closePrompt == shown)
        workspace.answer(shown, confirmed: false)
        try await task.value
    }

    // MARK: Window prompt (spec §7.5)

    @Test func windowCloseWithTwoContentsShowsOnePromptWithTheCount() async throws {
        let (a, first) = try await add()
        let (_, second) = try await add(besides: a)
        let prompt = try await workspace.perform(.closeWindow(main), answering: true)
        #expect(prompt?.kind == .window(panes: 2))
        #expect(prompt?.title == "Close window with 2 panes?")
        #expect(prompt?.confirmTitle == "Close All")
        #expect(prompt?.window == main)
        #expect(first.willReleaseCalls == 1 && second.willReleaseCalls == 1)
        #expect(workspace.session.windows.isEmpty)
    }

    @Test func cancellingTheWindowPromptClosesNothingAndAsksNobody() async throws {
        let (a, first) = try await add()
        let (_, second) = try await add(besides: a)
        let session = try Migrator.encode(workspace.session)
        let prompt = try await workspace.perform(.closeWindow(main), answering: false)
        #expect(prompt != nil)
        #expect(try Migrator.encode(workspace.session) == session)
        #expect(workspace.runtime == WorkspaceRuntime())
        #expect(first.shouldCloseCalls == 0 && second.shouldCloseCalls == 0)
        #expect(first.willReleaseCalls == 0 && second.willReleaseCalls == 0)
    }

    @Test func placeholdersCountTowardTheWindowPrompt() async throws {
        let (a, content) = try await add()
        try workspace.addPlaceholder(besides: a)
        try await workspace.perform(.split(a, edge: .bottom))
        #expect(workspace.closePromptKind(forWindow: main) == .window(panes: 2), "empty panes don't count")
        let prompt = try await workspace.perform(.closeWindow(main), answering: true)
        #expect(prompt?.kind == .window(panes: 2))
        #expect(content.shouldCloseCalls == 1 && content.willReleaseCalls == 1)
    }

    @Test func aWindowWithOneContentOrNoneNeedsNoWindowPrompt() async throws {
        #expect(workspace.closePromptKind(forWindow: main) == nil)
        let (pane, content) = try await add()
        try await workspace.perform(.split(pane, edge: .right))
        #expect(workspace.closePromptKind(forWindow: main) == nil)
        try await workspace.perform(.closeWindow(main))
        #expect(content.shouldCloseCalls == 1 && content.willReleaseCalls == 1)
        #expect(workspace.closePrompt == nil)
    }

    @Test func aWindowWhoseOnlyContentIsAPlaceholderUsesThePlaceholderConfirmation() async throws {
        try workspace.addPlaceholder()
        #expect(workspace.closePromptKind(forWindow: main) == .placeholder(typeName: "test.missing"))
    }

    @Test func aContentThatDeclinesAfterTheWindowPromptStillCancelsTheClose() async throws {
        let (a, first) = try await add()
        let (_, second) = try await add(besides: a)
        second.acceptsClose = false
        let session = try Migrator.encode(workspace.session)
        try await workspace.perform(.closeWindow(main), answering: true)
        #expect(try Migrator.encode(workspace.session) == session)
        #expect(first.willReleaseCalls == 0 && second.willReleaseCalls == 0)
        #expect(workspace.runtime == WorkspaceRuntime())
    }
}
