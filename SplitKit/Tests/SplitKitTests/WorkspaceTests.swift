import AppKit
import Foundation
import SwiftUI
import Testing
import SplitKitContent
import SplitKitModel
@testable import SplitKit

/// `SplitKitWorkspace` (§5, §6.2–§6.5): default layout, commands through `SessionEngine.apply`, content
/// creation after a successful transaction, release with `willRelease()`, and failures that change nothing.
@MainActor @Suite struct WorkspaceTests {
    let workspace: SplitKitWorkspace
    let main: WindowID

    init() throws {
        workspace = try makeWorkspace()
        main = try #require(workspace.mainWindow)
    }

    var window: WindowLayout { workspace.windowLayout(main)! }
    var leaves: [(pane: PaneID, content: ContentID?)] { window.root?.leaves ?? [] }

    func content(in pane: PaneID) -> ContentID? { leaves.first { $0.pane == pane }?.content }
    func object(_ id: ContentID?) -> TestContent? { id.flatMap { workspace.store[$0] as? TestContent } }

    /// Adds a `TestContent` into the empty window and returns its pane.
    func addFirst() async throws -> PaneID {
        try await workspace.addContent(TestContent.type, url: nil, into: nil)
        return try #require(leaves.first?.pane)
    }

    /// Splits `pane` at `edge` and fills the new empty pane with a `TestContent`; returns the new pane.
    func addNext(to pane: PaneID, edge: DropEdge) async throws -> PaneID {
        let before = Set(leaves.map(\.pane))
        try await workspace.perform(.split(pane, edge: edge))
        let new = try #require(leaves.first { !before.contains($0.pane) }?.pane)
        try await workspace.addContent(TestContent.type, url: nil, into: new)
        return new
    }

    /// Runs `operation`, expects it to throw, and expects session bytes, runtime and live objects unchanged.
    func expectNoChange(_ operation: () async throws -> Void) async throws -> (any Error)? {
        let bytes = try Migrator.encode(workspace.session)
        let runtime = workspace.runtime
        let objects = workspace.store.objects.mapValues(ObjectIdentifier.init)
        var thrown: (any Error)?
        do { try await operation() } catch { thrown = error }
        #expect(thrown != nil, "expected the operation to fail")
        #expect(try Migrator.encode(workspace.session) == bytes)
        #expect(workspace.runtime == runtime)
        #expect(workspace.store.objects.mapValues(ObjectIdentifier.init) == objects)
        return thrown
    }

    // MARK: Default layout

    @Test func defaultLayoutIsOneEmptyMainWindow() throws {
        #expect(workspace.session.windows.count == 1)
        #expect(window.kind == .main)
        #expect(window.root == nil)
        #expect(window.placement == .defaultMainWindow)
        #expect(workspace.session.contents.isEmpty)
        #expect(workspace.runtime == WorkspaceRuntime())
    }

    @Test func restoreReportsThePersistenceSource() throws {
        #expect(try makeWorkspace(persistence: .disabled).restoreOrOpenDefault() == RestoreReport(source: .persistenceDisabled))
        let file = URL(filePath: "/nonexistent/session.json")
        #expect(try makeWorkspace(persistence: .file(file)).restoreOrOpenDefault() == RestoreReport(source: .noFile))
    }

    @Test func reopeningTheDefaultLayoutReleasesLiveObjects() async throws {
        let pane = try await addFirst()
        let first = try #require(object(content(in: pane)))
        _ = workspace.restoreOrOpenDefault()
        #expect(first.willReleaseCalls == 1)
        #expect(workspace.store.objects.isEmpty)
        #expect(workspace.session.windows.count == 1)
    }

    // MARK: Adding content (§6.2, §6.5)

    @Test func addContentIntoTheEmptyWindow() async throws {
        let pane = try await addFirst()
        let id = try #require(content(in: pane))
        #expect(window.activePane == pane)
        #expect(workspace.session.contents == [ContentRecord(id: id, type: TestContent.type, stateVersion: 2, state: Data())])
        #expect(object(id)?.id == id)
    }

