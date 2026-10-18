import AppKit
import SplitKitModel

/// Where *Pane ▸ Detach* and *Move to Window* place a new detached window (§9): the source window's frame
/// offset by 24 pt, resolved against the displays with the new window's content minimum. Pure over its inputs.
package enum DetachPlacement {
    /// Down and to the right, in AppKit's y-up space.
    package static let offset: CGFloat = 24

    /// The `SavedPlacement` of the detached window: `source` moved by `offset`, `DisplayPlacement.resolve`d with
    /// `contentMinSize` (turned into a frame minimum by the title bar of the coordinator's windows), and written
    /// back with `DisplayPlacement.placement(writing:displays:)`, so it is exactly the frame the window gets.
    @MainActor package static func placement(from source: CGRect, contentMinSize: CGSize, displays: [DisplaySnapshot]) -> SavedPlacement {
        let moved = source.offsetBy(dx: offset, dy: -offset)
        let minimum = NSWindow.frameRect(forContentRect: CGRect(origin: .zero, size: contentMinSize),
                                         styleMask: WindowCoordinator.styleMask).size
        let resolved = DisplayPlacement.resolve(DisplayPlacement.placement(writing: moved, displays: displays),
                                                minSize: minimum, displays: displays)
        return DisplayPlacement.placement(writing: resolved, displays: displays)
    }

    /// The displays as they are now (`NSScreen.screens`).
    @MainActor package static func currentDisplays() -> [DisplaySnapshot] {
        ScreenAdapter.currentDisplays()
    }
}
