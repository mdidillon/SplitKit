import SwiftUI
import SplitKitContent

/// The pure layout of the header's flexible region (spec §7.4; Docs/Design.md §6): which toolbar items stay
/// visible, which collapse into the overflow ⋯ and what happens to the title. No SwiftUI measuring happens
/// here; `PaneToolbarRegion` feeds it measured widths.
///
/// Items give way in this order as the width shrinks: `.low`, then `.normal` (within one priority the
/// later-declared item first), then the title truncates (middle) down to its minimum width, then `.high`
/// items, and last the title itself disappears, leaving only the handle, icon, ⋯, focus toggle and close.
struct PaneToolbarLayout: Equatable {
    struct Entry: Equatable {
        let id: String
        let priority: PaneToolbarItem.Priority
        let width: CGFloat
    }

    enum Title: Equatable {
        /// The title keeps its natural width.
        case full
        /// The title is middle-truncated to this width.
        case truncated(width: CGFloat)
        /// Not enough room for the title at its minimum width.
        case hidden
    }

    /// Ids of the items shown in the row, in declaration order.
    let visible: [String]
    /// Ids of the items in the overflow menu, in declaration order. The ⋯ button shows iff this is non-empty.
    let overflow: [String]
    let title: Title

    /// `available` is the width of the region; `titleWidth` the title pill's natural width; `titleMinWidth`
    /// the narrowest it may be truncated to; `overflowWidth` the ⋯ button; `spacing` the gap between elements.
    static func arrange(entries: [Entry], available: CGFloat, titleWidth: CGFloat, titleMinWidth: CGFloat,
                        overflowWidth: CGFloat, spacing: CGFloat) -> PaneToolbarLayout {
        var kept = Array(repeating: true, count: entries.count)

        /// Width of the kept items plus ⋯ when something collapsed; with `title`, the title pill as well.
        func used(title: CGFloat?) -> CGFloat {
            var widths = entries.indices.filter { kept[$0] }.map { entries[$0].width }
            if kept.contains(false) { widths.append(overflowWidth) }
            if let title { widths.append(title) }
            return widths.reduce(0, +) + spacing * CGFloat(max(widths.count - 1, 0))
        }
        func result(_ title: Title) -> PaneToolbarLayout {
            PaneToolbarLayout(visible: entries.indices.filter { kept[$0] }.map { entries[$0].id },
                              overflow: entries.indices.filter { !kept[$0] }.map { entries[$0].id },
                              title: title)
        }
        /// Title width left next to the kept items.
        func titleSpace() -> CGFloat {
            let rest = used(title: nil)
            return available - rest - (rest > 0 ? spacing : 0)
        }

        let removalOrder = entries.indices.sorted {
            (entries[$0].priority, entries.count - $0) < (entries[$1].priority, entries.count - $1)
        }
        let minimum = min(titleMinWidth, titleWidth)

        // Low and normal items collapse while the title is still whole.
        for index in removalOrder where entries[index].priority < .high {
            if used(title: titleWidth) <= available { break }
            kept[index] = false
        }
        if used(title: titleWidth) <= available { return result(.full) }

        // Then the title truncates; only when it can't, high items collapse one by one.
        for index in removalOrder.filter({ kept[$0] }) {
            if titleSpace() >= minimum { break }
            kept[index] = false
        }
        let space = titleSpace()
        if space >= titleWidth { return result(.full) }
        return result(space >= minimum ? .truncated(width: space) : .hidden)
    }
}
