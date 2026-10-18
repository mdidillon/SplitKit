import SwiftUI
import SplitKitContent
import SplitKitModel

extension SplitKitWorkspace {
    /// The header of `pane` resolved from the workspace (spec §7.1): title and icon from the content and the
    /// registry metadata, the state flags from the window and runtime, the pane menu and the content toolbar.
    func headerConfiguration(for pane: PaneID, in window: WindowLayout, content: ContentID?) -> PaneHeaderConfiguration {
        let metadata = content.flatMap(self.metadata(of:))
        let isActive = window.activePane == pane
        let items = content.flatMap { store[$0] }?.toolbarItems ?? []
        return PaneHeaderConfiguration(
            title: title(of: content, metadata: metadata),
            systemImage: content == nil ? nil : metadata?.systemImage,
            showsFocusToggle: configuration.focusModeEnabled,
            isActive: isActive,
            isDropTarget: isDropTarget(pane),
            isDraggedSource: draggedPane == pane,
            isPendingClose: isClosing(pane: pane),
            isEmpty: content == nil,
            isFocusMode: window.focusModePane == pane,
            menu: AnyView(PaneMenu(workspace: self, model: paneMenuModel(for: pane, content: content))),
            region: { title, decorate in
                AnyView(PaneToolbarRegion(items: items, title: title,
                                          decorateToolbar: { decorate(.init(content: $0)) }))
            },
            toggleFocusMode: { [self] in send(.toggleFocusMode(pane)) },
            close: { [self] in send(.closePane(pane)) })
    }

    /// The pane is the target of the drag that is running (§9).
    private func isDropTarget(_ pane: PaneID) -> Bool {
        if case .pane(pane, _) = dockTarget { true } else { false }
    }

    /// The content's title; "Add Content" for an empty pane (spec §7.1); the type name for a placeholder.
    private func title(of content: ContentID?, metadata: ContentRegistry.Metadata?) -> String {
        guard let content else { return ChromeText.addContent }
        if let object = store[content] { return object.title }
        return typeName(of: content) ?? ChromeText.addContent
    }
}
