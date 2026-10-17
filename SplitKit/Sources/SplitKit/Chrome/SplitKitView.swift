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
        Group {
            if let layout = workspace.windowLayout(window) {
                if let root = layout.root {
                    SplitLayoutView(workspace: workspace, window: layout, root: root)
                } else {
                    EmptyContentView(workspace: workspace, target: .emptyWindow)
                }
            }
        }
        .closePrompt(of: workspace, in: window)
    }
}

/// The body of an empty pane or of a `.main` window with `root == nil` (§6.1.6), drawn by the
/// `EmptyPaneStyle` (Docs/Design.md §7). Add Content opens the content picker for `target`.
struct EmptyContentView: View {
    let workspace: SplitKitWorkspace
    let target: ContentPicker.Target
    @Environment(\.emptyPaneStyle) private var style
    @State private var isPickerPresented = false

    var body: some View {
        let picker = workspace.contentPicker(for: target)
        style.makeBody(configuration: EmptyPaneConfiguration(
            kind: target == .emptyWindow ? .emptyWindow : .emptyPane, title: ChromeText.emptyTitle, message: nil,
            primaryAction: .init(title: ChromeText.addContent, isEnabled: picker.isEnabled) { isPickerPresented = true }))
            .contentPicker(picker, in: workspace, isPresented: $isPickerPresented)
    }
}

/// The user-visible chrome strings (spec §7.1, §8). Header control labels live in `SplitKitStyleConstants`.
enum ChromeText {
    static let addContent = "Add Content"
    static let emptyTitle = "No Content"
    static let add = "Add"
    static let detach = "Detach"
    static let moveToWindow = "Move to Window"
    static let splitRight = "Split Right"
    static let splitDown = "Split Down"
    static let restore = "Restore"
    static let close = "Close"
    static let cancel = "Cancel"
    static let closeAll = "Close All"

    /// The unavailable placeholder's message (spec §8).
    static func unavailable(_ typeName: String) -> String { "\(typeName) isn't available in this app" }

    /// The window close prompt (spec §7.5).
    static func closeWindowTitle(panes: Int) -> String { "Close window with \(panes) panes?" }
    static let closeWindowMessage = "The content of every pane in this window will be closed."

    /// SplitKit's own confirmation for closing an unavailable placeholder (spec §6.3, §8).
    static func closePlaceholderTitle(_ typeName: String) -> String { "Close \(typeName)?" }
    static let closePlaceholderMessage = "The pane and its saved content will be removed."
}

extension SplitKitWorkspace {
    /// Runs `command` from a chrome control. Failures leave the workspace unchanged (§6.2); showing them
    /// to the user is part of a later task.
    func send(_ command: SplitKitCommand) {
        Task { try? await perform(command) }
    }
}
