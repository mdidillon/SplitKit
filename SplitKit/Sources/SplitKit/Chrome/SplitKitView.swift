import SwiftUI
import SplitKitContent
import SplitKitModel

/// One window of a workspace (§5, §9 `.host` mode): its split tree, or the empty state of a main window
/// without panes. Renders nothing for a window that is not in the session.
public struct SplitKitView: View {
    let workspace: SplitKitWorkspace
    let window: WindowID

    public init(workspace: SplitKitWorkspace, window: WindowID) {
        self.workspace = workspace
        self.window = window
    }

    public var body: some View {
        if let layout = workspace.windowLayout(window) {
            if let root = layout.root {
                SplitLayoutView(workspace: workspace, window: layout, root: root)
            } else {
                EmptyWindowView(workspace: workspace)
            }
        }
    }
}

/// A `.main` window with `root == nil` (§6.1.6), drawn by the `EmptyPaneStyle` (Docs/Design.md §7).
struct EmptyWindowView: View {
    let workspace: SplitKitWorkspace
    @Environment(\.emptyPaneStyle) private var style

    var body: some View {
        style.makeBody(configuration: EmptyPaneConfiguration(
            kind: .emptyWindow, title: ChromeText.emptyTitle, message: nil,
            primaryAction: workspace.addContentAction(into: nil)))
    }
}

/// The user-visible chrome strings (spec §7.1, §8). Header control labels live in `SplitKitStyleConstants`.
enum ChromeText {
    static let addContent = "Add Content"
    static let emptyTitle = "No Content"
    static let splitRight = "Split Right"
    static let splitDown = "Split Down"
    static let restore = "Restore"
    static let close = "Close"

    /// The unavailable placeholder's message (spec §8).
    static func unavailable(_ typeName: String) -> String { "\(typeName) isn't available in this app" }
}

extension SplitKitWorkspace {
    /// Runs `command` from a chrome control. Failures leave the workspace unchanged (§6.2); showing them
    /// to the user is part of a later task.
    func send(_ command: SplitKitCommand) {
        Task { try? await perform(command) }
    }

    /// Add Content in an empty pane (`into`) or the empty window (`nil`). Until the content picker exists
    /// it adds the first registered type; disabled when nothing is registered.
    func addContentAction(into pane: PaneID?) -> EmptyPaneConfiguration.Action {
        let type = registry.registeredTypes.first
        return EmptyPaneConfiguration.Action(title: ChromeText.addContent, isEnabled: type != nil) {
            guard let type else { return }
            Task { try? await self.addContent(type, url: nil, into: pane) }
        }
    }
}