    @Test func addContentIntoAnEmptyPane() async throws {
        let first = try await addFirst()
        try await workspace.perform(.split(first, edge: .right))
        let empty = try #require(leaves.last?.pane)
        #expect(content(in: empty) == nil)
        try await workspace.addContent(TestContent.type, url: nil, into: empty)
        #expect(leaves.map(\.pane) == [first, empty])
        #expect(object(content(in: empty)) != nil)
        #expect(workspace.session.contents.count == 2)
    }

    @Test func addContentOfAnUnknownTypeChangesNothing() async throws {
        let error = try await expectNoChange {
            try await workspace.addContent(ContentType(raw: "test.unknown"), url: nil, into: nil)
        }
        guard case .unknownType(let type) = error as? RegistryError else { Issue.record("wrong error \(String(describing: error))"); return }
        #expect(type.raw == "test.unknown")
    }

    @Test func failedCreationDiscardsTheTransaction() async throws {
        let error = try await expectNoChange {
            try await workspace.addContent(FailingContent.type, url: nil, into: nil)
        }
        guard case .creationFailed(let type, _) = error as? RegistryError else { Issue.record("wrong error \(String(describing: error))"); return }
        #expect(type == FailingContent.type)
        #expect(window.root == nil)
    }

    @Test func addContentPassesTheURLIntoInit() async throws {
        let url = URL(filePath: "/tmp/a.test")
        try await workspace.addContent(TestContent.type, url: url, into: nil)
        #expect(object(leaves.first?.content)?.receivedURL == url)
    }

    @Test func aURLRejectedByInitChangesNothing() async throws {
        try workspace.registry.register(PickyContent.self)
        let url = URL(filePath: "/tmp/a.test")
        let intoWindow = try await expectNoChange {
            try await workspace.addContent(PickyContent.type, url: url, into: nil)
        }
        guard case .creationFailed(let type, .unsupportedFile(let rejected, _)) = intoWindow as? RegistryError else {
            Issue.record("wrong error \(String(describing: intoWindow))"); return
        }
        #expect(type == PickyContent.type)
        #expect(rejected == url)
        #expect(window.root == nil)
        #expect(workspace.session.contents.isEmpty)

        let first = try await addFirst()
        try await workspace.perform(.split(first, edge: .right))
        let empty = try #require(leaves.last?.pane)
        _ = try await expectNoChange {
            try await workspace.addContent(PickyContent.type, url: url, into: empty)
        }
        #expect(leaves.map(\.pane) == [first, empty])
        #expect(content(in: empty) == nil)
        #expect(workspace.session.contents.count == 1)

        try await workspace.addContent(PickyContent.type, url: nil, into: empty)
        #expect(content(in: empty) != nil)
    }

    @Test func addContentIntoAnOccupiedPaneCreatesNoObject() async throws {
        let pane = try await addFirst()
        let error = try await expectNoChange {
            try await workspace.addContent(TestContent.type, url: nil, into: pane)
        }
        guard case .creationFailed(_, .other(let reason)) = error as? RegistryError else { Issue.record("wrong error \(String(describing: error))"); return }
        #expect(reason.contains("centerInsertIntoOccupiedPane"))
    }

    // MARK: Structure through perform (§6.1.9 worked example)

    @Test func splitRightAndDownBuildTheWorkedExample() async throws {
        let a = try await addFirst()
        let b = try await addNext(to: a, edge: .right)
        let c = try await addNext(to: b, edge: .bottom)
        guard case let .split(_, .horizontal, children, fractions) = window.root,
              case let .split(_, .vertical, nested, nestedFractions) = children[1] else {
            Issue.record("expected H[A, V[B, C]], got \(String(describing: window.root))"); return
        }
        #expect(fractions == [0.5, 0.5])
        #expect(nestedFractions == [0.5, 0.5])
        #expect(nested.map(\.leaves.first?.pane) == [b, c])

        let d = try await addNext(to: a, edge: .right)
        guard case let .split(_, .horizontal, _, after) = window.root else { Issue.record("lost the root split"); return }
        #expect(after == [0.25, 0.25, 0.5])
        #expect(leaves.map(\.pane) == [a, d, b, c])
        #expect(workspace.session.contents.count == 4)
        #expect(workspace.store.objects.count == 4)
    }

