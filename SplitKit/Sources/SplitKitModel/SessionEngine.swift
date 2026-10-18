import Foundation

public enum SessionEngine {
    /// Pure. Returns the new session or throws; never repairs silently. New IDs come only from `ids`, drawn in the order of §6.1.9.
    ///
    /// Checks run in a fixed order: existence (`unknown…`), then pending state (`windowClosePending`
    /// before `paneClosePending`), then the transaction's own preconditions. Nothing is drawn from
    /// `ids` before all of these pass.
    public static func apply(_ t: LayoutTransaction, to s: Session, runtime: WorkspaceRuntime,
                             ids: inout some IDGenerator) throws(LayoutError) -> TransactionResult {
        var transition = Transition(session: s, runtime: runtime)
        try transition.run(t, ids: &ids)
        let result = transition.result
        #if DEBUG
        // §12: any violation after a transaction on a valid session is an engine bug.
        if validate(s).isEmpty {
            let violations = validate(result.session)
            assert(violations.isEmpty, "SessionEngine produced \(violations) for \(t)")
        }
        #endif
        return result
    }
}

/// The working copy of one transaction. Value semantics keep the caller's session and runtime untouched on throw.
struct Transition {
    var session: Session
    var runtime: WorkspaceRuntime
    var windowsCreated: [WindowID] = []
    var windowsClosed: [WindowID] = []
    var released: [ContentID] = []
    var normalizations: [Normalization] = []
    /// Windows that lost a pane or a content; detached ones left without content are closed (§6.1.6).
    var touched: [WindowID] = []

    init(session: Session, runtime: WorkspaceRuntime) {
        self.session = session
        self.runtime = runtime
    }

    var result: TransactionResult {
        TransactionResult(session: session, runtime: runtime, windowsCreated: windowsCreated,
                          windowsClosed: windowsClosed, released: released, normalizations: normalizations)
    }

    mutating func run(_ t: LayoutTransaction, ids: inout some IDGenerator) throws(LayoutError) {
        switch t {
        case let .insert(content, pane, edge, window):
            try insert(content, at: pane, edge: edge, in: window, ids: &ids)
        case let .insertIntoEmptyWindow(content, window):
            try insertIntoEmptyWindow(content, in: window, ids: &ids)
        case let .move(content, pane, edge, window):
            try move(content, to: pane, edge: edge, in: window, ids: &ids)
        case let .moveIntoEmptyWindow(content, window):
            try moveIntoEmptyWindow(content, in: window, ids: &ids)
        case let .reorder(split, from, to):
            try reorder(split, from: from, to: to)
        case let .resize(split, fractions):
            try resize(split, fractions: fractions)
        case let .beginClose(pane):
            try beginClose(pane)
        case let .commitClose(pane):
            try commitClose(pane)
        case let .cancelClose(pane):
            try cancelClose(pane)
        case let .commitReplace(pane, content):
            try commitReplace(pane, with: content)
        case let .beginCloseWindow(window):
            try beginCloseWindow(window)
        case let .commitCloseWindow(window):
            try commitCloseWindow(window)
        case let .cancelCloseWindow(window):
            try cancelCloseWindow(window)
        case let .openMainWindow(window, placement):
            try openMainWindow(window, placement: placement)
        case let .setFocusMode(pane, window):
            try setFocusMode(pane, in: window)
        case let .setActive(pane, window):
            try setActive(pane, in: window)
        case let .detach(pane, window, placement):
            try detach(pane, to: window, placement: placement, ids: &ids)
        }
        try closeDetachedWindowsWithoutContent()
    }

    // MARK: Lookups and checks

    func windowIndex(_ id: WindowID) -> Int? {
        session.windows.firstIndex { $0.id == id }
    }

    func requireWindow(_ id: WindowID) throws(LayoutError) -> Int {
        guard let index = windowIndex(id) else { throw .unknownWindow(id) }
        return index
    }

    /// The pane `id` inside window `window`.
    func requirePane(_ id: PaneID, inWindowAt window: Int) throws(LayoutError) -> PaneLocation {
        guard let root = session.windows[window].root, let path = root.path(ofPane: id) else { throw .unknownPane(id) }
        return location(window: window, path: path)
    }

    /// The pane `id` in any window.
    func requirePane(_ id: PaneID) throws(LayoutError) -> PaneLocation {
        for index in session.windows.indices {
            if let path = session.windows[index].root?.path(ofPane: id) { return location(window: index, path: path) }
        }
        throw .unknownPane(id)
    }

