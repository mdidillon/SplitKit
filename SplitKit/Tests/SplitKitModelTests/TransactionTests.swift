import Foundation
import Testing
@testable import SplitKitModel

let allEdges: [DropEdge] = [.left, .right, .top, .bottom, .center]
func pendingPane(_ n: Int) -> WorkspaceRuntime { WorkspaceRuntime(pendingCloses: [pid(n)]) }
func pendingWindow(_ n: Int) -> WorkspaceRuntime { WorkspaceRuntime(pendingWindowCloses: [wid(n)]) }

/// H[A(c1), B(c2)] in main window 1, plus detached window 2 with C(c3).
let twoWindows = session(mainWindow(1, h(1, [p(1, 1), p(2, 2)]), active: 1, focus: 1), detachedWindow(2, p(3, 3)))

@Suite("§6.2 edge and centre insert")
struct InsertTests {
    @Test func edgeInsertAppendsRecordAndClearsFocusMode() throws {
        let r = try apply(.insert(new(9), at: pid(2), edge: .right, in: wid(1)), to: twoWindows)
        #expect(r.session.root == h(1, [p(1, 1), p(2, 2), .pane(id: drawnPane(1), content: cid(9))], [0.5, 0.25, 0.25]))
        #expect(r.session.contents.last == ContentRecord(id: cid(9), type: testType, stateVersion: 1, state: Data(), availability: .hosted))
        #expect(r.session.contents.count == 4)
        #expect(r.session.windows[0].focusModePane == nil)
        #expect(r.session.windows[0].activePane == pid(1), "insert leaves activePane alone")
        #expect(r.released.isEmpty && r.windowsCreated.isEmpty && r.windowsClosed.isEmpty)
    }

    @Test func edgeInsertWithoutContentAddsEmptyPane() throws {
        let r = try apply(.insert(nil, at: pid(3), edge: .top, in: wid(2)), to: twoWindows)
        #expect(r.session.window(wid(2))?.root == .split(id: drawnSplit(2), axis: .vertical,
                                                         children: [.pane(id: drawnPane(1), content: nil), p(3, 3)], fractions: [0.5, 0.5]))
        #expect(r.session.contents == twoWindows.contents)
    }

    @Test func edgeInsertFailures() {
        expectFailure(.insert(new(9), at: pid(3), edge: .left, in: wid(1)), on: twoWindows, .unknownPane(pid(3)))
        expectFailure(.insert(new(9), at: pid(99), edge: .left, in: wid(1)), on: twoWindows, .unknownPane(pid(99)))
        expectFailure(.insert(new(9), at: pid(1), edge: .left, in: wid(99)), on: twoWindows, .unknownWindow(wid(99)))
        expectFailure(.insert(new(2), at: pid(1), edge: .left, in: wid(1)), on: twoWindows, .contentAlreadyHosted(cid(2)))
        expectFailure(.insert(new(9), at: pid(1), edge: .left, in: wid(1)), on: twoWindows, runtime: pendingPane(1), .paneClosePending(pid(1)))
        expectFailure(.insert(new(9), at: pid(1), edge: .left, in: wid(1)), on: twoWindows, runtime: pendingWindow(1), .windowClosePending(wid(1)))
    }

    @Test func contentAlreadyHostedCoversOrphanRecords() {
        var s = twoWindows
        s.contents.append(record(cid(9)))
        expectFailure(.insert(new(9), at: pid(1), edge: .left, in: wid(1)), on: s, .contentAlreadyHosted(cid(9)))
    }

    @Test func centerInsertIntoEmptyPane() throws {
        let s = session(mainWindow(1, h(1, [p(1, 1), p(2)]), focus: 1))
        let r = try apply(.insert(new(9), at: pid(2), edge: .center, in: wid(1)), to: s)
        #expect(r.session.root == h(1, [p(1, 1), p(2, 9)]))
        #expect(r.session.contents.map(\.id) == [cid(1), cid(9)])
        #expect(r.session.windows[0].focusModePane == nil)
    }

    @Test func centerInsertOfNothingIntoEmptyPaneIsANoOp() throws {
        let s = session(mainWindow(1, h(1, [p(1, 1), p(2)]), focus: 1))
        let r = try apply(.insert(nil, at: pid(2), edge: .center, in: wid(1)), to: s)
        #expect(r.isIdentity(of: s, WorkspaceRuntime()))
    }

    @Test func centerInsertIntoOccupiedPaneThrows() {
        expectFailure(.insert(new(9), at: pid(1), edge: .center, in: wid(1)), on: twoWindows, .centerInsertIntoOccupiedPane)
        expectFailure(.insert(nil, at: pid(1), edge: .center, in: wid(1)), on: twoWindows, .centerInsertIntoOccupiedPane)
    }
}

