import CoreGraphics
import SplitKitModel

/// An arrow direction in a window: ⌥⌘-arrows move the active pane, ⌃⌥⌘-arrows move its content (§7.5).
enum FocusDirection: CaseIterable, Hashable {
    case left, right, up, down

    /// The drop edge on the side of a pane that faces this direction's far side: moving a pane `right` of
    /// its neighbour drops it at the neighbour's `.right` edge.
    var edge: DropEdge {
        switch self {
        case .left: .left
        case .right: .right
        case .up: .top
        case .down: .bottom
        }
    }
}

/// Pure layout maths behind `SplitKitView` (§6.1.4): fractions → frames, minimum-size compression and
/// divider drags. Works in SwiftUI's local space (origin top-left, y down): `.horizontal` lays children
/// out left to right, `.vertical` top to bottom. Stored fractions are never rewritten here; a drag only
/// proposes new fractions for a `resize` transaction.
enum SplitGeometry {
    /// A pane's layout cell. The card inside it is inset by `metrics.contentPadding`.
    struct PaneFrame: Equatable {
        var pane: PaneID
        var content: ContentID?
        var frame: CGRect
    }

    /// The boundary between children `index` and `index + 1` of a split, with everything a drag needs.
    struct Divider: Equatable, Identifiable {
        struct ID: Hashable {
            var split: SplitID
            var index: Int
        }

        var split: SplitID
        var axis: SplitAxis
        var index: Int
        /// The fractions laid out (stored, or a live drag override).
        var fractions: [Double]
        /// The children's laid-out lengths along `axis`.
        var sizes: [CGFloat]
        /// The children's minimum lengths along `axis`.
        var minimums: [CGFloat]
        /// The pointer and drag area: `dividerHitWidth` across the boundary, the split's full length along it.
        var hitArea: CGRect

        var id: ID { ID(split: split, index: index) }
    }

    struct Layout: Equatable {
        var panes: [PaneFrame] = []
        /// In tree order: a split's divider `i` follows the dividers nested in its child `i`.
        var dividers: [Divider] = []
    }

    /// The smallest length a drag leaves a pane, so a proposed fraction stays `> 0` even with zero minimums.
    static let minimumDragLength: CGFloat = 1

    // MARK: Minimum sizes

    /// The minimum layout cell of a pane: the larger of `minimumPaneSize` and the content's `minimumSize`
    /// plus the header, per axis, plus the card inset on both sides. An empty or unknown content uses
    /// `minimumPaneSize` alone.
    static func cellMinimum(minimumPaneSize: CGSize, contentMinimum: CGSize?, headerHeight: CGFloat,
                            contentPadding: CGFloat) -> CGSize {
        let card = contentMinimum.map { CGSize(width: $0.width, height: $0.height + headerHeight) } ?? .zero
        return CGSize(width: max(minimumPaneSize.width, card.width) + 2 * contentPadding,
                      height: max(minimumPaneSize.height, card.height) + 2 * contentPadding)
    }

    /// Σ of the children's minimums along a split's axis, the largest across it.
    static func minimumSize(of node: LayoutNode, paneMinimum: (ContentID?) -> CGSize) -> CGSize {
        switch node {
        case let .pane(_, content):
            return paneMinimum(content)
        case let .split(_, axis, children, _):
            let sizes = children.map { minimumSize(of: $0, paneMinimum: paneMinimum) }
            switch axis {
            case .horizontal:
                return CGSize(width: sizes.map(\.width).reduce(0, +), height: sizes.map(\.height).max() ?? 0)
            case .vertical:
                return CGSize(width: sizes.map(\.width).max() ?? 0, height: sizes.map(\.height).reduce(0, +))
            }
        }
    }

    // MARK: Lengths (§6.1.4)

    /// The children's lengths along a split of length `available`. Each child gets `max(fraction × available,
    /// minimum)`: children whose share is below their minimum are fixed at it, and the rest is shared by
    /// the others in proportion to their fractions (repeated until no share is below its minimum). When
    /// `available < Σ minimums`, every child is compressed proportionally to its minimum. The lengths
    /// always sum to `available`.
    static func lengths(fractions: [Double], minimums: [CGFloat], available: CGFloat) -> [CGFloat] {
        let available = max(available, 0)
        let totalMinimum = minimums.reduce(0, +)
        if available <= totalMinimum, totalMinimum > 0 {
            return minimums.map { $0 * available / totalMinimum }
        }
        var fixed = Set<Int>()
        while true {
            let free = available - fixed.map { minimums[$0] }.reduce(0, +)
            let freeFraction = fractions.indices.filter { !fixed.contains($0) }.map { fractions[$0] }.reduce(0, +)
            let below = fractions.indices.filter {
                !fixed.contains($0) && CGFloat(fractions[$0] / freeFraction) * free < minimums[$0]
            }
            if below.isEmpty {
                return fractions.indices.map {
                    fixed.contains($0) ? minimums[$0] : CGFloat(fractions[$0] / freeFraction) * free
                }
            }
            fixed.formUnion(below)
        }
    }

