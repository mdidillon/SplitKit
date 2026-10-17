import SwiftUI

/// The public design tokens read by every SplitKit style (Docs/Design.md §2).
///
/// Each built-in style ships its own defaults (`SplitKitTokens.glass`, `SplitKitTokens.plain`);
/// a host may override any token and inject the result with `.splitKitTokens(_:)`.
/// This file and `SplitKitStyleConstants.swift` are the only places SplitKit spells out visual values.
public struct SplitKitTokens: Equatable, Sendable {
    public struct Metrics: Equatable, Sendable {
        /// Height of the pane header row.
        public var headerHeight: CGFloat
        /// Visible thickness of the divider line.
        public var dividerThickness: CGFloat
        /// Width of the divider's pointer and drag area, centred on the divider (≥ `dividerThickness`).
        public var dividerHitWidth: CGFloat
        /// Corner radius of the pane card (content clip and drop overlay).
        public var cornerRadius: CGFloat
        /// Inset of each pane card inside its layout cell; the gap between cards is twice this.
        public var contentPadding: CGFloat

        public init(headerHeight: CGFloat, dividerThickness: CGFloat, dividerHitWidth: CGFloat,
                    cornerRadius: CGFloat, contentPadding: CGFloat) {
            self.headerHeight = headerHeight
            self.dividerThickness = dividerThickness
            self.dividerHitWidth = dividerHitWidth
            self.cornerRadius = cornerRadius
            self.contentPadding = contentPadding
        }
    }

    public struct GlassTokens: Equatable, Sendable {
        /// Liquid Glass variant for chrome; maps to `Glass.regular` / `Glass.clear`.
        public enum Variant: Equatable, Sendable { case regular, clear }

        public var variant: Variant
        /// Optional tint on chrome glass (`Glass.tint(_:)`).
        public var tint: Color?

        public init(variant: Variant, tint: Color?) {
            self.variant = variant
            self.tint = tint
        }
    }

    public struct Colors: Equatable, Sendable {
        /// Marks the active pane.
        public var activeIndicator: Color
        /// Stroke and tint of drop targets.
        public var dropHighlight: Color

        public init(activeIndicator: Color, dropHighlight: Color) {
            self.activeIndicator = activeIndicator
            self.dropHighlight = dropHighlight
        }
    }

    public var metrics: Metrics
    public var glass: GlassTokens
    public var colors: Colors

    public init(metrics: Metrics, glass: GlassTokens, colors: Colors) {
        self.metrics = metrics
        self.glass = glass
        self.colors = colors
    }

    /// Defaults of the `.glass` style (Docs/Design.md §2).
    public static let glass = SplitKitTokens(
        metrics: Metrics(headerHeight: 28, dividerThickness: 1, dividerHitWidth: 8, cornerRadius: 10, contentPadding: 4),
        glass: GlassTokens(variant: .regular, tint: nil),
        colors: Colors(activeIndicator: .accentColor, dropHighlight: .accentColor)
    )

    /// Defaults of the `.plain` style (Docs/Design.md §2). `.plain` draws no glass, so its glass group
    /// is not used; it carries the same values as `.glass`.
    public static let plain = SplitKitTokens(
        metrics: Metrics(headerHeight: 28, dividerThickness: 1, dividerHitWidth: 8, cornerRadius: 0, contentPadding: 0),
        glass: GlassTokens(variant: .regular, tint: nil),
        colors: Colors(activeIndicator: .accentColor, dropHighlight: .accentColor)
    )
}

extension SplitKitTokens.GlassTokens {
    /// The Liquid Glass these tokens describe.
    var effect: Glass {
        switch variant {
        case .regular: Glass.regular.tint(tint)
        case .clear: Glass.clear.tint(tint)
        }
    }
}

extension EnvironmentValues {
    @Entry var splitKitTokens: SplitKitTokens = .glass
}

extension View {
    /// Sets the design tokens read by SplitKit's styles in this view hierarchy.
    public func splitKitTokens(_ tokens: SplitKitTokens) -> some View {
        environment(\.splitKitTokens, tokens)
    }
}