@Suite("§6.2 insert into empty window and open main window")
struct EmptyWindowTests {
    let empty = session(mainWindow(1, nil), detachedWindow(2, p(3, 3)))

    @Test func insertIntoEmptyWindow() throws {
        let r = try apply(.insertIntoEmptyWindow(new(9), in: wid(1)), to: empty)
        #expect(r.session.root == .pane(id: drawnPane(1), content: cid(9)))
        #expect(r.session.windows[0].activePane == drawnPane(1))
        #expect(r.session.contents.map(\.id) == [cid(3), cid(9)])
        #expect(r.session.contents.last?.state == Data())
    }

    @Test func insertEmptyPaneIntoEmptyWindow() throws {
        let r = try apply(.insertIntoEmptyWindow(nil, in: wid(1)), to: empty)
        #expect(r.session.root == .pane(id: drawnPane(1), content: nil))
        #expect(r.session.contents == empty.contents)
    }

    @Test func insertIntoEmptyWindowFailures() {
        expectFailure(.insertIntoEmptyWindow(new(9), in: wid(99)), on: empty, .unknownWindow(wid(99)))
        expectFailure(.insertIntoEmptyWindow(new(9), in: wid(2)), on: empty, .windowNotEmpty(wid(2)))
        expectFailure(.insertIntoEmptyWindow(new(9), in: wid(1)), on: twoWindows, .windowNotEmpty(wid(1)))
        expectFailure(.insertIntoEmptyWindow(new(3), in: wid(1)), on: empty, .contentAlreadyHosted(cid(3)))
        expectFailure(.insertIntoEmptyWindow(new(9), in: wid(1)), on: empty, runtime: pendingWindow(1), .windowClosePending(wid(1)))
        // A detached window with root == nil is invalid, but still not a target.
        expectFailure(.insertIntoEmptyWindow(nil, in: wid(5)), on: session(detachedWindow(5, nil)), .windowNotEmpty(wid(5)))
    }

    @Test func openMainWindow() throws {
        let zero = Session()
        let r = try apply(.openMainWindow(wid(7), placement: placement), to: zero)
        #expect(r.session.windows == [mainWindow(7, nil)])
        #expect(r.windowsCreated == [wid(7)])

        let onlyDetached = session(detachedWindow(2, p(3, 3)))
        let r2 = try apply(.openMainWindow(wid(7), placement: placement), to: onlyDetached)
        #expect(r2.session.windows.map(\.id) == [wid(2), wid(7)], "appended in creation order")
    }

    @Test func openMainWindowFailures() {
        expectFailure(.openMainWindow(wid(7), placement: placement), on: twoWindows, .mainWindowExists(wid(1)))
        expectFailure(.openMainWindow(wid(2), placement: placement), on: session(detachedWindow(2, p(3, 3))), .windowIDInUse(wid(2)))
    }
}

@Suite("§6.2 self-drop")
struct SelfDropTests {
    @Test("Self-drop is identity on every edge", arguments: allEdges)
    func selfDrop(edge: DropEdge) throws {
        let r = try apply(.move(cid(1), to: pid(1), edge: edge, in: wid(1)), to: twoWindows)
        #expect(r.isIdentity(of: twoWindows, WorkspaceRuntime()))
    }