    /// The pane hosting `id` in any window.
    func requireHost(of id: ContentID) throws(LayoutError) -> PaneLocation {
        for index in session.windows.indices {
            if let path = session.windows[index].root?.path(ofContent: id) { return location(window: index, path: path) }
        }
        throw .unknownContent(id)
    }

    func requireSplit(_ id: SplitID) throws(LayoutError) -> (window: Int, path: [Int]) {
        for index in session.windows.indices {
            if let path = session.windows[index].root?.path(ofSplit: id) { return (index, path) }
        }
        throw .unknownSplit(id)
    }

    func location(window: Int, path: [Int]) -> PaneLocation {
        guard case let .pane(pane, content) = session.windows[window].root![path] else { preconditionFailure("not a pane") }
        return PaneLocation(window: window, path: path, pane: pane, content: content)
    }

    func requireNotPending(window index: Int) throws(LayoutError) {
        let id = session.windows[index].id
        if runtime.pendingWindowCloses.contains(id) { throw .windowClosePending(id) }
    }

    func requireNotPending(pane id: PaneID) throws(LayoutError) {
        if runtime.pendingCloses.contains(id) { throw .paneClosePending(id) }
    }

    /// §6.3.3: resizing (or reordering) a split touches its direct child panes.
    func requireNoPendingChild(of split: LayoutNode) throws(LayoutError) {
        guard case let .split(_, _, children, _) = split else { return }
        for case let .pane(id, _) in children { try requireNotPending(pane: id) }
    }

    func requireNoRecord(_ content: NewContent?) throws(LayoutError) {
        guard let content else { return }
        if session.contents.contains(where: { $0.id == content.id }) { throw .contentAlreadyHosted(content.id) }
    }

    // MARK: Mutations

    mutating func appendRecord(_ content: NewContent?) {
        guard let content else { return }
        session.contents.append(ContentRecord(id: content.id, type: content.type, stateVersion: content.stateVersion,
                                              state: Data(), availability: .hosted))
    }

    mutating func removeRecord(_ id: ContentID) {
        session.contents.removeAll { $0.id == id }
        released.append(id)
    }

    mutating func setContent(_ content: ContentID?, at location: PaneLocation) {
        let root = session.windows[location.window].root!
        session.windows[location.window].root = root.replacing(at: location.path[...], with: .pane(id: location.pane, content: content))
    }

    /// Removes a pane (collapse/flatten), clears the window's focus mode and moves `activePane` to the
    /// nearest sibling if the removed pane was active or in focus mode (§6.1.9, §7.3).
    mutating func removePane(at location: PaneLocation) {
        var window = session.windows[location.window]
        let root = window.root!
        if window.activePane == location.pane || window.focusModePane == location.pane {
            window.activePane = Tree.nearestSibling(of: location.path, in: root)
        }
        window.focusModePane = nil
        window.root = Tree.remove(at: location.path, from: root, normalizations: &normalizations)
        session.windows[location.window] = window
        touched.append(window.id)
    }

    /// §6.1.6: a detached window in which no pane hosts content is removed and listed in `windowsClosed`.
    /// Removing it would discard any of its (empty) panes that are pending close, which §6.3.3 forbids.
    mutating func closeDetachedWindowsWithoutContent() throws(LayoutError) {
        for id in touched {
            guard let index = windowIndex(id), session.windows[index].kind == .detached else { continue }
            let leaves = session.windows[index].root?.leaves ?? []
            if leaves.contains(where: { $0.content != nil }) { continue }
            for leaf in leaves { try requireNotPending(pane: leaf.pane) }
            session.windows.remove(at: index)
            windowsClosed.append(id)
        }
    }

    // MARK: Transactions (§6.2)

    mutating func insert(_ content: NewContent?, at pane: PaneID, edge: DropEdge, in window: WindowID,
                         ids: inout some IDGenerator) throws(LayoutError) {
        let index = try requireWindow(window)
        let target = try requirePane(pane, inWindowAt: index)
        try requireNotPending(window: index)
        try requireNotPending(pane: pane)
        try requireNoRecord(content)
        if edge == .center {
            guard target.content == nil else { throw .centerInsertIntoOccupiedPane }
            // A centre insert of no content into an empty pane changes nothing.
            guard let content else { return }
            setContent(content.id, at: target)
        } else {
            let newPane = LayoutNode.pane(id: PaneID(raw: ids.next()), content: content?.id)
            session.windows[index].root = Tree.insert(newPane, nextTo: target.path, edge: edge,
                                                      in: session.windows[index].root!, ids: &ids)
        }
        session.windows[index].focusModePane = nil
        appendRecord(content)
    }

