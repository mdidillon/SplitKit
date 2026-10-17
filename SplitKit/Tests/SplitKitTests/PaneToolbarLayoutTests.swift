import SwiftUI
import Testing
import SplitKitContent
@testable import SplitKit

/// The pure toolbar layout (spec §7.4). Widths: title 100 (minimum 64), items 30, ⋯ 20, spacing 4.
@Suite struct PaneToolbarLayoutTests {
    let titleWidth: CGFloat = 100
    let titleMin: CGFloat = 64

    func arrange(_ entries: [PaneToolbarLayout.Entry], available: CGFloat) -> PaneToolbarLayout {
        PaneToolbarLayout.arrange(entries: entries, available: available, titleWidth: titleWidth,
                                  titleMinWidth: titleMin, overflowWidth: 20, spacing: 4)
    }

    let mixed = [toolbarEntry("low", .low), toolbarEntry("normal", .normal), toolbarEntry("high", .high)]

    @Test func wideShowsEverythingWithoutOverflow() {
        let layout = arrange(mixed, available: 1000)
        #expect(layout == PaneToolbarLayout(visible: ["low", "normal", "high"], overflow: [], title: .full))
    }

    @Test func exactFitNeedsNoOverflow() {
        // 100 + 3 × 30 + 3 gaps × 4
        #expect(arrange(mixed, available: 202).overflow.isEmpty)
        #expect(arrange(mixed, available: 201.5).overflow == ["low"])
    }

    @Test func lowOverflowsFirstThenNormal() {
        #expect(arrange(mixed, available: 195) == PaneToolbarLayout(visible: ["normal", "high"], overflow: ["low"], title: .full))
        #expect(arrange(mixed, available: 160) == PaneToolbarLayout(visible: ["high"], overflow: ["low", "normal"], title: .full))
    }

    @Test func titleTruncatesBeforeHighCollapses() {
        // ⋯ + high = 54; 140 leaves 140 - 54 - 4 = 82 for the title, above its minimum.
        #expect(arrange(mixed, available: 140) == PaneToolbarLayout(
            visible: ["high"], overflow: ["low", "normal"], title: .truncated(width: 82)))
        // 52 would be left: below the minimum, so the high item collapses and the title regains room.
        #expect(arrange(mixed, available: 110) == PaneToolbarLayout(
            visible: [], overflow: ["low", "normal", "high"], title: .truncated(width: 86)))
    }

    @Test func minimumWidthKeepsOnlyOverflowAndHidesTheTitle() {
        let layout = arrange(mixed, available: 60)
        #expect(layout == PaneToolbarLayout(visible: [], overflow: ["low", "normal", "high"], title: .hidden))
    }

    @Test func declarationOrderBreaksPriorityTies() {
        let normals = [toolbarEntry("a", .normal), toolbarEntry("b", .normal), toolbarEntry("c", .normal)]
        // title 100 + ⋯ + two items needs 192; three items need 202: the last declared overflows first.
        let layout = arrange(normals, available: 195)
        #expect(layout == PaneToolbarLayout(visible: ["a", "b"], overflow: ["c"], title: .full))
    }

    @Test func visibleAndOverflowKeepDeclarationOrder() {
        let entries = [toolbarEntry("h1", .high), toolbarEntry("l1", .low), toolbarEntry("n1", .normal),
                       toolbarEntry("l2", .low), toolbarEntry("h2", .high)]
        // Low, then normal overflow; the high items stay and the title truncates.
        let layout = arrange(entries, available: 170)
        #expect(layout == PaneToolbarLayout(visible: ["h1", "h2"], overflow: ["l1", "n1", "l2"], title: .truncated(width: 78)))
    }

    @Test func highItemsCollapseLastDeclaredFirst() {
        let highs = [toolbarEntry("h1", .high), toolbarEntry("h2", .high)]
        // Both fit with the title at its minimum? 62 left < 64 → h2 collapses, h1 stays.
        #expect(arrange(highs, available: 130) == PaneToolbarLayout(
            visible: ["h1"], overflow: ["h2"], title: .truncated(width: 72)))
        #expect(arrange(highs, available: 90) == PaneToolbarLayout(
            visible: [], overflow: ["h1", "h2"], title: .truncated(width: 66)))
    }

    @Test func noItemsMeansNoOverflowButTheTitleStillGivesWay() {
        #expect(arrange([], available: 1000) == PaneToolbarLayout(visible: [], overflow: [], title: .full))
        #expect(arrange([], available: 80) == PaneToolbarLayout(visible: [], overflow: [], title: .truncated(width: 80)))
        #expect(arrange([], available: 40) == PaneToolbarLayout(visible: [], overflow: [], title: .hidden))
    }

    @Test func shortTitleIsNeverTruncatedBelowItsOwnWidth() {
        // A 20 pt title with a 64 pt minimum keeps its 20 pt; only the high item gives way.
        let layout = PaneToolbarLayout.arrange(entries: [toolbarEntry("h", .high)], available: 50, titleWidth: 20,
                                               titleMinWidth: titleMin, overflowWidth: 20, spacing: 4)
        #expect(layout == PaneToolbarLayout(visible: [], overflow: ["h"], title: .full))
    }

    // MARK: Overflow mapping

    @Test func overflowMappingEnablesCustomOnlyWithAFallback() {
        let view = AnyView(Color.clear)
        let withFallback = PaneToolbarItem(id: "c1", title: "Custom", kind: .custom(minWidth: 40, view: view), fallbackAction: {})
        let without = PaneToolbarItem(id: "c2", title: "Custom", kind: .custom(minWidth: 40, view: view))
        let disabledWithFallback = PaneToolbarItem(id: "c3", title: "Custom", kind: .custom(minWidth: 40, view: view),
                                                   isEnabled: false, fallbackAction: {})
        let button = PaneToolbarItem(id: "b", title: "Button", kind: .button(action: {}))
        let disabledButton = PaneToolbarItem(id: "d", title: "Button", kind: .button(action: {}), isEnabled: false)
        let toggle = PaneToolbarItem(id: "t", title: "Toggle", kind: .toggle(isOn: .constant(true)))
        let menu = PaneToolbarItem(id: "m", title: "Menu", kind: .menu(items: [button]))
        #expect(withFallback.isEnabledInOverflow)
        #expect(!without.isEnabledInOverflow)
        #expect(!disabledWithFallback.isEnabledInOverflow)
        #expect(button.isEnabledInOverflow && toggle.isEnabledInOverflow && menu.isEnabledInOverflow)
        #expect(!disabledButton.isEnabledInOverflow)
    }
}
