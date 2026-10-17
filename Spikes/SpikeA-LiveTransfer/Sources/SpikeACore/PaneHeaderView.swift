import AppKit

/// Pane header: title, a "Move to Other Window" button, and the AppKit drag source.
@MainActor public final class PaneHeaderView: NSView, NSDraggingSource {
    /// Points the mouse must travel before a drag starts.
    public static let dragThreshold: CGFloat = 4

    weak var pane: PaneHostView?
    public let moveButton: NSButton
    private let titleLabel = NSTextField(labelWithString: "")
    private var mouseDownPoint: NSPoint?
    /// The transfer this header started and that AppKit has not ended yet.
    public private(set) var activeSession: TransferSessionID?

    init() {
        moveButton = NSButton(title: "Move ⇥", target: nil, action: nil)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.quaternaryLabelColor.cgColor
        titleLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        titleLabel.lineBreakMode = .byTruncatingMiddle
        moveButton.bezelStyle = .accessoryBarAction
        moveButton.controlSize = .small
        moveButton.refusesFirstResponder = true
        moveButton.toolTip = "Move to Other Window"
        moveButton.target = self
        moveButton.action = #selector(moveToOtherWindow)
        addSubview(titleLabel)
        addSubview(moveButton)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    override public func layout() {
        super.layout()
        moveButton.sizeToFit()
        moveButton.frame.origin = NSPoint(x: bounds.width - moveButton.frame.width - 6, y: (bounds.height - moveButton.frame.height) / 2)
        titleLabel.sizeToFit()
        titleLabel.frame = NSRect(x: 10, y: (bounds.height - titleLabel.frame.height) / 2,
                                  width: max(0, moveButton.frame.minX - 16), height: titleLabel.frame.height)
    }

    func setTitle(_ title: String, hasContent: Bool) {
        titleLabel.stringValue = (hasContent ? "⠿ " : "") + title
        titleLabel.textColor = hasContent ? .labelColor : .secondaryLabelColor
        moveButton.isHidden = !hasContent
        needsLayout = true
    }

    @objc private func moveToOtherWindow() {
        guard let pane, let coordinator = pane.coordinator, let content = pane.hostedContent else { return }
        do {
            try coordinator.moveToOtherWindow(content.id)
        } catch {
            NSSound.beep()
            coordinator.log("move to other window failed: \(error)")
        }
    }

    // MARK: Mouse → drag session

    override public func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override public func mouseDown(with event: NSEvent) {
        mouseDownPoint = convert(event.locationInWindow, from: nil)
    }

    override public func mouseUp(with event: NSEvent) {
        // A click without a drag makes the pane active (gives its content first responder).
        if mouseDownPoint != nil { pane?.takeFirstResponder() }
        mouseDownPoint = nil
    }

    override public func mouseDragged(with event: NSEvent) {
        guard let start = mouseDownPoint, activeSession == nil else { return }
        let point = convert(event.locationInWindow, from: nil)
        guard hypot(point.x - start.x, point.y - start.y) >= Self.dragThreshold else { return }
        mouseDownPoint = nil
        guard let pane, let coordinator = pane.coordinator, let content = pane.hostedContent else { return }
        let transfer: HostRegistry.Transfer
        do {
            transfer = try coordinator.beginTransfer(content.id)
        } catch {
            NSSound.beep()
            return
        }
        activeSession = transfer.id
        let item = NSPasteboardItem()
        item.setString(DragPayload(session: transfer.id, content: content.id).encoded, forType: .spikeATransfer)
        let draggingItem = NSDraggingItem(pasteboardWriter: item)
        draggingItem.setDraggingFrame(bounds, contents: dragImage(title: content.title))
        let session = beginDraggingSession(with: [draggingItem], event: event, source: self)
        session.animatesToStartingPositionsOnCancelOrFail = true
    }

    private func dragImage(title: String) -> NSImage {
        NSImage(size: bounds.size, flipped: false) { rect in
            NSColor.controlAccentColor.withAlphaComponent(0.85).setFill()
            NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6).fill()
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 12, weight: .semibold), .foregroundColor: NSColor.white,
            ]
            (title as NSString).draw(at: NSPoint(x: 10, y: (rect.height - 15) / 2), withAttributes: attributes)
            return true
        }
    }

    // MARK: NSDraggingSource

    public func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        // Panes can only move inside this app; dropping on Finder, Desktop etc. is refused (→ cancel).
        context == .withinApplication ? .move : []
    }

    public func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        handleDragEnded(operation: operation)
    }

    /// End of the AppKit session. An empty operation (Esc, outside, invalid target) cancels the transfer.
    /// Public so tests can drive the source side without a real `NSDraggingSession`.
    public func handleDragEnded(operation: NSDragOperation) {
        guard let session = activeSession else { return }
        activeSession = nil
        pane?.coordinator?.endDrag(session, operation: operation)
    }
}