    @Test("Self-drop on a pending pane or in a pending window is still identity", arguments: allEdges)
    func selfDropWhilePending(edge: DropEdge) throws {
        for runtime in [pendingPane(1), pendingWindow(1)] {
            let r = try apply(.move(cid(1), to: pid(1), edge: edge, in: wid(1)), to: twoWindows, runtime: runtime)
            #expect(r.isIdentity(of: twoWindows, runtime))
        }
    }

    @Test func selfDropIgnoresTheWindowArgument() throws {
        let r = try apply(.move(cid(1), to: pid(1), edge: .left, in: wid(99)), to: twoWindows)
        #expect(r.isIdentity(of: twoWindows, WorkspaceRuntime()))
    }

    @Test func selfDropOfUnhostedContentThrows() {
        expectFailure(.move(cid(99), to: pid(1), edge: .center, in: wid(1)), on: twoWindows, .unknownContent(cid(99)))
    }
}

@Suite("§6.2 edge move, swap, move into empty window, dock")
struct MoveTests {
    @Test func edgeMoveWithinWindow() throws {
        let s = session(mainWindow(1, h(1, [p(1, 1), p(2, 2), p(3, 3)], [0.5, 0.25, 0.25]), active: 2, focus: 2))
        let r = try apply(.move(cid(1), to: pid(3), edge: .right, in: wid(1)), to: s)
        #expect(r.session.root == h(1, [p(2, 2), p(3, 3), .pane(id: drawnPane(1), content: cid(1))], [0.5, 0.25, 0.25]))
        #expect(r.session.contents == s.contents, "records untouched")
        #expect(r.session.windows[0].focusModePane == nil)
        #expect(r.released.isEmpty)
    }

    @Test func edgeMoveOfActivePaneMovesActiveToNearestSibling() throws {
        let s = session(mainWindow(1, h(1, [p(1, 1), p(2, 2), p(3, 3)]), active: 1))
        let r = try apply(.move(cid(1), to: pid(3), edge: .bottom, in: wid(1)), to: s)
        #expect(r.session.windows[0].activePane == pid(2))
    }

