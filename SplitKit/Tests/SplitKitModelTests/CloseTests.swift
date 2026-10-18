import Foundation
import Testing
@testable import SplitKitModel

@Suite("§6.3 two-stage pane close")
struct PaneCloseTests {
    /// Main: H[A(c1), V[B(c2), C(c3)]]; detached 2: D(c4).
    let s = session(mainWindow(1, h(1, [p(1, 1), v(2, [p(2, 2), p(3, 3)])]), active: 2), detachedWindow(2, p(4, 4)))

    @Test func beginCloseMarksPendingOnly() throws {
        let r = try apply(.beginClose(pid(2)), to: s)
        #expect(r.session == s)
        #expect(encoded(r.session) == encoded(s), "pending state is runtime-only, never encoded")
        #expect(r.runtime.pendingCloses == [pid(2)])
        #expect(r.released.isEmpty)
    }

    @Test func acceptCommitsRemovalAndReleases() throws {
        let begun = try apply(.beginClose(pid(2)), to: s)
        let r = try apply(.commitClose(pid(2)), to: begun.session, runtime: begun.runtime)
        #expect(r.session.root == h(1, [p(1, 1), p(3, 3)]))
        #expect(r.released == [cid(2)])
        #expect(r.session.contents.map(\.id) == [cid(1), cid(3), cid(4)])
        #expect(r.runtime == WorkspaceRuntime())
        #expect(r.normalizations == [.collapsed(sid(2))])
        #expect(r.session.windows[0].activePane == pid(3))
    }

    @Test func declineCancelsAndChangesNothingElse() throws {
        let begun = try apply(.beginClose(pid(2)), to: s)
        let r = try apply(.cancelClose(pid(2)), to: begun.session, runtime: begun.runtime)
        #expect(r.isIdentity(of: s, WorkspaceRuntime()))
    }

    @Test("Concurrent operations on a pending pane throw paneClosePending")
    func concurrentOperations() throws {
        let rt = pendingPane(2)
        let blocked: [LayoutTransaction] = [
            .move(cid(2), to: pid(1), edge: .left, in: wid(1)),        // move from P
            .move(cid(1), to: pid(2), edge: .center, in: wid(1)),      // swap into P
            .move(cid(4), to: pid(2), edge: .right, in: wid(1)),       // dock next to P
            .detach(pid(2), to: wid(9), placement: placement),
            .resize(splitID: sid(2), fractions: [0.5, 0.5]),           // P's parent
            .reorder(splitID: sid(2), from: 0, to: 1),
            .beginClose(pid(2)),                                       // second close
            .insert(new(9), at: pid(2), edge: .top, in: wid(1)),
            .setActive(pid(2), in: wid(1)),
            .setFocusMode(pid(2), in: wid(1)),
            .beginCloseWindow(wid(1)),
        ]
        for t in blocked { expectFailure(t, on: s, runtime: rt, .paneClosePending(pid(2))) }

        // Elsewhere, transactions proceed and keep the pending flag.
        let elsewhere = try apply(.move(cid(1), to: pid(4), edge: .left, in: wid(2)), to: s, runtime: rt)
        #expect(elsewhere.runtime == rt)
        let resizeOuter = try apply(.resize(splitID: sid(1), fractions: [0.25, 0.75]), to: s, runtime: rt)
        #expect(resizeOuter.runtime == rt)
        // A self-drop on P stays a no-op.
        let selfDrop = try apply(.move(cid(2), to: pid(2), edge: .center, in: wid(1)), to: s, runtime: rt)
        #expect(selfDrop.isIdentity(of: s, rt))
        // P's PaneID is stable, so commit still works after the unrelated move.
        let committed = try apply(.commitClose(pid(2)), to: elsewhere.session, runtime: elsewhere.runtime)
        #expect(committed.released == [cid(2)])
    }

    @Test func commitAndCancelWithoutBeginThrow() {
        expectFailure(.commitClose(pid(2)), on: s, .noCloseInProgress(pid(2)))
        expectFailure(.cancelClose(pid(2)), on: s, .noCloseInProgress(pid(2)))
        expectFailure(.beginClose(pid(99)), on: s, .unknownPane(pid(99)))
        expectFailure(.commitClose(pid(99)), on: s, runtime: pendingPane(99), .unknownPane(pid(99)))
        expectFailure(.cancelClose(pid(99)), on: s, runtime: pendingPane(99), .unknownPane(pid(99)))
    }

