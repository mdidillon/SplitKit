import SwiftUI
import SplitKitModel

/// A confirmation of the close UI (spec §7.5, §8): the one window prompt, or SplitKit's own confirmation for
/// an unavailable placeholder. Runtime-only; the window that hosts the pane shows it as an alert.
struct ClosePrompt: Equatable, Identifiable {
    enum Kind: Equatable {
        /// "Close window with N panes?" with Close All / Cancel (spec §7.5).
        case window(panes: Int)
        /// Close of an unavailable placeholder, which has no `shouldClose()` (spec §6.3.2, §8).
        case placeholder(typeName: String)
    }

    let id: Int
    let window: WindowID
    let kind: Kind

    var title: String {
        switch kind {
        case let .window(panes): ChromeText.closeWindowTitle(panes: panes)
        case let .placeholder(typeName): ChromeText.closePlaceholderTitle(typeName)
        }
    }

    var message: String {
        switch kind {
        case .window: ChromeText.closeWindowMessage
        case .placeholder: ChromeText.closePlaceholderMessage
        }
    }

    var confirmTitle: String {
        switch kind {
        case .window: ChromeText.closeAll
        case .placeholder: ChromeText.close
        }
    }
}

extension SplitKitWorkspace {
    /// The confirmation closing `window` needs, or nil. Two or more panes with content (hosted or
    /// placeholder) get the one window prompt; a window whose only content is a placeholder gets the
    /// placeholder's confirmation. Empty panes never count.
    func closePromptKind(forWindow window: WindowID) -> ClosePrompt.Kind? {
        let contents = windowLayout(window)?.root?.leaves.compactMap(\.content) ?? []
        if contents.count > 1 { return .window(panes: contents.count) }
        if let only = contents.first, store[only] == nil { return .placeholder(typeName: typeName(of: only) ?? "") }
        return nil
    }
}

extension View {
    /// Presents the workspace's current close prompt as an alert when it belongs to `window`. Dismissing
    /// the alert any other way than Close answers it with Cancel.
    func closePrompt(of workspace: SplitKitWorkspace, in window: WindowID) -> some View {
        let prompt = workspace.closePrompt.flatMap { $0.window == window ? $0 : nil }
        return alert(
            prompt?.title ?? "",
            isPresented: Binding(
                get: { prompt != nil },
                set: { if !$0, let prompt { workspace.answer(prompt, confirmed: false) } }),
            presenting: prompt
        ) { prompt in
            Button(prompt.confirmTitle, role: .destructive) { workspace.answer(prompt, confirmed: true) }
            Button(ChromeText.cancel, role: .cancel) { workspace.answer(prompt, confirmed: false) }
        } message: { prompt in
            Text(prompt.message)
        }
    }
}