    @Test func edgeMoveOntoSiblingThatCollapses() throws {
        // Removing A collapses H into B; B then splits vertically.
        let s = session(mainWindow(1, h(1, [p(1, 1), p(2, 2)])))
        let r = try apply(.move(cid(1), to: pid(2), edge: .top, in: wid(1)), to: s)
        #expect(r.session.root == .split(id: drawnSplit(2), axis: .vertical,
                                         children: [.pane(id: drawnPane(1), content: cid(1)), p(2, 2)], fractions: [0.5, 0.5]))
        #expect(r.normalizations == [.collapsed(sid(1))])
    }

    @Test func edgeMoveFailures() {
        expectFailure(.move(cid(99), to: pid(2), edge: .left, in: wid(1)), on: twoWindows, .unknownContent(cid(99)))
        expectFailure(.move(cid(1), to: pid(99), edge: .left, in: wid(1)), on: twoWindows, .unknownPane(pid(99)))
        expectFailure(.move(cid(1), to: pid(3), edge: .left, in: wid(1)), on: twoWindows, .unknownPane(pid(3)))
        expectFailure(.move(cid(1), to: pid(2), edge: .left, in: wid(99)), on: twoWindows, .unknownWindow(wid(99)))
        expectFailure(.move(cid(1), to: pid(2), edge: .left, in: wid(1)), on: twoWindows, runtime: pendingPane(1), .paneClosePending(pid(1)))
        expectFailure(.move(cid(1), to: pid(2), edge: .left, in: wid(1)), on: twoWindows, runtime: pendingPane(2), .paneClosePending(pid(2)))
        expectFailure(.move(cid(3), to: pid(2), edge: .left, in: wid(1)), on: twoWindows, runtime: pendingWindow(2), .windowClosePending(wid(2)))
        expectFailure(.move(cid(3), to: pid(2), edge: .left, in: wid(1)), on: twoWindows, runtime: pendingWindow(1), .windowClosePending(wid(1)))
    }

    @Test func swapExchangesContents() throws {
        let r = try apply(.move(cid(1), to: pid(2), edge: .center, in: wid(1)), to: twoWindows)
        #expect(r.session.root == h(1, [p(1, 2), p(2, 1)]))
        #expect(r.session.contents == twoWindows.contents)
        #expect(r.session.windows[0].activePane == pid(1), "panes stay; activePane names the slot")
        #expect(r.session.windows[0].focusModePane == nil)
        #expect(r.released.isEmpty && r.windowsClosed.isEmpty && r.normalizations.isEmpty)
    }

    @Test func centerMoveIntoEmptyPaneLeavesSourceEmpty() throws {
        let s = session(mainWindow(1, h(1, [p(1, 1), p(2)])))
        let r = try apply(.move(cid(1), to: pid(2), edge: .center, in: wid(1)), to: s)
        #expect(r.session.root == h(1, [p(1), p(2, 1)]))
    }

    @Test func swapFailures() {
        expectFailure(.move(cid(1), to: pid(2), edge: .center, in: wid(1)), on: twoWindows, runtime: pendingPane(1), .paneClosePending(pid(1)))
        expectFailure(.move(cid(1), to: pid(2), edge: .center, in: wid(1)), on: twoWindows, runtime: pendingPane(2), .paneClosePending(pid(2)))
    }

    @Test func dockEdgeClosesEmptiedDetachedWindow() throws {
        let r = try apply(.move(cid(3), to: pid(2), edge: .right, in: wid(1)), to: twoWindows)
        #expect(r.session.windows.map(\.id) == [wid(1)])
        #expect(r.windowsClosed == [wid(2)])
        #expect(r.session.root == h(1, [p(1, 1), p(2, 2), .pane(id: drawnPane(1), content: cid(3))], [0.5, 0.25, 0.25]))
        #expect(r.released.isEmpty)
        #expect(r.session.contents == twoWindows.contents)
    }

    @Test func dockCenterSwapsAcrossWindows() throws {
        let r = try apply(.move(cid(3), to: pid(1), edge: .center, in: wid(1)), to: twoWindows)
        #expect(r.session.root == h(1, [p(1, 3), p(2, 2)]))
        #expect(r.session.window(wid(2))?.root == p(3, 1))
        #expect(r.windowsClosed.isEmpty)
    }

    @Test func dockCenterIntoEmptyPaneClosesDetachedWindow() throws {
        let s = session(mainWindow(1, h(1, [p(1, 1), p(2)])), detachedWindow(2, p(3, 3)))
        let r = try apply(.move(cid(3), to: pid(2), edge: .center, in: wid(1)), to: s)
        #expect(r.session.windows.map(\.id) == [wid(1)])
        #expect(r.windowsClosed == [wid(2)])
        #expect(r.session.root == h(1, [p(1, 1), p(2, 3)]))
    }

    @Test func dockFromDetachedWindowWithMoreContentKeepsIt() throws {
        let s = session(mainWindow(1, p(1, 1)), detachedWindow(2, v(2, [p(3, 3), p(4, 4)]), active: 3))
        let r = try apply(.move(cid(3), to: pid(1), edge: .left, in: wid(1)), to: s)
        #expect(r.session.window(wid(2))?.root == p(4, 4))
        #expect(r.session.window(wid(2))?.activePane == pid(4))
        #expect(r.windowsClosed.isEmpty)
    }

    @Test func moveFromMainIntoDetachedWindowLeavesMainEmpty() throws {
        let s = session(mainWindow(1, p(1, 1), active: 1), detachedWindow(2, p(3, 3)))
        let r = try apply(.move(cid(1), to: pid(3), edge: .right, in: wid(2)), to: s)
        #expect(r.session.windows[0].root == nil)
        #expect(r.session.windows[0].activePane == nil)
        #expect(r.session.window(wid(2))?.root?.leaves.map(\.content) == [cid(3), cid(1)])
    }

    @Test func failedDockLeavesBothWindowsUnchanged() {
        expectFailure(.move(cid(3), to: pid(1), edge: .left, in: wid(1)), on: twoWindows, runtime: pendingPane(1), .paneClosePending(pid(1)))
        expectFailure(.move(cid(3), to: pid(1), edge: .center, in: wid(1)), on: twoWindows, runtime: pendingPane(3), .paneClosePending(pid(3)))
    }

    @Test func moveIntoEmptyWindowDocksAndClosesDetached() throws {
        let s = session(mainWindow(1, nil), detachedWindow(2, p(3, 3)))
        let r = try apply(.moveIntoEmptyWindow(cid(3), in: wid(1)), to: s)
        #expect(r.session.windows.map(\.id) == [wid(1)])
        #expect(r.session.root == .pane(id: drawnPane(1), content: cid(3)))
        #expect(r.windowsClosed == [wid(2)])
        #expect(r.released.isEmpty)
        #expect(r.session.contents == s.contents)
    }

    @Test func moveIntoEmptyWindowFailures() {
        let s = session(mainWindow(1, nil), detachedWindow(2, p(3, 3)), detachedWindow(4, p(4, 4)))
        expectFailure(.moveIntoEmptyWindow(cid(99), in: wid(1)), on: s, .unknownContent(cid(99)))
        expectFailure(.moveIntoEmptyWindow(cid(3), in: wid(99)), on: s, .unknownWindow(wid(99)))
        expectFailure(.moveIntoEmptyWindow(cid(3), in: wid(4)), on: s, .windowNotEmpty(wid(4)))
        expectFailure(.moveIntoEmptyWindow(cid(3), in: wid(1)), on: twoWindows, .windowNotEmpty(wid(1)))
        expectFailure(.moveIntoEmptyWindow(cid(3), in: wid(1)), on: s, runtime: pendingPane(3), .paneClosePending(pid(3)))
        expectFailure(.moveIntoEmptyWindow(cid(3), in: wid(1)), on: s, runtime: pendingWindow(1), .windowClosePending(wid(1)))
        expectFailure(.moveIntoEmptyWindow(cid(3), in: wid(1)), on: s, runtime: pendingWindow(2), .windowClosePending(wid(2)))
    }
}

