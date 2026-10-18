import AppKit
import SwiftUI

/// Transparent AppKit overlay that maps raw trackpad and mouse events onto the spec §10 camera contract:
///
/// | Event | Action |
/// |---|---|
/// | left-drag / one-finger click-drag | orbit |
/// | ⇧ + left-drag, middle-drag | pan |
/// | scroll with precise deltas (trackpad two-finger) | pan |
/// | scroll without precise deltas (mouse wheel) | dolly |
/// | pinch (magnify) | dolly |
struct CameraInputView: NSViewRepresentable {
    let stage: ModelStage

    func makeNSView(context: Context) -> InputNSView {
        let view = InputNSView()
        view.stage = stage
        return view
    }

    func updateNSView(_ view: InputNSView, context: Context) {
        view.stage = stage
    }

    final class InputNSView: NSView {
        weak var stage: ModelStage?

        override var acceptsFirstResponder: Bool { true }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func layout() {
            super.layout()
            stage?.viewportSize = bounds.size
        }

        // The press goes on to the pane card (click activates the pane); the drag then comes to this view.
        override func mouseDown(with event: NSEvent) {
            window?.makeFirstResponder(self)
            super.mouseDown(with: event)
        }

        override func mouseDragged(with event: NSEvent) {
            if event.modifierFlags.contains(.shift) {
                stage?.pan(dx: event.deltaX, dy: event.deltaY)
            } else {
                stage?.orbit(dx: event.deltaX, dy: event.deltaY)
            }
        }

        override func otherMouseDragged(with event: NSEvent) {
            stage?.pan(dx: event.deltaX, dy: event.deltaY)
        }

        override func scrollWheel(with event: NSEvent) {
            if event.hasPreciseScrollingDeltas {
                // Trackpad (and Magic Mouse surface): content follows the fingers.
                stage?.pan(dx: event.scrollingDeltaX, dy: event.scrollingDeltaY)
            } else {
                stage?.scrollZoom(dy: event.scrollingDeltaY)
            }
        }

        override func magnify(with event: NSEvent) {
            stage?.pinch(event.magnification)
        }
    }
}
