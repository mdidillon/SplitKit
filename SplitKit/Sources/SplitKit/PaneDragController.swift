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
        guard let workspace, active?.payload.drag == payload.drag, let layout = workspace.windowLayout(window) else { return nil }
        let candidate: DockTarget
        if layout.root == nil {
            guard layout.kind == .main else { return nil }
            candidate = .emptyWindow(window)
        } else {
            guard let cells = workspace.paneCells[window], let cell = cells.cells.first(where: { $0.frame.contains(point) }),
                  cell.pane != payload.pane else { return nil }
            let zone = SplitGeometry.dropZone(at: point, in: cells.card(of: cell),
                                              centreFraction: SplitKitStyleConstants.dropZoneCentreFraction)
            candidate = .pane(cell.pane, zone)
        }
        return isValid(candidate, in: window, for: payload) ? candidate : nil
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

extension SplitKitWorkspace {
    /// Makes `pane` the active pane of its window (a click on its header, §7.3).
    func activate(_ pane: PaneID) {
        guard let window = try? window(containing: pane), windowLayout(window)?.activePane != pane else { return }
        send(.setActive(pane, in: window))
    }
}