    @Test func swapKeepsBothObjects() async throws {
        let a = try await addFirst()
        let b = try await addNext(to: a, edge: .right)
        let contentA = try #require(content(in: a)), contentB = try #require(content(in: b))
        let objectA = try #require(object(contentA)), objectB = try #require(object(contentB))
        try await workspace.perform(.move(contentA, to: b, edge: .center))
        #expect(content(in: a) == contentB)
        #expect(content(in: b) == contentA)
        #expect(object(contentA) === objectA)
        #expect(object(contentB) === objectB)
        #expect(objectA.willReleaseCalls == 0 && objectB.willReleaseCalls == 0)
    }

    @Test func edgeMoveKeepsTheObjectAndCollapsesTheSource() async throws {
        let a = try await addFirst()
        let b = try await addNext(to: a, edge: .right)
        let c = try await addNext(to: b, edge: .bottom)
        let contentC = try #require(content(in: c))
        let objectC = try #require(object(contentC))
        try await workspace.perform(.move(contentC, to: a, edge: .left))
        #expect(leaves.map(\.content) == [contentC, content(in: a), content(in: b)])
        #expect(!leaves.map(\.pane).contains(c))
        #expect(object(contentC) === objectC)
        guard case let .split(_, .horizontal, children, _) = window.root else { Issue.record("expected one H split"); return }
        #expect(children.count == 3)
    }

    @Test func selfDropIsANoOp() async throws {
        let a = try await addFirst()
        let id = try #require(content(in: a))
        let bytes = try Migrator.encode(workspace.session)
        try await workspace.perform(.move(id, to: a, edge: .right))
        #expect(try Migrator.encode(workspace.session) == bytes)
    }

    @Test func resizeAndReorder() async throws {
        let a = try await addFirst()
        let b = try await addNext(to: a, edge: .right)
        guard case let .split(split, _, _, _) = window.root else { Issue.record("expected a split"); return }
        try await workspace.perform(.resize(splitID: split, fractions: [0.3, 0.7]))
        guard case let .split(_, _, _, resized) = window.root else { return }
        #expect(resized == [0.3, 0.7])
        try await workspace.perform(.reorder(splitID: split, from: 0, to: 1))
        guard case let .split(_, _, _, reordered) = window.root else { return }
        #expect(reordered == [0.7, 0.3])
        #expect(leaves.map(\.pane) == [b, a])
    }

    @Test func aDragResultIsStoredWithoutNormalisation() async throws {
        let a = try await addFirst()
        _ = try await addNext(to: a, edge: .right)
        guard case let .split(split, axis, _, fractions) = window.root else { Issue.record("expected a split"); return }
        let divider = SplitGeometry.Divider(split: split, axis: axis, index: 0, fractions: fractions,
                                            sizes: [333, 333], minimums: [100, 100], hitArea: .zero)
        let dragged = SplitGeometry.dragFractions(divider, translation: 77)
        let result = try workspace.commit(.resize(splitID: split, fractions: dragged))
        #expect(result.normalizations.isEmpty)
        guard case let .split(_, _, _, stored) = window.root else { return }
        #expect(stored == dragged)
    }

    // MARK: Focus (§7.3)

    @Test func clickSetsTheActivePane() async throws {
        let a = try await addFirst()
        let b = try await addNext(to: a, edge: .right)
        try await workspace.perform(.setActive(b, in: main))
        #expect(window.activePane == b)
        try await workspace.perform(.setActive(nil, in: main))
        #expect(window.activePane == nil)
    }

    @Test func toggleFocusModeEntersAndLeaves() async throws {
        let a = try await addFirst()
        let b = try await addNext(to: a, edge: .right)
        try await workspace.perform(.toggleFocusMode(b))
        #expect(window.focusModePane == b)
        #expect(window.activePane == b)
        try await workspace.perform(.toggleFocusMode(b))
        #expect(window.focusModePane == nil)
        try await workspace.perform(.setFocusMode(a, in: main))
        #expect(window.focusModePane == a)
        try await workspace.perform(.split(a, edge: .bottom))
        #expect(window.focusModePane == nil, "a structural transaction clears focus mode")
    }

