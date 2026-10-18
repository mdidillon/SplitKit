import CoreGraphics
import Foundation
import SwiftUI
import Testing
import SplitKitModel
@testable import SplitKit

/// The workspace ↔ window layer connection (§5, §6.2 side-effect order, §6.3.5, §8 snapshot on window
/// close, §9 placement write-back and `contentMinSize`), with a recording window host: no window is shown.

private let userPlacement = SavedPlacement(intendedFrame: CGRect(x: 40, y: 60, width: 900, height: 700),
                                           displayID: "display-1", relativeOrigin: CGPoint(x: 40, y: 35))

@MainActor
@Suite struct WindowHostTests {
    @Test func bothModesGetTheCoordinatorAndNoWindowOpensBeforeARestore() throws {
        let managed = try SplitKitWorkspace(registry: .init(), configuration: SplitKitConfiguration(persistence: .disabled))
        #expect(managed.windowHost is CoordinatedWindows)
        // `.host` mode: the same layer, which opens detached windows only (the host owns its main window, §9).
        let hosted = try SplitKitWorkspace(registry: .init(), configuration: SplitKitConfiguration(
            windowManagement: .host(makeDetachedWindow: nil), persistence: .disabled))
        #expect(hosted.windowHost is CoordinatedWindows)
    }

    @Test func theWindowContentHookWrapsEveryWindowAndNilLeavesItAlone() throws {
        var wrapped = 0
        let hooked = try SplitKitWorkspace(registry: .init(), configuration: SplitKitConfiguration(
            persistence: .disabled, windowContent: { view in wrapped += 1; return AnyView(view.splitKitTokens(.plain)) }))
        let window = WindowID(raw: UUID())
        _ = CoordinatedWindows.content(of: hooked, window: window) { _ in }
        _ = CoordinatedWindows.content(of: hooked, window: window) { _ in }
        #expect(wrapped == 2)

        let plain = try SplitKitWorkspace(registry: .init(), configuration: SplitKitConfiguration(persistence: .disabled))
        #expect(plain.configuration.windowContent == nil)
        _ = CoordinatedWindows.content(of: plain, window: window) { _ in }
        #expect(wrapped == 2)
    }

    @Test func aRestoreOpensTheSessionWindowsAndAnotherRestoreClosesThemFirst() async throws {
        let file = try sessionFile(type: TestContent.type.raw, state: Data(), availability: .hosted)
        let (workspace, host) = try hostedWorkspace(.custom(MemoryStore(data: file.bytes)))
        _ = await workspace.restoreOrOpenDefaultAsync()
        let restored = file.session.windows[0].id
        #expect(host.calls == [.open([restored])])

        _ = await workspace.restoreOrOpenDefaultAsync()
        #expect(host.calls == [.open([restored]), .close([restored]), .open([restored])])
    }

    @Test func theDefaultLayoutOpensItsMainWindow() throws {
        let (workspace, host) = try hostedWorkspace()
        _ = workspace.restoreOrOpenDefault()
        #expect(host.calls == [.open([workspace.mainLayout.id])])
    }