    mutating func insertIntoEmptyWindow(_ content: NewContent?, in window: WindowID,
                                        ids: inout some IDGenerator) throws(LayoutError) {
        let index = try requireWindow(window)
        try requireNotPending(window: index)
        guard session.windows[index].kind == .main, session.windows[index].root == nil else { throw .windowNotEmpty(window) }
        try requireNoRecord(content)
        let pane = PaneID(raw: ids.next())
        session.windows[index].root = .pane(id: pane, content: content?.id)
        session.windows[index].activePane = pane
        session.windows[index].focusModePane = nil
        appendRecord(content)
    }

    mutating func move(_ content: ContentID, to pane: PaneID, edge: DropEdge, in window: WindowID,
                       ids: inout some IDGenerator) throws(LayoutError) {
        let source = try requireHost(of: content)
        // Self-drop: always a no-op, even if pending; `window` is not consulted (§6.2 lists no other failure).
        if source.pane == pane { return }
        let index = try requireWindow(window)
        let target = try requirePane(pane, inWindowAt: index)
        try requireNotPending(window: source.window)
        try requireNotPending(window: index)
        try requireNotPending(pane: source.pane)
        try requireNotPending(pane: pane)

        if edge == .center {
            // Swap, or a plain move when the target is empty; panes stay, contents exchange.
            setContent(target.content, at: source)
            setContent(content, at: target)
            session.windows[source.window].focusModePane = nil
            session.windows[index].focusModePane = nil
            touched.append(session.windows[source.window].id)
        } else {
            removePane(at: source)
            let target = try requirePane(pane, inWindowAt: index)
            let newPane = LayoutNode.pane(id: PaneID(raw: ids.next()), content: content)
            session.windows[index].root = Tree.insert(newPane, nextTo: target.path, edge: edge,
                                                      in: session.windows[index].root!, ids: &ids)
            session.windows[index].focusModePane = nil
        }
    }

    mutating func moveIntoEmptyWindow(_ content: ContentID, in window: WindowID,
                                      ids: inout some IDGenerator) throws(LayoutError) {
        let source = try requireHost(of: content)
        let index = try requireWindow(window)
        try requireNotPending(window: source.window)
        try requireNotPending(window: index)
        try requireNotPending(pane: source.pane)
        guard session.windows[index].kind == .main, session.windows[index].root == nil else { throw .windowNotEmpty(window) }
        removePane(at: source)
        session.windows[index].root = .pane(id: PaneID(raw: ids.next()), content: content)
    }

    mutating func reorder(_ split: SplitID, from: Int, to: Int) throws(LayoutError) {
        let (index, path) = try requireSplit(split)
        try requireNotPending(window: index)
        let node = session.windows[index].root![path]
        try requireNoPendingChild(of: node)
        guard case let .split(id, axis, children, fractions) = node else { preconditionFailure("not a split") }
        guard children.indices.contains(from), children.indices.contains(to) else { throw .indexOutOfRange }
        guard from != to else { return }
        var newChildren = children, newFractions = fractions
        newChildren.insert(newChildren.remove(at: from), at: to)
        newFractions.insert(newFractions.remove(at: from), at: to)
        session.windows[index].root = session.windows[index].root!.replacing(
            at: path[...], with: .split(id: id, axis: axis, children: newChildren, fractions: newFractions))
    }

    mutating func resize(_ split: SplitID, fractions: [Double]) throws(LayoutError) {
        let (index, path) = try requireSplit(split)
        try requireNotPending(window: index)
        let node = session.windows[index].root![path]
        try requireNoPendingChild(of: node)
        guard case let .split(id, axis, children, _) = node else { preconditionFailure("not a split") }
        guard fractions.count == children.count else {
            throw .invalidFractions(reason: "expected \(children.count) fractions, got \(fractions.count)")
        }
        guard fractions.allSatisfy(\.isFinite) else { throw .invalidFractions(reason: "non-finite fraction") }
        guard fractions.allSatisfy({ $0 > 0 }) else { throw .invalidFractions(reason: "fraction ≤ 0") }
        let sum = fractions.reduce(0, +)
        guard sum.isFinite else { throw .invalidFractions(reason: "sum of fractions is not finite") }
        var stored = fractions
        if abs(sum - 1) > SessionEngine.fractionTolerance {
            stored = Tree.normalized(fractions)
            guard stored.allSatisfy({ $0 > 0 }) else { throw .invalidFractions(reason: "fraction underflows to 0 when normalised") }
            normalizations.append(.normalizedFractions(id))
        }
        session.windows[index].root = session.windows[index].root!.replacing(
            at: path[...], with: .split(id: id, axis: axis, children: children, fractions: stored))
    }

