import AppKit
import SplitKitModel

/// What the drop side of a pane drag asks of its owner. `point` is in the window's content space, origin
/// top-left, y down: the space SwiftUI lays the split view out in.
@MainActor package protocol DockTargetDelegate: AnyObject {
    /// The target under `point`, or nil when it is not a valid drop (self-drop, pending close, a failing move).
    func dockTarget(in window: WindowID, at point: CGPoint, for payload: PaneDragPayload) -> DockTarget?
    /// The drag is over `window` (entered or moved) and `target` is what a drop there would do.
    func dockHover(_ target: DockTarget?, in window: WindowID, for payload: PaneDragPayload)
    /// The drag left `window`, or ended over it.
    func dockExited(window: WindowID)
    /// Runs the drop. False leaves everything unchanged (AppKit then ends the drag as cancelled).
    func dockPerform(_ payload: PaneDragPayload, onto target: DockTarget) -> Bool
}

/// The content view of every window the coordinator shows and the drop destination of its panes (§9, §11.1).
/// Pane drags register on this one view instead of on each pane: AppKit finds the destination by walking
/// up from the view under the cursor, so hosted content (AppKit views, SwiftUI hosting views) never
/// intercepts a drop. The zone under the cursor is decided by the delegate; this view only translates.
@MainActor package final class DockDropContainerView: NSView {
    package let windowID: WindowID
    package weak var delegate: (any DockTargetDelegate)?

    package init(windowID: WindowID, content: NSView) {
        self.windowID = windowID
        super.init(frame: content.frame)
        content.frame = bounds
        content.autoresizingMask = [.width, .height]
        addSubview(content)
        registerForDraggedTypes([.splitKitPane])
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    /// Top-left origin, like SwiftUI, so a window point needs no flipping.
    override package var isFlipped: Bool { true }

    /// An image of `rect` (content space) as drawn now; nil for an empty rect or when the view has no bitmap.
    package func snapshot(of rect: CGRect) -> NSImage? {
        let visible = rect.intersection(bounds)
        guard !visible.isEmpty, let representation = bitmapImageRepForCachingDisplay(in: visible) else { return nil }
        cacheDisplay(in: visible, to: representation)
        let image = NSImage(size: visible.size)
        image.addRepresentation(representation)
        return image
    }

    // MARK: NSDraggingDestination

    private func evaluate(_ info: any NSDraggingInfo) -> NSDragOperation {
        guard let delegate, let payload = PaneDragPayload(pasteboard: info.draggingPasteboard) else { return [] }
        let point = convert(info.draggingLocation, from: nil)
        let target = delegate.dockTarget(in: windowID, at: point, for: payload)
        delegate.dockHover(target, in: windowID, for: payload)
        return target == nil ? [] : .move
    }

    override package func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation { evaluate(sender) }
    override package func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation { evaluate(sender) }
    override package func draggingExited(_ sender: (any NSDraggingInfo)?) { delegate?.dockExited(window: windowID) }
    override package func draggingEnded(_ sender: any NSDraggingInfo) { delegate?.dockExited(window: windowID) }

    override package func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        guard let delegate, let payload = PaneDragPayload(pasteboard: sender.draggingPasteboard),
              let target = delegate.dockTarget(in: windowID, at: convert(sender.draggingLocation, from: nil), for: payload)
        else { return false }
        delegate.dockExited(window: windowID)
        return delegate.dockPerform(payload, onto: target)
    }
}
