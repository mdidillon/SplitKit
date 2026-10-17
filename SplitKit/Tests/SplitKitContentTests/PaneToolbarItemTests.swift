import SwiftUI
import Testing
@testable import SplitKitContent

@MainActor
@Suite struct PaneToolbarItemTests {
    @Test func defaultsMatchTheContract() {
        let item = PaneToolbarItem(id: "reset", title: "Reset", kind: .button(action: {}))
        #expect(item.id == "reset")
        #expect(item.title == "Reset")
        #expect(item.systemImage == nil)
        #expect(item.priority == .normal)
        #expect(item.isEnabled)
        #expect(item.keyboardShortcut == nil)
        #expect(item.fallbackAction == nil)
    }

    @Test func priorityOrdersLowNormalHigh() {
        #expect(PaneToolbarItem.Priority.low < .normal)
        #expect(PaneToolbarItem.Priority.normal < .high)
        #expect(PaneToolbarItem.Priority.low < .high)
        #expect(!(PaneToolbarItem.Priority.high < .low))
        #expect([.high, .low, .normal, .low].sorted() == [.low, .low, .normal, .high] as [PaneToolbarItem.Priority])
    }

    @Test func layoutOrderIsPriorityThenDeclarationOrder() {
        func item(_ id: String, _ priority: PaneToolbarItem.Priority) -> PaneToolbarItem {
            PaneToolbarItem(id: id, title: id, kind: .button(action: {}), priority: priority)
        }
        let declared = [item("a", .low), item("b", .high), item("c", .normal), item("d", .high), item("e", .low)]
        // `sorted(by:)` is not guaranteed stable, so the stable form the layout code needs is spelled out.
        let ordered = declared.enumerated()
            .sorted { ($0.element.priority, $1.offset) > ($1.element.priority, $0.offset) }
            .map(\.element.id)
        #expect(ordered == ["b", "d", "c", "a", "e"])
    }

    @Test func customValuesAreKept() {
        var fired = 0
        let item = PaneToolbarItem(
            id: "x", title: "X", systemImage: "star", kind: .toggle(isOn: .constant(true)),
            priority: .high, isEnabled: false, keyboardShortcut: KeyboardShortcut("0"),
            fallbackAction: { fired += 1 }
        )
        #expect(item.systemImage == "star")
        #expect(item.priority == .high)
        #expect(!item.isEnabled)
        #expect(item.keyboardShortcut != nil)
        item.fallbackAction?()
        #expect(fired == 1)
        guard case .toggle(let isOn) = item.kind else { Issue.record("wrong kind"); return }
        #expect(isOn.wrappedValue)
    }

    @Test func buttonActionRuns() {
        var count = 0
        let item = PaneToolbarItem(id: "b", title: "B", kind: .button(action: { count += 1 }))
        guard case .button(let action) = item.kind else { Issue.record("wrong kind"); return }
        action()
        #expect(count == 1)
    }

    @Test func menuNestsItems() {
        let child = PaneToolbarItem(id: "child", title: "Child", kind: .button(action: {}))
        let menu = PaneToolbarItem(id: "menu", title: "Menu", kind: .menu(items: [child]))
        guard case .menu(let items) = menu.kind else { Issue.record("wrong kind"); return }
        #expect(items.map(\.id) == ["child"])
    }
}