    // MARK: Layout

    /// The pane cells and dividers of `node` laid out in `rect`. `overrides` replaces a split's stored
    /// fractions while its divider is dragged (ignored if the count doesn't match).
    static func layout(_ node: LayoutNode, in rect: CGRect, dividerHitWidth: CGFloat,
                       overrides: [SplitID: [Double]] = [:], paneMinimum: (ContentID?) -> CGSize) -> Layout {
        var layout = Layout()
        place(node, in: rect, dividerHitWidth: dividerHitWidth, overrides: overrides, paneMinimum: paneMinimum,
              into: &layout)
        return layout
    }

    private static func place(_ node: LayoutNode, in rect: CGRect, dividerHitWidth: CGFloat,
                              overrides: [SplitID: [Double]], paneMinimum: (ContentID?) -> CGSize,
                              into layout: inout Layout) {
        switch node {
        case let .pane(id, content):
            layout.panes.append(PaneFrame(pane: id, content: content, frame: rect))
        case let .split(id, axis, children, stored):
            let fractions = overrides[id].flatMap { $0.count == children.count ? $0 : nil } ?? stored
            let minimums = children.map { length(of: minimumSize(of: $0, paneMinimum: paneMinimum), along: axis) }
            let sizes = lengths(fractions: fractions, minimums: minimums, available: length(of: rect.size, along: axis))
            var offset = axis == .horizontal ? rect.minX : rect.minY
            for (index, child) in children.enumerated() {
                let cell = axis == .horizontal
                    ? CGRect(x: offset, y: rect.minY, width: sizes[index], height: rect.height)
                    : CGRect(x: rect.minX, y: offset, width: rect.width, height: sizes[index])
                place(child, in: cell, dividerHitWidth: dividerHitWidth, overrides: overrides,
                      paneMinimum: paneMinimum, into: &layout)
                offset += sizes[index]
                guard index < children.count - 1 else { continue }
                let hitArea = axis == .horizontal
                    ? CGRect(x: offset - dividerHitWidth / 2, y: rect.minY, width: dividerHitWidth, height: rect.height)
                    : CGRect(x: rect.minX, y: offset - dividerHitWidth / 2, width: rect.width, height: dividerHitWidth)
                layout.dividers.append(Divider(split: id, axis: axis, index: index, fractions: fractions,
                                               sizes: sizes, minimums: minimums, hitArea: hitArea))
            }
        }
    }

    /// Focus mode (§7.3, Docs/Design.md §7): only the focus-mode pane, filling `rect`, and no dividers.
    /// Unchanged when `pane` is nil or not in the layout.
    static func focusing(_ layout: Layout, on pane: PaneID?, in rect: CGRect) -> Layout {
        guard let pane, var focused = layout.panes.first(where: { $0.pane == pane }) else { return layout }
        focused.frame = rect
        return Layout(panes: [focused], dividers: [])
    }

    // MARK: Neighbours

