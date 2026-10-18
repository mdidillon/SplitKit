import AppKit

/// The ghost of a pane dragged out of its window (§9): a borderless, semi-transparent snapshot that follows
/// the cursor. It takes no mouse events, so the drag still sees what is under it. Must never outlive the drag.
@MainActor package final class GhostWindow {
    private let window: NSWindow

    /// `frame` is the window frame the drop would create; `image` fills it. `opacity` is the ghost opacity
    /// (Docs/Design.md §3), so what is under the ghost stays visible.
    package init(image: NSImage?, frame: CGRect, opacity: Double) {
        window = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.ignoresMouseEvents = true
        window.level = .floating
        window.alphaValue = opacity
        let view = NSImageView(frame: CGRect(origin: .zero, size: frame.size))
        view.image = image
        view.imageScaling = .scaleAxesIndependently
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        window.contentView = view
        window.setFrame(frame, display: false)
        window.orderFrontRegardless()
    }

    package var frame: CGRect { window.frame }

    package func move(to frame: CGRect) {
        window.setFrame(frame, display: true)
    }

    package func close() {
        window.orderOut(nil)
        window.close()
    }
}