    @Test func toggleFocusModeDoesNothingWhenDisabled() async throws {
        let registry = ContentRegistry()
        try registry.register(TestContent.self)
        let disabled = SplitKitWorkspace(registry: registry,
                                         configuration: SplitKitConfiguration(persistence: .disabled, focusModeEnabled: false),
                                         ids: SeededIDGenerator(seed: 1))
        _ = disabled.restoreOrOpenDefault()
        try await disabled.addContent(TestContent.type, url: nil, into: nil)
        let window = try #require(disabled.mainWindow.flatMap(disabled.windowLayout))
        let pane = try #require(window.root?.leaves.first?.pane)
        try await disabled.perform(.toggleFocusMode(pane))
        #expect(disabled.windowLayout(window.id)?.focusModePane == nil)
    }

    // MARK: Close (§6.3) and release (§6.5)

    @Test func acceptedCloseReleasesTheContent() async throws {
        let a = try await addFirst()
        let b = try await addNext(to: a, edge: .right)
        let id = try #require(content(in: b))
        let released = try #require(object(id))
        try await workspace.perform(.closePane(b))
        #expect(released.shouldCloseCalls == 1)
        #expect(released.willReleaseCalls == 1)
        #expect(workspace.store[id] == nil)
        #expect(workspace.record(id) == nil)
        #expect(leaves.map(\.pane) == [a])
        #expect(workspace.runtime.pendingCloses.isEmpty)
    }

    @Test func declinedCloseChangesNothing() async throws {
        let a = try await addFirst()
        let object = try #require(object(content(in: a)))
        object.acceptsClose = false
        let bytes = try Migrator.encode(workspace.session)
        try await workspace.perform(.closePane(a))
        #expect(object.shouldCloseCalls == 1)
        #expect(object.willReleaseCalls == 0)
        #expect(try Migrator.encode(workspace.session) == bytes)
        #expect(workspace.runtime == WorkspaceRuntime())
    }

    @Test func closingTheLastPaneLeavesTheEmptyState() async throws {
        let a = try await addFirst()
        try await workspace.perform(.closePane(a))
        #expect(window.root == nil)
        #expect(workspace.session.windows.count == 1)
        #expect(workspace.store.objects.isEmpty)
    }

    @Test func closingAnEmptyPaneAsksNobody() async throws {
        let a = try await addFirst()
        try await workspace.perform(.split(a, edge: .right))
        let empty = try #require(leaves.last?.pane)
        try await workspace.perform(.closePane(empty))
        #expect(leaves.map(\.pane) == [a])
        #expect(object(content(in: a))?.shouldCloseCalls == 0)
    }

    @Test func windowCloseWithOneDeclineClosesNothing() async throws {
        let a = try await addFirst()
        let b = try await addNext(to: a, edge: .right)
        let objectA = try #require(object(content(in: a))), objectB = try #require(object(content(in: b)))
        objectB.acceptsClose = false
        let bytes = try Migrator.encode(workspace.session)
        try await workspace.perform(.closeWindow(main), answering: true)
        #expect(objectA.shouldCloseCalls == 1 && objectB.shouldCloseCalls == 1)
        #expect(objectA.willReleaseCalls == 0 && objectB.willReleaseCalls == 0)
        #expect(try Migrator.encode(workspace.session) == bytes)
        #expect(workspace.runtime == WorkspaceRuntime())
    }