@Suite("§6.2 reorder and resize")
struct ReorderResizeTests {
    let s = session(mainWindow(1, h(1, [p(1, 1), v(2, [p(2, 2), p(3, 3)]), p(4, 4)], [0.25, 0.5, 0.25])))

    @Test func reorderNestedSplit() throws {
        let r = try apply(.reorder(splitID: sid(2), from: 0, to: 1), to: s)
        #expect(r.session.root == h(1, [p(1, 1), v(2, [p(3, 3), p(2, 2)]), p(4, 4)], [0.25, 0.5, 0.25]))
        #expect(r.session.contents == s.contents)
    }

    @Test func reorderFailures() {
        expectFailure(.reorder(splitID: sid(1), from: 3, to: 0), on: s, .indexOutOfRange)
        expectFailure(.reorder(splitID: sid(1), from: 0, to: 3), on: s, .indexOutOfRange)
        expectFailure(.reorder(splitID: sid(1), from: -1, to: 0), on: s, .indexOutOfRange)
        expectFailure(.reorder(splitID: sid(99), from: 0, to: 1), on: s, .unknownSplit(sid(99)))
        expectFailure(.reorder(splitID: sid(1), from: 0, to: 1), on: s, runtime: pendingPane(4), .paneClosePending(pid(4)))
        expectFailure(.reorder(splitID: sid(1), from: 0, to: 1), on: s, runtime: pendingWindow(1), .windowClosePending(wid(1)))
    }

    @Test func resizeReplacesFractions() throws {
        let r = try apply(.resize(splitID: sid(1), fractions: [0.5, 0.25, 0.25]), to: s)
        #expect(fractions(r.session.root) == [0.5, 0.25, 0.25])
        #expect(r.normalizations.isEmpty)
    }

    @Test func resizeNormalisesAValidSum() throws {
        let r = try apply(.resize(splitID: sid(2), fractions: [2, 1]), to: s)
        guard case let .split(_, _, children, _) = r.session.root else { Issue.record("not a split"); return }
        #expect(approxEqual(fractions(children[1]), [2.0 / 3, 1.0 / 3]))
        #expect(r.normalizations == [.normalizedFractions(sid(2))])
    }

