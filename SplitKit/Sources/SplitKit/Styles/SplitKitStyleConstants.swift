import SwiftUI

/// Internal style values every style needs that are not public tokens (Docs/Design.md §3), plus the
/// semantic colours (§4.3), header symbols (§6, §7) and text styles (§8) the built-in styles use.
/// This is the only place these values live; changing one is a change to Docs/Design.md first.
enum SplitKitStyleConstants {
    // §3
    static let headerHorizontalPadding: CGFloat = 6
    static let headerItemSpacing: CGFloat = 4
    static let headerControlSize: ControlSize = .small
    static let headerSymbolScale: Image.Scale = .small
    static let headerTitleMinWidth: CGFloat = 64
    static let activeIndicatorThickness: CGFloat = 2
    static let dropOverlayFillOpacity: Double = 0.18
    static let dropOverlayStroke: CGFloat = 2
    static let draggedSourceOpacity: Double = 0.5
    static let emptyStateSymbolSize: CGFloat = 28
    static let emptyStateSpacing: CGFloat = 8
    static let animation: Animation = .smooth

    /// §4.3 semantic colours.
    enum Colors {
        static let separator = Color(nsColor: .separatorColor)
        /// `.plain` header row background (§4.2).
        static let plainHeaderBackground = Color(nsColor: .windowBackgroundColor)
    }

    /// §6 and §7 SF Symbols.
    enum Symbols {
        static let dragHandle = "line.3.horizontal"
        static let titleMenuIndicator = "chevron.down"
        static let overflow = "ellipsis"
        static let enterFocusMode = "arrow.up.left.and.arrow.down.right"
        static let exitFocusMode = "arrow.down.right.and.arrow.up.left"
        static let close = "xmark"
        static let emptyPane = "plus.rectangle.on.rectangle"
        static let unknownContent = "questionmark.square.dashed"
    }

    /// §8 typography.
    enum Typography {
        static let headerTitle: Font = .callout.weight(.medium)
        static let toolbarLabel: Font = .callout
        static let emptyStateSymbol: Font = .system(size: emptyStateSymbolSize)
        static let emptyStateTitle: Font = .title3
        static let emptyStateBody: Font = .callout
    }

    /// §5 accessibility strings.
    enum Accessibility {
        static let pendingCloseValue = "Closing"
        static let focusOnValue = "On"
        static let focusOffValue = "Off"
        static let focusToggleLabel = "Focus Pane"
        static let closeLabel = "Close Pane"
        static let overflowLabel = "More"
    }
}