    @Test func windowCloseReleasesEveryContent() async throws {
        let a = try await addFirst()
        let b = try await addNext(to: a, edge: .right)
        let objects = try [a, b].map { try #require(object(content(in: $0))) }
        try await workspace.perform(.closeWindow(main), answering: true)
        #expect(objects.allSatisfy { $0.willReleaseCalls == 1 })
        #expect(workspace.session.windows.isEmpty)
        #expect(workspace.session.contents.isEmpty)
        #expect(workspace.store.objects.isEmpty)
    }

    // MARK: Failures (§6.2: all-or-nothing)

    @Test func failedCommandsLeaveSessionRuntimeAndObjectsUnchanged() async throws {
        let a = try await addFirst()
        let b = try await addNext(to: a, edge: .right)
        guard case let .split(split, _, _, _) = window.root else { Issue.record("expected a split"); return }
        let unknownPane = PaneID(raw: UUID()), unknownContent = ContentID(raw: UUID())
        let failures: [(SplitKitCommand, LayoutError)] = [
            (.split(unknownPane, edge: .right), .unknownPane(unknownPane)),
            (.move(unknownContent, to: a, edge: .left), .unknownContent(unknownContent)),
            (.resize(splitID: split, fractions: [0.5, .nan]), .invalidFractions(reason: "non-finite fraction")),
            (.resize(splitID: split, fractions: [1]), .invalidFractions(reason: "expected 2 fractions, got 1")),
            (.reorder(splitID: split, from: 0, to: 2), .indexOutOfRange),
            (.setActive(unknownPane, in: main), .unknownPane(unknownPane)),
            (.toggleFocusMode(unknownPane), .unknownPane(unknownPane)),
            (.closePane(unknownPane), .unknownPane(unknownPane)),
        ]
        for (command, expected) in failures {
            let error = try await expectNoChange { try await workspace.perform(command) }
            #expect(error as? LayoutError == expected, "\(command)")
        }
        #expect(object(content(in: b))?.willReleaseCalls == 0)
    }

    @Test func aPendingCloseBlocksOtherCommandsOnThatPane() async throws {
        let a = try await addFirst()
        let b = try await addNext(to: a, edge: .right)
        try workspace.commit(.beginClose(b))
        let error = try await expectNoChange { try await workspace.perform(.split(b, edge: .bottom)) }
        #expect(error as? LayoutError == .paneClosePending(b))
        let addError = try await expectNoChange { try await workspace.addContent(TestContent.type, url: nil, into: b) }
        guard case .creationFailed(_, .other(let reason)) = addError as? RegistryError else { Issue.record("wrong error"); return }
        #expect(reason.contains("paneClosePending"))
    }

    // MARK: Single host (§6.4)

    @Test func oneContentIsNeverHostedInTwoWindows() {
        let store = ContentStore()
        let id = ContentID(raw: UUID())
        let first = WindowID(raw: UUID()), second = WindowID(raw: UUID())
        #expect(store.beginHosting(id, in: first))
        #expect(store.beginHosting(id, in: first), "a second view in the same window (re-hosting) is allowed")
        #expect(!store.beginHosting(id, in: second))
        store.endHosting(id, in: second)
        #expect(store.hostingWindows(of: id) == [first])
        store.endHosting(id, in: first)
        #expect(store.hostingWindows(of: id) == [first])
        store.endHosting(id, in: first)
        #expect(store.hostingWindows(of: id).isEmpty)
        #expect(store.beginHosting(id, in: second))
    }

    // MARK: Rendering

    @Test func splitKitViewRendersTheEmptyWindowATreeAndFocusMode() async throws {
        let size = SavedPlacement.defaultMainWindow.intendedFrame.size
        host(SplitKitView(workspace: workspace, window: main), size: size)
        let a = try await addFirst()
        let b = try await addNext(to: a, edge: .right)
        _ = try await addNext(to: b, edge: .bottom)
        try await workspace.perform(.split(a, edge: .bottom))   // one empty pane
        host(SplitKitView(workspace: workspace, window: main), size: size)
        host(SplitKitView(workspace: workspace, window: main).splitKitTokens(.plain).paneHeaderStyle(.plain)
            .paneDividerStyle(.plain).emptyPaneStyle(.plain), size: size)
        let objects = leaves.compactMap { object($0.content) }
        #expect(objects.count == 3)
        #expect(objects.allSatisfy { $0.makeViewCalls > 0 }, "every hosted content's view was made")

        try await workspace.perform(.toggleFocusMode(b))
        let focused = try #require(object(content(in: b)))
        let before = focused.makeViewCalls
        host(SplitKitView(workspace: workspace, window: main), size: size)
        #expect(focused.makeViewCalls > before)
        host(SplitKitView(workspace: workspace, window: WindowID(raw: UUID())), size: size)   // unknown: renders nothing
    }
}
