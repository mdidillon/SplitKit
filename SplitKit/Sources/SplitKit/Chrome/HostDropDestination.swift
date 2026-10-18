import SwiftUI
import SplitKitModel
import SplitKitWindows

/// Makes a host-owned window a pane drop destination (§9 `.host`): `SplitKitView` lays it over its content in
/// `.host` mode. It is the same `DockDropContainerView` the coordinator's windows use, in its overlay form,
/// asking the same `PaneDragController`, so drops dock into a host window exactly as into a SplitKit one.
/// It never touches the window or its frame.
struct HostDropDestination: NSViewRepresentable {
    let workspace: SplitKitWorkspace
    let window: WindowID

    /// True where `SplitKitView` must provide the destination itself: a main window in `.host` mode. The
    /// detached windows of `.host` mode belong to the window layer, which wraps their content already.
    static func isNeeded(by workspace: SplitKitWorkspace, window: WindowID) -> Bool {
        guard case .host = workspace.configuration.windowManagement else { return false }
        return workspace.windowLayout(window)?.kind == .main
    }

    func makeNSView(context: Context) -> DockDropContainerView {
        let view = DockDropContainerView(overlayFor: window)
        updateNSView(view, context: context)
        return view
    }

    func updateNSView(_ view: DockDropContainerView, context: Context) {
        view.delegate = workspace.dragController
    }
}
