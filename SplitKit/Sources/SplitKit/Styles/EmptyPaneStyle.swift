import SwiftUI

/// Draws the body of an empty pane, an empty window and the unavailable-content placeholder
/// (spec §7.1, §8; Docs/Design.md §7). Works like `ButtonStyle`.
public protocol EmptyPaneStyle {
    associatedtype Body: View
    @MainActor @ViewBuilder func makeBody(configuration: EmptyPaneConfiguration) -> Body
}

public struct EmptyPaneConfiguration {
    public enum Kind: Equatable, Sendable {
        /// A pane that hosts no content.
        case emptyPane
        /// A main window without panes.
        case emptyWindow
        /// A pane whose content type isn't available (spec §8); carries the type's SF Symbol when known.
        case unavailable(systemImage: String?)
    }

    /// A button the chrome supplies, e.g. Add Content, Restore or Close.
    public struct Action {
        public let title: String
        public let isEnabled: Bool
        private let action: @MainActor () -> Void

        @MainActor public func perform() { action() }

        init(title: String, isEnabled: Bool = true, action: @escaping @MainActor () -> Void) {
            self.title = title
            self.isEnabled = isEnabled
            self.action = action
        }
    }

    public let kind: Kind
    /// Title line; `nil` for the unavailable placeholder.
    public let title: String?
    /// Secondary text: a hint, or the unavailable message (spec §8).
    public let message: String?
    /// Add Content, or Restore for the placeholder.
    public let primaryAction: Action
    /// Close for the placeholder; `nil` otherwise.
    public let secondaryAction: Action?

    init(kind: Kind, title: String?, message: String?, primaryAction: Action, secondaryAction: Action? = nil) {
        self.kind = kind
        self.title = title
        self.message = message
        self.primaryAction = primaryAction
        self.secondaryAction = secondaryAction
    }
}

// MARK: State mapping shared by the built-in styles (Docs/Design.md §7)

extension EmptyPaneConfiguration {
    /// `plus.rectangle.on.rectangle` when empty; the type's symbol, or `questionmark.square.dashed`
    /// when unknown, for the placeholder.
    var symbol: String {
        switch kind {
        case .emptyPane, .emptyWindow: SplitKitStyleConstants.Symbols.emptyPane
        case .unavailable(let systemImage): systemImage ?? SplitKitStyleConstants.Symbols.unknownContent
        }
    }

    /// Add Content is prominent; Restore and Close are regular buttons.
    var primaryActionIsProminent: Bool {
        switch kind {
        case .emptyPane, .emptyWindow: true
        case .unavailable: false
        }
    }
}

// MARK: Type erasure and environment

struct AnyEmptyPaneStyle {
    let style: any EmptyPaneStyle

    init(_ style: some EmptyPaneStyle) { self.style = style }

    @MainActor func makeBody(configuration: EmptyPaneConfiguration) -> AnyView {
        AnyView(style.makeBody(configuration: configuration))
    }
}

extension EnvironmentValues {
    @Entry var emptyPaneStyle = AnyEmptyPaneStyle(GlassEmptyPaneStyle())
}

extension View {
    /// Sets the style of empty panes, empty windows and unavailable placeholders in this view hierarchy.
    public func emptyPaneStyle<S: EmptyPaneStyle>(_ style: S) -> some View {
        environment(\.emptyPaneStyle, AnyEmptyPaneStyle(style))
    }
}

// MARK: Built-in styles

/// The default empty state with glass buttons (Docs/Design.md §4.1).
public struct GlassEmptyPaneStyle: EmptyPaneStyle {
    public init() {}
    public func makeBody(configuration: EmptyPaneConfiguration) -> some View {
        BuiltInEmptyPane(configuration: configuration, look: .glass)
    }
}

/// The empty state with bordered buttons (Docs/Design.md §4.2).
public struct PlainEmptyPaneStyle: EmptyPaneStyle {
    public init() {}
    public func makeBody(configuration: EmptyPaneConfiguration) -> some View {
        BuiltInEmptyPane(configuration: configuration, look: .plain)
    }
}

extension EmptyPaneStyle where Self == GlassEmptyPaneStyle {
    public static var glass: GlassEmptyPaneStyle { GlassEmptyPaneStyle() }
}

extension EmptyPaneStyle where Self == PlainEmptyPaneStyle {
    public static var plain: PlainEmptyPaneStyle { PlainEmptyPaneStyle() }
}

/// The one empty-state composition both built-in styles render: symbol, title, message, buttons.
struct BuiltInEmptyPane: View {
    let configuration: EmptyPaneConfiguration
    let look: BuiltInLook

    private typealias Constants = SplitKitStyleConstants

    var body: some View {
        VStack(spacing: Constants.emptyStateSpacing) {
            Image(systemName: configuration.symbol)
                .font(Constants.Typography.emptyStateSymbol)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            if let title = configuration.title {
                Text(title)
                    .font(Constants.Typography.emptyStateTitle)
                    .foregroundStyle(.primary)
            }
            if let message = configuration.message {
                Text(message)
                    .font(Constants.Typography.emptyStateBody)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            HStack(spacing: Constants.emptyStateSpacing) {
                button(configuration.primaryAction)
                    .emptyStateButtonStyle(look, prominent: configuration.primaryActionIsProminent)
                if let secondary = configuration.secondaryAction {
                    button(secondary)
                        .emptyStateButtonStyle(look, prominent: false)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func button(_ action: EmptyPaneConfiguration.Action) -> some View {
        Button(action.title) { action.perform() }
            .disabled(!action.isEnabled)
    }
}