    /// The pane that ⌥⌘-arrow focus movement and ⌃⌥⌘-arrow moves go to (§7.5). The tree is laid out in a
    /// unit square from its stored fractions (no minimum sizes, no window size), so the rule is the same in
    /// every window size. A candidate lies wholly beyond `pane`'s edge in `direction` and overlaps `pane`'s
    /// extent across that direction. The winner has the smallest gap, then the largest overlap, then comes
    /// first in tree order. Nil when no pane qualifies (or `pane` isn't in the tree).
    static func neighbour(of pane: PaneID, toward direction: FocusDirection, in root: LayoutNode) -> PaneID? {
        let unit = CGRect(x: 0, y: 0, width: 1, height: 1)
        let cells = layout(root, in: unit, dividerHitWidth: 0, paneMinimum: { _ in .zero }).panes
        guard let from = cells.first(where: { $0.pane == pane })?.frame else { return nil }
        let epsilon: CGFloat = 1e-9
        var best: (pane: PaneID, gap: CGFloat, overlap: CGFloat)?
        for cell in cells where cell.pane != pane {
            let frame = cell.frame
            let gap: CGFloat, overlap: CGFloat
            switch direction {
            case .right: (gap, overlap) = (frame.minX - from.maxX, overlapLength(frame.minY, frame.maxY, from.minY, from.maxY))
            case .left: (gap, overlap) = (from.minX - frame.maxX, overlapLength(frame.minY, frame.maxY, from.minY, from.maxY))
            case .down: (gap, overlap) = (frame.minY - from.maxY, overlapLength(frame.minX, frame.maxX, from.minX, from.maxX))
            case .up: (gap, overlap) = (from.minY - frame.maxY, overlapLength(frame.minX, frame.maxX, from.minX, from.maxX))
            }
            guard gap > -epsilon, overlap > epsilon else { continue }
            if let current = best, gap > current.gap + epsilon || (gap > current.gap - epsilon && overlap <= current.overlap + epsilon) {
                continue
            }
            best = (cell.pane, gap, overlap)
        }
        return best?.pane
    }

    private static func overlapLength(_ aMin: CGFloat, _ aMax: CGFloat, _ bMin: CGFloat, _ bMax: CGFloat) -> CGFloat {
        min(aMax, bMax) - max(aMin, bMin)
    }

    // MARK: Divider drag

    /// The fractions after dragging `divider` by `translation` points along its axis, measured from the
    /// state captured at drag start. Only the two neighbours change: each keeps at least its minimum
    /// (and `minimumDragLength`), and their combined fraction is shared in proportion to their new
    /// lengths, so the sum is unchanged. A compressed pair (no room above the minimums) does not move.
    static func dragFractions(_ divider: Divider, translation: CGFloat) -> [Double] {
        let leading = divider.index, trailing = divider.index + 1
        let lower = max(divider.minimums[leading], minimumDragLength) - divider.sizes[leading]
        let upper = divider.sizes[trailing] - max(divider.minimums[trailing], minimumDragLength)
        guard lower <= upper else { return divider.fractions }
        let shift = min(max(translation, lower), upper)
        let a = divider.sizes[leading] + shift, b = divider.sizes[trailing] - shift
        let pair = divider.fractions[leading] + divider.fractions[trailing]
        var fractions = divider.fractions
        fractions[leading] = pair * Double(a / (a + b))
        fractions[trailing] = pair - fractions[leading]
        return fractions
    }

    private static func length(of size: CGSize, along axis: SplitAxis) -> CGFloat {
        axis == .horizontal ? size.width : size.height
    }
}

// MARK: Drop zones (§9)

extension SplitGeometry {
    /// The card drawn inside a layout cell: the cell inset by `contentPadding` (Docs/Design.md §2).
    static func card(of cell: CGRect, contentPadding: CGFloat) -> CGRect {
        cell.insetBy(dx: contentPadding, dy: contentPadding)
    }

    /// The drop zone under `point` in a card (§9): the centre rectangle (`centreFraction` of each side) is a
    /// swap; outside it the card is cut along its diagonals into the four edge halves. A point outside the
    /// card (the gap between cards) takes the nearest side, so the zones tile the whole cell.
    static func dropZone(at point: CGPoint, in card: CGRect, centreFraction: CGFloat) -> DropEdge {
        guard card.width > 0, card.height > 0 else { return .center }
        let dx = (point.x - card.midX) / card.width, dy = (point.y - card.midY) / card.height
        let half = centreFraction / 2
        if abs(dx) <= half, abs(dy) <= half { return .center }
        if abs(dx) > abs(dy) { return dx < 0 ? .left : .right }
        return dy < 0 ? .top : .bottom
    }

    /// The part of `card` that `zone` highlights (Docs/Design.md §7): the whole card for the centre, else that half.
    static func dropRect(for zone: DropEdge, in card: CGRect) -> CGRect {
        switch zone {
        case .center: card
        case .left: CGRect(x: card.minX, y: card.minY, width: card.width / 2, height: card.height)
        case .right: CGRect(x: card.midX, y: card.minY, width: card.width / 2, height: card.height)
        case .top: CGRect(x: card.minX, y: card.minY, width: card.width, height: card.height / 2)
        case .bottom: CGRect(x: card.minX, y: card.midY, width: card.width, height: card.height / 2)
        }
    }
}
