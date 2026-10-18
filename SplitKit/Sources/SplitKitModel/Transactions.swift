import Foundation

/// Every layout change is one of these, applied by `SessionEngine.apply` (§6.2).
public enum LayoutTransaction: Sendable {
    case insert(NewContent?, at: PaneID, edge: DropEdge, in: WindowID)  // edge ≠ .center: split; .center: into empty pane only; nil = new empty pane
    case insertIntoEmptyWindow(NewContent?, in: WindowID)               // .main window with root == nil (empty state ▸ Add)
    case move(ContentID, to: PaneID, edge: DropEdge, in: WindowID)      // .center = swap (§6.2)
    case moveIntoEmptyWindow(ContentID, in: WindowID)                   // dock into an empty main window
    case reorder(splitID: SplitID, from: Int, to: Int)
    case resize(splitID: SplitID, fractions: [Double])
    case beginClose(PaneID)                                             // stage 1, see §6.3
    case commitClose(PaneID)                                            // stage 2
    case cancelClose(PaneID)
    case commitReplace(PaneID, with: NewContent)                        // stage 2 alternative: replace content in place (§6.3.6)
    case beginCloseWindow(WindowID)                                     // §6.3.4
    case commitCloseWindow(WindowID)
    case cancelCloseWindow(WindowID)
    case openMainWindow(WindowID /* new */, placement: SavedPlacement)  // File ▸ New Window when no main window exists
    case setFocusMode(PaneID?, in: WindowID)
    case setActive(PaneID?, in: WindowID)
    case detach(PaneID, to: WindowID /* new */, placement: SavedPlacement)
}

public struct TransactionResult: Sendable {
    public var session: Session
    public var runtime: WorkspaceRuntime
    public var windowsCreated: [WindowID]      // the coordinator acts on these only after success
    public var windowsClosed: [WindowID]
    public var released: [ContentID]          // contents whose host must dispose them
    public var normalizations: [Normalization] // only the transaction cases below

    /// Public so a caller that applies several transactions on one working copy (Dock Back, §9) can merge
    /// their results into the one it commits.
    public init(session: Session, runtime: WorkspaceRuntime, windowsCreated: [WindowID], windowsClosed: [WindowID],
                released: [ContentID], normalizations: [Normalization]) {
        self.session = session
        self.runtime = runtime
        self.windowsCreated = windowsCreated
        self.windowsClosed = windowsClosed
        self.released = released
        self.normalizations = normalizations
    }
}

/// Every normalisation SplitKit reports. Transactions produce only the first three; Migrator.decode only the last three.
public enum Normalization: Equatable, Sendable {
    case flattened(SplitID)                // a same-axis child split was merged into its parent; this (child) ID is gone
    case collapsed(SplitID)                // a split left with one child was replaced by that child; this ID is gone
    case normalizedFractions(SplitID)      // resize input with a valid but un-normalised sum was scaled to sum 1
    case droppedOrphanRecord(ContentID)    // load: a record no pane references was removed
    case clearedActivePane(WindowID)       // load: dangling activePane set to nil
    case clearedFocusModePane(WindowID)    // load: dangling focusModePane set to nil
}

/// Runtime-only state: never encoded, never part of `Session` equality.
public struct WorkspaceRuntime: Equatable, Sendable {
    public var pendingCloses: Set<PaneID> = []
    public var pendingWindowCloses: Set<WindowID> = []
    public var activeDrag: DragSessionID? = nil

    public init(pendingCloses: Set<PaneID> = [], pendingWindowCloses: Set<WindowID> = [], activeDrag: DragSessionID? = nil) {
        self.pendingCloses = pendingCloses
        self.pendingWindowCloses = pendingWindowCloses
        self.activeDrag = activeDrag
    }
}
