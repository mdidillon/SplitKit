import SwiftUI

/// The look a built-in style renders (Docs/Design.md §4.1 `.glass`, §4.2 `.plain`). The built-in
/// header, divider and empty-pane views are shared by both styles and branch only on this value.
enum BuiltInLook: Equatable, Sendable {
    case glass, plain
}

private typealias Constants = SplitKitStyleConstants

extension View {
    /// Header buttons, menus and toggles: borderless controls in both looks (§4.1, §4.2), at the header
    /// control size and symbol scale (§3). The `.glass` glass comes from `headerControlGlass`. Menus draw
    /// their own ▾ (§6), so the system indicator is hidden.
    func headerControlStyle() -> some View {
        buttonStyle(.borderless)
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .controlSize(Constants.headerControlSize)
            .imageScale(Constants.headerSymbolScale)
    }

    /// The token-driven glass pill behind one header control in `.glass` (§4.1); `.plain` adds nothing.
    @ViewBuilder
    func headerControlGlass(_ look: BuiltInLook, tokens: SplitKitTokens) -> some View {
        switch look {
        case .glass: glassEffect(tokens.glass.effect.interactive(), in: .capsule)
        case .plain: self
        }
    }

    /// Buttons in the empty pane, empty window and unavailable placeholder (§4.1, §4.2, §7).
    @ViewBuilder
    func emptyStateButtonStyle(_ look: BuiltInLook, prominent: Bool) -> some View {
        switch (look, prominent) {
        case (.glass, true): buttonStyle(.glassProminent)
        case (.glass, false): buttonStyle(.glass)
        case (.plain, true): buttonStyle(.borderedProminent)
        case (.plain, false): buttonStyle(.bordered)
        }
    }

    /// Header and content of the pane being dragged (§3, §7).
    func draggedSourceOpacity(_ isDraggedSource: Bool) -> some View {
        opacity(isDraggedSource ? Constants.draggedSourceOpacity : 1)
    }
}

/// Wraps the header controls in one `GlassEffectContainer` for `.glass` (§4.1); `.plain` uses none.
struct HeaderControlGroup<Content: View>: View {
    let look: BuiltInLook
    @ViewBuilder let content: Content

    var body: some View {
        switch look {
        case .glass: GlassEffectContainer(spacing: Constants.headerItemSpacing) { content }
        case .plain: content
        }
    }
}