    @Test func resizeWithinToleranceIsStoredAsGiven() throws {
        let r = try apply(.resize(splitID: sid(2), fractions: [0.5 + 4e-10, 0.5]), to: s)
        #expect(r.normalizations.isEmpty)
    }

    @Test func resizeOfAGrandparentIgnoresPendingGrandchildren() throws {
        let r = try apply(.resize(splitID: sid(1), fractions: [0.5, 0.25, 0.25]), to: s, runtime: pendingPane(2))
        #expect(r.runtime == pendingPane(2))
    }

    @Test("Resize rejects bad input", arguments: [
        ([0.5, 0.5], "expected 3 fractions, got 2"),
        ([0.5, .nan, 0.5], "non-finite fraction"),
        ([0.5, .infinity, 0.5], "non-finite fraction"),
        ([0.5, 0, 0.5], "fraction ≤ 0"),
        ([0.5, -0.25, 0.75], "fraction ≤ 0"),
        ([.greatestFiniteMagnitude, .greatestFiniteMagnitude, 1], "sum of fractions is not finite"),
        ([5e-324, 1e300, 1], "fraction underflows to 0 when normalised"),
    ])
    func resizeInvalid(input: [Double], reason: String) {
        expectFailure(.resize(splitID: sid(1), fractions: input), on: s, .invalidFractions(reason: reason))
    }

    @Test func resizeFailures() {
        expectFailure(.resize(splitID: sid(99), fractions: [0.5, 0.5]), on: s, .unknownSplit(sid(99)))
        expectFailure(.resize(splitID: sid(2), fractions: [0.5, 0.5]), on: s, runtime: pendingPane(3), .paneClosePending(pid(3)))
        expectFailure(.resize(splitID: sid(2), fractions: [0.5, 0.5]), on: s, runtime: pendingWindow(1), .windowClosePending(wid(1)))
    }
}

@Suite("§6.2 detach")
struct DetachTests {
    let other = SavedPlacement(intendedFrame: CGRect(x: 24, y: 24, width: 400, height: 300), displayID: "d", relativeOrigin: CGPoint(x: 24, y: 24))

    @Test func detachCreatesWindow() throws {
        let r = try apply(.detach(pid(2), to: wid(5), placement: other), to: twoWindows)
        #expect(r.session.windows.map(\.id) == [wid(1), wid(2), wid(5)])
        #expect(r.session.windows[2] == WindowLayout(id: wid(5), kind: .detached, root: .pane(id: drawnPane(1), content: cid(2)), placement: other))
        #expect(r.session.root == p(1, 1))
        #expect(r.normalizations == [.collapsed(sid(1))])
        #expect(r.windowsCreated == [wid(5)])
        #expect(r.session.contents == twoWindows.contents)
        #expect(r.session.windows[0].focusModePane == nil)
    }

    @Test func detachOnlyPaneOfMainLeavesEmptyState() throws {
        let s = session(mainWindow(1, p(1, 1), active: 1))
        let r = try apply(.detach(pid(1), to: wid(5), placement: other), to: s)
        #expect(r.session.windows[0].root == nil)
        #expect(r.session.windows[0].activePane == nil)
        #expect(r.session.windows.count == 2)
    }

    @Test func detachOnlyPaneOfDetachedWindowClosesIt() throws {
        let r = try apply(.detach(pid(3), to: wid(5), placement: other), to: twoWindows)
        #expect(r.session.windows.map(\.id) == [wid(1), wid(5)])
        #expect(r.windowsCreated == [wid(5)])
        #expect(r.windowsClosed == [wid(2)])
    }

    @Test func detachFailures() {
        let withEmpty = session(mainWindow(1, h(1, [p(1, 1), p(2)])))
        expectFailure(.detach(pid(2), to: wid(5), placement: other), on: withEmpty, .unknownContent(.emptyPane))
        expectFailure(.detach(pid(99), to: wid(5), placement: other), on: twoWindows, .unknownPane(pid(99)))
        expectFailure(.detach(pid(1), to: wid(2), placement: other), on: twoWindows, .windowIDInUse(wid(2)))
        expectFailure(.detach(pid(1), to: wid(5), placement: other), on: twoWindows, runtime: pendingPane(1), .paneClosePending(pid(1)))
        expectFailure(.detach(pid(1), to: wid(5), placement: other), on: twoWindows, runtime: pendingWindow(1), .windowClosePending(wid(1)))
    }
}

