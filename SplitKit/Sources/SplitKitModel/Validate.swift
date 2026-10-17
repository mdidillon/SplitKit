import Foundation

extension SessionEngine {
    /// A split's fractions must sum to `1 ± fractionTolerance` (§6.1.3).
    static let fractionTolerance = 1e-9

    /// Empty = valid; model-level only (no registry). Violations are listed in a fixed order: window-level
    /// checks and each window's tree in `windows` order (depth-first), then records in `contents` order.
    public static func validate(_ s: Session) -> [InvariantViolation] {
        var validator = Validator()
        validator.check(s)
        return validator.violations
    }
}

private struct Validator {
    var violations: [InvariantViolation] = []
    var windowIDs: Set<WindowID> = []
    var paneIDs: Set<PaneID> = []
    var splitIDs: Set<SplitID> = []
    var hosted: [ContentID: Int] = [:]
    var hostedOrder: [ContentID] = []

    mutating func report(_ violation: InvariantViolation) {
        if !violations.contains(violation) { violations.append(violation) }
    }

    mutating func check(_ s: Session) {
        if s.windows.count(where: { $0.kind == .main }) > 1 { report(.multipleMainWindows) }
        for window in s.windows { check(window) }

        for id in hostedOrder where hosted[id, default: 0] > 1 { report(.duplicateContentID(id)) }
        var recordIDs: Set<ContentID> = []
        for record in s.contents where !recordIDs.insert(record.id).inserted { report(.duplicateRecord(record.id)) }
        for id in hostedOrder where !recordIDs.contains(id) { report(.missingContentRecord(id)) }
        for record in s.contents where hosted[record.id] == nil { report(.orphanRecord(record.id)) }
    }

    mutating func check(_ window: WindowLayout) {
        if !windowIDs.insert(window.id).inserted { report(.duplicateWindowID(window.id)) }
        var panes: Set<PaneID> = []
        if let root = window.root {
            walk(root, parentAxis: nil, panes: &panes)
            if window.kind == .detached, !root.leaves.contains(where: { $0.content != nil }) {
                report(.detachedWindowWithoutContent(window.id))
            }
        } else if window.kind == .detached {
            report(.nilRootInDetachedWindow(window.id))
        }
        if let active = window.activePane, !panes.contains(active) { report(.danglingActivePane(window.id)) }
        if let focus = window.focusModePane, !panes.contains(focus) { report(.danglingFocusModePane(window.id)) }
    }

    mutating func walk(_ node: LayoutNode, parentAxis: SplitAxis?, panes: inout Set<PaneID>) {
        switch node {
        case let .pane(id, content):
            if !paneIDs.insert(id).inserted { report(.duplicatePaneID(id)) }
            panes.insert(id)
            if let content {
                if hosted[content] == nil { hostedOrder.append(content) }
                hosted[content, default: 0] += 1
            }
        case let .split(id, axis, children, fractions):
            if !splitIDs.insert(id).inserted { report(.duplicateSplitID(id)) }
            if axis == parentAxis { report(.sameAxisNesting(id)) }
            if children.count < 2 { report(.singleChildSplit(id)) }
            if fractions.count != children.count {
                report(.fractionCountMismatch(id))
            } else if !fractions.allSatisfy({ $0.isFinite && $0 > 0 })
                        || abs(fractions.reduce(0, +) - 1) > SessionEngine.fractionTolerance {
                report(.badFractions(id))
            }
            for child in children { walk(child, parentAxis: axis, panes: &panes) }
        }
    }
}
