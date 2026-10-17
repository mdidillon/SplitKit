import AppKit

public struct TransferOutcome: Equatable, Sendable {
    public var decision: DropDecision
    /// The content held first responder in the source when the drop happened.
    public var sourceHadResponder: Bool
    /// After the drop, the destination window's first responder is inside the destination pane.
    public var responderInDestination: Bool

    public var moved: Bool { if case .move = decision { true } else { false } }
}

/// Owns the content store, the ownership registry and every pane; performs re-hosting.
///
/// Order of a transfer (spec §6.2): validate purely → commit registry → side effects
/// (uninstall source view → install destination view → first responder). Any thrown error
/// happens before the first side effect, so a failed drop changes nothing.
@MainActor public final class TransferCoordinator {
    public private(set) var registry = HostRegistry()
    public let ledger = HostingLedger()
    public private(set) var store: [ContentID: any SpikeContent] = [:]
    /// Weak: the windows own their views.
    private var panes: [HostID: WeakPane] = [:]
    /// Demo: bring the destination window forward when the responder moves. Tests turn it off.
    public var activatesDestinationWindow = true
    public var logger: (@MainActor (String) -> Void)?

    private struct WeakPane { weak var view: PaneHostView? }

    public init() {}

    func log(_ message: String) { logger?(message) }

    public func pane(_ id: HostID) -> PaneHostView? { panes[id]?.view }

    public var allPanes: [PaneHostView] {
        registry.hosts.keys.sorted().compactMap { panes[$0]?.view }
    }

    // MARK: Setup

    public func makePane(in window: WindowID, acceptsDrops: Bool = true) throws(TransferError) -> PaneHostView {
        let pane = PaneHostView(acceptsDrops: acceptsDrops, ledger: ledger)
        try registry.addHost(pane.hostID, window: window, acceptsDrops: acceptsDrops)
        pane.coordinator = self
        panes[pane.hostID] = WeakPane(view: pane)
        return pane
    }

    /// Adds a content to the store (first time) and hosts it. Hosting a hosted content throws.
    public func add(_ content: any SpikeContent, to host: HostID) throws(TransferError) {
        if let existing = store[content.id], existing !== content { throw .contentAlreadyHosted(content.id, in: registry.host(of: content.id) ?? host) }
        guard let pane = pane(host) else { throw .unknownHost(host) }
        var next = registry
        try next.place(content.id, in: host)
        registry = next
        store[content.id] = content
        pane.install(content)
        verifySingleHost(content.id)
    }

    // MARK: Transfer

    public func beginTransfer(_ content: ContentID) throws(TransferError) -> HostRegistry.Transfer {
        guard store[content] != nil else { throw .unknownContent(content) }
        var next = registry
        let transfer = try next.beginTransfer(content)
        registry = next
        pane(transfer.source)?.setPlaceholder(true)
        log("begin \(transfer.id) \(content) from \(transfer.source)")
        return transfer
    }

    public func validateDrop(_ session: TransferSessionID, onto host: HostID) throws(TransferError) -> DropDecision {
        try registry.validateDrop(session, onto: host)
    }

    @discardableResult
    public func completeTransfer(_ session: TransferSessionID, onto target: HostID) throws(TransferError) -> TransferOutcome {
        var next = registry
        let decision = try next.completeTransfer(session, onto: target)
        guard case .move(let contentID, let from, let to) = decision else {
            // Self-drop: no-op apart from ending the transfer.
            let source = registry.activeTransfer?.source
            registry = next
            source.flatMap(pane)?.setPlaceholder(false)
            log("self-drop \(session): no-op")
            return TransferOutcome(decision: decision, sourceHadResponder: false, responderInDestination: false)
        }
        guard let source = pane(from), let destination = pane(to), let content = store[contentID] else {
            throw .unknownHost(pane(from) == nil ? from : to)
        }

        // Everything below is side effects after a successful, already-validated commit.
        let hadResponder = source.containsFirstResponder()
        registry = next
        source.uninstall()
        destination.install(content)
        var responderMoved = false
        if hadResponder {
            if activatesDestinationWindow { destination.window?.makeKeyAndOrderFront(nil) }
            responderMoved = destination.takeFirstResponder()
        }
        verifySingleHost(contentID)
        log("moved \(contentID) \(from) → \(to); responder \(hadResponder ? (responderMoved ? "moved" : "LOST") : "not held")")
        return TransferOutcome(decision: decision, sourceHadResponder: hadResponder, responderInDestination: responderMoved)
    }

    /// Esc / drop outside / failed drop. Leaves registry, views and content as before `beginTransfer`.
    public func cancelTransfer(_ session: TransferSessionID) {
        let source = registry.activeTransfer?.id == session ? registry.activeTransfer?.source : nil
        guard registry.cancelTransfer(session) else { return }
        source.flatMap(pane)?.setPlaceholder(false)
        for pane in allPanes { pane.setHighlight(accepts: nil) }
        log("cancelled \(session)")
    }

    /// Called by the drag source when AppKit ends the session.
    public func endDrag(_ session: TransferSessionID, operation: NSDragOperation) {
        // A successful drop already completed the transfer; anything still active was not accepted.
        if registry.activeTransfer?.id == session { cancelTransfer(session) }
    }

    /// Command path ("Move to Other Window"): same transaction as a drag, without the mouse.
    @discardableResult
    public func move(_ content: ContentID, to target: HostID) throws(TransferError) -> TransferOutcome {
        let transfer = try beginTransfer(content)
        do {
            return try completeTransfer(transfer.id, onto: target)
        } catch {
            cancelTransfer(transfer.id)
            throw error
        }
    }

    /// First empty, drop-accepting pane in another window.
    public func targetInOtherWindow(for content: ContentID) -> HostID? {
        guard let source = registry.host(of: content), let window = registry.hosts[source]?.window else { return nil }
        return registry.hosts.keys.sorted().first { host in
            let info = registry.hosts[host]!
            return info.window != window && info.acceptsDrops && registry.content(in: host) == nil
        }
    }

    @discardableResult
    public func moveToOtherWindow(_ content: ContentID) throws(TransferError) -> TransferOutcome {
        guard let target = targetInOtherWindow(for: content) else { throw .noEmptyTargetInOtherWindow }
        return try move(content, to: target)
    }

    // MARK: Single host and residue

    /// View-level check: exactly one live hosting container for this content across all windows.
    private func verifySingleHost(_ content: ContentID) {
        let count = allPanes.filter { $0.container?.contentID == content && $0.window != nil }.count
        let attached = store[content]?.attachmentCount ?? 0
        if (count > 1) || attached > 1 {
            SpikeInvariant.failure("\(content): \(count) hosting containers, attachmentCount \(attached)")
        }
    }

    public func residue(windows: [NSWindow]) -> ResidueReport {
        ResidueReport(
            windows: windows.map { WindowResidue(window: $0) },
            registrySnapshot: registry.encodedSnapshot(),
            ledger: ledger.claims.sorted { $0.key < $1.key }.map { "\($0.key)@\($0.value)" },
            attachmentCounts: store.keys.sorted().map { store[$0]!.attachmentCount }
        )
    }
}
