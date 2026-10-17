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
            headerStyle.makeBody(configuration: headerConfiguration)
            contentBody
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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
            emptyStyle.makeBody(configuration: EmptyPaneConfiguration(
                kind: .emptyPane, title: ChromeText.emptyTitle, message: nil,
                primaryAction: workspace.addContentAction(into: pane)))
        }
    }

    private func activate() {
        guard window.activePane != pane else { return }
        workspace.send(.setActive(pane, in: window.id))
    }

    // MARK: Header

    private var headerConfiguration: PaneHeaderConfiguration {
        let metadata = content.flatMap(workspace.metadata(of:))
        return PaneHeaderConfiguration(
            title: title(metadata),
            systemImage: content == nil ? nil : metadata?.systemImage,
            showsFocusToggle: workspace.configuration.focusModeEnabled,
            isActive: window.activePane == pane,
            isPendingClose: workspace.runtime.pendingCloses.contains(pane),
            isEmpty: content == nil,
            isFocusMode: window.focusModePane == pane,
            menu: AnyView(paneMenu),
            toolbar: AnyView(EmptyView()),
            toggleFocusMode: { workspace.send(.toggleFocusMode(pane)) },
            close: { workspace.send(.closePane(pane)) })
    }

    /// The content's title; "Add Content" for an empty pane (spec §7.1); the type name for a placeholder.
    private func title(_ metadata: ContentRegistry.Metadata?) -> String {
        guard let content else { return ChromeText.addContent }
        if let object = workspace.store[content] { return object.title }
        return metadata?.displayName ?? workspace.record(content)?.type.raw ?? ChromeText.addContent
    }

    /// The structural items available now; the full pane menu (spec §7.1) comes with the header task.
    @ViewBuilder private var paneMenu: some View {
        Button(ChromeText.splitRight) { workspace.send(.split(pane, edge: .right)) }
        Button(ChromeText.splitDown) { workspace.send(.split(pane, edge: .bottom)) }
        Divider()
        Button(SplitKitStyleConstants.Accessibility.closeLabel) { workspace.send(.closePane(pane)) }
    }

    // MARK: Placeholder

    /// A pane whose content has no live object (spec §8): Restore comes with the persistence task.
    private func unavailableConfiguration(_ content: ContentID) -> EmptyPaneConfiguration {
        let metadata = workspace.metadata(of: content)
        let typeName = metadata?.displayName ?? workspace.record(content)?.type.raw ?? ""
        return EmptyPaneConfiguration(
            kind: .unavailable(systemImage: metadata?.systemImage), title: nil,
            message: ChromeText.unavailable(typeName),
            primaryAction: EmptyPaneConfiguration.Action(title: ChromeText.restore, isEnabled: false) {},
            secondaryAction: EmptyPaneConfiguration.Action(title: ChromeText.close) {
                workspace.send(.closePane(pane))
            })
    }
}

/// The view of one live content object, keyed by its `ContentID` so a swap or move re-hosts it instead
/// of reusing another content's view state. Registers with the `ContentStore` while on screen; a second
/// window hosting the same content is a programmer error (§6.4, §12).
struct HostedContentView: View {
    let object: any PaneContent
    let content: ContentID
    let window: WindowID
    let store: ContentStore

    var body: some View {
        object.makeView()
            .id(content)
            .onAppear {
                let hosted = store.beginHosting(content, in: window)
                assert(hosted, "content \(content) is already hosted in another window")
            }
            .onDisappear { store.endHosting(content, in: window) }
    }
}
