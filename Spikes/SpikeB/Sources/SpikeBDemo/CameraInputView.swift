import AppKit
import SwiftUI

/// Transparent AppKit overlay that maps raw trackpad/mouse events onto the §10 camera contract:
///
/// | Event | Action |
/// |---|---|
/// | left-drag / one-finger click-drag | orbit |
/// | ⇧ + left-drag, middle-drag | pan |
/// | scroll with precise deltas (trackpad two-finger) | pan |
/// | scroll without precise deltas (mouse wheel) | dolly |
/// | pinch (magnify) | dolly |
struct CameraInputView: NSViewRepresentable {
    let model: ViewerModel

    func makeNSView(context: Context) -> InputNSView {
        let view = InputNSView()
        view.model = model
        return view
    }

    func updateNSView(_ view: InputNSView, context: Context) {
        view.model = model
    }

    final class InputNSView: NSView {
        weak var model: ViewerModel?

        override var acceptsFirstResponder: Bool { true }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func layout() {
            super.layout()
            model?.viewportSize = bounds.size
        }

        override func mouseDragged(with event: NSEvent) {
            if event.modifierFlags.contains(.shift) {
                model?.pan(dx: event.deltaX, dy: event.deltaY)
            } else {
                model?.orbit(dx: event.deltaX, dy: event.deltaY)
            }
        }

        override func otherMouseDragged(with event: NSEvent) {
            model?.pan(dx: event.deltaX, dy: event.deltaY)
        }

        override func scrollWheel(with event: NSEvent) {
            if event.hasPreciseScrollingDeltas {
                // Trackpad (and Magic Mouse surface): content follows the fingers.
                model?.pan(dx: event.scrollingDeltaX, dy: event.scrollingDeltaY)
            } else {
                model?.scrollZoom(dy: event.scrollingDeltaY)
            }
        }

        override func magnify(with event: NSEvent) {
            model?.pinch(event.magnification)
        }
    }
}
