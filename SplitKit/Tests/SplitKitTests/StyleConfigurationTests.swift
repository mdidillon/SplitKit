import SwiftUI
import Testing
@testable import SplitKit

/// Configuration state → look, accessibility and actions (Docs/Design.md §5–§7).
@MainActor @Suite struct StyleConfigurationTests {
    // MARK: Header

    @Test func activeHeaderIsPrimaryAndSelected() {
        let configuration = headerConfiguration(isActive: true)
        #expect(configuration.emphasis == .primary)
        #expect(configuration.accessibilityTraits == .isSelected)
    }

    @Test func inactiveHeaderIsSecondaryAndNotSelected() {
        let configuration = headerConfiguration()
        #expect(configuration.emphasis == .secondary)
        #expect(configuration.accessibilityTraits == [])
    }

    @Test func focusToggleExposesOnOff() {
        #expect(headerConfiguration(isFocusMode: true).focusToggleAccessibilityValue == "On")
        #expect(headerConfiguration(isFocusMode: false).focusToggleAccessibilityValue == "Off")
    }

    @Test func pendingCloseExposesClosingAndDisablesControls() {
        let pending = headerConfiguration(isPendingClose: true)
        #expect(pending.accessibilityValue == "Closing")
        #expect(pending.controlsDisabled)

        let idle = headerConfiguration()
        #expect(idle.accessibilityValue == nil)
        #expect(!idle.controlsDisabled)
    }

    @Test func focusToggleSymbolFollowsFocusMode() {
        #expect(headerConfiguration().focusSymbol == "arrow.up.left.and.arrow.down.right")
        #expect(headerConfiguration(isFocusMode: true).focusSymbol == "arrow.down.right.and.arrow.up.left")
    }

    @Test func stateFlagsArePassedThrough() {
        let configuration = headerConfiguration(isHovered: true, isDropTarget: true, isDraggedSource: true, isEmpty: true)
        #expect(configuration.isHovered)
        #expect(configuration.isDropTarget)
        #expect(configuration.isDraggedSource)
        #expect(configuration.isEmpty)
        #expect(!configuration.isActive && !configuration.isPendingClose && !configuration.isFocusMode)
    }

    @Test func headerActionsCallTheChrome() {
        var calls: [String] = []
        let configuration = headerConfiguration(toggleFocusMode: { calls.append("focus") },
                                                close: { calls.append("close") })
        configuration.toggleFocusMode()
        configuration.close()
        #expect(calls == ["focus", "close"])
    }

    // MARK: Divider

    @Test func glassDividerLineOnlyOnHoverAndDrag() {
        #expect(DividerLine(PaneDividerConfiguration(axis: .horizontal), look: .glass) == .hidden)
        #expect(DividerLine(PaneDividerConfiguration(axis: .horizontal, isHovered: true), look: .glass) == .separator)
        #expect(DividerLine(PaneDividerConfiguration(axis: .vertical, isDragging: true), look: .glass) == .accent)
        #expect(DividerLine(PaneDividerConfiguration(axis: .vertical, isHovered: true, isDragging: true), look: .glass) == .accent)
    }

    @Test func plainDividerLineAlwaysVisible() {
        #expect(DividerLine(PaneDividerConfiguration(axis: .horizontal), look: .plain) == .separator)
        #expect(DividerLine(PaneDividerConfiguration(axis: .horizontal, isHovered: true), look: .plain) == .separator)
        #expect(DividerLine(PaneDividerConfiguration(axis: .vertical, isDragging: true), look: .plain) == .accent)
    }

    // MARK: Empty pane, empty window, unavailable placeholder

    @Test func emptyStatesUseTheEmptySymbolAndAProminentAdd() {
        for kind in [EmptyPaneConfiguration.Kind.emptyPane, .emptyWindow] {
            let configuration = emptyConfiguration(kind)
            #expect(configuration.symbol == "plus.rectangle.on.rectangle")
            #expect(configuration.primaryActionIsProminent)
            #expect(configuration.secondaryAction == nil)
        }
    }

    @Test func placeholderUsesTheTypeSymbolOrTheUnknownSymbol() {
        #expect(emptyConfiguration(.unavailable(systemImage: "cube")).symbol == "cube")
        #expect(emptyConfiguration(.unavailable(systemImage: nil)).symbol == "questionmark.square.dashed")
        #expect(!emptyConfiguration(.unavailable(systemImage: nil)).primaryActionIsProminent)
    }

    @Test func emptyPaneActionsCallTheChrome() {
        var calls = 0
        let action = EmptyPaneConfiguration.Action(title: "Restore", isEnabled: false) { calls += 1 }
        action.perform()
        #expect(calls == 1)
        #expect(!action.isEnabled)
        #expect(action.title == "Restore")
    }
}
