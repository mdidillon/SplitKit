import AppKit
import SwiftUI

extension NSPasteboard.PasteboardType {
    /// Private, in-app drag type carrying a transfer session and content ID.
    public static let spikeATransfer = NSPasteboard.PasteboardType("com.splitkit.spikea.transfer")
}

/// Pasteboard payload of a pane drag. Only the session ID matters to the coordinator;
/// a stale or foreign payload is rejected by `validateDrop`.
public struct DragPayload: Equatable, Sendable {
    public var session: TransferSessionID
    public var content: ContentID

    public init(session: TransferSessionID, content: ContentID) {
        self.session = session
        self.content = content
    }

    public var encoded: String { session.raw.uuidString + "|" + content.raw.uuidString }

    public init?(_ string: String) {
        let parts = string.split(separator: "|")
        guard parts.count == 2, let s = UUID(uuidString: String(parts[0])), let c = UUID(uuidString: String(parts[1])) else { return nil }
        self.init(session: TransferSessionID(s), content: ContentID(c))
    }

    @MainActor public init?(pasteboard: NSPasteboard) {
        guard let string = pasteboard.string(forType: .spikeATransfer) else { return nil }
        self.init(string)
    }
}

/// Wraps the single `NSHostingView` of a hosted content. Exactly one per hosted content, app-wide.
@MainActor public final class ContentHostContainer: NSView {
    public let contentID: ContentID
    public let hostingView: NSHostingView<AnyView>

    init(contentID: ContentID, rootView: AnyView) {
        self.contentID = contentID
        self.hostingView = NSHostingView(rootView: rootView)
        super.init(frame: .zero)
        hostingView.frame = bounds
        hostingView.autoresizingMask = [.width, .height]
        addSubview(hostingView)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }
}

/// Shown over the source pane while its content is being dragged. Must never outlive the drag.
@MainActor public final class DragPlaceholderView: NSView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.6).cgColor
        let label = NSTextField(labelWithString: "Moving…")
        label.font = .systemFont(ofSize: 15, weight: .medium)
        label.textColor = .secondaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }
    override public func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// Drop-target highlight; accept (accent) or reject (red). Must never outlive the hover.
@MainActor public final class DropHighlightView: NSView {
    public let accepts: Bool

    init(accepts: Bool) {
        self.accepts = accepts
        super.init(frame: .zero)
        wantsLayer = true
        let color: NSColor = accepts ? .controlAccentColor : .systemRed
        layer?.borderColor = color.cgColor
        layer?.borderWidth = 3
        layer?.backgroundColor = color.withAlphaComponent(0.12).cgColor
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }
    override public func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// One pane: a header (drag source) and a body hosting at most one content. Also the drag destination.
@MainActor public final class PaneHostView: NSView {
    public static let headerHeight: CGFloat = 28

    public let hostID: HostID
    public let acceptsDrops: Bool
    public let header: PaneHeaderView
    public private(set) var hostedContent: (any SpikeContent)?
    public private(set) var container: ContentHostContainer?
    public private(set) var placeholder: DragPlaceholderView?
    public private(set) var highlight: DropHighlightView?
    weak var coordinator: TransferCoordinator?

    private let ledger: HostingLedger
    private let bodyView = NSView()
    private let emptyLabel: NSTextField

