import Foundation

// Identity types (§4, §5). PaneID, ContentID and ContentType are independent: moving content keeps
// its ContentID while the PaneID names the slot.

public struct PaneID: Hashable, Codable, Sendable {
    public let raw: UUID
    public init(raw: UUID) { self.raw = raw }
}

public struct SplitID: Hashable, Codable, Sendable {
    public let raw: UUID
    public init(raw: UUID) { self.raw = raw }
}

public struct WindowID: Hashable, Codable, Sendable {
    public let raw: UUID
    public init(raw: UUID) { self.raw = raw }
}

public struct ContentID: Hashable, Codable, Sendable {
    public let raw: UUID
    public init(raw: UUID) { self.raw = raw }
}

/// Reverse-DNS content kind, e.g. `"splitkit.image"`.
public struct ContentType: Hashable, Codable, Sendable {
    public let raw: String
    public init(raw: String) { self.raw = raw }
}

/// Not `Axis`: avoids a clash with `SwiftUI.Axis`.
public enum SplitAxis: String, Codable, Sendable {
    case horizontal, vertical
}

/// Runtime only, never encoded.
public struct DragSessionID: Hashable, Sendable {
    public let raw: UUID
    public init(raw: UUID) { self.raw = raw }
}

public enum DropEdge: String, Codable, Sendable {
    case left, right, top, bottom, center
}

extension DropEdge {
    /// §6.1.9: `left`/`right` → `.horizontal`, `top`/`bottom` → `.vertical`; nil for `.center`.
    var axis: SplitAxis? {
        switch self {
        case .left, .right: .horizontal
        case .top, .bottom: .vertical
        case .center: nil
        }
    }

    /// §6.1.9: `left`/`top` place the new pane before the target, `right`/`bottom` after it.
    var placesBefore: Bool { self == .left || self == .top }
}

extension ContentID {
    /// Carried by `LayoutError.unknownContent` when `detach` (or Replace Content, Move to Window) names an empty
    /// pane: §6.2 prescribes `unknownContent`, but an empty pane has no `ContentID`, so the all-zero UUID stands in.
    package static let emptyPane = ContentID(raw: UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)))
}
