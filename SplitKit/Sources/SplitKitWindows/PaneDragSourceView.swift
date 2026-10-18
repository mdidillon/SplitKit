import AppKit
import SplitKitModel

/// What starting a header drag needs (§9): the payload and the pane's rects in the window's content space
/// (top-left origin, y down). `card` is snapshotted for the ghost, `header` is the drag image.
package struct PaneDragStart: Equatable {
    package var payload: PaneDragPayload
    package var card: CGRect
    package var header: CGRect

    package init(payload: PaneDragPayload, card: CGRect, header: CGRect) {
        self.payload = payload
        self.card = card
        self.header = header
    }
}

/// The drag-source side's owner (§9, §11.1). `paneDragEnded` is the single cancel and cleanup point.
@MainActor package protocol PaneDragSourceDelegate: AnyObject {
    /// nil refuses the drag: no content, a pending close, or a drag already running.
    func paneDragBegin(pane: PaneID) -> PaneDragStart?
    /// The session started. `mouse` is where it began in content space; the snapshots are nil without a bitmap.
    func paneDragStarted(card: NSImage?, mouse: CGPoint)
    /// The cursor moved (screen space) while `sourceWindow` is the window of the dragged pane. True while
    /// the ghost window stands in for the drag image.
    func paneDragMoved(to screenPoint: CGPoint, sourceWindow: CGRect) -> Bool
    /// The session ended: dropped, cancelled with Esc, or released over nothing.
    func paneDragEnded(at screenPoint: CGPoint, operation: NSDragOperation, escape: Bool)
    /// A click on the handle without a drag.
    func paneClicked(pane: PaneID)
}

/// The drag handle of a pane header: the `NSDraggingSource` of a pane drag (§9, §11.1). The mouse must move
/// `DragOut.startThreshold` before a session begins; a click without a drag makes the pane active. Only an
/// in-app `.move` is offered, so Finder, the Desktop and other apps refuse the drop.
@MainActor package final class PaneDragSourceView: NSView {
    package weak var delegate: (any PaneDragSourceDelegate)?
    package var pane: PaneID?
    private var mouseDown: NSPoint?
    private var isDragging = false

    override package func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override package func mouseDown(with event: NSEvent) {
        mouseDown = event.locationInWindow
    }

    override package func mouseUp(with event: NSEvent) {
        defer { mouseDown = nil }
        if mouseDown != nil, let pane { delegate?.paneClicked(pane: pane) }
    }

    override package func mouseDragged(with event: NSEvent) {
        guard let start = mouseDown, !isDragging,
              DragOut.exceedsStartThreshold(from: start, to: event.locationInWindow) else { return }
        mouseDown = nil
        guard let pane, let delegate, let start = delegate.paneDragBegin(pane: pane) else { return }
        let container = DockDropContainerView.destination(in: window)
        let card = container?.snapshot(of: start.card)
        let headerImage = container?.snapshot(of: start.header)
        delegate.paneDragStarted(card: card, mouse: container?.convert(event.locationInWindow, from: nil) ?? .zero)

        let source = DragSource(delegate: delegate, sourceWindow: { [weak self] in self?.window?.frame ?? .zero })
        let item = NSDraggingItem(pasteboardWriter: pasteboardItem(for: start.payload))
        let frame = container.map { convert(start.header, from: $0) } ?? bounds
        source.item = (frame, headerImage)
        item.setDraggingFrame(frame, contents: headerImage ?? NSImage(size: frame.size))
        isDragging = true
        source.onEnd = { [weak self] in self?.isDragging = false }
        let session = beginDraggingSession(with: [item], event: event, source: source)
        session.animatesToStartingPositionsOnCancelOrFail = true
        source.start()
    }

    private func pasteboardItem(for payload: PaneDragPayload) -> NSPasteboardItem {
        let item = NSPasteboardItem()
        item.setString(payload.encoded, forType: .splitKitPane)
        return item
    }
}

/// The `NSDraggingSource` of one session. Separate from the view because the header is torn down when a drop
/// moves its pane; AppKit must still reach the end callback, so this object keeps itself alive until it ends.
@MainActor private final class DragSource: NSObject, NSDraggingSource {
    private weak var delegate: (any PaneDragSourceDelegate)?
    private let sourceWindow: @MainActor () -> CGRect
    private var frozenSourceWindow = CGRect.zero
    private var keepAlive: DragSource?
    private var escapeMonitor: Any?
    private var escapePressed = false
    private var ghostShowing = false
    var item: (frame: CGRect, image: NSImage?) = (.zero, nil)
    var onEnd: (@MainActor () -> Void)?

    private static let escapeKeyCode: UInt16 = 53

    init(delegate: any PaneDragSourceDelegate, sourceWindow: @escaping @MainActor () -> CGRect) {
        self.delegate = delegate
        self.sourceWindow = sourceWindow
    }

    func start() {
        keepAlive = self
        frozenSourceWindow = sourceWindow()
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == Self.escapeKeyCode { MainActor.assumeIsolated { self?.escapePressed = true } }
            return event
        }
    }

    nonisolated func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .withinApplication ? .move : []
    }

    nonisolated func draggingSession(_ session: NSDraggingSession, movedTo screenPoint: NSPoint) {
        let changed: Bool? = MainActor.assumeIsolated {
            guard let delegate else { return nil }
            // The window may close mid-drag (a drop that empties it); the frame from the start stays valid.
            let window = sourceWindow()
            if !window.isEmpty { frozenSourceWindow = window }
            let ghost = delegate.paneDragMoved(to: screenPoint, sourceWindow: frozenSourceWindow)
            defer { ghostShowing = ghost }
            return ghost == ghostShowing ? nil : ghost
        }
        guard let ghost = changed else { return }
        // The ghost replaces the drag image, and nothing slides back when the ghost becomes a window.
        session.animatesToStartingPositionsOnCancelOrFail = !ghost
        let (frame, image) = MainActor.assumeIsolated { item }
        session.enumerateDraggingItems(options: [], for: nil, classes: [NSPasteboardItem.self], searchOptions: [:]) { draggingItem, _, _ in
            if ghost {
                draggingItem.imageComponentsProvider = { [] }
            } else {
                draggingItem.setDraggingFrame(frame, contents: image ?? NSImage(size: frame.size))
            }
        }
    }

    nonisolated func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        MainActor.assumeIsolated {
            let current = NSApp.currentEvent
            let escape = escapePressed || (current?.type == .keyDown && current?.keyCode == Self.escapeKeyCode)
            if let escapeMonitor { NSEvent.removeMonitor(escapeMonitor) }
            escapeMonitor = nil
            delegate?.paneDragEnded(at: screenPoint, operation: operation, escape: escape)
            onEnd?()
            keepAlive = nil
        }
    }
}
