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

    /// A file from outside the app (Finder) is over `window` at `point`; true when a drop there would open it
    /// (a registered type matches and the zone under the cursor can take it). The delegate shows the zone.
    func fileDropHover(_ url: URL, in window: WindowID, at point: CGPoint) -> Bool
    /// The file drag left `window`, or ended over it.
    func fileDropExited(window: WindowID)
    /// Opens the file at the zone under `point`. False leaves everything unchanged.
    func fileDropPerform(_ url: URL, in window: WindowID, at point: CGPoint) -> Bool
}

/// The content view of every window the coordinator shows and the drop destination of its panes (§9, §11.1).
/// Pane drags register on this one view instead of on each pane: AppKit finds the destination by walking
/// up from the view under the cursor, so hosted content (AppKit views, SwiftUI hosting views) never
/// intercepts a drop. The zone under the cursor is decided by the delegate; this view only translates.
@MainActor package final class DockDropContainerView: NSView {
    package let windowID: WindowID
    package weak var delegate: (any DockTargetDelegate)?

    /// True for the destination a `.host` window gets on top of its own content (`init(overlayFor:)`).
    package let isOverlay: Bool

    package init(windowID: WindowID, content: NSView) {
        self.windowID = windowID
        isOverlay = false
        super.init(frame: content.frame)
        content.frame = bounds
        content.autoresizingMask = [.width, .height]
        addSubview(content)
        registerForDraggedTypes(Self.draggedTypes)
    }

    /// The drop destination of a window the host owns (§9 `.host`): a transparent view laid over the host's
    /// content, which SplitKit cannot wrap. It takes part in hit testing only while a pane drag is under the
    /// cursor, so clicks, scrolls and hovers reach the host's views as before.
    package init(overlayFor windowID: WindowID) {
        self.windowID = windowID
        isOverlay = true
        super.init(frame: .zero)
        registerForDraggedTypes(Self.draggedTypes)
    }

    /// What a window accepts: a pane of this app, or a file from outside it (Finder).
    package static let draggedTypes: [NSPasteboard.PasteboardType] = [.splitKitPane, .fileURL]

    /// The first file URL on `pasteboard`, if any.
    package static func fileURL(in pasteboard: NSPasteboard) -> URL? {
        let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]
        return urls?.first
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    /// Top-left origin, like SwiftUI, so a window point needs no flipping.
    override package var isFlipped: Bool { true }

    /// Whether a drop this view takes is in flight: the dragging pasteboard holds a pane payload or a file URL
    /// and the event being handled is a drag (the pasteboard keeps its payload after the drop, so it alone is
    /// not enough).
    package static func isDropInFlight(event: NSEvent.EventType?, pasteboardTypes: [NSPasteboard.PasteboardType]?) -> Bool {
        (event == .leftMouseDragged || event == nil) && pasteboardTypes?.contains(where: draggedTypes.contains) == true
    }

    /// The types on the system dragging pasteboard, read by the overlay's hit test. Tests replace it, since the
    /// real pasteboard keeps the payload of the last drag on the machine.
    package var dragPasteboardTypes: @MainActor () -> [NSPasteboard.PasteboardType]? = { NSPasteboard(name: .drag).types }

    override package func hitTest(_ point: NSPoint) -> NSView? {
        guard isOverlay else { return super.hitTest(point) }
        let drag = Self.isDropInFlight(event: NSApp?.currentEvent?.type, pasteboardTypes: dragPasteboardTypes())
        return drag ? super.hitTest(point) : nil
    }

    /// The drop destination of `window`: its content view (`.splitKit` windows) or the overlay inside the
    /// host's content (`.host` windows).
    package static func destination(in window: NSWindow?) -> DockDropContainerView? {
        func search(_ view: NSView) -> DockDropContainerView? {
            if let container = view as? DockDropContainerView { return container }
            for subview in view.subviews { if let found = search(subview) { return found } }
            return nil
        }
        return window?.contentView.flatMap(search)
    }

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
        guard let delegate else { return [] }
        let point = convert(info.draggingLocation, from: nil)
        if let payload = PaneDragPayload(pasteboard: info.draggingPasteboard) {
            let target = delegate.dockTarget(in: windowID, at: point, for: payload)
            delegate.dockHover(target, in: windowID, for: payload)
            return target == nil ? [] : .move
        }
        if let url = Self.fileURL(in: info.draggingPasteboard) {
            return delegate.fileDropHover(url, in: windowID, at: point) ? .copy : []
        }
        return []
    }

    override package func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation { evaluate(sender) }
    override package func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation { evaluate(sender) }
    override package func draggingExited(_ sender: (any NSDraggingInfo)?) { exited() }
    override package func draggingEnded(_ sender: any NSDraggingInfo) { exited() }

    private func exited() {
        delegate?.dockExited(window: windowID)
        delegate?.fileDropExited(window: windowID)
    }

    override package func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        if PaneDragPayload(pasteboard: sender.draggingPasteboard) == nil, let delegate,
           let url = Self.fileURL(in: sender.draggingPasteboard) {
            let point = convert(sender.draggingLocation, from: nil)
            delegate.fileDropExited(window: windowID)
            return delegate.fileDropPerform(url, in: windowID, at: point)
        }
        guard let delegate, let payload = PaneDragPayload(pasteboard: sender.draggingPasteboard),
              let target = delegate.dockTarget(in: windowID, at: convert(sender.draggingLocation, from: nil), for: payload)
        else { return false }
        delegate.dockExited(window: windowID)
        return delegate.dockPerform(payload, onto: target)
    }
}
