import SwiftUI
import SplitKitModel

/// A window's split tree, laid out flat by `SplitGeometry`: one pane card per `PaneID` and one divider
/// handle per split boundary, each positioned absolutely. Because cards are keyed by `PaneID` and not
/// nested in split views, a split, move or close never rebuilds the cards that stay (§6.4 re-hosting).
struct SplitLayoutView: View {
    let workspace: SplitKitWorkspace
    let window: WindowLayout
    let root: LayoutNode
    /// Fractions of splits whose divider is being dragged; committed by one `resize` on mouse-up.
    @State private var liveFractions: [SplitID: [Double]] = [:]
    @Environment(\.splitKitTokens) private var tokens

    var body: some View {
        GeometryReader { proxy in
            let bounds = CGRect(origin: .zero, size: proxy.size)
            let layout = SplitGeometry.focusing(
                SplitGeometry.layout(root, in: bounds, dividerHitWidth: tokens.metrics.dividerHitWidth,
                                     overrides: liveFractions,
                                     paneMinimum: { workspace.paneMinimum($0, tokens: tokens) }),
                on: window.focusModePane, in: bounds)
            ZStack(alignment: .topLeading) {
                ForEach(layout.panes, id: \.pane) { cell in
                    PaneCardView(workspace: workspace, window: window, pane: cell.pane, content: cell.content)
                        .frame(width: cell.frame.width, height: cell.frame.height)
                        .position(x: cell.frame.midX, y: cell.frame.midY)
                }
                ForEach(layout.dividers) { divider in
                    PaneDividerHandle(divider: divider,
                                      onChange: { liveFractions[divider.split] = $0 },
                                      onEnd: { endDrag(divider.split, fractions: $0) })
                        .frame(width: divider.hitArea.width, height: divider.hitArea.height)
                        .position(x: divider.hitArea.midX, y: divider.hitArea.midY)
                }
            }
            .frame(width: bounds.width, height: bounds.height)
        }
    }

    /// Mouse-up: one `resize` with the final fractions (none if unchanged), then the live override goes.
    private func endDrag(_ split: SplitID, fractions: [Double]?) {
        guard let fractions else {
            liveFractions[split] = nil
            return
        }
        Task {
            try? await workspace.perform(.resize(splitID: split, fractions: fractions))
            liveFractions[split] = nil
        }
    }
}

extension SplitKitWorkspace {
    /// The minimum layout cell of a pane hosting `content` (§6.1.4), with `tokens`' header and card inset.
    func paneMinimum(_ content: ContentID?, tokens: SplitKitTokens) -> CGSize {
        SplitGeometry.cellMinimum(minimumPaneSize: configuration.minimumPaneSize,
                                  contentMinimum: content.flatMap(metadata(of:))?.minimumSize,
                                  headerHeight: tokens.metrics.headerHeight,
                                  contentPadding: tokens.metrics.contentPadding)
    }

    /// The window's `contentMinSize` (§6.1.4): the summed pane minimums of its tree; for the empty state,
    /// one empty pane's. The split view fills the content area, so there is no further chrome to add.
    /// Focus mode doesn't change it: the tree is untouched. Zero for a window not in the session.
    func minimumContentSize(of window: WindowID, tokens: SplitKitTokens) -> CGSize {
        guard let layout = windowLayout(window) else { return .zero }
        guard let root = layout.root else { return paneMinimum(nil, tokens: tokens) }
        return SplitGeometry.minimumSize(of: root) { paneMinimum($0, tokens: tokens) }
    }
}
