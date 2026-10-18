import AppKit
import Testing
import SplitKitModel
@testable import SplitKitWindows

/// The drag mechanism of the window layer (§9, §11.1 Spike A): payload, threshold and end decisions as pure
/// functions, and the drop destination driven directly through a stand-in for `NSDraggingInfo`, since a real
/// mouse `NSDraggingSession` can't be created in a test.

private let payload = PaneDragPayload(drag: DragSessionID(raw: UUID()), content: ContentID(raw: UUID()),
                                      pane: PaneID(raw: UUID()), window: WindowID(raw: UUID()))
private let windowFrame = CGRect(x: 100, y: 100, width: 400, height: 300)

@Suite struct DragDecisionTests {
    @Test func theStartThresholdIsFourPoints() {
        #expect(DragOut.startThreshold == 4)
        #expect(!DragOut.exceedsStartThreshold(from: .zero, to: CGPoint(x: 3, y: 0)))
        #expect(!DragOut.exceedsStartThreshold(from: .zero, to: CGPoint(x: 2, y: 2)))
        #expect(DragOut.exceedsStartThreshold(from: .zero, to: CGPoint(x: 4, y: 0)))
        #expect(DragOut.exceedsStartThreshold(from: CGPoint(x: 10, y: 10), to: CGPoint(x: 10, y: 6)))
        #expect(DragOut.exceedsStartThreshold(from: .zero, to: CGPoint(x: 3, y: 3)))
    }

    @Test func beyondThresholdMeansMoreThanThresholdOutsideTheFrame() {
        func beyond(_ x: CGFloat, _ y: CGFloat) -> Bool {
            DragOut.isBeyondThreshold(cursor: CGPoint(x: x, y: y), window: windowFrame, threshold: 40)
        }
        #expect(!beyond(300, 200), "inside")
        #expect(!beyond(500, 200), "on the edge")
        #expect(!beyond(540, 200), "exactly the threshold outside is still within it")
        #expect(beyond(541, 200))
        #expect(beyond(300, 59) && !beyond(300, 60), "below")
        #expect(beyond(300, 441) && !beyond(300, 440), "above")
        #expect(!beyond(528, 428), "the corner distance is Euclidean: 28, 28 → 39.6")
        #expect(beyond(530, 430), "30, 30 → 42.4")
        #expect(!DragOut.isBeyondThreshold(cursor: CGPoint(x: 5000, y: 5000), window: windowFrame, threshold: .infinity))
    }

    @Test func theGhostShowsOnlyForAnEnabledDragOutOverNoWindow() {
        func shows(allows: Bool = true, x: CGFloat = 900, over: Bool = false) -> Bool {
            DragOut.showsGhost(allowsDragOut: allows, cursor: CGPoint(x: x, y: 200), sourceWindow: windowFrame,
                               threshold: 40, overDockWindow: over)
        }
        #expect(shows())
        #expect(!shows(allows: false), "Detach.commandOnly and .disabled")
        #expect(!shows(over: true), "over another SplitKit window the drop is a dock or a cancel")
        #expect(!shows(x: 520), "within the threshold")
    }

    @Test @MainActor func theGhostKeepsTheCursorAtTheGrabPointOfTheCard() {
        let card = CGSize(width: 300, height: 200)
        let frame = DragOut.ghostFrame(cursor: CGPoint(x: 1000, y: 800), grab: CGPoint(x: 20, y: 10), contentSize: card)
        let titleBar = frame.height - card.height
        #expect(frame.size.width == card.width && titleBar >= 0)
        #expect(frame.minX == 980)
        // The card's top-left is 20 right of and 10 above the cursor; the card's top is the window's top minus the title bar.
        #expect(frame.maxY - titleBar == 810)
    }

    @Test func theEndOfASessionIsDecidedByOperationEscapeAndGhost() {
        let table: [(operation: NSDragOperation, escape: Bool, ghost: CGRect?, expected: DragEnd)] = [
            (.move, false, nil, .docked),
            (.move, true, nil, .docked),
            ([], false, nil, .cancel),
            ([], true, nil, .cancel),
            ([], true, windowFrame, .cancel),
            ([], false, windowFrame, .detach(windowFrame)),
        ]
        for row in table {
            #expect(DragEnd.decide(operation: row.operation, escape: row.escape, ghostFrame: row.ghost) == row.expected)
        }
    }
}

@Suite struct PaneDragPayloadTests {
    @Test @MainActor func itRoundTripsThroughTheStringAndThePasteboard() throws {
        #expect(PaneDragPayload(payload.encoded) == payload)
        let pasteboard = NSPasteboard.withUniqueName()
        pasteboard.clearContents()
        pasteboard.setString(payload.encoded, forType: .splitKitPane)
        #expect(PaneDragPayload(pasteboard: pasteboard) == payload)
        #expect(payload.encoded.count == 4 * 36 + 3, "four UUIDs and no content: IDs only")
    }

    @Test(arguments: ["", "x", "a|b|c|d", "\(UUID())|\(UUID())|\(UUID())", "\(UUID())|\(UUID())|\(UUID())|\(UUID())|\(UUID())"])
    func foreignOrMalformedPayloadsAreRejected(_ string: String) {
        #expect(PaneDragPayload(string) == nil)
    }
}

