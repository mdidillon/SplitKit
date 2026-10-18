import Foundation
import Testing
import SplitKitContent
import SplitKitModel
@testable import SplitKit

/// Detach, Move to Window and Dock Back (spec §9, §13): live objects keep their identity and state, a failed
/// transaction creates, closes and releases nothing, Dock Back is one all-or-nothing commit.
@MainActor @Suite struct DetachDockTests {
    let workspace: SplitKitWorkspace
    let host: RecordingWindowHost
    var main: WindowID { workspace.mainLayout.id }

    init() throws {
        (workspace, host) = try hostedWorkspace()
        _ = workspace.restoreOrOpenDefault()
    }

    /// `count` contents of `type` in a row in the main window, in tree order.
    @discardableResult
    func addRow(_ count: Int, _ type: ContentType = CounterContent.type) async throws -> [ContentID] {
        try await workspace.addContent(type, url: nil, into: nil)
        for _ in 1..<count {
            try await workspace.addContent(type, besides: try #require(workspace.mainLeaves.last?.pane), edge: .right)
        }
        return workspace.mainLeaves.compactMap(\.content)
    }

    func pane(of content: ContentID) throws -> PaneID { try #require(workspace.host(of: content)).pane }
    func window(of content: ContentID) throws -> WindowID { try #require(workspace.host(of: content)).window }
    func counter(_ content: ContentID) throws -> CounterContent { try #require(workspace.store[content] as? CounterContent) }
    func test(_ content: ContentID) throws -> TestContent { try #require(workspace.store[content] as? TestContent) }
    func state() throws -> (Data, WorkspaceRuntime, [RecordingWindowHost.Call]) {
        (try Migrator.encode(workspace.session), workspace.runtime, host.calls)
    }

    /// Asserts `body` throws and that session bytes, runtime and window calls are as before.
    func expectUnchanged(_ comment: Comment, _ body: () async throws -> Void) async throws {
        let before = try state()
        await #expect(throws: LayoutError.self) { try await body() }
        let after = try state()
        #expect(before.0 == after.0, comment)
        #expect(before.1 == after.1, comment)
        #expect(before.2 == after.2, "no window is created, moved or closed")
    }

    // MARK: Identity and state through detach → move → dock back (spec §6.4)

    @Test func aCounterKeepsItsObjectAndStateThroughDetachMoveAndDockBack() async throws {
        let ids = try await addRow(3)
        let counters = try ids.map(counter)
        for (index, counter) in counters.enumerated() { counter.count = index + 1 }

        try await workspace.perform(.detach(try pane(of: ids[1])))
        let detached = try window(of: ids[1])
        #expect(detached != main && workspace.windowLayout(detached)?.kind == .detached)
        #expect(host.calls.last == .open([detached]))
        #expect(try counter(ids[1]) === counters[1] && counters[1].count == 2)

        try await workspace.perform(.moveToWindow(try pane(of: ids[0]), detached))
        #expect(try window(of: ids[0]) == detached && workspace.windowLayout(detached)?.root?.leaves.count == 2)
        #expect(try counter(ids[0]) === counters[0])

        try await workspace.perform(.dockBack(detached))
        #expect(workspace.windowLayout(detached) == nil && host.calls.last == .close([detached]))
        let order = workspace.mainLeaves.compactMap(\.content)
        #expect(Set(order) == Set(ids), "all three are in the main window again")
        #expect(order.firstIndex(of: ids[1])! + 1 == order.firstIndex(of: ids[0])!, "tree order is kept")
        for (index, content) in ids.enumerated() {
            #expect(try counter(content) === counters[index] && counters[index].count == index + 1)
        }
        #expect(workspace.store.objects.count == 3)
        #expect(workspace.runtime == WorkspaceRuntime())
    }

    @Test func nothingIsReleasedOrAskedWhileContentTravels() async throws {
        let ids = try await addRow(2, TestContent.type)
        let objects = try ids.map(test)
        try await workspace.perform(.detach(try pane(of: ids[0])))
        try await workspace.perform(.dockBack(try window(of: ids[0])))
        #expect(objects.allSatisfy { $0.willReleaseCalls == 0 && $0.shouldCloseCalls == 0 })
    }

    // MARK: Detach

    @Test func detachPlacesTheWindowOffsetFromItsSourceAndResolved() async throws {
        let ids = try await addRow(2)
        let source = workspace.mainLayout.placement.intendedFrame
        try await workspace.perform(.detach(try pane(of: ids[1])))
        let placement = try #require(workspace.windowLayout(try window(of: ids[1]))?.placement)
        let expected = CGRect(x: source.minX + 24, y: max(source.minY - 24, testDisplay.visibleFrame.minY),
                              width: source.width, height: source.height)
        #expect(placement.intendedFrame == expected)
        #expect(placement.displayID == "test")
        #expect(workspace.mainLeaves.count == 1, "the main window keeps the other pane")
    }

    @Test func detachingTheOnlyPaneLeavesTheMainWindowEmpty() async throws {
        let ids = try await addRow(1)
        try await workspace.perform(.detach(try pane(of: ids[0])))
        #expect(workspace.mainLayout.root == nil)
        #expect(workspace.session.windows.map(\.kind) == [.main, .detached])
    }

    @Test func aFailedDetachCreatesNoWindow() async throws {
        let ids = try await addRow(2)
        try await workspace.perform(.split(try pane(of: ids[1]), edge: .right))
        let empty = try #require(workspace.mainLeaves.last?.pane)
        try await expectUnchanged("an empty pane has no content") { try await workspace.perform(.detach(empty)) }
        try await expectUnchanged("an unknown pane") { try await workspace.perform(.detach(PaneID(raw: UUID()))) }

        let pending = try pane(of: ids[0])
        try workspace.commit(.beginClose(pending))
        try await expectUnchanged("a pane in a pending close") { try await workspace.perform(.detach(pending)) }
        try workspace.commit(.cancelClose(pending))

        try workspace.commit(.beginCloseWindow(main))
        try await expectUnchanged("a window in a pending close") { try await workspace.perform(.detach(try pane(of: ids[1]))) }
    }

    @Test func detachIsOffWhenDisabledAndAvailableAsACommandWhenCommandOnly() async throws {
        let (disabled, _) = try hostedWorkspace(detach: .disabled)
        _ = disabled.restoreOrOpenDefault()
        try await disabled.addContent(CounterContent.type, url: nil, into: nil)
        let pane = try #require(disabled.mainLeaves.first?.pane)
        let model = disabled.activePaneMenuModel(in: disabled.mainLayout.id)
        #expect(!model.offersDetach && !model.isEnabled(.detach) && !model.canMoveToWindow)
        let before = try Migrator.encode(disabled.session)
        try await disabled.perform(.detach(pane))
        #expect(try Migrator.encode(disabled.session) == before, "nothing happens with Detach.disabled")

        let (commandOnly, _) = try hostedWorkspace(detach: .commandOnly)
        _ = commandOnly.restoreOrOpenDefault()
        try await commandOnly.addContent(CounterContent.type, url: nil, into: nil)
        #expect(commandOnly.activePaneMenuModel(in: commandOnly.mainLayout.id).offersDetach)
        try await commandOnly.perform(.detach(try #require(commandOnly.mainLeaves.first?.pane)))
        #expect(commandOnly.session.windows.count == 2)
    }

    // MARK: Move to Window

    @Test func moveToWindowListsEveryOtherWindowMainFirstTitledByItsContent() async throws {
        let ids = try await addRow(3)
        try await workspace.perform(.detach(try pane(of: ids[0])))
        try await workspace.perform(.detach(try pane(of: ids[1])))
        let (first, second) = (try window(of: ids[0]), try window(of: ids[1]))

        let fromDetached = workspace.moveTargets(excluding: first)
        #expect(fromDetached.map(\.id) == [main, second])
        #expect(fromDetached.allSatisfy { $0.title == "Counter" })
        #expect(workspace.moveTargets(excluding: main).map(\.id) == [first, second])
        let menu = workspace.paneMenuModel(for: try pane(of: ids[2]), content: ids[2])
        #expect(menu.windowChoices.map(\.id) == [first, second] && menu.canMoveToWindow)
        #expect(menu.title(.moveToWindow(first)) == "Counter")
    }

    @Test func moveToWindowInsertsRightOfTheActivePaneOrTheLastPane() async throws {
        let ids = try await addRow(4)
        try await workspace.perform(.detach(try pane(of: ids[3])))        // detached: [3]
        let detached = try window(of: ids[3])
        try await workspace.perform(.setActive(try pane(of: ids[0]), in: main))

        try await workspace.perform(.moveToWindow(try pane(of: ids[2]), detached))
        #expect(workspace.windowLayout(detached)?.root?.leaves.compactMap(\.content) == [ids[3], ids[2]], "no active pane: after the last one")

        try await workspace.perform(.moveToWindow(try pane(of: ids[3]), main))
        #expect(workspace.mainLeaves.compactMap(\.content) == [ids[0], ids[3], ids[1]], "right of the active pane")
    }

    @Test func movingTheLastContentOutOfADetachedWindowClosesIt() async throws {
        let ids = try await addRow(2)
        try await workspace.perform(.detach(try pane(of: ids[1])))
        let detached = try window(of: ids[1])
        try await workspace.perform(.moveToWindow(try pane(of: ids[1]), main))
        #expect(workspace.windowLayout(detached) == nil && host.calls.last == .close([detached]))
        #expect(workspace.store.objects.count == 2)
    }

    @Test func movingIntoAnEmptyMainWindowFillsIt() async throws {
        let ids = try await addRow(2)
        try await workspace.perform(.detach(try pane(of: ids[0])))
        try await workspace.perform(.detach(try pane(of: ids[1])))
        #expect(workspace.mainLayout.root == nil)
        let first = try window(of: ids[0])
        try await workspace.perform(.moveToWindow(try pane(of: ids[0]), main))
        #expect(workspace.mainLeaves.compactMap(\.content) == [ids[0]] && workspace.windowLayout(first) == nil)
    }

    @Test func aFailedMoveToWindowChangesNothing() async throws {
        let ids = try await addRow(2)
        try await workspace.perform(.detach(try pane(of: ids[1])))
        let detached = try window(of: ids[1])
        try await workspace.perform(.split(try pane(of: ids[0]), edge: .right))
        let empty = try #require(workspace.mainLeaves.last?.pane)
        try await expectUnchanged("an empty pane") { try await workspace.perform(.moveToWindow(empty, detached)) }
        try await expectUnchanged("an unknown window") { try await workspace.perform(.moveToWindow(try pane(of: ids[0]), WindowID(raw: UUID()))) }
        let pending = try pane(of: ids[1])
        try workspace.commit(.beginClose(pending))
        try await expectUnchanged("a pending source") { try await workspace.perform(.moveToWindow(pending, main)) }
    }

    // MARK: Dock Back

    @Test func dockBackIsOneCommitAndOneSnapshot() async throws {
        let store = MemoryStore()
        let (workspace, host) = try hostedWorkspace(.custom(store), debounce: .seconds(3600))
        _ = await workspace.restoreOrOpenDefaultAsync()
        try await workspace.addContent(TestContent.type, url: nil, into: nil)
        for _ in 0..<2 { try await workspace.addContent(TestContent.type, besides: workspace.mainLeaves.last!.pane, edge: .right) }
        let ids = workspace.mainLeaves.compactMap(\.content)
        try await workspace.perform(.detach(try #require(workspace.host(of: ids[0])).pane))
        let detached = try #require(workspace.host(of: ids[0])).window
        try await workspace.perform(.moveToWindow(try #require(workspace.host(of: ids[1])).pane, detached))
        try await workspace.saveNow()                    // baseline; the hour-long debounce would never settle
        let saves = store.saved.count

        try await workspace.perform(.dockBack(detached))
        await workspace.settleAutosave()

        #expect(store.saved.count == saves + 1, "exactly one snapshot")
        let saved = try Migrator.decode(#require(store.data)).0
        #expect(saved.windows.map(\.id) == [workspace.mainLayout.id])
        #expect(saved.windows[0].root?.leaves.count == 3)
        #expect(host.calls.last == .close([detached]))
    }

    @Test func dockBackOpensTheMainWindowFirstWhenThereIsNone() async throws {
        let ids = try await addRow(1)
        try await workspace.perform(.detach(try pane(of: ids[0])))
        let detached = try window(of: ids[0])
        try await workspace.perform(.closeWindow(main))          // empty: closes without asking
        #expect(workspace.session.windows.map(\.id) == [detached])

        try await workspace.perform(.dockBack(detached))
        let newMain = try #require(workspace.mainWindow)
        #expect(workspace.session.windows.map(\.id) == [newMain])
        #expect(workspace.mainLeaves.compactMap(\.content) == ids)
        #expect(workspace.mainLayout.placement == .defaultMainWindow)
        #expect(host.calls.suffix(2) == [.open([newMain]), .close([detached])], "main window first, then the detached one goes")
        #expect(try counter(ids[0]).id == ids[0])
    }

    @Test func dockBackKeepsTheTreeOrderOfTheDetachedWindow() async throws {
        let ids = try await addRow(4)
        try await workspace.perform(.detach(try pane(of: ids[3])))
        let detached = try window(of: ids[3])
        for content in [ids[1], ids[0]] { try await workspace.perform(.moveToWindow(try pane(of: content), detached)) }
        let docked = try #require(workspace.windowLayout(detached)?.root?.leaves).compactMap(\.content)
        #expect(Set(docked) == [ids[0], ids[1], ids[3]] && docked.first == ids[3])

        try await workspace.perform(.dockBack(detached))
        let order = workspace.mainLeaves.compactMap(\.content)
        let start = try #require(order.firstIndex(of: docked[0]))
        #expect(Array(order[start..<(start + docked.count)]) == docked, "the docked contents are adjacent, in the detached window's order")
    }

    @Test func aFailedDockBackReleasesNothingAndChangesNothing() async throws {
        let ids = try await addRow(3, TestContent.type)
        let objects = try ids.map(test)
        try await workspace.perform(.detach(try pane(of: ids[0])))
        let detached = try window(of: ids[0])
        try await workspace.perform(.moveToWindow(try pane(of: ids[1]), detached))
        #expect(workspace.windowLayout(detached)?.root?.leaves.count == 2)
        // The second content can't move: its pane is in a pending close. The first move would succeed.
        let blocked = try pane(of: ids[1])
        try workspace.commit(.beginClose(blocked))

        try await expectUnchanged("the first move is discarded with the failed second one") {
            try await workspace.perform(.dockBack(detached))
        }
        #expect(objects.allSatisfy { $0.willReleaseCalls == 0 && $0.shouldCloseCalls == 0 })
        #expect(workspace.store.objects.count == 3)
        #expect(workspace.windowLayout(detached)?.root?.leaves.count == 2 && workspace.mainLeaves.count == 1)
    }

    @Test func dockBackOfAnUnknownOrMainWindowThrowsAndChangesNothing() async throws {
        try await addRow(1)
        try await expectUnchanged("main window") { try await workspace.perform(.dockBack(main)) }
        try await expectUnchanged("unknown window") { try await workspace.perform(.dockBack(WindowID(raw: UUID()))) }
    }

    @Test func aFailedDockBackThatWouldOpenTheMainWindowOpensNone() async throws {
        let ids = try await addRow(2, TestContent.type)
        try await workspace.perform(.detach(try pane(of: ids[0])))
        let detached = try window(of: ids[0])
        try await workspace.perform(.moveToWindow(try pane(of: ids[1]), detached))
        try await workspace.perform(.closeWindow(main))
        let pending = try pane(of: ids[1])
        try workspace.commit(.beginClose(pending))
        try await expectUnchanged("openMainWindow is part of the discarded working copy") {
            try await workspace.perform(.dockBack(detached))
        }
        #expect(workspace.mainWindow == nil)
    }

    @Test func theMenuOffersDockBackInDetachedWindowsOnly() async throws {
        let ids = try await addRow(2)
        try await workspace.perform(.detach(try pane(of: ids[1])))
        let detached = try window(of: ids[1])
        #expect(!workspace.activePaneMenuModel(in: main).isEnabled(.dockBack))
        #expect(workspace.paneMenuModel(for: try pane(of: ids[1]), content: ids[1]).isEnabled(.dockBack))
        #expect(workspace.activePaneMenuModel(in: detached).title(.dockBack) == "Dock Back")
        await workspace.paneMenuModel(for: try pane(of: ids[1]), content: ids[1]).run(.dockBack, in: workspace)
        #expect(workspace.windowLayout(detached) == nil && workspace.mainLeaves.count == 2)
    }

    // MARK: Closing a detached window (spec §9)

    @Test func theDetachedWindowPromptOffersDockBackInsteadAndTheMainWindowPromptDoesNot() async throws {
        let ids = try await addRow(3, TestContent.type)
        let objects = try ids.map(test)
        try await workspace.perform(.detach(try pane(of: ids[0])))
        let detached = try window(of: ids[0])
        try await workspace.perform(.moveToWindow(try pane(of: ids[1]), detached))

        #expect(workspace.closePromptKind(forWindow: detached) == .window(panes: 2, offersDockBack: true))
        #expect(workspace.closePromptKind(forWindow: main) == nil, "one pane left: no window prompt")
        try await workspace.perform(.moveToWindow(try pane(of: ids[2]), detached))
        let task = Task { try await workspace.perform(.closeWindow(detached)) }
        await waitUntil("the window prompt") { workspace.closePrompt != nil }
        let prompt = try #require(workspace.closePrompt)
        #expect(prompt.offersDockBack && prompt.window == detached)
        workspace.answer(prompt, .dockBack)
        try await task.value

        #expect(workspace.windowLayout(detached) == nil, "the window closed")
        #expect(Set(workspace.mainLeaves.compactMap(\.content)) == Set(ids), "its contents are in the main window")
        #expect(objects.allSatisfy { $0.willReleaseCalls == 0 && $0.shouldCloseCalls == 0 })
        #expect(workspace.runtime == WorkspaceRuntime())
    }

    @Test func closeAllAndCancelStillWorkOnTheDetachedPrompt() async throws {
        let ids = try await addRow(2, TestContent.type)
        let objects = try ids.map(test)
        try await workspace.perform(.detach(try pane(of: ids[0])))
        let detached = try window(of: ids[0])
        try await workspace.perform(.moveToWindow(try pane(of: ids[1]), detached))

        try await workspace.perform(.closeWindow(detached), answering: false)
        #expect(workspace.windowLayout(detached) != nil && workspace.runtime == WorkspaceRuntime())
        try await workspace.perform(.closeWindow(detached), answering: true)
        #expect(workspace.windowLayout(detached) == nil && workspace.store.objects.isEmpty)
        #expect(objects.allSatisfy { $0.willReleaseCalls == 1 })
    }
}

/// The single host (spec §6.4, §12) with real, unshown windows: opening a window lays out and renders its panes
/// at once, before a source window has re-rendered and dropped its view.
@MainActor @Suite(.serialized) struct RealWindowHostingTests {
    @Test func detachMoveAndDockBackHandTheViewOverWithoutADoubleHost() async throws {
        let workspace = try makePersistentWorkspace(.disabled)
        let windows = CoordinatedWindows(workspace: workspace)
        windows.showsWindows = false
        workspace.windowHost = windows
        _ = workspace.restoreOrOpenDefault()
        let main = workspace.mainLayout.id
        defer { windows.close(workspace.session.windows.map(\.id)) }

        try await workspace.addContent(CounterContent.type, url: nil, into: nil)
        try await workspace.addContent(CounterContent.type, besides: try #require(workspace.mainLeaves.last?.pane), edge: .right)
        let ids = workspace.mainLeaves.compactMap(\.content)
        func hosted(_ content: ContentID, in window: WindowID) async {
            await waitUntil("\(content) hosted in \(window) only") { workspace.store.hostingWindows(of: content) == [window] }
        }
        for id in ids { await hosted(id, in: main) }

        try await workspace.perform(.detach(try #require(workspace.host(of: ids[1])).pane))
        let detached = try #require(workspace.host(of: ids[1])).window
        await hosted(ids[1], in: detached)

        try await workspace.perform(.moveToWindow(try #require(workspace.host(of: ids[0])).pane, detached))
        await hosted(ids[0], in: detached)

        try await workspace.perform(.dockBack(detached))
        for id in ids { await hosted(id, in: main) }
    }
}