    // MARK: Two-stage close (§6.3)

    mutating func beginClose(_ pane: PaneID) throws(LayoutError) {
        let location = try requirePane(pane)
        try requireNotPending(window: location.window)
        try requireNotPending(pane: pane)
        runtime.pendingCloses.insert(pane)
    }

    mutating func commitClose(_ pane: PaneID) throws(LayoutError) {
        let location = try requirePane(pane)
        try requireNotPending(window: location.window)
        guard runtime.pendingCloses.contains(pane) else { throw .noCloseInProgress(pane) }
        runtime.pendingCloses.remove(pane)
        removePane(at: location)
        if let content = location.content { removeRecord(content) }
    }

    mutating func cancelClose(_ pane: PaneID) throws(LayoutError) {
        let location = try requirePane(pane)
        try requireNotPending(window: location.window)
        guard runtime.pendingCloses.contains(pane) else { throw .noCloseInProgress(pane) }
        runtime.pendingCloses.remove(pane)
    }

    /// §6.3.6: the pane keeps its ID, position and fraction; the old record is released, the new one appended.
    mutating func commitReplace(_ pane: PaneID, with content: NewContent) throws(LayoutError) {
        let location = try requirePane(pane)
        try requireNotPending(window: location.window)
        guard runtime.pendingCloses.contains(pane) else { throw .noCloseInProgress(pane) }
        guard let old = location.content else { throw .unknownContent(.emptyPane) }
        try requireNoRecord(content)
        runtime.pendingCloses.remove(pane)
        setContent(content.id, at: location)
        removeRecord(old)
        appendRecord(content)
    }

    mutating func beginCloseWindow(_ window: WindowID) throws(LayoutError) {
        let index = try requireWindow(window)
        try requireNotPending(window: index)
        for leaf in session.windows[index].root?.leaves ?? [] { try requireNotPending(pane: leaf.pane) }
        runtime.pendingWindowCloses.insert(window)
    }

    mutating func commitCloseWindow(_ window: WindowID) throws(LayoutError) {
        let index = try requireWindow(window)
        guard runtime.pendingWindowCloses.contains(window) else { throw .noWindowCloseInProgress(window) }
        runtime.pendingWindowCloses.remove(window)
        for leaf in session.windows[index].root?.leaves ?? [] {
            if let content = leaf.content { removeRecord(content) }
        }
        session.windows.remove(at: index)
        windowsClosed.append(window)
    }

    mutating func cancelCloseWindow(_ window: WindowID) throws(LayoutError) {
        _ = try requireWindow(window)
        guard runtime.pendingWindowCloses.contains(window) else { throw .noWindowCloseInProgress(window) }
        runtime.pendingWindowCloses.remove(window)
    }

    // MARK: Windows and focus

    mutating func openMainWindow(_ window: WindowID, placement: SavedPlacement) throws(LayoutError) {
        if let main = session.windows.first(where: { $0.kind == .main }) { throw .mainWindowExists(main.id) }
        if windowIndex(window) != nil { throw .windowIDInUse(window) }
        session.windows.append(WindowLayout(id: window, kind: .main, root: nil, placement: placement))
        windowsCreated.append(window)
    }

    mutating func setFocusMode(_ pane: PaneID?, in window: WindowID) throws(LayoutError) {
        let index = try requireWindow(window)
        try requireNotPending(window: index)
        if let pane {
            _ = try requirePane(pane, inWindowAt: index)
            try requireNotPending(pane: pane)
            session.windows[index].activePane = pane
        }
        session.windows[index].focusModePane = pane
    }

    mutating func setActive(_ pane: PaneID?, in window: WindowID) throws(LayoutError) {
        let index = try requireWindow(window)
        try requireNotPending(window: index)
        if let pane {
            _ = try requirePane(pane, inWindowAt: index)
            try requireNotPending(pane: pane)
        }
        session.windows[index].activePane = pane
    }

    mutating func detach(_ pane: PaneID, to window: WindowID, placement: SavedPlacement,
                         ids: inout some IDGenerator) throws(LayoutError) {
        let source = try requirePane(pane)
        try requireNotPending(window: source.window)
        try requireNotPending(pane: pane)
        guard let content = source.content else { throw .unknownContent(.emptyPane) }
        if windowIndex(window) != nil { throw .windowIDInUse(window) }
        removePane(at: source)
        session.windows.append(WindowLayout(id: window, kind: .detached,
                                            root: .pane(id: PaneID(raw: ids.next()), content: content),
                                            placement: placement))
        windowsCreated.append(window)
    }
}