@MainActor @Suite struct DockDropContainerTests {
    final class Delegate: DockTargetDelegate {
        var target: DockTarget? = .pane(PaneID(raw: UUID()), .left)
        var performResult = true
        var points: [CGPoint] = []
        var hovers: [DockTarget?] = []
        var exits = 0
        var performed: [DockTarget] = []

        func dockTarget(in window: WindowID, at point: CGPoint, for payload: PaneDragPayload) -> DockTarget? {
            points.append(point)
            return target
        }
        func dockHover(_ target: DockTarget?, in window: WindowID, for payload: PaneDragPayload) { hovers.append(target) }
        func dockExited(window: WindowID) { exits += 1 }
        func dockPerform(_ payload: PaneDragPayload, onto target: DockTarget) -> Bool {
            performed.append(target)
            return performResult
        }
    }

    func container(_ delegate: Delegate) -> DockDropContainerView {
        let view = DockDropContainerView(windowID: WindowID(raw: UUID()), content: NSView(frame: CGRect(x: 0, y: 0, width: 200, height: 100)))
        view.delegate = delegate
        return view
    }

    @Test func itRegistersForThePrivatePaneTypeOnly() {
        let delegate = Delegate()
        #expect(container(delegate).registeredDraggedTypes == [.splitKitPane])
    }

    @Test func aValidTargetAcceptsAMoveAndReportsTheHover() {
        let delegate = Delegate()
        let view = container(delegate)
        let info = FakeDraggingInfo(payload: payload, location: CGPoint(x: 30, y: 20))
        #expect(view.draggingEntered(info) == .move)
        #expect(view.draggingUpdated(info) == .move)
        #expect(delegate.hovers == [delegate.target, delegate.target])
        view.draggingExited(info)
        #expect(delegate.exits == 1)
    }

    @Test func theDelegateGetsTheTopLeftOriginPoint() {
        let delegate = Delegate()
        let view = container(delegate)
        // The container is flipped, so a point 20 above its bottom edge (window space) is 80 below its top.
        _ = view.draggingEntered(FakeDraggingInfo(payload: payload, location: CGPoint(x: 30, y: 20)))
        #expect(view.isFlipped && delegate.points == [CGPoint(x: 30, y: 80)])
    }

    @Test func noTargetRefusesTheDropAndNeverPerforms() {
        let delegate = Delegate()
        delegate.target = nil
        let view = container(delegate)
        let info = FakeDraggingInfo(payload: payload, location: .zero)
        #expect(view.draggingEntered(info) == [])
        #expect(!view.performDragOperation(info))
        #expect(delegate.performed.isEmpty)
    }

    @Test func aForeignPasteboardIsIgnored() {
        let delegate = Delegate()
        let view = container(delegate)
        let info = FakeDraggingInfo(payload: nil, location: .zero)
        #expect(view.draggingEntered(info) == [])
        #expect(!view.performDragOperation(info))
        #expect(delegate.points.isEmpty && delegate.hovers.isEmpty && delegate.performed.isEmpty)
    }

    @Test func aDropPerformsOntoTheTargetAndReturnsTheDelegatesAnswer() {
        let delegate = Delegate()
        let view = container(delegate)
        let info = FakeDraggingInfo(payload: payload, location: .zero)
        #expect(view.performDragOperation(info))
        #expect(delegate.performed == [delegate.target!] && delegate.exits == 1)
        delegate.performResult = false
        #expect(!view.performDragOperation(info))
    }
}

/// Stand-in for AppKit's dragging info so tests can drive the real `NSDraggingDestination` methods.
@MainActor final class FakeDraggingInfo: NSObject, @MainActor NSDraggingInfo {
    let draggingPasteboard: NSPasteboard
    let draggingDestinationWindow: NSWindow? = nil
    let draggingLocation: NSPoint

    init(payload: PaneDragPayload?, location: NSPoint) {
        draggingPasteboard = NSPasteboard.withUniqueName()
        draggingPasteboard.clearContents()
        if let payload { draggingPasteboard.setString(payload.encoded, forType: .splitKitPane) }
        draggingLocation = location
    }

    var draggingSourceOperationMask: NSDragOperation { .move }
    var draggedImageLocation: NSPoint { .zero }
    var draggedImage: NSImage? { nil }
    var draggingSource: Any? { nil }
    var draggingSequenceNumber: Int { 1 }
    func slideDraggedImage(to screenPoint: NSPoint) {}
    var draggingFormation: NSDraggingFormation = .default
    var animatesToDestination = false
    var numberOfValidItemsForDrop = 1
    func enumerateDraggingItems(options enumOpts: NSDraggingItemEnumerationOptions = [], for view: NSView?,
                                classes classArray: [AnyClass], searchOptions: [NSPasteboard.ReadingOptionKey: Any] = [:],
                                using block: (NSDraggingItem, Int, UnsafeMutablePointer<ObjCBool>) -> Void) {}
    var springLoadingHighlight: NSSpringLoadingHighlight { .none }
    func resetSpringLoading() {}
}