    @Test func paneTransactionsInPendingWindowThrowWindowClosePending() {
        for t: LayoutTransaction in [.beginClose(pid(1)), .commitClose(pid(1)), .cancelClose(pid(1))] {
            expectFailure(t, on: s, runtime: pendingWindow(1), .windowClosePending(wid(1)))
        }
    }

    @Test func lastPaneOfMainWindowLeavesEmptyState() throws {
        let r = try close(pid(1), in: session(mainWindow(1, p(1, 1), active: 1, focus: 1)))
        #expect(r.session.windows == [mainWindow(1, nil)])
        #expect(r.released == [cid(1)])
        #expect(r.session.contents.isEmpty)
        #expect(r.windowsClosed.isEmpty)
    }

    @Test func lastContentOfDetachedWindowClosesIt() throws {
        let r = try close(pid(4), in: s)
        #expect(r.session.windows.map(\.id) == [wid(1)])
        #expect(r.windowsClosed == [wid(2)])
        #expect(r.released == [cid(4)])
    }

    @Test func detachedWindowWithOnlyEmptyPanesLeftCloses() throws {
        let d = session(mainWindow(1, p(1, 1)), detachedWindow(2, h(2, [p(3, 3), p(4)])))
        let r = try close(pid(3), in: d)
        #expect(r.windowsClosed == [wid(2)])
        #expect(r.session.windows.count == 1)
    }

    @Test func autoClosingAWindowWithAPendingEmptyPaneThrows() throws {
        let d = session(mainWindow(1, p(1, 1)), detachedWindow(2, h(2, [p(3, 3), p(4)])))
        let rt = WorkspaceRuntime(pendingCloses: [pid(3), pid(4)])
        expectFailure(.commitClose(pid(3)), on: d, runtime: rt, .paneClosePending(pid(4)))
        // Committing the empty pane first works; the window still has content.
        let first = try apply(.commitClose(pid(4)), to: d, runtime: rt)
        #expect(first.released.isEmpty)
        #expect(first.session.window(wid(2))?.root == p(3, 3))
    }

    @Test func closingAnEmptyPaneReleasesNothing() throws {
        let r = try close(pid(2), in: session(mainWindow(1, h(1, [p(1, 1), p(2)]))))
        #expect(r.released.isEmpty)
        #expect(r.session.root == p(1, 1))
    }
}

@Suite("§6.3.6 replace content")
struct ReplaceContentTests {
    /// Main: H[A(c1) 0.25, B(c2) 0.75, C(empty)] with B active; detached 2: D(c4).
    let s = session(mainWindow(1, h(1, [p(1, 1), p(2, 2), p(3)], [0.25, 0.5, 0.25]), active: 2), detachedWindow(2, p(4, 4)))

    @Test func commitReplacesInPlace() throws {
        let begun = try apply(.beginClose(pid(2)), to: s)
        let r = try apply(.commitReplace(pid(2), with: new(9)), to: begun.session, runtime: begun.runtime)
        #expect(r.session.root == h(1, [p(1, 1), p(2, 9), p(3)], [0.25, 0.5, 0.25]), "PaneID, position and fraction are kept")
        #expect(r.released == [cid(2)])
        #expect(r.session.contents.map(\.id) == [cid(1), cid(4), cid(9)])
        #expect(r.session.contents.last == record(cid(9)))
        #expect(r.runtime == WorkspaceRuntime())
        #expect(r.session.windows[0].activePane == pid(2))
        #expect(r.windowsCreated.isEmpty && r.windowsClosed.isEmpty && r.normalizations.isEmpty)
    }

    @Test func replacesTheOnlyContentOfADetachedWindow() throws {
        let begun = try apply(.beginClose(pid(4)), to: s)
        let r = try apply(.commitReplace(pid(4), with: new(9)), to: begun.session, runtime: begun.runtime)
        #expect(r.session.window(wid(2))?.root == p(4, 9))
        #expect(r.windowsClosed.isEmpty)
    }

    @Test func replacesAnUnavailablePlaceholder() throws {
        var u = s
        u.contents[1].availability = .unavailable
        let begun = try apply(.beginClose(pid(2)), to: u)
        let r = try apply(.commitReplace(pid(2), with: new(9)), to: begun.session, runtime: begun.runtime)
        #expect(r.released == [cid(2)])
        #expect(r.session.contents.contains { $0.id == cid(9) && $0.availability == .hosted })
    }

