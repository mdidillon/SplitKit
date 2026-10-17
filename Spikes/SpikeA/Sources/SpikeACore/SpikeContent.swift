import SwiftUI

/// Where first responder goes when a content that held it lands in a new pane.
public enum ResponderKind: Sendable {
    /// The first editable text field inside the content's view.
    case firstTextField
    /// The pane host view itself (contents without a natural key view, e.g. 3D).
    case paneContainer
}

/// Cut-down `PaneContent` (spec §5) with only what Spike A needs.
/// The object is owned by the coordinator's store and is never recreated by a move.
@MainActor public protocol SpikeContent: AnyObject, Observable {
    var id: ContentID { get }
    var title: String { get }
    var responderKind: ResponderKind { get }
    /// Number of panes currently attached. Must be 0 or 1 (single host).
    var attachmentCount: Int { get }
    /// Times `makeView()` was called; re-hosting is allowed to call it again (spec §5).
    var makeViewCalls: Int { get }
    func makeView() -> AnyView
    func didAttach(to host: HostID)
    func willDetach(from host: HostID)
}

/// Tracks which pane currently has a live view for each content, across all windows.
/// A second claim for a content is the "double host" programmer error (spec §6.4, §12).
@MainActor public final class HostingLedger {
    public private(set) var claims: [ContentID: HostID] = [:]

    public init() {}

    /// Returns false (release fallback) or traps (debug) when the content is already hosted elsewhere.
    @discardableResult
    public func claim(_ content: ContentID, by host: HostID) -> Bool {
        if let existing = claims[content], existing != host {
            SpikeInvariant.failure("double host: \(content) is hosted by \(existing), \(host) tried to host it too")
            return false
        }
        claims[content] = host
        return true
    }

    public func release(_ content: ContentID, by host: HostID) {
        guard claims[content] == host else {
            SpikeInvariant.failure("\(host) released \(content) it does not hold")
            return
        }
        claims[content] = nil
    }
}
