import AppKit
import SwiftUI
import Testing
@testable import SplitKit

/// Tokens and styles reach the view hierarchy through the environment (default `.glass`, override `.plain`),
/// and the built-in styles render every state while reading their metrics from the tokens.
@MainActor @Suite struct StyleEnvironmentTests {
    // MARK: Propagation

    @Test func defaultsAreGlass() throws {
        let environment = try capturedEnvironment { $0 }
        #expect(environment.splitKitTokens == .glass)
        #expect(environment.paneHeaderStyle.style is GlassPaneHeaderStyle)
        #expect(environment.paneDividerStyle.style is GlassPaneDividerStyle)
        #expect(environment.emptyPaneStyle.style is GlassEmptyPaneStyle)
    }

    @Test func plainOverridesEveryStyleAndTheTokens() throws {
        let environment = try capturedEnvironment {
            $0.splitKitTokens(.plain).paneHeaderStyle(.plain).paneDividerStyle(.plain).emptyPaneStyle(.plain)
        }
        #expect(environment.splitKitTokens == .plain)
        #expect(environment.paneHeaderStyle.style is PlainPaneHeaderStyle)
        #expect(environment.paneDividerStyle.style is PlainPaneDividerStyle)
        #expect(environment.emptyPaneStyle.style is PlainEmptyPaneStyle)
    }

    @Test func innermostOverrideWins() throws {
        var custom = SplitKitTokens.glass
        custom.metrics.cornerRadius = 0
        let environment = try capturedEnvironment {
            $0.splitKitTokens(custom).paneHeaderStyle(.glass)
                .splitKitTokens(.plain).paneHeaderStyle(.plain)
        }
        #expect(environment.splitKitTokens == custom)
        #expect(environment.paneHeaderStyle.style is GlassPaneHeaderStyle)
    }

    @Test func eachStyleIsIndependent() throws {
        let environment = try capturedEnvironment { $0.paneDividerStyle(.plain) }
        #expect(environment.paneHeaderStyle.style is GlassPaneHeaderStyle)
        #expect(environment.paneDividerStyle.style is PlainPaneDividerStyle)
        #expect(environment.emptyPaneStyle.style is GlassEmptyPaneStyle)
        #expect(environment.splitKitTokens == .glass)
    }

    // MARK: Rendering

    @Test(arguments: [BuiltInLook.glass, .plain])
    func headerRendersEveryStateAtTheTokenHeight(_ look: BuiltInLook) {
        let tokens = look == .glass ? SplitKitTokens.glass : .plain
        for configuration in allHeaderStates() {
            let header = BuiltInPaneHeader(configuration: configuration, look: look).splitKitTokens(tokens)
            #expect(host(header).fittingSize.height == tokens.metrics.headerHeight)
        }
    }

    @Test func headerHeightFollowsAnOverriddenToken() {
        var tokens = SplitKitTokens.glass
        tokens.metrics.headerHeight = 40
        let header = AnyPaneHeaderStyle(.glass).makeBody(configuration: headerConfiguration()).splitKitTokens(tokens)
        #expect(host(header).fittingSize.height == 40)
    }

    @Test(arguments: [BuiltInLook.glass, .plain])
    func dividerRendersEveryState(_ look: BuiltInLook) {
        for axis in [Axis.horizontal, .vertical] {
            for (hovered, dragging) in [(false, false), (true, false), (false, true)] {
                let configuration = PaneDividerConfiguration(axis: axis, isHovered: hovered, isDragging: dragging)
                host(BuiltInPaneDivider(configuration: configuration, look: look))
            }
        }
    }

    @Test(arguments: [BuiltInLook.glass, .plain])
    func emptyPaneRendersEveryKind(_ look: BuiltInLook) {
        for kind in [EmptyPaneConfiguration.Kind.emptyPane, .emptyWindow, .unavailable(systemImage: "cube"),
                     .unavailable(systemImage: nil)] {
            host(BuiltInEmptyPane(configuration: emptyConfiguration(kind), look: look))
        }
    }

    @Test func environmentStylesRenderThroughTheTypeEraser() throws {
        let environment = try capturedEnvironment { $0.paneHeaderStyle(.plain).paneDividerStyle(.plain).emptyPaneStyle(.plain) }
        host(environment.paneHeaderStyle.makeBody(configuration: headerConfiguration()))
        host(environment.paneDividerStyle.makeBody(configuration: PaneDividerConfiguration(axis: .horizontal)))
        host(environment.emptyPaneStyle.makeBody(configuration: emptyConfiguration(.emptyPane)))
    }
}

// MARK: Helpers

/// Every header state the built-in styles must render (Docs/Design.md §7).
@MainActor
private func allHeaderStates() -> [PaneHeaderConfiguration] {
    [
        headerConfiguration(isActive: true),
        headerConfiguration(),
        headerConfiguration(isHovered: true),
        headerConfiguration(isDropTarget: true),
        headerConfiguration(isDraggedSource: true),
        headerConfiguration(isActive: true, isPendingClose: true),
        headerConfiguration(title: "Add Content", systemImage: nil, isEmpty: true),
        headerConfiguration(isActive: true, isFocusMode: true),
    ]
}

/// The environment a view sees after `modify` applies modifiers above it.
@MainActor
private func capturedEnvironment(_ modify: (EnvironmentProbe) -> some View) throws -> EnvironmentValues {
    let box = EnvironmentProbe.Box()
    host(modify(EnvironmentProbe(box: box)))
    return try #require(box.values)
}

private struct EnvironmentProbe: View {
    final class Box { var values: EnvironmentValues? }
    let box: Box
    @Environment(\.self) private var environment

    var body: some View {
        box.values = environment
        return Color.clear
    }
}