@Suite("§7.3 setFocusMode and setActive")
struct FocusTests {
    @Test func focusModeSetsBothFields() throws {
        let r = try apply(.setFocusMode(pid(2), in: wid(1)), to: twoWindows)
        #expect(r.session.windows[0].focusModePane == pid(2))
        #expect(r.session.windows[0].activePane == pid(2))
        let cleared = try apply(.setFocusMode(nil, in: wid(1)), to: r.session)
        #expect(cleared.session.windows[0].focusModePane == nil)
        #expect(cleared.session.windows[0].activePane == pid(2))
        #expect(cleared.session.root == twoWindows.root, "tree untouched")
    }

    @Test func setActive() throws {
        let r = try apply(.setActive(pid(2), in: wid(1)), to: twoWindows)
        #expect(r.session.windows[0].activePane == pid(2))
        #expect(r.session.windows[0].focusModePane == pid(1))
        let cleared = try apply(.setActive(nil, in: wid(1)), to: r.session)
        #expect(cleared.session.windows[0].activePane == nil)
    }

    @Test func focusFailures() {
        for t: (PaneID?, WindowID) -> LayoutTransaction in [{ .setFocusMode($0, in: $1) }, { .setActive($0, in: $1) }] {
            expectFailure(t(pid(3), wid(1)), on: twoWindows, .unknownPane(pid(3)))
            expectFailure(t(pid(1), wid(99)), on: twoWindows, .unknownWindow(wid(99)))
            expectFailure(t(pid(1), wid(1)), on: twoWindows, runtime: pendingPane(1), .paneClosePending(pid(1)))
            expectFailure(t(nil, wid(1)), on: twoWindows, runtime: pendingWindow(1), .windowClosePending(wid(1)))
        }
    }
}

@Suite("§6.5 content record lifecycle and .unavailable")
struct RecordLifecycleTests {
    var s: Session {
        var s = session(mainWindow(1, h(1, [p(1, 1), p(2, 2)])), detachedWindow(2, p(3, 3)))
        s.contents[0] = record(cid(1), state: Data([9, 9]), availability: .unavailable)
        return s
    }

    @Test func unavailableContentTakesPartInEveryTransaction() throws {
        let edge = try apply(.move(cid(1), to: pid(2), edge: .bottom, in: wid(1)), to: s)
        #expect(edge.session.contents == s.contents)
        let swap = try apply(.move(cid(1), to: pid(3), edge: .center, in: wid(2)), to: s)
        #expect(swap.session.contents == s.contents)
        #expect(swap.session.window(wid(2))?.root == p(3, 1))
        let detach = try apply(.detach(pid(1), to: wid(5), placement: placement), to: s)
        #expect(detach.session.contents == s.contents)
        let closed = try close(pid(1), in: s)
        #expect(closed.released == [cid(1)])
        #expect(closed.session.contents.map(\.id) == [cid(2), cid(3)])
    }

    @Test func recordsKeepInsertionOrderAndStateAcrossOperations() throws {
        var current = s
        for t: LayoutTransaction in [.insert(new(7), at: pid(2), edge: .left, in: wid(1)),
                                     .reorder(splitID: sid(1), from: 0, to: 2),
                                     .resize(splitID: sid(1), fractions: [1, 1, 2]),
                                     .setActive(pid(2), in: wid(1)),
                                     .move(cid(7), to: pid(3), edge: .top, in: wid(2))] {
            current = try apply(t, to: current).session
        }
        #expect(current.contents.map(\.id) == [cid(1), cid(2), cid(3), cid(7)])
        #expect(Array(current.contents.prefix(3)) == s.contents)
        #expect(current.contents[3].state.isEmpty, "not captured yet")
    }
}
