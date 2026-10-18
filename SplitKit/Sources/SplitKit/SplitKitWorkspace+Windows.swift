import Foundation
import SwiftUI
import SplitKitModel
import SplitKitWindows

/// Detach, Move to Window and Dock Back (spec §9). Each is the existing transactions applied through
/// `commit`, so a failure changes nothing and no window is created, moved or closed (§6.2).
extension SplitKitWorkspace {
    /// A window in the Move to Window submenu.
    struct WindowChoice: Equatable {
        let id: WindowID
        let title: String
    }

    /// Pane ▸ Detach: the pane's content goes into a new detached window, placed like its source window
    /// offset by 24 pt and resolved against the displays (`DetachPlacement`). Does nothing when detaching is
    /// `.disabled`. An empty pane throws `unknownContent`. With `frame` (a dragged-out ghost dropped, §9) the
    /// window appears there, resolved against the displays, instead of offset from its source.
    func detach(_ pane: PaneID, at frame: CGRect? = nil) throws(LayoutError) {
        guard configuration.detach != .disabled else { return }
        let window = try window(containing: pane)
        let source = windowLayout(window)
        let content = source?.root?.leaves.first { $0.pane == pane }?.content
        let minimum = paneMinimum(content, tokens: EnvironmentValues().splitKitTokens)
        let placement = if let frame {
            DetachPlacement.placement(at: frame, contentMinSize: minimum, displays: displays())
        } else {
            DetachPlacement.placement(from: source?.placement.intendedFrame ?? .zero,
                                      contentMinSize: minimum, displays: displays())
        }
        try commit(.detach(pane, to: WindowID(raw: ids.next()), placement: placement))
    }

    /// Pane ▸ Move to Window ▸: the pane's content becomes a `.right` edge insert next to `window`'s active
    /// pane (its last pane in tree order if none is active), or fills an empty main window. A detached source
    /// window left without content closes (§6.1.6). Does nothing when detaching is `.disabled`.
    func moveToWindow(_ pane: PaneID, _ window: WindowID) throws(LayoutError) {
        guard configuration.detach != .disabled else { return }
        let source = try self.window(containing: pane)
        guard let content = windowLayout(source)?.root?.leaves.first(where: { $0.pane == pane })?.content else {
            throw .unknownContent(.emptyPane)
        }
        guard let target = windowLayout(window) else { throw .unknownWindow(window) }
        if let anchor = Self.dockAnchor(in: target) {
            try commit(.move(content, to: anchor, edge: .right, in: window))
        } else {
            try commit(.moveIntoEmptyWindow(content, in: window))
        }
    }

    /// Window ▸ Dock Back, the detached pane menu and the close prompt's *Dock Back Instead*: every content of
    /// the detached `window` moves into the main window, in tree order, each with the Move to Window rule (the
    /// first next to the main window's active pane, each following one next to the pane the previous one
    /// got, so the order is kept). Opens the main window first if there is none. The sequence runs on a
    /// working copy and is committed once, so it is one snapshot and any failure changes nothing.
    func dockBack(_ window: WindowID) throws(LayoutError) {
        guard let layout = windowLayout(window), layout.kind == .detached else { throw .unknownWindow(window) }
        var working = TransactionResult(session: session, runtime: runtime, windowsCreated: [], windowsClosed: [],
                                        released: [], normalizations: [])
        func run(_ transaction: LayoutTransaction) throws(LayoutError) {
            let step = try SessionEngine.apply(transaction, to: working.session, runtime: working.runtime, ids: &ids)
            working.session = step.session
            working.runtime = step.runtime
            working.windowsCreated += step.windowsCreated
            working.windowsClosed += step.windowsClosed
            working.released += step.released
            working.normalizations += step.normalizations
        }
        func main() -> WindowLayout? { working.session.windows.first { $0.kind == .main } }

        if main() == nil { try run(.openMainWindow(WindowID(raw: ids.next()), placement: .defaultMainWindow)) }
        let target = main()!.id
        var anchor: PaneID?
        for content in layout.root?.leaves.compactMap(\.content) ?? [] {
            if let next = anchor ?? main().flatMap(Self.dockAnchor(in:)) {
                try run(.move(content, to: next, edge: .right, in: target))
            } else {
                try run(.moveIntoEmptyWindow(content, in: target))
            }
            anchor = main()?.root?.leaves.first { $0.content == content }?.pane
        }
        commit(working)
    }

    /// The pane a docked content goes next to: the window's active pane, else its last pane in tree order;
    /// nil for an empty window.
    private static func dockAnchor(in window: WindowLayout) -> PaneID? {
        guard let leaves = window.root?.leaves else { return nil }
        return leaves.first { $0.pane == window.activePane }?.pane ?? leaves.last?.pane
    }

    /// The windows Move to Window ▸ lists for a pane in `window`: every other window, the main window first,
    /// then the detached windows in session order, each titled by its active content.
    func moveTargets(excluding window: WindowID?) -> [WindowChoice] {
        let others = session.windows.filter { $0.id != window }
        return (others.filter { $0.kind == .main } + others.filter { $0.kind == .detached })
            .map { WindowChoice(id: $0.id, title: title(of: $0)) }
    }

    /// The title of a window in a menu: its active content's title, else its first content's, else
    /// "Empty Window".
    private func title(of window: WindowLayout) -> String {
        let leaves = window.root?.leaves.filter { $0.content != nil } ?? []
        guard let content = (leaves.first { $0.pane == window.activePane } ?? leaves.first)?.content else {
            return ChromeText.emptyWindowTitle
        }
        return store[content]?.title ?? typeName(of: content) ?? ChromeText.emptyWindowTitle
    }
}
