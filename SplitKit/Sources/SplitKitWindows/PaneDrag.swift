import AppKit
import SplitKitModel

extension NSPasteboard.PasteboardType {
    /// The private, in-app type of a pane drag (§11.1 Spike A). It carries IDs only, never content.
    package static let splitKitPane = NSPasteboard.PasteboardType("com.splitkit.pane-drag")
}

/// What a pane drag carries on the pasteboard: the drag session, the dragged content and where it comes from.
/// IDs only (§11.1); a stale or foreign payload is rejected by the drop side.
package struct PaneDragPayload: Equatable, Sendable {
    package var drag: DragSessionID
    package var content: ContentID
    package var pane: PaneID
    package var window: WindowID

    package init(drag: DragSessionID, content: ContentID, pane: PaneID, window: WindowID) {
        self.drag = drag
        self.content = content
        self.pane = pane
        self.window = window
    }

    package var encoded: String {
        [drag.raw, content.raw, pane.raw, window.raw].map(\.uuidString).joined(separator: "|")
    }

    package init?(_ string: String) {
        let fields = string.split(separator: "|")
        let parts = fields.compactMap { UUID(uuidString: String($0)) }
        guard fields.count == 4, parts.count == 4 else { return nil }
        self.init(drag: DragSessionID(raw: parts[0]), content: ContentID(raw: parts[1]),
                  pane: PaneID(raw: parts[2]), window: WindowID(raw: parts[3]))
    }

    @MainActor package init?(pasteboard: NSPasteboard) {
        guard let string = pasteboard.string(forType: .splitKitPane) else { return nil }
        self.init(string)
    }
}

/// Where a header drag may land (§9): a pane's edge half or centre, or an empty main window.
package enum DockTarget: Equatable, Sendable {
    case pane(PaneID, DropEdge)
    case emptyWindow(WindowID)
}

/// How a drag session ended (§9). Pure, so the decision is tested without a real `NSDraggingSession`.
package enum DragEnd: Equatable, Sendable {
    /// A destination took the drop; the transaction already ran.
    case docked
    /// Esc, a drop within the undock threshold, over an invalid target, or with drag-out disabled: no change.
    case cancel
    /// A drop beyond the threshold outside every window: a detached window at this frame (§9).
    case detach(CGRect)

    /// `operation` is what AppKit reports; `ghostFrame` is the ghost window's frame when it was showing.
    package static func decide(operation: NSDragOperation, escape: Bool, ghostFrame: CGRect?) -> DragEnd {
        if !operation.isEmpty { return .docked }
        if escape { return .cancel }
        return ghostFrame.map { .detach($0) } ?? .cancel
    }
}

/// The pure geometry of dragging a pane out of its window (§9). Screen space, y up.
package enum DragOut {
    /// The header drag starts after the mouse moved this far (§11.1).
    package static let startThreshold: CGFloat = 4

    /// True once the mouse has moved `startThreshold` or more from where it went down.
    package static func exceedsStartThreshold(from start: CGPoint, to point: CGPoint) -> Bool {
        hypot(point.x - start.x, point.y - start.y) >= startThreshold
    }

    /// True when `cursor` is more than `threshold` outside `window` (the distance to the frame, not to its centre).
    package static func isBeyondThreshold(cursor: CGPoint, window: CGRect, threshold: CGFloat) -> Bool {
        let dx = max(window.minX - cursor.x, 0, cursor.x - window.maxX)
        let dy = max(window.minY - cursor.y, 0, cursor.y - window.maxY)
        return hypot(dx, dy) > threshold
    }

    /// Whether the ghost shows: drag-out enabled, beyond the threshold, over no SplitKit window (§9).
    package static func showsGhost(allowsDragOut: Bool, cursor: CGPoint, sourceWindow: CGRect, threshold: CGFloat,
                                   overDockWindow: Bool) -> Bool {
        allowsDragOut && !overDockWindow && isBeyondThreshold(cursor: cursor, window: sourceWindow, threshold: threshold)
    }

    /// The ghost's frame, and so the new window's: a window frame for a card of `contentSize`, placed so
    /// the cursor stays at `grab` (offset from the card's top-left, y down) as when the drag began.
    @MainActor package static func ghostFrame(cursor: CGPoint, grab: CGPoint, contentSize: CGSize) -> CGRect {
        let size = NSWindow.frameRect(forContentRect: CGRect(origin: .zero, size: contentSize),
                                      styleMask: WindowCoordinator.styleMask).size
        return CGRect(x: cursor.x - grab.x, y: cursor.y + grab.y - contentSize.height, width: size.width, height: size.height)
    }
}
