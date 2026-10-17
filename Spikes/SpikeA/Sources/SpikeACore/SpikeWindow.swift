import AppKit

/// Builds a window whose content is a row of panes. Shared by the demo and the tests.
@MainActor public enum SpikeWindow {
    public static func make(title: String, panes: [PaneHostView], origin: NSPoint = .zero) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(origin: origin, size: NSSize(width: 300 * CGFloat(panes.count), height: 380)),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = title
        window.isReleasedWhenClosed = false
        let stack = NSStackView(views: panes)
        stack.orientation = .horizontal
        stack.distribution = .fillEqually
        stack.spacing = 1
        window.contentView = stack
        window.contentView?.layoutSubtreeIfNeeded()
        return window
    }
}
