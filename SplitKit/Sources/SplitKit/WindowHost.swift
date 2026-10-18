import AppKit
import SwiftUI
import SplitKitModel
import SplitKitWindows

/// What a workspace asks of the window layer. It is called only after a transaction succeeded, in the
/// §6.2 side-effect order (create windows → re-host → release → close windows → snapshot).
@MainActor protocol WorkspaceWindowHost: AnyObject {
    /// Shows windows of the session that have none yet.
    func open(_ windows: [WindowID])
    func close(_ windows: [WindowID])
    func bringForward(_ window: WindowID)
    /// Hands over user moves and resizes that are still being coalesced (before a snapshot).
    func flushPendingPlacements()
}

/// Connects a workspace to a `WindowCoordinator` (§5, §9). Each window shows `SplitKitView` for its
/// `WindowID`, so the coordinator never sees SplitKit UI types (§3). User actions on a window come back as
/// workspace calls: a move or resize as its new placement, the close button as the two-stage `closeWindow`
/// (§6.3.4), key changes as `keyWindow`. The coordinator is created with the first window, so a workspace
/// that never shows one creates no AppKit objects.
///
/// `.splitKit` mode: it opens and closes every window. `.host` mode: the host owns the main window, so only
/// detached windows are opened here, created by the host's `makeDetachedWindow` when given (SplitKit then
/// sets no frame on it), else by SplitKit.
@MainActor final class CoordinatedWindows: WorkspaceWindowHost {
    private weak var workspace: SplitKitWorkspace?
    private var coordinator: WindowCoordinator?
    /// False in tests, which place real windows without showing them (`WindowCoordinator.showsWindows`).
    var showsWindows = true

    init(workspace: SplitKitWorkspace) {
        self.workspace = workspace
    }

    func open(_ windows: [WindowID]) {
        guard let workspace else { return }
        let tokens = EnvironmentValues().splitKitTokens
        for id in windows {
            guard let layout = workspace.windowLayout(id) else { continue }
            var hostWindow: NSWindow?
            if case let .host(makeDetachedWindow) = workspace.configuration.windowManagement {
                guard layout.kind == .detached else { continue }
                hostWindow = makeDetachedWindow?(id)
            }
            makeCoordinator(workspace).open(id, placement: layout.placement,
                                            contentMinSize: workspace.minimumContentSize(of: id, tokens: tokens),
                                            hostWindow: hostWindow)
        }
    }

    func close(_ windows: [WindowID]) {
        for id in windows { coordinator?.close(id) }
    }

    func bringForward(_ window: WindowID) {
        coordinator?.bringForward(window)
    }

    func flushPendingPlacements() {
        coordinator?.flushPendingPlacements()
    }

    /// The root view of a window: `CoordinatedWindowView`, passed through the host's
    /// `configuration.windowContent` hook when there is one. The one place window content is built.
    static func content(of workspace: SplitKitWorkspace, window: WindowID,
                        setMinimumSize: @escaping @MainActor (CGSize) -> Void) -> AnyView {
        let view = AnyView(CoordinatedWindowView(workspace: workspace, window: window, setMinimumSize: setMinimumSize))
        return workspace.configuration.windowContent?(view) ?? view
    }

    private func makeCoordinator(_ workspace: SplitKitWorkspace) -> WindowCoordinator {
        if let coordinator { return coordinator }
        let coordinator = WindowCoordinator { [weak self, unowned workspace] id in
            let view = NSHostingView(rootView: Self.content(of: workspace, window: id) { size in
                self?.coordinator?.setContentMinSize(size, for: id)
            })
            view.sizingOptions = []          // the window's size limits come from `contentMinSize` only
            return view
        }
        coordinator.onUserPlacementChange = { [weak workspace] in workspace?.userPlaced($0, $1) }
        coordinator.onCloseRequest = { [weak workspace] in workspace?.send(.closeWindow($0)) }
        coordinator.onKeyWindowChange = { [weak workspace] in workspace?.keyWindowChanged($0) }
        coordinator.dockDelegate = workspace.dragController
        coordinator.showsWindows = showsWindows
        self.coordinator = coordinator
        return coordinator
    }
}

/// The content of a coordinator window: `SplitKitView`, reporting the window's minimum content size
/// whenever the tree or the tokens change it.
private struct CoordinatedWindowView: View {
    let workspace: SplitKitWorkspace
    let window: WindowID
    let setMinimumSize: @MainActor (CGSize) -> Void
    @Environment(\.splitKitTokens) private var tokens

    var body: some View {
        let minimum = workspace.minimumContentSize(of: window, tokens: tokens)
        SplitKitView(workspace: workspace, window: window)
            .onChange(of: minimum) { setMinimumSize(minimum) }
    }
}
