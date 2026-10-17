import Foundation

/// A pane found in the session: its window index, its path of child indices from the root, and its content.
struct PaneLocation: Equatable {
    var window: Int
    var path: [Int]
    var pane: PaneID
    var content: ContentID?
}

extension LayoutNode {
    /// The node at `path` (child indices from this node). The path must be valid.
    subscript(path: some Collection<Int>) -> LayoutNode {
        var node = self
        for i in path {
            guard case let .split(_, _, children, _) = node else { preconditionFailure("path runs through a pane") }
            node = children[i]
        }
        return node
    }

    /// A copy with the node at `path` replaced by `new`.
    func replacing(at path: ArraySlice<Int>, with new: LayoutNode) -> LayoutNode {
        guard let i = path.first else { return new }
        guard case let .split(id, axis, oldChildren, fractions) = self else { preconditionFailure("path runs through a pane") }
        var children = oldChildren
        children[i] = children[i].replacing(at: path.dropFirst(), with: new)
        return .split(id: id, axis: axis, children: children, fractions: fractions)
    }

    /// Leaves in depth-first order.
    var leaves: [(pane: PaneID, content: ContentID?)] {
        switch self {
        case let .pane(id, content): [(id, content)]
        case let .split(_, _, children, _): children.flatMap(\.leaves)
        }
    }

    var firstLeaf: PaneID {
        switch self {
        case let .pane(id, _): id
        case let .split(_, _, children, _): children[0].firstLeaf
        }
    }

    var lastLeaf: PaneID {
        switch self {
        case let .pane(id, _): id
        case let .split(_, _, children, _): children[children.count - 1].lastLeaf
        }
    }

    /// Depth-first path to the first node matching `match`.
    func path(where match: (LayoutNode) -> Bool) -> [Int]? {
        if match(self) { return [] }
        guard case let .split(_, _, children, _) = self else { return nil }
        for (i, child) in children.enumerated() {
            if let sub = child.path(where: match) { return [i] + sub }
        }
        return nil
    }

    func path(ofPane id: PaneID) -> [Int]? {
        path { if case let .pane(p, _) = $0 { p == id } else { false } }
    }

    func path(ofSplit id: SplitID) -> [Int]? {
        path { if case let .split(s, _, _, _) = $0 { s == id } else { false } }
    }

    func path(ofContent id: ContentID) -> [Int]? {
        path { if case let .pane(_, c) = $0 { c == id } else { false } }
    }
}

/// Deterministic tree arithmetic of §6.1.9.
enum Tree {
    /// Divides by the sum so the stored sum stays within `1 ± 1e-9` (not reported).
    static func normalized(_ fractions: [Double]) -> [Double] {
        let sum = fractions.reduce(0, +)
        return fractions.map { $0 / sum }
    }

    /// Edge insert of `new` next to the node at `target`. If the target's parent split has the edge's
    /// axis, `new` joins it and the target's fraction `f` becomes `f/2 + f/2`; otherwise the target is
    /// replaced by a new split `[0.5, 0.5]`, whose `SplitID` is drawn here (after the caller drew the PaneID).
    static func insert(_ new: LayoutNode, nextTo target: [Int], edge: DropEdge, in root: LayoutNode,
                       ids: inout some IDGenerator) -> LayoutNode {
        guard let axis = edge.axis else { preconditionFailure("edge insert needs an edge") }
        let before = edge.placesBefore
        if let k = target.last {
            let parentPath = target.dropLast()
            if case let .split(id, parentAxis, oldChildren, oldFractions) = root[parentPath], parentAxis == axis {
                var children = oldChildren, fractions = oldFractions
                let half = fractions[k] / 2
                fractions[k] = half
                let index = before ? k : k + 1
                children.insert(new, at: index)
                fractions.insert(half, at: index)
                return root.replacing(at: parentPath[...],
                                      with: .split(id: id, axis: axis, children: children, fractions: normalized(fractions)))
            }
        }
        let targetNode = root[target]
        let split = LayoutNode.split(id: SplitID(raw: ids.next()), axis: axis,
                                     children: before ? [new, targetNode] : [targetNode, new], fractions: [0.5, 0.5])
        return root.replacing(at: target[...], with: split)
    }

    /// Removes the node at `path`. Remaining siblings become `fᵢ / (1 − r)`; a split left with one child
    /// collapses into it (`.collapsed`), and a collapsed-in split with its new parent's axis is merged
    /// into that parent with fractions multiplied by its slot fraction (`.flattened`). Returns nil when
    /// the root itself is removed.
    static func remove(at path: [Int], from root: LayoutNode, normalizations: inout [Normalization]) -> LayoutNode? {
        guard let k = path.last else { return nil }
        let parentPath = path.dropLast()
        guard case let .split(id, axis, children, fractions) = root[parentPath] else { preconditionFailure("parent is not a split") }
        var remaining = children, rest = fractions
        remaining.remove(at: k)
        let r = rest.remove(at: k)
        rest = normalized(rest.map { $0 / (1 - r) })

        guard remaining.count == 1 else {
            return root.replacing(at: parentPath[...], with: .split(id: id, axis: axis, children: remaining, fractions: rest))
        }
        normalizations.append(.collapsed(id))
        let survivor = remaining[0]
        if let slot = parentPath.last,
           case let .split(childID, childAxis, grandchildren, childFractions) = survivor,
           case let .split(gid, gaxis, gchildren, gfractions) = root[parentPath.dropLast()],
           childAxis == gaxis {
            let slotFraction = gfractions[slot]
            var merged = gchildren, mergedFractions = gfractions
            merged.replaceSubrange(slot...slot, with: grandchildren)
            mergedFractions.replaceSubrange(slot...slot, with: childFractions.map { $0 * slotFraction })
            normalizations.append(.flattened(childID))
            return root.replacing(at: parentPath.dropLast()[...],
                                  with: .split(id: gid, axis: gaxis, children: merged, fractions: normalized(mergedFractions)))
        }
        return root.replacing(at: parentPath[...], with: survivor)
    }

    /// The new `activePane` after the pane at `path` is removed: the first leaf of the following
    /// sibling, or the last leaf of the preceding one if it was the last child; nil if it was the root.
    static func nearestSibling(of path: [Int], in root: LayoutNode) -> PaneID? {
        guard let k = path.last else { return nil }
        guard case let .split(_, _, children, _) = root[path.dropLast()] else { preconditionFailure("parent is not a split") }
        return k + 1 < children.count ? children[k + 1].firstLeaf : children[k - 1].lastLeaf
    }
}
