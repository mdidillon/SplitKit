import SwiftUI

/// Draws the divider between two panes of a split. Works like `ButtonStyle`. The chrome sizes the
/// divider to `metrics.dividerHitWidth` and handles the pointer and dragging; the style fills that frame.
public protocol PaneDividerStyle {
    associatedtype Body: View
    @MainActor @ViewBuilder func makeBody(configuration: PaneDividerConfiguration) -> Body
}

public struct PaneDividerConfiguration {
    /// The axis along which the split lays out its panes; the divider line runs across it
    /// (`.horizontal`: panes side by side, vertical line).
    public let axis: Axis
    public let isHovered: Bool
    public let isDragging: Bool

    init(axis: Axis, isHovered: Bool = false, isDragging: Bool = false) {
        self.axis = axis
        self.isHovered = isHovered
        self.isDragging = isDragging
    }
}

// MARK: Type erasure and environment

struct AnyPaneDividerStyle {
    let style: any PaneDividerStyle

    init(_ style: some PaneDividerStyle) { self.style = style }

    @MainActor func makeBody(configuration: PaneDividerConfiguration) -> AnyView {
        AnyView(style.makeBody(configuration: configuration))
    }
}

extension EnvironmentValues {
    @Entry var paneDividerStyle = AnyPaneDividerStyle(GlassPaneDividerStyle())
}

extension View {
    /// Sets the style of split dividers in this view hierarchy.
    public func paneDividerStyle<S: PaneDividerStyle>(_ style: S) -> some View {
        environment(\.paneDividerStyle, AnyPaneDividerStyle(style))
    }
}

// MARK: Built-in styles

/// The default divider: a line only on hover and while dragging (Docs/Design.md §4.1).
public struct GlassPaneDividerStyle: PaneDividerStyle {
    public init() {}
    public func makeBody(configuration: PaneDividerConfiguration) -> some View {
        BuiltInPaneDivider(configuration: configuration, look: .glass)
    }
}

/// An always-visible divider line (Docs/Design.md §4.2).
public struct PlainPaneDividerStyle: PaneDividerStyle {
    public init() {}
    public func makeBody(configuration: PaneDividerConfiguration) -> some View {
        BuiltInPaneDivider(configuration: configuration, look: .plain)
    }
}

extension PaneDividerStyle where Self == GlassPaneDividerStyle {
    public static var glass: GlassPaneDividerStyle { GlassPaneDividerStyle() }
}

extension PaneDividerStyle where Self == PlainPaneDividerStyle {
    public static var plain: PlainPaneDividerStyle { PlainPaneDividerStyle() }
}

/// Which line a built-in divider shows (Docs/Design.md §4.1, §4.2, §7).
enum DividerLine: Equatable {
    case hidden, separator, accent

    init(_ configuration: PaneDividerConfiguration, look: BuiltInLook) {
        if configuration.isDragging {
            self = .accent
        } else if look == .plain || configuration.isHovered {
            self = .separator
        } else {
            self = .hidden
        }
    }
}

/// The one divider both built-in styles render.
struct BuiltInPaneDivider: View {
    let configuration: PaneDividerConfiguration
    let look: BuiltInLook
    @Environment(\.splitKitTokens) private var tokens

    var body: some View {
        ZStack {
            Color.clear
            switch DividerLine(configuration, look: look) {
            case .hidden: EmptyView()
            case .separator: line(SplitKitStyleConstants.Colors.separator)
            case .accent: line(tokens.colors.activeIndicator)
            }
        }
        .contentShape(Rectangle())
    }

    @ViewBuilder private func line(_ color: Color) -> some View {
        switch configuration.axis {
        case .horizontal: Rectangle().fill(color).frame(width: tokens.metrics.dividerThickness)
        case .vertical: Rectangle().fill(color).frame(height: tokens.metrics.dividerThickness)
        }
    }
}
