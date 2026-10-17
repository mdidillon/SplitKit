import CoreGraphics
import Foundation

/// A layout tree. Invariants in §6.1; arithmetic in §6.1.9.
public indirect enum LayoutNode: Codable, Equatable, Sendable {
    case pane(id: PaneID, content: ContentID?)
    case split(id: SplitID, axis: SplitAxis, children: [LayoutNode], fractions: [Double])
}

/// Where a window was last placed by the user (§9). Resolved against the current displays by `DisplayPlacement.resolve`.
public struct SavedPlacement: Codable, Equatable, Sendable {
    public var intendedFrame: CGRect          // last frame the USER set, global space
    public var displayID: String?             // hint only
    public var relativeOrigin: CGPoint?       // point offset of intendedFrame.origin from that display's visibleFrame.origin

    public init(intendedFrame: CGRect, displayID: String? = nil, relativeOrigin: CGPoint? = nil) {
        self.intendedFrame = intendedFrame
        self.displayID = displayID
        self.relativeOrigin = relativeOrigin
    }
}

extension SavedPlacement {
    /// 1200 × 800 pt, centred on the main display by §9 (`relativeOrigin == nil`): the v0 → v1 migration
    /// placement (§8), also used for the main window of the default layout.
    package static let defaultMainWindow = SavedPlacement(intendedFrame: CGRect(x: 0, y: 0, width: 1200, height: 800),
                                                          displayID: nil, relativeOrigin: nil)
}

public struct WindowLayout: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable { case main, detached }
    public var id: WindowID
    public var kind: Kind
    public var root: LayoutNode?          // nil only for .main = empty state
    public var activePane: PaneID?        // keyboard/selection focus
    public var focusModePane: PaneID?     // pane filling the window; tree untouched
    public var placement: SavedPlacement  // see §9

    public init(id: WindowID, kind: Kind, root: LayoutNode?, activePane: PaneID? = nil,
                focusModePane: PaneID? = nil, placement: SavedPlacement) {
        self.id = id
        self.kind = kind
        self.root = root
        self.activePane = activePane
        self.focusModePane = focusModePane
        self.placement = placement
    }
}

/// What an insert adds; becomes a `ContentRecord` (§6.5).
public struct NewContent: Equatable, Sendable {
    public var id: ContentID                                 // caller-generated
    public var type: ContentType
    public var stateVersion: Int                             // C.stateVersion of the registered type

    public init(id: ContentID, type: ContentType, stateVersion: Int) {
        self.id = id
        self.type = type
        self.stateVersion = stateVersion
    }
}

public struct Session: Codable, Equatable, Sendable {
    public static let currentVersion = 1
    public var version: Int
    public var windows: [WindowLayout]     // creation order (§6.1.8)
    public var contents: [ContentRecord]   // insertion order

    public init(version: Int = Session.currentVersion, windows: [WindowLayout] = [], contents: [ContentRecord] = []) {
        self.version = version
        self.windows = windows
        self.contents = contents
    }
}

public struct ContentRecord: Codable, Equatable, Sendable {
    public var id: ContentID; public var type: ContentType
    public var stateVersion: Int; public var state: Data
    public var availability: Availability = .hosted
    public enum Availability: String, Codable, Sendable {
        case hosted        // a live object exists (or will on restore)
        case unavailable   // type not registered: shown as a recoverable placeholder, never hosted, data retained verbatim
    }

    public init(id: ContentID, type: ContentType, stateVersion: Int, state: Data, availability: Availability = .hosted) {
        self.id = id
        self.type = type
        self.stateVersion = stateVersion
        self.state = state
        self.availability = availability
    }

    /// A missing `availability` key decodes as the declared default, `.hosted` (§5). Encoding always writes it.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(ContentID.self, forKey: .id)
        type = try container.decode(ContentType.self, forKey: .type)
        stateVersion = try container.decode(Int.self, forKey: .stateVersion)
        state = try container.decode(Data.self, forKey: .state)
        availability = try container.decodeIfPresent(Availability.self, forKey: .availability) ?? .hosted
    }
}
