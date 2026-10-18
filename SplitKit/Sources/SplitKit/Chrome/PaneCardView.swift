import SwiftUI
import SplitKitContent
import SplitKitModel

/// One pane card (Docs/Design.md §4): the header through the `PaneHeaderStyle`, then the content's
/// view, an empty pane or an unavailable placeholder, clipped to `metrics.cornerRadius` and inset by
/// `metrics.contentPadding` inside its layout cell. A click anywhere in the card makes it the active pane.
struct PaneCardView: View {
    let workspace: SplitKitWorkspace
    let window: WindowLayout
    let pane: PaneID
    let content: ContentID?
    @Environment(\.splitKitTokens) private var tokens
    @Environment(\.paneHeaderStyle) private var headerStyle
    @Environment(\.emptyPaneStyle) private var emptyStyle

    var body: some View {
        VStack(spacing: 0) {
            header
            contentBody
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .draggedSourceOpacity(workspace.draggedPane == pane)
                .creationFailureBanner(workspace, at: .pane(pane))
        }
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: tokens.metrics.cornerRadius, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: tokens.metrics.cornerRadius, style: .continuous))
        .simultaneousGesture(TapGesture().onEnded { activate() })
        .padding(tokens.metrics.contentPadding)
    }

    @ViewBuilder private var contentBody: some View {
        if let content {
            if let object = workspace.store[content] {
                HostedContentView(object: object, content: content, window: window.id, store: workspace.store)
            } else {
                emptyStyle.makeBody(configuration: unavailableConfiguration(content))
            }
        } else {
            EmptyContentView(workspace: workspace, target: .emptyPane(pane))
        }
    }

    private func activate() {
        workspace.activate(pane)
    }

    // MARK: Header

    /// The header through the style; right-click opens the same pane menu as the title ▾ (spec §7.1).
    private var header: some View {
        let configuration = workspace.headerConfiguration(for: pane, in: window, content: content)
        return headerStyle.makeBody(configuration: configuration)
            .contextMenu { configuration.menu }
            .overlay(alignment: .leading) {
                PaneDragHandle(workspace: workspace, pane: pane)
                    .frame(width: tokens.metrics.headerHeight, height: tokens.metrics.headerHeight)
                    .allowsHitTesting(!configuration.isPendingClose)
            }
    }

    // MARK: Placeholder

    /// A pane whose content has no live object (spec §8). Restore is enabled once the registry has the type
    /// (and no close is pending) and runs `restoreUnavailable`; a failed retry keeps the placeholder with the
    /// "couldn't be restored" message. Close asks SplitKit's own confirmation (`closePane`).
    private func unavailableConfiguration(_ content: ContentID) -> EmptyPaneConfiguration {
        let isClosing = workspace.isClosing(pane: pane)
        let typeName = workspace.typeName(of: content) ?? ""
        let message = if case .restoreFailed = workspace.unavailableReasons[content] {
            ChromeText.restoreFailed(typeName)
        } else {
            ChromeText.unavailable(typeName)
        }
        return EmptyPaneConfiguration(
            kind: .unavailable(systemImage: workspace.metadata(of: content)?.systemImage), title: nil,
            message: message,
            primaryAction: EmptyPaneConfiguration.Action(
                title: ChromeText.restore, isEnabled: !isClosing && workspace.metadata(of: content) != nil) {
                try? workspace.restoreUnavailable(content)
            },
            secondaryAction: EmptyPaneConfiguration.Action(title: ChromeText.close, isEnabled: !isClosing) {
                workspace.send(.closePane(pane))
            })
    }
}

/// The view of one live content object, keyed by its `ContentID` so a swap or move re-hosts it instead
/// of reusing another content's view state. Registers with the `ContentStore` while on screen; a second
/// window hosting the same content is a programmer error (§6.4, §12). Opening a window renders it at once,
/// so after a detach, Move to Window or Dock Back the destination can render before the source window has
/// dropped the view: the destination shows nothing until the source lets go (§6.2: re-host after the windows
/// are created).
struct HostedContentView: View {
    let object: any PaneContent
    let content: ContentID
    let window: WindowID
    let store: ContentStore

    var body: some View {
        if store.canHost(content, in: window) {
            object.makeView()
                .id(content)
                .onAppear {
                    let hosted = store.beginHosting(content, in: window)
                    assert(hosted, "content \(content) is already hosted in another window")
                }
                .onDisappear { store.endHosting(content, in: window) }
        }
    }
}
