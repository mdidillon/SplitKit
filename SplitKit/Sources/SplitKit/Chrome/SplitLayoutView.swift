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
                                     overrides: liveFractions, paneMinimum: paneMinimum),
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

    private func paneMinimum(_ content: ContentID?) -> CGSize {
        SplitGeometry.cellMinimum(minimumPaneSize: workspace.configuration.minimumPaneSize,
                                  contentMinimum: content.flatMap(workspace.metadata(of:))?.minimumSize,
                                  headerHeight: tokens.metrics.headerHeight,
                                  contentPadding: tokens.metrics.contentPadding)
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
