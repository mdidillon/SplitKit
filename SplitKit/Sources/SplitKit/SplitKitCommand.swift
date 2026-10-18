import SplitKitModel

/// A user-level command run by `SplitKitWorkspace.perform(_:)` (§5). Each case maps to one or more
/// `LayoutTransaction`s; the workspace looks up the window a pane belongs to.
///
/// §5 references `SplitKitCommand` without declaring it: this is the minimal set Phase 2 needs
/// (deviation candidate, pending Marc's approval). Adding content is `addContent(_:url:into:)`.
public enum SplitKitCommand: Sendable {
    /// A new empty pane next to `pane` (`insert(nil, …)`): Split Right is `.right`, Split Down is `.bottom`.
    case split(PaneID, edge: DropEdge)
    /// An edge move (move + split) or, with `.center`, a swap (§6.2). `to` may be in another window.
    case move(ContentID, to: PaneID, edge: DropEdge)
    case reorder(splitID: SplitID, from: Int, to: Int)
    case resize(splitID: SplitID, fractions: [Double])
    case setActive(PaneID?, in: WindowID)
    case setFocusMode(PaneID?, in: WindowID)
    /// Enters focus mode for `pane`, or leaves it if `pane` is already the focus-mode pane (§7.3).
    case toggleFocusMode(PaneID)
    /// Two-stage close of one pane: `beginClose`, then `commitClose` if the content accepts, else `cancelClose` (§6.3).
    case closePane(PaneID)
    /// Two-stage close of a window: every hosted content is asked in tree order; one decline cancels (§6.3.4).
    case closeWindow(WindowID)
    /// File ▸ New Window (§6.3.5): brings the main window forward, or opens one (`openMainWindow`) when
    /// there is none.
    case newWindow
    /// Pane ▸ Detach: the pane's content moves into a new detached window, placed 24 pt off its source window
    /// (§9). Does nothing when `SplitKitConfiguration.detach` is `.disabled`.
    case detach(PaneID)
    /// Pane ▸ Move to Window ▸: a cross-window `move` as a `.right` edge insert next to the target window's
    /// active pane (its last pane if none is active), or into an empty main window (§9). Does nothing when
    /// `detach` is `.disabled`.
    case moveToWindow(PaneID, WindowID)
    /// Window ▸ Dock Back: every content of the detached window moves into the main window, in tree order, as
    /// one all-or-nothing commit; the main window is opened first if there is none (§9).
    case dockBack(WindowID)
}