    @Test func failuresLeaveSessionAndRuntimeUnchanged() {
        expectFailure(.commitReplace(pid(99), with: new(9)), on: s, runtime: pendingPane(99), .unknownPane(pid(99)))
        expectFailure(.commitReplace(pid(2), with: new(9)), on: s, .noCloseInProgress(pid(2)))
        expectFailure(.commitReplace(pid(3), with: new(9)), on: s, runtime: pendingPane(3), .unknownContent(.emptyPane))
        expectFailure(.commitReplace(pid(2), with: new(1)), on: s, runtime: pendingPane(2), .contentAlreadyHosted(cid(1)))
        expectFailure(.commitReplace(pid(2), with: new(2)), on: s, runtime: pendingPane(2), .contentAlreadyHosted(cid(2)))
        expectFailure(.commitReplace(pid(2), with: new(9)), on: s,
                      runtime: WorkspaceRuntime(pendingCloses: [pid(2)], pendingWindowCloses: [wid(1)]), .windowClosePending(wid(1)))
    }
}

@Suite("§6.3.4 window close")
struct WindowCloseTests {
    /// Main 1: H[A(c1), B, C(c3)]; detached 2: V[D(c4), E(c5)].
    let s = session(mainWindow(1, h(1, [p(1, 1), p(2), p(3, 3)])), detachedWindow(2, v(2, [p(4, 4), p(5, 5)])))

    @Test func allAcceptCommitsInOneTransaction() throws {
        let begun = try apply(.beginCloseWindow(wid(1)), to: s)
        #expect(begun.session == s)
        #expect(begun.runtime.pendingWindowCloses == [wid(1)])
        let r = try apply(.commitCloseWindow(wid(1)), to: begun.session, runtime: begun.runtime)
        #expect(r.session.windows.map(\.id) == [wid(2)])
        #expect(r.windowsClosed == [wid(1)])
        #expect(r.released == [cid(1), cid(3)], "depth-first order")
        #expect(r.session.contents.map(\.id) == [cid(4), cid(5)])
        #expect(r.runtime == WorkspaceRuntime())
    }

    @Test func oneDeclineClosesNothing() throws {
        let begun = try apply(.beginCloseWindow(wid(2)), to: s)
        // SplitKit asks D (accepts) then E (declines) → cancel.
        let r = try apply(.cancelCloseWindow(wid(2)), to: begun.session, runtime: begun.runtime)
        #expect(r.isIdentity(of: s, WorkspaceRuntime()))
    }

    @Test func closingTheLastWindowLeavesZeroWindowsThenOpenMain() throws {
        let only = session(mainWindow(1, nil))
        let begun = try apply(.beginCloseWindow(wid(1)), to: only)
        let r = try apply(.commitCloseWindow(wid(1)), to: begun.session, runtime: begun.runtime)
        #expect(r.session.windows.isEmpty)
        #expect(r.released.isEmpty)
        #expect(SessionEngine.validate(r.session).isEmpty, "zero windows is valid")
        let reopened = try apply(.openMainWindow(wid(3), placement: placement), to: r.session)
        #expect(reopened.session.windows.map(\.id) == [wid(3)])
    }

    @Test func transactionsTouchingAPendingWindowThrow() throws {
        let rt = pendingWindow(1)
        let blocked: [LayoutTransaction] = [
            .insert(new(9), at: pid(1), edge: .left, in: wid(1)),
            .move(cid(1), to: pid(4), edge: .left, in: wid(2)),
            .move(cid(4), to: pid(2), edge: .center, in: wid(1)),
            .beginClose(pid(1)),
            .beginCloseWindow(wid(1)),
            .resize(splitID: sid(1), fractions: [0.25, 0.25, 0.5]),
            .reorder(splitID: sid(1), from: 0, to: 1),
            .setActive(pid(1), in: wid(1)),
            .detach(pid(1), to: wid(9), placement: placement),
        ]
        for t in blocked { expectFailure(t, on: s, runtime: rt, .windowClosePending(wid(1))) }
        let elsewhere = try apply(.move(cid(4), to: pid(5), edge: .center, in: wid(2)), to: s, runtime: rt)
        #expect(elsewhere.runtime == rt)
    }

    @Test func windowCloseFailures() {
        expectFailure(.beginCloseWindow(wid(1)), on: s, runtime: pendingPane(3), .paneClosePending(pid(3)))
        expectFailure(.commitCloseWindow(wid(1)), on: s, .noWindowCloseInProgress(wid(1)))
        expectFailure(.cancelCloseWindow(wid(1)), on: s, .noWindowCloseInProgress(wid(1)))
        for t: LayoutTransaction in [.beginCloseWindow(wid(99)), .commitCloseWindow(wid(99)), .cancelCloseWindow(wid(99))] {
            expectFailure(t, on: s, runtime: pendingWindow(99), .unknownWindow(wid(99)))
        }
    }
}
