import SwiftUI
import SplitKitModel

/// Draws the drop zone of a header drag over the target pane (spec §9, Docs/Design.md §4, §7). Works like
/// `ButtonStyle`. The chrome sizes the body to the zone (that half of the card, or the whole card for the
/// centre) and animates it; the style fills that frame.
public protocol DropOverlayStyle {
    associatedtype Body: View
    @MainActor @ViewBuilder func makeBody(configuration: DropOverlayConfiguration) -> Body
}

public struct DropOverlayConfiguration {
    /// The zone being targeted: an edge half (an edge move) or `.center` (a swap, or a move into an empty pane).
    public let zone: DropEdge
    /// The pane card's corner radius (`metrics.cornerRadius`).
    public let cornerRadius: CGFloat

    init(zone: DropEdge, cornerRadius: CGFloat) {
        self.zone = zone
        self.cornerRadius = cornerRadius
    }

    /// The zone's shape: the card's shape for the centre, and for an edge half the card's corners on the
    /// outside only, so the halves line up with the card.
    public var shape: UnevenRoundedRectangle {
        let r = cornerRadius
        let corners: RectangleCornerRadii = switch zone {
        case .center: .init(topLeading: r, bottomLeading: r, bottomTrailing: r, topTrailing: r)
        case .left: .init(topLeading: r, bottomLeading: r, bottomTrailing: 0, topTrailing: 0)
        case .right: .init(topLeading: 0, bottomLeading: 0, bottomTrailing: r, topTrailing: r)
        case .top: .init(topLeading: r, bottomLeading: 0, bottomTrailing: 0, topTrailing: r)
        case .bottom: .init(topLeading: 0, bottomLeading: r, bottomTrailing: r, topTrailing: 0)
        }
        return UnevenRoundedRectangle(cornerRadii: corners, style: .continuous)
    }
}

// MARK: Type erasure and environment

struct AnyDropOverlayStyle {
    let style: any DropOverlayStyle

    init(_ style: some DropOverlayStyle) { self.style = style }

    @MainActor func makeBody(configuration: DropOverlayConfiguration) -> AnyView {
        AnyView(style.makeBody(configuration: configuration))
    }
}

extension EnvironmentValues {
    @Entry var dropOverlayStyle = AnyDropOverlayStyle(GlassDropOverlayStyle())
}

extension View {
    /// Sets the style of the drop overlay in this view hierarchy.
    public func dropOverlayStyle<S: DropOverlayStyle>(_ style: S) -> some View {
        environment(\.dropOverlayStyle, AnyDropOverlayStyle(style))
    }
}

// MARK: Built-in styles

/// The default overlay: `.thinMaterial` in the zone shape with the `dropHighlight` fill and stroke
/// (Docs/Design.md §4.1).
public struct GlassDropOverlayStyle: DropOverlayStyle {
    public init() {}
    public func makeBody(configuration: DropOverlayConfiguration) -> some View {
        BuiltInDropOverlay(configuration: configuration, look: .glass)
    }
}

/// The `dropHighlight` fill and stroke only, no material (Docs/Design.md §4.2).
public struct PlainDropOverlayStyle: DropOverlayStyle {
    public init() {}
    public func makeBody(configuration: DropOverlayConfiguration) -> some View {
        BuiltInDropOverlay(configuration: configuration, look: .plain)
    }
}

extension DropOverlayStyle where Self == GlassDropOverlayStyle {
    public static var glass: GlassDropOverlayStyle { GlassDropOverlayStyle() }
}

extension DropOverlayStyle where Self == PlainDropOverlayStyle {
    public static var plain: PlainDropOverlayStyle { PlainDropOverlayStyle() }
}

/// The one overlay both built-in styles render (Docs/Design.md §4.1, §4.2, §7).
struct BuiltInDropOverlay: View {
    let configuration: DropOverlayConfiguration
    let look: BuiltInLook
    @Environment(\.splitKitTokens) private var tokens

    private typealias Constants = SplitKitStyleConstants

    var body: some View {
        let shape = configuration.shape
        ZStack {
            switch look {
            case .glass: shape.fill(.thinMaterial)
            case .plain: EmptyView()
            }
            shape.fill(tokens.colors.dropHighlight.opacity(Constants.dropOverlayFillOpacity))
            shape.strokeBorder(tokens.colors.dropHighlight, lineWidth: Constants.dropOverlayStroke)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Places the style's drop overlay on the zone `zone` of `card` (a rect in the space of the enclosing
/// view) and animates it (Docs/Design.md §7). One view for pane targets and the empty window.
struct DropOverlayView: View {
    let zone: DropEdge
    let card: CGRect
    @Environment(\.splitKitTokens) private var tokens
    @Environment(\.dropOverlayStyle) private var style

    var body: some View {
        let rect = SplitGeometry.dropRect(for: zone, in: card)
        style.makeBody(configuration: DropOverlayConfiguration(zone: zone, cornerRadius: tokens.metrics.cornerRadius))
            .frame(width: rect.width, height: rect.height)
            .position(x: rect.midX, y: rect.midY)
            .transition(.opacity)
            .animation(SplitKitStyleConstants.animation, value: rect)
    }
}