    /// `ledger` is shared by every pane of the app; it is what makes a double host detectable.
    public init(hostID: HostID = HostID(), acceptsDrops: Bool = true, ledger: HostingLedger) {
        self.hostID = hostID
        self.acceptsDrops = acceptsDrops
        self.ledger = ledger
        self.header = PaneHeaderView()
        self.emptyLabel = NSTextField(labelWithString: acceptsDrops ? "Empty pane: drop here" : "Locked pane: invalid drop target")
        super.init(frame: NSRect(x: 0, y: 0, width: 300, height: 300))
        header.pane = self
        emptyLabel.textColor = acceptsDrops ? .tertiaryLabelColor : .systemRed
        emptyLabel.alignment = .center
        addSubview(bodyView)
        addSubview(header)
        bodyView.addSubview(emptyLabel)
        focusRingType = .exterior
        registerForDraggedTypes([.spikeATransfer])
        updateHeader()
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    override public var isFlipped: Bool { true }

    override public func layout() {
        super.layout()
        header.frame = NSRect(x: 0, y: 0, width: bounds.width, height: Self.headerHeight)
        bodyView.frame = NSRect(x: 0, y: Self.headerHeight, width: bounds.width, height: max(0, bounds.height - Self.headerHeight))
        emptyLabel.sizeToFit()
        emptyLabel.frame.origin = NSPoint(x: (bodyView.bounds.width - emptyLabel.frame.width) / 2,
                                          y: (bodyView.bounds.height - emptyLabel.frame.height) / 2)
        container?.frame = bodyView.bounds
        placeholder?.frame = bounds
        highlight?.frame = bounds
    }

    // MARK: Hosting (called by the coordinator only)

    /// Creates a fresh hosting view for an existing content object. Returns false if refused (double host).
    @discardableResult
    func install(_ content: any SpikeContent) -> Bool {
        guard hostedContent == nil else {
            SpikeInvariant.failure("\(hostID) already hosts \(hostedContent!.id)")
            return false
        }
        guard ledger.claim(content.id, by: hostID) else { return false }
        let container = ContentHostContainer(contentID: content.id, rootView: content.makeView())
        container.frame = bodyView.bounds
        container.autoresizingMask = [.width, .height]
        bodyView.addSubview(container)
        self.container = container
        hostedContent = content
        emptyLabel.isHidden = true
        updateHeader()
        content.didAttach(to: hostID)
        needsLayout = true
        return true
    }

    /// Tears down the hosting view; the content object itself survives in the store.
    @discardableResult
    func uninstall() -> (any SpikeContent)? {
        guard let content = hostedContent else { return nil }
        content.willDetach(from: hostID)
        if window?.firstResponder.map(isOwnResponder) == true { window?.makeFirstResponder(nil) }
        container?.removeFromSuperview()
        container = nil
        hostedContent = nil
        ledger.release(content.id, by: hostID)
        setPlaceholder(false)
        emptyLabel.isHidden = false
        updateHeader()
        return content
    }

    func setPlaceholder(_ shown: Bool) {
        if shown, placeholder == nil {
            let p = DragPlaceholderView(frame: bounds)
            addSubview(p)
            placeholder = p
        } else if !shown, let p = placeholder {
            p.removeFromSuperview()
            placeholder = nil
        }
    }

    func setHighlight(accepts: Bool?) {
        if highlight?.accepts != accepts {
            highlight?.removeFromSuperview()
            highlight = nil
        }
        if let accepts, highlight == nil {
            let h = DropHighlightView(accepts: accepts)
            h.frame = bounds
            addSubview(h)
            highlight = h
        }
    }

    private func updateHeader() {
        header.setTitle(hostedContent?.title ?? (acceptsDrops ? "Empty" : "Locked"), hasContent: hostedContent != nil)
    }

    // MARK: First responder

    private func isOwnResponder(_ responder: NSResponder) -> Bool {
        if let editor = responder as? NSTextView, editor.isFieldEditor, let owner = editor.delegate as? NSView {
            return owner === self || owner.isDescendant(of: self)
        }
        if let view = responder as? NSView { return view === self || view.isDescendant(of: self) }
        return false
    }

    /// True if the window's first responder is this pane or anything inside it (incl. a field editor).
    public func containsFirstResponder() -> Bool {
        guard let responder = window?.firstResponder else { return false }
        return isOwnResponder(responder)
    }

    /// Hands first responder to the hosted content. Returns whether it ended up inside this pane.
    @discardableResult
    public func takeFirstResponder() -> Bool {
        guard let window, let content = hostedContent else { return false }
        layoutSubtreeIfNeeded()
        switch content.responderKind {
        case .firstTextField:
            if let field = container.flatMap(Self.firstEditableTextField(in:)) {
                window.makeFirstResponder(field)
            } else {
                window.makeFirstResponder(self)
            }
        case .paneContainer:
            window.makeFirstResponder(self)
        }
        return containsFirstResponder()
    }

    static func firstEditableTextField(in view: NSView) -> NSTextField? {
        if let field = view as? NSTextField, field.isEditable, field.acceptsFirstResponder { return field }
        for sub in view.subviews {
            if let found = firstEditableTextField(in: sub) { return found }
        }
        return nil
    }

    override public var acceptsFirstResponder: Bool { hostedContent != nil }

    override public func becomeFirstResponder() -> Bool {
        noteFocusRingMaskChanged()
        return true
    }

    override public func resignFirstResponder() -> Bool {
        noteFocusRingMaskChanged()
        return true
    }

    override public var focusRingMaskBounds: NSRect { bounds }
    override public func drawFocusRingMask() { bounds.insetBy(dx: 2, dy: 2).fill() }

    // MARK: NSDraggingDestination

    private func evaluate(_ info: any NSDraggingInfo) -> NSDragOperation {
        guard let coordinator, let payload = DragPayload(pasteboard: info.draggingPasteboard) else {
            setHighlight(accepts: nil)
            return []
        }
        switch Result(catching: { () throws(TransferError) in try coordinator.validateDrop(payload.session, onto: hostID) }) {
        case .success(.move):
            setHighlight(accepts: true)
            return .move
        case .success(.selfDrop):
            setHighlight(accepts: nil)
            return []
        case .failure:
            setHighlight(accepts: false)
            return []
        }
    }

    override public func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation { evaluate(sender) }
    override public func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation { evaluate(sender) }
    override public func draggingExited(_ sender: (any NSDraggingInfo)?) { setHighlight(accepts: nil) }
    override public func draggingEnded(_ sender: any NSDraggingInfo) { setHighlight(accepts: nil) }
    override public func concludeDragOperation(_ sender: (any NSDraggingInfo)?) { setHighlight(accepts: nil) }

    override public func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        setHighlight(accepts: nil)
        guard let coordinator, let payload = DragPayload(pasteboard: sender.draggingPasteboard) else { return false }
        do {
            let outcome = try coordinator.completeTransfer(payload.session, onto: hostID)
            return outcome.moved
        } catch {
            return false
        }
    }
}
