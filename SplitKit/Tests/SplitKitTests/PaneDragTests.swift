import AppKit
import Foundation
import Testing
import SplitKitContent
import SplitKitModel
import SplitKitWindows
@testable import SplitKit

/// Zone hit-testing is pure geometry (§9, Docs/Design.md §3).
@Suite struct DropZoneGeometryTests {
    let card = CGRect(x: 100, y: 200, width: 400, height: 200)
    let fraction = SplitKitStyleConstants.dropZoneCentreFraction

    func zone(_ x: CGFloat, _ y: CGFloat) -> DropEdge {
        SplitGeometry.dropZone(at: CGPoint(x: x, y: y), in: card, centreFraction: fraction)
    }

    @Test func theCentreIsTheMiddleHalfOfEachSide() {
        #expect(zone(300, 300) == .center)
        #expect(zone(201, 251) == .center && zone(399, 349) == .center, "inside the corners of the centre rectangle")
        #expect(zone(199, 300) == .left, "just beyond the centre rectangle in x")
        #expect(zone(300, 249) == .top, "just beyond the centre rectangle in y")
    }

    @Test func theEdgesAreTheDiagonalHalves() {
        #expect(zone(110, 300) == .left)
        #expect(zone(490, 300) == .right)
        #expect(zone(300, 205) == .top)
        #expect(zone(300, 395) == .bottom)
        // Card-relative distances decide: on the diagonal itself the tie goes to the top or bottom edge.
        #expect(zone(130, 215) == .top, "dx = −0.425, dy = −0.425")
        #expect(zone(129, 215) == .left)
        #expect(zone(130, 205) == .top)
    }

    @Test func theGapAroundACardTakesTheNearestSide() {
        #expect(zone(90, 300) == .left && zone(510, 300) == .right)
        #expect(zone(300, 190) == .top && zone(300, 410) == .bottom)
    }

    @Test func theCentreFractionScalesTheCentre() {
        #expect(SplitGeometry.dropZone(at: CGPoint(x: 140, y: 300), in: card, centreFraction: 1) == .center)
        #expect(SplitGeometry.dropZone(at: CGPoint(x: 300, y: 300), in: card, centreFraction: 0) == .center, "the exact middle")
        #expect(SplitGeometry.dropZone(at: CGPoint(x: 310, y: 300), in: card, centreFraction: 0) == .right)
        #expect(SplitGeometry.dropZone(at: .zero, in: .zero, centreFraction: fraction) == .center, "a degenerate card")
    }

    @Test func eachZoneHighlightsItsHalfOfTheCard() {
        func rect(_ zone: DropEdge) -> CGRect { SplitGeometry.dropRect(for: zone, in: card) }
        #expect(rect(.center) == card)
        #expect(rect(.left) == CGRect(x: 100, y: 200, width: 200, height: 200))
        #expect(rect(.right) == CGRect(x: 300, y: 200, width: 200, height: 200))
        #expect(rect(.top) == CGRect(x: 100, y: 200, width: 400, height: 100))
        #expect(rect(.bottom) == CGRect(x: 100, y: 300, width: 400, height: 100))
    }

    @Test func theCardIsTheCellInsetByTheContentPadding() {
        #expect(SplitGeometry.card(of: CGRect(x: 0, y: 0, width: 100, height: 50), contentPadding: 4) == CGRect(x: 4, y: 4, width: 92, height: 42))
    }
}

/// The drag coordination (§9, §6.2): begin, hover, drop, ghost and the single cleanup, driven directly the way
/// AppKit would call it, since a mouse `NSDraggingSession` can't run in a test.
@MainActor @Suite struct PaneDragControllerTests {
    let workspace: SplitKitWorkspace
    let host: RecordingWindowHost
    let controller: PaneDragController
    var main: WindowID { workspace.mainLayout.id }

    /// The source window's frame in screen space, away from the test display's edges.
    let sourceWindow = CGRect(x: 100, y: 100, width: 800, height: 600)

    init(detach: SplitKitConfiguration.Detach = .enabled) throws {
        (workspace, host) = try hostedWorkspace(detach: detach)
        controller = workspace.dragController
        _ = workspace.restoreOrOpenDefault()
    }

