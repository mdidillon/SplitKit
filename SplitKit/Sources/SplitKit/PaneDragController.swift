import AppKit
import SplitKitModel
import SplitKitWindows

/// What a window's split view laid out last (the cells and the tokens it used): the geometry a drop is
/// hit-tested against, so the drop zones are exactly what the user sees (§9).
struct PaneCells: Equatable {
    var cells: [SplitGeometry.PaneFrame]
    var contentPadding: CGFloat
    var headerHeight: CGFloat

    func card(of cell: SplitGeometry.PaneFrame) -> CGRect {
        SplitGeometry.card(of: cell.frame, contentPadding: contentPadding)
    }
}

/// Runs the header drags of one workspace (spec §9, §11.1 Spike A): it starts a drag, hit-tests the drop
/// zones, performs the drop, shows the ghost window and cleans up. `paneDragEnded` is the single
/// cancel and cleanup point of AppKit's session; a successful drop cleans up at once (the dragged header may
/// already be gone), and every cleanup is idempotent. While a drag runs `runtime.activeDrag` is set and the
/// layout is untouched until a drop succeeds, so a cancelled drag leaves session and runtime as they were.
@MainActor final class PaneDragController: PaneDragSourceDelegate, DockTargetDelegate {
    struct Active {
        var payload: PaneDragPayload
        var card: CGRect
        var grab: CGPoint = .zero
        var snapshot: NSImage?
        var ghost: GhostWindow?
        /// Where the ghost is now, i.e. where a release would detach.
        var ghostFrame: CGRect?
        /// The window the cursor is over, if any; the ghost never shows over a window.
        var hoverWindow: WindowID?
    }

    private weak var workspace: SplitKitWorkspace?
    private(set) var active: Active?

    init(workspace: SplitKitWorkspace) {
        self.workspace = workspace
    }

    // MARK: Source

    func paneDragBegin(pane: PaneID) -> PaneDragStart? {
        guard active == nil, let workspace, !workspace.isClosing(pane: pane),
              let window = try? workspace.window(containing: pane),
              let content = workspace.windowLayout(window)?.root?.leaves.first(where: { $0.pane == pane })?.content,
              let cells = workspace.paneCells[window], let cell = cells.cells.first(where: { $0.pane == pane })
        else { return nil }
        let drag = DragSessionID(raw: workspace.ids.next())
        let payload = PaneDragPayload(drag: drag, content: content, pane: pane, window: window)
        let card = cells.card(of: cell)
        let header = CGRect(origin: card.origin, size: CGSize(width: card.width, height: min(cells.headerHeight, card.height)))
        active = Active(payload: payload, card: card)
        workspace.setActiveDrag(drag)
        workspace.draggedPane = pane
        return PaneDragStart(payload: payload, card: card, header: header)
    }

    func paneDragStarted(card: NSImage?, mouse: CGPoint) {
        guard var current = active else { return }
        current.snapshot = card
        current.grab = CGPoint(x: mouse.x - current.card.minX, y: mouse.y - current.card.minY)
        active = current
    }

    func paneDragMoved(to screenPoint: CGPoint, sourceWindow: CGRect) -> Bool {
        guard var current = active, let workspace else { return false }
        let configuration = workspace.configuration
        let shows = DragOut.showsGhost(allowsDragOut: configuration.detach == .enabled, cursor: screenPoint,
                                       sourceWindow: sourceWindow, threshold: configuration.undockThreshold,
                                       overDockWindow: current.hoverWindow != nil)
        if shows {
            let frame = DragOut.ghostFrame(cursor: screenPoint, grab: current.grab, contentSize: current.card.size)
            if let ghost = current.ghost {
                ghost.move(to: frame)
            } else {
                current.ghost = GhostWindow(image: current.snapshot, frame: frame, opacity: SplitKitStyleConstants.ghostOpacity)
            }
            current.ghostFrame = frame
        } else {
            current.ghost?.close()
            current.ghost = nil
            current.ghostFrame = nil
        }
        active = current
        return shows
    }

    /// The single end of a session: docked (already done), cancelled, or released outside as a detach.
    func paneDragEnded(at screenPoint: CGPoint, operation: NSDragOperation, escape: Bool) {
        let ghostFrame = active?.ghostFrame
        let pane = active?.payload.pane
        let end = DragEnd.decide(operation: operation, escape: escape, ghostFrame: ghostFrame)
        finish()
        if case let .detach(frame) = end, let pane, let workspace {
            try? workspace.detach(pane, at: frame)
        }
    }

    func paneClicked(pane: PaneID) {
        workspace?.activate(pane)
    }

    /// Ends the drag state: ghost closed, overlay and dragged-source look gone, `activeDrag` cleared.
    /// Safe to call again.
    private func finish() {
        active?.ghost?.close()
        active = nil
        guard let workspace else { return }
        workspace.draggedPane = nil
        workspace.dockTarget = nil
        workspace.setActiveDrag(nil)
    }

    // MARK: Destination

    func dockTarget(in window: WindowID, at point: CGPoint, for payload: PaneDragPayload) -> DockTarget? {
        guard active?.payload.drag == payload.drag, let candidate = zone(in: window, at: point, excluding: payload.pane) else { return nil }
        return isValid(candidate, in: window, for: payload) ? candidate : nil
    }