    @Test func aFailedTransactionTouchesNoWindow() async throws {
        let (workspace, host) = try hostedWorkspace()
        _ = workspace.restoreOrOpenDefault()
        let before = host.calls
        await #expect(throws: LayoutError.self) { try await workspace.perform(.closePane(PaneID(raw: UUID()))) }
        #expect(throws: LayoutError.mainWindowExists(workspace.mainLayout.id)) {
            try workspace.commit(.openMainWindow(WindowID(raw: UUID()), placement: .defaultMainWindow))
        }
        await #expect(throws: LayoutError.self) { try await workspace.perform(.closeWindow(WindowID(raw: UUID()))) }
        #expect(host.calls == before)
    }

    @Test func closingAWindowClosesItAfterTheReleaseAndSnapshotsAtOnce() async throws {
        let store = MemoryStore()
        let (workspace, host) = try hostedWorkspace(.custom(store), debounce: .seconds(3600))
        _ = await workspace.restoreOrOpenDefaultAsync()
        try await workspace.addContent(TestContent.type, url: nil, into: nil)
        let main = workspace.mainLayout.id
        let content = try #require(workspace.store[workspace.mainLeaves[0].content!] as? TestContent)
        try await workspace.perform(.closeWindow(main))

        #expect(content.willReleaseCalls == 1)
        #expect(host.calls.last == .close([main]))
        await workspace.settleAutosave()
        #expect(store.saved.count == 1)              // not waiting for the hour-long debounce (§8)
        #expect(try Migrator.decode(#require(store.data)).0.windows.isEmpty)
    }

    @Test func newWindowBringsTheMainWindowForwardOrOpensOne() async throws {
        let (workspace, host) = try hostedWorkspace()
        _ = workspace.restoreOrOpenDefault()
        let first = workspace.mainLayout.id
        try await workspace.perform(.newWindow)
        #expect(host.calls.last == .bringForward(first))

        try await workspace.perform(.closeWindow(first))           // an empty window closes without asking
        #expect(workspace.session.windows.isEmpty)                 // the app stays alive with zero windows (§6.3.5)
        try await workspace.perform(.newWindow)
        let second = workspace.mainLayout
        #expect(second.id != first && second.root == nil && second.placement == .defaultMainWindow)
        #expect(host.calls.suffix(2) == [.close([first]), .open([second.id])])
    }

    @Test func aUserPlacementIsSavedAndAnUnchangedOneIsNot() async throws {
        let store = MemoryStore()
        let (workspace, _) = try hostedWorkspace(.custom(store))
        _ = await workspace.restoreOrOpenDefaultAsync()
        let main = workspace.mainLayout.id
        workspace.userPlaced(main, userPlacement)
        #expect(workspace.mainLayout.placement == userPlacement)
        await workspace.settleAutosave()
        let saves = store.saved.count
        #expect(try Migrator.decode(#require(store.data)).0.windows[0].placement == userPlacement)

        workspace.userPlaced(main, userPlacement)
        workspace.userPlaced(WindowID(raw: UUID()), .defaultMainWindow)
        await workspace.settleAutosave()
        #expect(store.saved.count == saves)
    }

    @Test func saveNowTakesPlacementsTheHostIsStillCoalescing() async throws {
        let store = MemoryStore()
        let (workspace, host) = try hostedWorkspace(.custom(store), debounce: .seconds(3600))
        _ = await workspace.restoreOrOpenDefaultAsync()
        host.deliver = { workspace.userPlaced($0, $1) }
        host.pendingPlacements = [(workspace.mainLayout.id, userPlacement)]
        try await workspace.saveNow()
        #expect(try Migrator.decode(#require(store.data)).0.windows[0].placement == userPlacement)
    }

    @Test func theContentMinimumSizeIsTheSumOfThePaneMinimums() async throws {
        let workspace = try makeWorkspace()
        let main = workspace.mainLayout.id
        let tokens = SplitKitTokens.glass
        let inset = 2 * tokens.metrics.contentPadding
        let empty = CGSize(width: 160 + inset, height: 100 + inset)                 // minimumPaneSize
        let test = CGSize(width: 200 + inset, height: 120 + tokens.metrics.headerHeight + inset)
        #expect(workspace.minimumContentSize(of: main, tokens: tokens) == empty)  // the empty state

        try await workspace.addContent(TestContent.type, url: nil, into: nil)
        #expect(workspace.minimumContentSize(of: main, tokens: tokens) == test)
        try await workspace.perform(.split(workspace.mainLeaves[0].pane, edge: .right))
        try await workspace.perform(.split(workspace.mainLeaves[1].pane, edge: .bottom))
        // H[test, V[empty, empty]]: widths add along H, heights along V.
        #expect(workspace.minimumContentSize(of: main, tokens: tokens)
                == CGSize(width: test.width + empty.width, height: max(test.height, 2 * empty.height)))

        try await workspace.perform(.toggleFocusMode(workspace.mainLeaves[0].pane))
        #expect(workspace.minimumContentSize(of: main, tokens: tokens).width == test.width + empty.width)
        #expect(workspace.minimumContentSize(of: WindowID(raw: UUID()), tokens: tokens) == .zero)
    }
}
