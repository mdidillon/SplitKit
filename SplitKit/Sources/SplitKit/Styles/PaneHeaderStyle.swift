import SwiftUI

/// Draws a pane header (spec §7.1, Docs/Design.md §6–§7). Works like `ButtonStyle`: SplitKit's chrome
/// builds a `PaneHeaderConfiguration` and the style arranges and decorates it.
public protocol PaneHeaderStyle {
    associatedtype Body: View
    @MainActor @ViewBuilder func makeBody(configuration: PaneHeaderConfiguration) -> Body
}

/// Everything a `PaneHeaderStyle` needs, without any knowledge of the workspace model.
///
/// The chrome resolves the model into display values and state flags, and supplies the parts whose
/// behaviour it owns as type-erased `Element`s: the pane menu's items and the laid-out content toolbar
/// (including its overflow, spec §7.4). Focus and close are actions the style triggers.
public struct PaneHeaderConfiguration {
    /// A view supplied by the chrome, type-erased like `ButtonStyleConfiguration.Label`.
    public struct Element: View {
        let content: AnyView
        public var body: some View { content }
    }

    /// The content's title, or "Add Content" for an empty pane (spec §7.1).
    public let title: String
    /// The content type's SF Symbol; `nil` for an empty pane.
    public let systemImage: String?
    /// `false` when both rearrange and detach are disabled (spec §7.1).
    public let showsDragHandle: Bool
    /// `false` when focus mode is disabled in `SplitKitConfiguration`.
    public let showsFocusToggle: Bool

    /// The window's `activePane` (spec §7.3).
    public let isActive: Bool
    public let isHovered: Bool
    /// The pane is the current drop target of a drag.
    public let isDropTarget: Bool
    /// The pane is the source of the current drag.
    public let isDraggedSource: Bool
    /// A two-stage close is waiting for the content (spec §6.3).
    public let isPendingClose: Bool
    /// The pane hosts no content.
    public let isEmpty: Bool
    /// The pane is the window's `focusModePane`.
    public let isFocusMode: Bool

    /// The items of the title ▾ menu (content picker / pane menu, spec §7.1).
    public let menu: Element
    /// The content toolbar items, already laid out with their overflow (spec §7.4).
    public let toolbar: Element

    private let toggleFocusModeAction: @MainActor () -> Void
    private let closeAction: @MainActor () -> Void

    /// Enters or leaves focus mode for this pane.
    @MainActor public func toggleFocusMode() { toggleFocusModeAction() }
    /// Starts closing this pane (spec §6.3).
    @MainActor public func close() { closeAction() }

    @MainActor init(title: String, systemImage: String?, showsDragHandle: Bool = true, showsFocusToggle: Bool = true,
         isActive: Bool = false, isHovered: Bool = false, isDropTarget: Bool = false, isDraggedSource: Bool = false,
         isPendingClose: Bool = false, isEmpty: Bool = false, isFocusMode: Bool = false,
         menu: AnyView, toolbar: AnyView,
         toggleFocusMode: @escaping @MainActor () -> Void, close: @escaping @MainActor () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.showsDragHandle = showsDragHandle
        self.showsFocusToggle = showsFocusToggle
        self.isActive = isActive
        self.isHovered = isHovered
        self.isDropTarget = isDropTarget
        self.isDraggedSource = isDraggedSource
        self.isPendingClose = isPendingClose
        self.isEmpty = isEmpty
        self.isFocusMode = isFocusMode
        self.menu = Element(content: menu)
        self.toolbar = Element(content: toolbar)
        self.toggleFocusModeAction = toggleFocusMode
        self.closeAction = close
    }
}

// MARK: State mapping shared by the built-in styles (Docs/Design.md §5–§7)

/// Foreground emphasis of chrome that shows the active state.
enum ChromeEmphasis: Equatable {
    case primary, secondary

    var style: HierarchicalShapeStyle {
        switch self {
        case .primary: .primary
        case .secondary: .secondary
        }
    }
}

extension PaneHeaderConfiguration {
    /// Content icon and title: `.primary` when active, `.secondary` when inactive (§6, §7).
    var emphasis: ChromeEmphasis { isActive ? .primary : .secondary }

    /// The focus toggle's symbol: enter outside focus mode, exit inside it (§6).
    var focusSymbol: String {
        isFocusMode ? SplitKitStyleConstants.Symbols.exitFocusMode : SplitKitStyleConstants.Symbols.enterFocusMode
    }

    /// The active pane carries `.isSelected` (§5).
    var accessibilityTraits: AccessibilityTraits { isActive ? .isSelected : [] }

    /// A pending close exposes the value "Closing" (§5).
    var accessibilityValue: String? { isPendingClose ? SplitKitStyleConstants.Accessibility.pendingCloseValue : nil }

    /// The focus toggle exposes "On" in focus mode and "Off" otherwise (§5).
    var focusToggleAccessibilityValue: String {
        isFocusMode ? SplitKitStyleConstants.Accessibility.focusOnValue : SplitKitStyleConstants.Accessibility.focusOffValue
    }

    /// While a close is pending, every control except the close slot is disabled (§7).
    var controlsDisabled: Bool { isPendingClose }
}

// MARK: Type erasure and environment

struct AnyPaneHeaderStyle {
    let style: any PaneHeaderStyle

    init(_ style: some PaneHeaderStyle) { self.style = style }