    /// The drop zone under `point` in `window` (the empty window, or a pane's edge half or centre), apart from
    /// `excluded`'s own pane: the geometry both pane drags and file drops are hit-tested against.
    private func zone(in window: WindowID, at point: CGPoint, excluding excluded: PaneID?) -> DockTarget? {
        guard let workspace, let layout = workspace.windowLayout(window) else { return nil }
        if layout.root == nil { return layout.kind == .main ? .emptyWindow(window) : nil }
        guard let cells = workspace.paneCells[window], let cell = cells.cells.first(where: { $0.frame.contains(point) }),
              cell.pane != excluded else { return nil }
        return .pane(cell.pane, SplitGeometry.dropZone(at: point, in: cells.card(of: cell),
                                                       centreFraction: SplitKitStyleConstants.dropZoneCentreFraction))
    }

    /// Whether the drop would succeed: the transaction computed on a copy, nothing committed (§6.2).
    private func isValid(_ target: DockTarget, in window: WindowID, for payload: PaneDragPayload) -> Bool {
        guard let workspace else { return false }
        var ids = workspace.ids
        return (try? SessionEngine.apply(Self.transaction(for: target, in: window, content: payload.content),
                                         to: workspace.session, runtime: workspace.runtime, ids: &ids)) != nil
    }

    private static func transaction(for target: DockTarget, in window: WindowID, content: ContentID) -> LayoutTransaction {
        switch target {
        case let .pane(pane, edge): .move(content, to: pane, edge: edge, in: window)
        case let .emptyWindow(empty): .moveIntoEmptyWindow(content, in: empty)
        }
    }

    func dockHover(_ target: DockTarget?, in window: WindowID, for payload: PaneDragPayload) {
        guard active?.payload.drag == payload.drag, let workspace else { return }
        active?.hoverWindow = window
        if workspace.dockTarget != target { workspace.dockTarget = target }
    }

    func dockExited(window: WindowID) {
        guard active?.hoverWindow == window else { return }
        active?.hoverWindow = nil
        workspace?.dockTarget = nil
    }

    func dockPerform(_ payload: PaneDragPayload, onto target: DockTarget) -> Bool {
        guard let workspace, active?.payload.drag == payload.drag else { return false }
        var docked = true
        do {
            switch target {
            case let .pane(pane, edge): try workspace.move(payload.content, to: pane, edge: edge)
            case let .emptyWindow(window): try workspace.commit(.moveIntoEmptyWindow(payload.content, in: window))
            }
        } catch {
            docked = false
        }
        finish()
        return docked
    }
}

// MARK: File drops (Finder)

extension PaneDragController {
    /// What a drop of `url` at `point` would do, or nil: a registered type must match the file, no pane
    /// drag may be running, and the zone must not be closing.
    private func fileDrop(of url: URL, in window: WindowID, at point: CGPoint) -> (type: ContentType, target: ContentPicker.Target, zone: DockTarget)? {
        guard let workspace, active == nil, let type = workspace.registry.type(for: url),
              let zone = zone(in: window, at: point, excluding: nil) else { return nil }
        let target = workspace.insertTarget(for: zone)
        guard workspace.contentPicker(for: target).isEnabled else { return nil }
        return (type, target, zone)
    }

    func fileDropHover(_ url: URL, in window: WindowID, at point: CGPoint) -> Bool {
        let drop = fileDrop(of: url, in: window, at: point)
        if workspace?.dockTarget != drop?.zone { workspace?.dockTarget = drop?.zone }
        return drop != nil
    }

    func fileDropExited(window: WindowID) {
        if active == nil { workspace?.dockTarget = nil }
    }

    /// Opens `url` at the zone under `point` through the picker's insert path (`ContentPicker.Target.insert`);
    /// a failure shows inline in the target. The insert runs after the drop returns (a replace may ask to close).
    func fileDropPerform(_ url: URL, in window: WindowID, at point: CGPoint) -> Bool {
        guard let workspace, let drop = fileDrop(of: url, in: window, at: point) else { return false }
        workspace.dockTarget = nil
        Task { await drop.target.insert(drop.type, url: url, in: workspace) }
        return true
    }
}

extension SplitKitWorkspace {
    /// Where a file dropped on `zone` goes (spec §9): an edge zone splits (a new pane beside), the centre of
    /// an empty pane or window fills it, the centre of an occupied pane replaces its content.
    func insertTarget(for zone: DockTarget) -> ContentPicker.Target {
        switch zone {
        case .emptyWindow:
            return .emptyWindow
        case let .pane(pane, edge):
            guard edge == .center else { return .besides(pane, edge) }
            let occupied = allLeaves.first { $0.pane == pane }?.content != nil
            return occupied ? .replacing(pane) : .emptyPane(pane)
        }
    }

    /// Makes `pane` the active pane of its window (a click on its header, §7.3).
    func activate(_ pane: PaneID) {
        guard let window = try? window(containing: pane), windowLayout(window)?.activePane != pane else { return }
        send(.setActive(pane, in: window))
    }
}
