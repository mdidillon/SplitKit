import AppKit
import SplitKitModel

/// Owns the `NSWindow`s of a workspace in `.splitKit` mode (§5, §9): creates, places, brings forward and
/// closes them. It knows windows only by `WindowID` and their content only as the `NSView` the injected
/// factory makes, so this target never depends on the SplitKit UI target (§3). It acts only when told to,
/// i.e. after a transaction succeeded (§6.2); user actions on a window are reported back through the
/// callbacks, never applied to the session here.
///
/// Placement (§9): a window opens at `DisplayPlacement.resolve` of its `SavedPlacement`, with the frame
/// minimum that its `contentMinSize` needs. A user move or resize is written back with
/// `DisplayPlacement.placement(writing:displays:)` (coalesced, `writeBackDelay`); the coordinator's own
/// frames and the system's re-placement after a display change are not (`PlacementWriteBack`). When the
/// displays change, every window is resolved again from its saved placement, so it returns to its
/// intended spot when a display comes back.
@MainActor public final class WindowCoordinator: NSObject, NSWindowDelegate {
    /// How long a user move or resize waits before it is reported, so a drag reports once.
    static let writeBackDelay: Duration = .milliseconds(300)

    /// A user move or resize of a window: its new placement.
    package var onUserPlacementChange: (@MainActor (WindowID, SavedPlacement) -> Void)?
    /// The window's close button (or File ▸ Close of the system): the window stays open; the owner decides.
    package var onCloseRequest: (@MainActor (WindowID) -> Void)?
    /// The coordinator window that became key, or nil when one stopped being key.
    package var onKeyWindowChange: (@MainActor (WindowID?) -> Void)?

    /// The owner of pane drops (§9): every window's content view is a drop destination that asks it.
    package weak var dockDelegate: (any DockTargetDelegate)? {
        didSet { for entry in entries.values { (entry.window.contentView as? DockDropContainerView)?.delegate = dockDelegate } }
    }

    static let styleMask: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .resizable]

    private struct Entry {
        let window: NSWindow
        /// False for a window the host created (`.host` mode): its placement is reported, its frame never set (§9).
        let ownsFrame: Bool
        var placement: SavedPlacement
        var writeBack: PlacementWriteBack
    }

    private let makeContentView: @MainActor (WindowID) -> NSView
    private let displays: @MainActor () -> [DisplaySnapshot]
    private var entries: [WindowID: Entry] = [:]
    /// Set while the coordinator itself sets a frame, so that change is not written back.
    private var isApplyingFrame = false
    private var pendingPlacements: [WindowID: SavedPlacement] = [:]
    private var writeBackTask: Task<Void, Never>?
    private var screenObserver: (any NSObjectProtocol)?

    /// `makeContentView` builds the content of a window; `displays` is the screen adapter (§9).
    package init(makeContentView: @escaping @MainActor (WindowID) -> NSView,
                 displays: @escaping @MainActor () -> [DisplaySnapshot] = ScreenAdapter.currentDisplays) {
        self.makeContentView = makeContentView
        self.displays = displays
        super.init()
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.displaysDidChange() }
        }
    }

    isolated deinit {
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
    }

    /// The windows the coordinator has open.
    package var windowIDs: Set<WindowID> { Set(entries.keys) }

    /// Creates the window `id`, places it and makes it key. An open `id` is only brought forward.
    /// With `hostWindow` (`.host` mode, `makeDetachedWindow`), that window gets the content and delegate but
    /// its frame is left to the host (§9: SplitKit only sets frames on windows it created).
    package func open(_ id: WindowID, placement: SavedPlacement, contentMinSize: CGSize, hostWindow: NSWindow? = nil) {
        guard entries[id] == nil else {
            bringForward(id)
            return
        }
        let window: NSWindow
        if let hostWindow {
            window = hostWindow
        } else {
            window = NSWindow(contentRect: placement.intendedFrame, styleMask: Self.styleMask, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.isRestorable = false
            window.tabbingMode = .disallowed
            window.title = ProcessInfo.processInfo.processName
        }
        let container = DockDropContainerView(windowID: id, content: makeContentView(id))
        container.delegate = dockDelegate
        window.contentView = container
        window.contentMinSize = contentMinSize
        window.delegate = self
        entries[id] = Entry(window: window, ownsFrame: hostWindow == nil, placement: placement,
                            writeBack: PlacementWriteBack(displays: displays()))
        place(id)
        window.makeKeyAndOrderFront(nil)
    }

    /// Closes the window `id` without asking (the close was committed already). Unknown IDs are ignored.
    package func close(_ id: WindowID) {
        guard let entry = entries.removeValue(forKey: id) else { return }
        pendingPlacements[id] = nil
        entry.window.delegate = nil
        entry.window.close()
    }

    package func bringForward(_ id: WindowID) {
        guard let window = entries[id]?.window else { return }
        if window.isMiniaturized { window.deminiaturize(nil) }
        window.makeKeyAndOrderFront(nil)
    }

    /// The smallest content size of the window `id`: the summed pane minimums of its tree (§6.1.4).
    package func setContentMinSize(_ size: CGSize, for id: WindowID) {
        entries[id]?.window.contentMinSize = size
    }

    /// Reports the coalesced user moves and resizes now (before a snapshot, e.g. at quit).
    package func flushPendingPlacements() {
        writeBackTask?.cancel()
        writeBackTask = nil
        let pending = pendingPlacements
        pendingPlacements = [:]
        for (id, placement) in pending { onUserPlacementChange?(id, placement) }
    }

    // MARK: Placement

    /// Sets the window's frame to its resolved saved placement (§9).
    private func place(_ id: WindowID) {
        guard let entry = entries[id], entry.ownsFrame else { return }
        let window = entry.window
        let minimum = window.frameRect(forContentRect: CGRect(origin: .zero, size: window.contentMinSize)).size
        let frame = DisplayPlacement.resolve(entry.placement, minSize: minimum, displays: displays())
        isApplyingFrame = true
        window.setFrame(frame, display: true)
        isApplyingFrame = false
    }

    private func displaysDidChange() {
        for id in entries.keys { place(id) }
    }

    private func frameDidChange(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, let id = id(of: window) else { return }
        let interacting = window.inLiveResize || NSEvent.pressedMouseButtons != 0
        guard let placement = entries[id]?.writeBack.frameChanged(to: window.frame, displays: displays(),
                                                                   applyingOwnFrame: isApplyingFrame,
                                                                   userInteracting: interacting) else { return }
        entries[id]?.placement = placement
        pendingPlacements[id] = placement
        writeBackTask?.cancel()
        writeBackTask = Task { [weak self] in
            do { try await Task.sleep(for: Self.writeBackDelay) } catch { return }
            self?.flushPendingPlacements()
        }
    }

    private func id(of window: Any?) -> WindowID? {
        entries.first { $0.value.window === window as? NSWindow }?.key
    }

    // MARK: NSWindowDelegate

    public func windowDidMove(_ notification: Notification) { frameDidChange(notification) }

    public func windowDidResize(_ notification: Notification) { frameDidChange(notification) }

    public func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard let onCloseRequest, let id = id(of: sender) else { return true }
        onCloseRequest(id)
        return false
    }

    public func windowDidBecomeKey(_ notification: Notification) {
        if let id = id(of: notification.object) { onKeyWindowChange?(id) }
    }

    public func windowDidResignKey(_ notification: Notification) {
        if id(of: notification.object) != nil { onKeyWindowChange?(nil) }
    }
}