    @MainActor func makeBody(configuration: PaneHeaderConfiguration) -> AnyView {
        AnyView(style.makeBody(configuration: configuration))
    }
}

extension EnvironmentValues {
    @Entry var paneHeaderStyle = AnyPaneHeaderStyle(GlassPaneHeaderStyle())
}

extension View {
    /// Sets the style of pane headers in this view hierarchy.
    public func paneHeaderStyle<S: PaneHeaderStyle>(_ style: S) -> some View {
        environment(\.paneHeaderStyle, AnyPaneHeaderStyle(style))
    }
}

// MARK: Built-in styles

/// The default header style: glass pills in one glass container (Docs/Design.md §4.1).
public struct GlassPaneHeaderStyle: PaneHeaderStyle {
    public init() {}
    public func makeBody(configuration: PaneHeaderConfiguration) -> some View {
        BuiltInPaneHeader(configuration: configuration, look: .glass)
    }
}

/// An opaque header with borderless controls (Docs/Design.md §4.2).
public struct PlainPaneHeaderStyle: PaneHeaderStyle {
    public init() {}
    public func makeBody(configuration: PaneHeaderConfiguration) -> some View {
        BuiltInPaneHeader(configuration: configuration, look: .plain)
    }
}

extension PaneHeaderStyle where Self == GlassPaneHeaderStyle {
    public static var glass: GlassPaneHeaderStyle { GlassPaneHeaderStyle() }
}

extension PaneHeaderStyle where Self == PlainPaneHeaderStyle {
    public static var plain: PlainPaneHeaderStyle { PlainPaneHeaderStyle() }
}

/// The one header row both built-in styles render (Docs/Design.md §4, §6, §7, §8).
struct BuiltInPaneHeader: View {
    let configuration: PaneHeaderConfiguration
    let look: BuiltInLook
    @Environment(\.splitKitTokens) private var tokens

    private typealias Constants = SplitKitStyleConstants

    var body: some View {
        HStack(spacing: Constants.headerItemSpacing) {
            if configuration.showsDragHandle {
                Image(systemName: Constants.Symbols.dragHandle)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            if let systemImage = configuration.systemImage {
                Image(systemName: systemImage)
                    .foregroundStyle(configuration.emphasis.style)
                    .accessibilityHidden(true)
            }
            HeaderControlGroup(look: look) {
                HStack(spacing: Constants.headerItemSpacing) {
                    titleMenu
                    Spacer(minLength: 0)
                    configuration.toolbar
                        .font(Constants.Typography.toolbarLabel)
                        .headerControlGlass(look, tokens: tokens)
                        .disabled(configuration.controlsDisabled)
                    if configuration.showsFocusToggle {
                        focusToggle
                    }
                    closeSlot
                }
            }
        }
        .headerControlStyle()
        .padding(.horizontal, Constants.headerHorizontalPadding)
        .frame(maxWidth: .infinity, minHeight: tokens.metrics.headerHeight, maxHeight: tokens.metrics.headerHeight)
        .background { background }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Constants.Colors.separator)
                .frame(height: tokens.metrics.dividerThickness)
        }
        .overlay(alignment: .top) {
            if configuration.isActive {
                Rectangle()
                    .fill(tokens.colors.activeIndicator)
                    .frame(height: Constants.activeIndicatorThickness)
            }
        }
        .draggedSourceOpacity(configuration.isDraggedSource)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(configuration.title)
        .animation(Constants.animation, value: configuration.isActive)
        .animation(Constants.animation, value: configuration.isPendingClose)
        .animation(Constants.animation, value: configuration.isDropTarget)
    }

    @ViewBuilder private var background: some View {
        switch look {
        case .glass: EmptyView()
        case .plain: Constants.Colors.plainHeaderBackground
        }
    }

    private var titleMenu: some View {
        Menu {
            configuration.menu
        } label: {
            HStack(spacing: Constants.headerItemSpacing) {
                Text(configuration.title)
                    .font(Constants.Typography.headerTitle)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Image(systemName: Constants.Symbols.titleMenuIndicator)
            }
            .foregroundStyle(configuration.emphasis.style)
        }
        .headerControlGlass(look, tokens: tokens)
        .disabled(configuration.controlsDisabled)
        .help(configuration.title)
        .accessibilityLabel(configuration.title)
        .accessibilityValue(configuration.accessibilityValue ?? "")
        .accessibilityAddTraits(configuration.accessibilityTraits)
    }

    private var focusToggle: some View {
        Button {
            configuration.toggleFocusMode()
        } label: {
            Label(Constants.Accessibility.focusToggleLabel, systemImage: configuration.focusSymbol)
                .labelStyle(.iconOnly)
        }
        .headerControlGlass(look, tokens: tokens)
        .disabled(configuration.controlsDisabled)
        .help(Constants.Accessibility.focusToggleLabel)
        .accessibilityValue(configuration.focusToggleAccessibilityValue)
    }

    @ViewBuilder private var closeSlot: some View {
        if configuration.isPendingClose {
            ProgressView()
                .accessibilityLabel(Constants.Accessibility.closeLabel)
                .accessibilityValue(Constants.Accessibility.pendingCloseValue)
        } else {
            Button {
                configuration.close()
            } label: {
                Label(Constants.Accessibility.closeLabel, systemImage: Constants.Symbols.close)
                    .labelStyle(.iconOnly)
            }
            .headerControlGlass(look, tokens: tokens)
            .help(Constants.Accessibility.closeLabel)
        }
    }
}