    /// `count` counters in a row in the main window with their cells registered, in tree order.
    @discardableResult
    func addRow(_ count: Int) async throws -> [ContentID] {
        try await workspace.addContent(CounterContent.type, url: nil, into: nil)
        for _ in 1..<count {
            try await workspace.addContent(CounterContent.type, besides: try #require(workspace.mainLeaves.last?.pane), edge: .right)
        }
        workspace.registerPaneCells(of: main)
        return workspace.mainLeaves.compactMap(\.content)
    }

    func pane(of content: ContentID) throws -> PaneID { try #require(workspace.host(of: content)).pane }
    func window(of content: ContentID) throws -> WindowID { try #require(workspace.host(of: content)).window }
    func counter(_ content: ContentID) throws -> CounterContent { try #require(workspace.store[content] as? CounterContent) }

    /// The centre of `content`'s card in its window, or a point `dx`/`dy` off it.
    func point(in content: ContentID, dx: CGFloat = 0, dy: CGFloat = 0) throws -> CGPoint {
        let window = try window(of: content), pane = try pane(of: content)
        let cells = try #require(workspace.paneCells[window])
        let card = cells.card(of: try #require(cells.cells.first { $0.pane == pane }))
        return CGPoint(x: card.midX + dx, y: card.midY + dy)
    }

    @discardableResult
    func begin(_ content: ContentID) throws -> PaneDragStart {
        let start = try #require(controller.paneDragBegin(pane: try pane(of: content)))
        controller.paneDragStarted(card: nil, mouse: CGPoint(x: start.card.minX + 10, y: start.card.minY + 10))
        return start
    }

    func hover(_ start: PaneDragStart, over content: ContentID, dx: CGFloat = 0, dy: CGFloat = 0) throws -> DockTarget? {
        let window = try window(of: content)
        let target = controller.dockTarget(in: window, at: try point(in: content, dx: dx, dy: dy), for: start.payload)
        controller.dockHover(target, in: window, for: start.payload)
        return target
    }

    /// Everything a cancelled drag must leave as it was: session bytes, runtime and window calls.
    struct Observed: Equatable {
        var session: Data
        var runtime: WorkspaceRuntime
        var calls: [RecordingWindowHost.Call]
    }

    func state() throws -> Observed {
        Observed(session: try Migrator.encode(workspace.session), runtime: workspace.runtime, calls: host.calls)
    }

    func expectClean(_ comment: Comment = "") {
        #expect(workspace.runtime.activeDrag == nil, comment)
        #expect(workspace.draggedPane == nil && workspace.dockTarget == nil && controller.active == nil, comment)
    }

    // MARK: Begin

    @Test func beginningMarksTheRuntimeAndTheDraggedPane() async throws {
        let ids = try await addRow(2)
        let start = try begin(ids[0])
        #expect(workspace.runtime.activeDrag == start.payload.drag)
        #expect(workspace.draggedPane == (try pane(of: ids[0])))
        #expect(start.payload.content == ids[0] && start.payload.window == main)
        #expect(start.header.minY == start.card.minY && start.header.height == SplitKitTokens.glass.metrics.headerHeight)
        #expect(controller.paneDragBegin(pane: try pane(of: ids[1])) == nil, "one drag at a time")
    }

    @Test func emptyAndPendingClosePanesCannotBeDragged() async throws {
        let ids = try await addRow(2)
        try await workspace.perform(.split(try pane(of: ids[1]), edge: .right))
        workspace.registerPaneCells(of: main)
        let empty = try #require(workspace.mainLeaves.last?.pane)
        #expect(controller.paneDragBegin(pane: empty) == nil)

        let closing = try pane(of: ids[0])
        try workspace.commit(.beginClose(closing))
        #expect(controller.paneDragBegin(pane: closing) == nil)
        #expect(controller.paneDragBegin(pane: PaneID(raw: UUID())) == nil, "unknown pane")
        expectClean()
    }

    // MARK: Zones and drops (§6.2)

    @Test func anEdgeZoneMovesAndTheCentreSwaps() async throws {
        let ids = try await addRow(3)
        let objects = try ids.map(counter)
        for (index, object) in objects.enumerated() { object.count = index + 10 }

        var start = try begin(ids[0])
        let edge = try #require(try hover(start, over: ids[2], dx: 60))
        #expect(edge == .pane(try pane(of: ids[2]), .right))
        #expect(workspace.dockTarget == edge)
        #expect(controller.dockPerform(start.payload, onto: edge))
        #expect(workspace.mainLeaves.compactMap(\.content) == [ids[1], ids[2], ids[0]])
        expectClean("a drop ends the drag")

        workspace.registerPaneCells(of: main)
        start = try begin(ids[1])
        let centre = try #require(try hover(start, over: ids[0]))
        #expect(centre == .pane(try pane(of: ids[0]), .center))
        #expect(controller.dockPerform(start.payload, onto: centre))
        #expect(workspace.mainLeaves.compactMap(\.content) == [ids[0], ids[2], ids[1]], "swapped")
        for (index, object) in objects.enumerated() {
            #expect(try counter(ids[index]) === object && object.count == index + 10, "identity and state survive")
        }
        controller.paneDragEnded(at: .zero, operation: .move, escape: false)
        expectClean("the end after a drop is a no-op")
    }

    @Test func theSourcePaneAndAPendingCloseTargetAreNoTargets() async throws {
        let ids = try await addRow(2)
        let start = try begin(ids[0])
        #expect(try hover(start, over: ids[0]) == nil, "self-drop: no overlay, nothing to do")
        #expect(workspace.dockTarget == nil)
        #expect(try hover(start, over: ids[1]) != nil)

        try workspace.commit(.beginClose(try pane(of: ids[1])))
        #expect(try hover(start, over: ids[1]) == nil, "paneClosePending")
        #expect(workspace.dockTarget == nil)
    }

    @Test func aStaleOrForeignDragIsRefused() async throws {
        let ids = try await addRow(2)
        let start = try begin(ids[0])
        var stale = start.payload
        stale.drag = DragSessionID(raw: UUID())
        let window = try window(of: ids[1])
        #expect(controller.dockTarget(in: window, at: try point(in: ids[1]), for: stale) == nil)
        #expect(!controller.dockPerform(stale, onto: .pane(try pane(of: ids[1]), .center)))
        #expect(workspace.mainLeaves.compactMap(\.content) == ids)
    }

    @Test func aFailingDropReturnsFalseAndChangesNothing() async throws {
        let ids = try await addRow(2)
        let before = try state()
        let start = try begin(ids[0])
        #expect(!controller.dockPerform(start.payload, onto: .pane(PaneID(raw: UUID()), .left)))
        #expect(try state() == before, "only the drag mark changed, and it is cleared")
        expectClean()
    }

    @Test func aDropIntoAnEmptyMainWindowMovesTheContentFromADetachedWindow() async throws {
        let ids = try await addRow(1)
        let counter = try counter(ids[0])
        counter.count = 7
        try await workspace.perform(.detach(try pane(of: ids[0])))
        let detached = try window(of: ids[0])
        workspace.registerPaneCells(of: detached)
        #expect(workspace.mainLayout.root == nil)

        let start = try begin(ids[0])
        #expect(start.payload.window == detached)
        let target = try #require(controller.dockTarget(in: main, at: .zero, for: start.payload))
        #expect(target == .emptyWindow(main))
        controller.dockHover(target, in: main, for: start.payload)
        #expect(workspace.dockTarget == .emptyWindow(main))
        #expect(controller.dockPerform(start.payload, onto: target))
        #expect(try window(of: ids[0]) == main && (try self.counter(ids[0])) === counter && counter.count == 7)
        #expect(workspace.windowLayout(detached) == nil && host.calls.last == .close([detached]))
        expectClean()
    }

    @Test func aDetachedWindowIsNeverAnEmptyWindowTarget() async throws {
        let ids = try await addRow(2)
        let start = try begin(ids[0])
        #expect(controller.dockTarget(in: WindowID(raw: UUID()), at: .zero, for: start.payload) == nil, "unknown window")
    }

    @Test func aDropIntoAnotherWindowKeepsTheCounterObjectAndState() async throws {
        let ids = try await addRow(2)
        let objects = try ids.map(counter)
        objects[0].count = 3
        objects[1].count = 4
        try await workspace.perform(.detach(try pane(of: ids[0])))
        let detached = try window(of: ids[0])
        workspace.registerPaneCells(of: detached)
        workspace.registerPaneCells(of: main)

        let start = try begin(ids[0])
        let target = try #require(try hover(start, over: ids[1], dy: 200))
        #expect(target == .pane(try pane(of: ids[1]), .bottom))
        #expect(controller.dockPerform(start.payload, onto: target))
        #expect(try window(of: ids[0]) == main && workspace.mainLeaves.compactMap(\.content) == [ids[1], ids[0]])
        #expect(try counter(ids[0]) === objects[0] && objects[0].count == 3)
        #expect(try counter(ids[1]) === objects[1] && objects[1].count == 4)
        #expect(workspace.windowLayout(detached) == nil, "the emptied detached window closes")
        #expect(workspace.store.objects.count == 2)
        expectClean()
    }

    // MARK: Every end path (§9)

    @Test func everyCancelPathClearsTheDragAndLeavesSessionAndRuntimeIdentical() async throws {
        let ids = try await addRow(2)
        let before = try state()

        // Released within the undock threshold with no target.
        var start = try begin(ids[0])
        #expect(workspace.runtime.activeDrag != nil)
        #expect(!controller.paneDragMoved(to: CGPoint(x: 920, y: 300), sourceWindow: sourceWindow), "20 pt outside is within 40")
        controller.paneDragEnded(at: CGPoint(x: 920, y: 300), operation: [], escape: false)
        expectClean("within the threshold")
        #expect(try state() == before)

        // Esc before and after the ghost appeared.
        start = try begin(ids[0])
        controller.paneDragEnded(at: .zero, operation: [], escape: true)
        expectClean("Esc")
        start = try begin(ids[0])
        #expect(controller.paneDragMoved(to: CGPoint(x: 1500, y: 300), sourceWindow: sourceWindow))
        controller.paneDragEnded(at: CGPoint(x: 1500, y: 300), operation: [], escape: true)
        expectClean("Esc with the ghost showing")
        #expect(try state() == before, "no window was created")

        // An invalid target: hovered, then released over it.
        start = try begin(ids[0])
        #expect(try hover(start, over: ids[0]) == nil)
        controller.paneDragEnded(at: .zero, operation: [], escape: false)
        expectClean("invalid target")

        // A refused drop (performDragOperation false) ends as a cancel too.
        start = try begin(ids[0])
        #expect(!controller.dockPerform(start.payload, onto: .pane(PaneID(raw: UUID()), .center)))
        controller.paneDragEnded(at: .zero, operation: [], escape: false)
        expectClean("refused drop")

        // An end without a begin, and twice.
        controller.paneDragEnded(at: .zero, operation: [], escape: false)
        controller.paneDragEnded(at: .zero, operation: .move, escape: true)
        expectClean("stray ends")
        #expect(try state() == before)
    }

    @Test func aSuccessfulDropClearsTheDragEvenBeforeAppKitEndsTheSession() async throws {
        let ids = try await addRow(2)
        let start = try begin(ids[0])
        let target = try #require(try hover(start, over: ids[1], dx: -150))
        #expect(controller.dockPerform(start.payload, onto: target))
        expectClean("cleaned up at the drop: the dragged header may be gone")
        controller.paneDragEnded(at: .zero, operation: .move, escape: false)
        expectClean()
    }

    // MARK: Drag-out and ghost (§9)

    @Test func releasingTheGhostDetachesOnceAtTheGhostFrame() async throws {
        let ids = try await addRow(2)
        let counter = try counter(ids[1])
        counter.count = 9
        let callsBefore = host.calls
        let start = try begin(ids[1])
        let cursor = CGPoint(x: 1000, y: 800)
        #expect(controller.paneDragMoved(to: CGPoint(x: 1100, y: 600), sourceWindow: sourceWindow), "100 pt outside → ghost")
        #expect(controller.paneDragMoved(to: cursor, sourceWindow: sourceWindow))
        let ghost = try #require(controller.active?.ghostFrame)
        let grab = CGPoint(x: 10, y: 10)
        #expect(ghost == DragOut.ghostFrame(cursor: cursor, grab: grab, contentSize: start.card.size))

        controller.paneDragEnded(at: cursor, operation: [], escape: false)
        expectClean()
        let detached = try window(of: ids[1])
        #expect(Array(host.calls.dropFirst(callsBefore.count)) == [.open([detached])] && detached != main, "detach ran once")
        let placement = try #require(workspace.windowLayout(detached)?.placement)
        #expect(placement.intendedFrame == ghost, "the ghost frame fits the display, so it is the resolved frame")
        #expect(try self.counter(ids[1]) === counter && counter.count == 9)
        #expect(workspace.mainLeaves.compactMap(\.content) == [ids[0]])

        controller.paneDragEnded(at: cursor, operation: [], escape: false)
        #expect(Array(host.calls.dropFirst(callsBefore.count)) == [.open([detached])], "a second end changes nothing")
    }

    @Test func theDetachedFrameIsResolvedAgainstTheDisplay() async throws {
        let ids = try await addRow(2)
        try begin(ids[1])
        // Far past the display's right edge: the ghost is where the cursor is, the window is pulled inside.
        let cursor = CGPoint(x: 1590, y: 500)
        #expect(controller.paneDragMoved(to: cursor, sourceWindow: sourceWindow))
        let ghost = try #require(controller.active?.ghostFrame)
        #expect(ghost.maxX > testDisplay.visibleFrame.maxX)
        controller.paneDragEnded(at: cursor, operation: [], escape: false)
        let frame = try #require(workspace.windowLayout(try window(of: ids[1]))?.placement.intendedFrame)
        #expect(frame.size == ghost.size && frame.maxX == testDisplay.visibleFrame.maxX)
    }

    @Test func theGhostGoesWhenTheCursorComesBackOrIsOverAnotherWindow() async throws {
        let ids = try await addRow(2)
        let callsBefore = host.calls
        let start = try begin(ids[0])
        #expect(controller.paneDragMoved(to: CGPoint(x: 1200, y: 300), sourceWindow: sourceWindow))
        #expect(!controller.paneDragMoved(to: CGPoint(x: 910, y: 300), sourceWindow: sourceWindow))
        #expect(controller.active?.ghostFrame == nil)

        #expect(controller.paneDragMoved(to: CGPoint(x: 1200, y: 300), sourceWindow: sourceWindow))
        let other = WindowID(raw: UUID())
        controller.dockHover(nil, in: other, for: start.payload)
        #expect(!controller.paneDragMoved(to: CGPoint(x: 1200, y: 300), sourceWindow: sourceWindow), "over another SplitKit window")
        controller.paneDragEnded(at: .zero, operation: [], escape: false)
        #expect(host.calls == callsBefore, "an invalid target over a window cancels: no window was created")
        #expect(workspace.mainLeaves.count == 2)
        expectClean()
    }

    @Test func leavingTheDestinationClearsTheOverlay() async throws {
        let ids = try await addRow(2)
        let start = try begin(ids[0])
        #expect(try hover(start, over: ids[1]) != nil && workspace.dockTarget != nil)
        controller.dockExited(window: main)
        #expect(workspace.dockTarget == nil)
        controller.paneDragEnded(at: .zero, operation: [], escape: false)
        expectClean()
    }

    @Test(arguments: [SplitKitConfiguration.Detach.commandOnly, .disabled])
    func commandOnlyAndDisabledTurnOffDragOutButNotDocking(_ detach: SplitKitConfiguration.Detach) async throws {
        let suite = try PaneDragControllerTests(detach: detach)
        let ids = try await suite.addRow(2)
        let before = try suite.state()
        try suite.begin(ids[0])
        #expect(!suite.controller.paneDragMoved(to: CGPoint(x: 1500, y: 300), sourceWindow: suite.sourceWindow), "no ghost")
        suite.controller.paneDragEnded(at: CGPoint(x: 1500, y: 300), operation: [], escape: false)
        #expect(try suite.state() == before, "release outside cancels")
        suite.expectClean()

        let docking = try suite.begin(ids[0])
        let target = try #require(try suite.hover(docking, over: ids[1]))
        #expect(suite.controller.dockPerform(docking.payload, onto: target), "docking still works")
    }
}
