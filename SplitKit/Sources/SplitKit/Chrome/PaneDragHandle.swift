import SwiftUI
import SplitKitModel
import SplitKitWindows

/// The AppKit drag source over the drag handle of a pane header (spec §9, §11.1). The chrome puts it over the
/// handle's corner of the header (`metrics.headerHeight` square, leading); the drag itself, the threshold and
/// the click-to-activate live in `PaneDragSourceView`, and the session in the workspace's `PaneDragController`.
struct PaneDragHandle: NSViewRepresentable {
    let workspace: SplitKitWorkspace
    let pane: PaneID

    func makeNSView(context: Context) -> PaneDragSourceView {
        PaneDragSourceView()
    }

    func updateNSView(_ view: PaneDragSourceView, context: Context) {
        view.pane = pane
        view.delegate = workspace.dragController
    }
}
