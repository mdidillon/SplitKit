import AppKit
import SwiftUI
import Testing
@testable import SpikeACore

/// Integration: two real NSWindows with NSHostingViews; transfers via the coordinator API and
/// the real NSDraggingDestination methods (no mouse).
@MainActor @Suite(.serialized) struct WindowTransferTests {
    @Test func counterMovesWithIdentityStateAndResponder() async throws {
        let f = try TwoWindowFixture()
        defer { f.close() }
        f.counter.count = 7
        f.counter.note = "hello"
        #expect(f.a1.takeFirstResponder())
        #expect(f.windowA.firstResponder.map { $0 is NSTextView } == true, "a SwiftUI TextField's field editor holds focus")
        weak let weakContainer = f.a1.container
        weak let weakHosting = f.a1.container?.hostingView
        #expect(weakContainer != nil && weakHosting != nil)

        let outcome = try f.coordinator.moveToOtherWindow(f.counter.id)
        await f.settle()

        #expect(outcome.moved && outcome.sourceHadResponder && outcome.responderInDestination)
        #expect(f.coordinator.store[f.counter.id] === f.counter, "same object, never recreated")
        #expect(f.b1.hostedContent === f.counter)
        #expect(f.counter.count == 7 && f.counter.note == "hello")
        #expect(f.counter.attachmentCount == 1)
        #expect(f.counter.makeViewCalls == 2, "re-hosting builds a new view for the same object")
        #expect(f.coordinator.registry.host(of: f.counter.id) == f.b1.hostID)
        #expect(f.b1.containsFirstResponder())
        #expect(!f.a1.containsFirstResponder())
        let editor = try #require(f.windowB.firstResponder as? NSTextView)
        #expect(editor.isFieldEditor && (editor.delegate as? NSView)?.isDescendant(of: f.b1) == true)

        // Typing goes to the moved text field and into the same content object.
        editor.insertText("!", replacementRange: editor.selectedRange())
        await f.settle()
        #expect(f.counter.note.contains("!"), "typed text reached the moved content (note=\(f.counter.note))")

        let r = f.residue()
        #expect(r.windows[0].contentContainers == 1 && r.windows[0].hostedContents == [f.spinner.id])
        #expect(r.windows[1].contentContainers == 1 && r.windows[1].hostedContents == [f.counter.id])
        #expect(r.windows.allSatisfy { $0.placeholders == 0 && $0.highlights == 0 })

        await f.settle(0.2)
        #expect(weakContainer == nil, "old hosting container was deallocated")
        #expect(weakHosting == nil, "old NSHostingView was deallocated")
    }

    @Test func spinnerMovesWithIdentityAngleAndResponder() async throws {
        let f = try TwoWindowFixture()
        defer { f.close() }
        f.spinner.angle = 1.2345
        #expect(f.a2.takeFirstResponder())
        #expect(f.windowA.firstResponder === f.a2)

        let outcome = try f.coordinator.move(f.spinner.id, to: f.b2.hostID)
        await f.settle()

        #expect(outcome.moved && outcome.responderInDestination)
        #expect(f.coordinator.store[f.spinner.id] === f.spinner)
        #expect(f.b2.hostedContent === f.spinner)
        #expect(f.spinner.angle == 1.2345)
        #expect(f.spinner.attachmentCount == 1)
        #expect(f.windowB.firstResponder === f.b2)
        #expect(f.windowA.firstResponder !== f.a2)
    }

    @Test func liveRotationContinuesAcrossMoveWithOneDriver() async throws {
        let f = try TwoWindowFixture(autoRotate: true)
        defer { f.close() }
        await f.settle(0.2)
        let beforeMove = f.spinner.angle
        #expect(beforeMove > 0, "driver is running")
        try f.coordinator.move(f.spinner.id, to: f.b1.hostID)
        #expect(f.spinner.angle >= beforeMove, "angle carried over, not reset")
        #expect(f.spinner.isTicking && f.spinner.attachmentCount == 1)
        await f.settle(0.2)
        #expect(f.spinner.angle > beforeMove, "keeps rotating in the destination")
    }

    @Test func cancelledDragLeavesNoResidue() async throws {
        let f = try TwoWindowFixture()
        defer { f.close() }
        f.counter.count = 3
        #expect(f.a1.takeFirstResponder())
        let before = f.residue()
        let responderBefore = f.windowA.firstResponder

        let t = try f.coordinator.beginTransfer(f.counter.id)
        #expect(f.residue().windows[0].placeholders == 1, "source shows a placeholder while dragging")
        // Hover over a valid target, then leave it (as when the user drags back out).
        let info = FakeDraggingInfo(payload: DragPayload(session: t.id, content: f.counter.id), window: f.windowB)
        #expect(f.b1.draggingEntered(info) == .move)
        #expect(f.b1.highlight != nil)
        f.b1.draggingExited(info)
        // Esc / drop outside: AppKit ends the session with no operation.
        f.coordinator.endDrag(t.id, operation: [])
        await f.settle()

        #expect(f.residue() == before)
        #expect(f.windowA.firstResponder === responderBefore)
        #expect(f.counter.count == 3 && f.counter.makeViewCalls == 1, "no re-host happened")
    }

    @Test func failedDropOnInvalidTargetLeavesNoResidue() async throws {
        let f = try TwoWindowFixture()
        defer { f.close() }
        let before = f.residue()

        let t = try f.coordinator.beginTransfer(f.counter.id)
        let duringRegistry = f.coordinator.registry.encodedSnapshot()
        let payload = DragPayload(session: t.id, content: f.counter.id)
        for target in [f.locked, f.a2] { // locked pane, and a pane occupied by the spinner
            let info = FakeDraggingInfo(payload: payload, window: target.window)
            #expect(target.draggingEntered(info) == [])
            #expect(target.highlight?.accepts == false, "invalid target shows a reject highlight")
            #expect(target.performDragOperation(info) == false)
            target.draggingEnded(info)
            #expect(target.highlight == nil)
            #expect(f.coordinator.registry.encodedSnapshot() == duringRegistry, "failed drop mutated nothing")
        }
        f.coordinator.endDrag(t.id, operation: [])
        await f.settle()

        #expect(f.residue() == before)
        #expect(f.counter.makeViewCalls == 1 && f.spinner.makeViewCalls == 1)
    }

    @Test func dropThroughDraggingDestinationMovesContent() async throws {
        let f = try TwoWindowFixture()
        defer { f.close() }
        let t = try f.coordinator.beginTransfer(f.counter.id)
        let info = FakeDraggingInfo(payload: DragPayload(session: t.id, content: f.counter.id), window: f.windowB)
        #expect(f.b2.draggingEntered(info) == .move)
        #expect(f.b2.performDragOperation(info))
        f.b2.concludeDragOperation(info)
        f.coordinator.endDrag(t.id, operation: .move) // AppKit's source callback after the drop
        await f.settle()

        #expect(f.b2.hostedContent === f.counter)
        #expect(f.a1.hostedContent == nil)
        let r = f.residue()
        #expect(r.windows.allSatisfy { $0.placeholders == 0 && $0.highlights == 0 })
        #expect(r.windows.map(\.contentContainers) == [1, 1])
        #expect(f.coordinator.registry.activeTransfer == nil)
    }

    @Test func selfDropIsNoOp() async throws {
        let f = try TwoWindowFixture()
        defer { f.close() }
        let before = f.residue()
        let t = try f.coordinator.beginTransfer(f.counter.id)
        let info = FakeDraggingInfo(payload: DragPayload(session: t.id, content: f.counter.id), window: f.windowA)
        #expect(f.a1.draggingEntered(info) == [])
        #expect(f.a1.performDragOperation(info) == false)
        f.coordinator.endDrag(t.id, operation: [])
        await f.settle()
        #expect(f.residue() == before)
        #expect(f.counter.makeViewCalls == 1)
    }

    @Test func doubleHostThroughCoordinatorThrows() async throws {
        let f = try TwoWindowFixture()
        defer { f.close() }
        let before = f.residue()
        #expect(throws: TransferError.contentAlreadyHosted(f.counter.id, in: f.a1.hostID)) {
            try f.coordinator.add(f.counter, to: f.b1.hostID)
        }
        #expect(f.residue() == before)
    }

    @Test func rapidRepeatedTransfersKeepOneHost() async throws {
        let f = try TwoWindowFixture()
        defer { f.close() }
        f.counter.count = 42
        f.spinner.angle = 0.5
        let targets = [f.a1, f.a2, f.b1, f.b2, f.locked]
        var rng = SplitMix64(seed: 0xA11CE)
        var weakHostingViews: [() -> NSHostingView<AnyView>?] = []
        var moves = 0
        for _ in 0..<300 {
            let content: any SpikeContent = rng.next() % 2 == 0 ? f.counter : f.spinner
            let target = targets[Int(rng.next() % UInt64(targets.count))]
            if let old = f.coordinator.allPanes.first(where: { $0.hostedContent === content })?.container?.hostingView {
                weak let w = old
                weakHostingViews.append { w }
            }
            if (try? f.coordinator.move(content.id, to: target.hostID))?.moved == true { moves += 1 }

            let r = f.residue()
            let hosted = r.windows.flatMap(\.hostedContents)
            #expect(hosted.sorted() == [f.counter.id, f.spinner.id].sorted(), "each content in exactly one pane")
            #expect(r.windows.reduce(0) { $0 + $1.hostingViews } == 2)
            #expect(r.windows.allSatisfy { $0.placeholders == 0 && $0.highlights == 0 })
            #expect(f.coordinator.ledger.claims.count == 2)
            #expect(r.attachmentCounts == [1, 1])
            #expect(f.coordinator.registry.invariantViolations().isEmpty)
        }
        await f.settle(0.2)
        #expect(moves > 50)
        #expect(f.counter.count == 42 && f.spinner.angle == 0.5)
        let live = weakHostingViews.filter { $0().map { $0.window == nil } ?? false }.count
        #expect(live <= 2, "detached hosting views are freed (still alive: \(live))")
    }
}

/// The debug assertion itself: hosting one content in two panes traps (spec §6.4, §12).
@Suite struct DoubleHostAssertionTests {
    @Test func ledgerDoubleClaimTraps() async {
        await #expect(processExitsWith: .failure) {
            await MainActor.run {
                let ledger = HostingLedger()
                let content = ContentID()
                ledger.claim(content, by: HostID())
                ledger.claim(content, by: HostID())
            }
        }
    }

    @Test func installingOneContentInTwoPanesTraps() async {
        await #expect(processExitsWith: .failure) {
            await MainActor.run {
                let ledger = HostingLedger()
                let counter = CounterContent()
                PaneHostView(ledger: ledger).install(counter)
                PaneHostView(ledger: ledger).install(counter)
            }
        }
    }

    /// Control for the test above: a single install in the same child-process setup exits cleanly,
    /// so the trap comes from the double-host assertion and not from the environment.
    @Test func installingOneContentOnceExitsCleanly() async {
        await #expect(processExitsWith: .success) {
            await MainActor.run {
                let ledger = HostingLedger()
                let counter = CounterContent()
                PaneHostView(ledger: ledger).install(counter)
                PaneHostView(ledger: ledger).install(CounterContent())
            }
        }
    }

    @Test @MainActor func sameHostReclaimIsAllowed() {
        let ledger = HostingLedger()
        let content = ContentID(), host = HostID()
        #expect(ledger.claim(content, by: host))
        #expect(ledger.claim(content, by: host))
        ledger.release(content, by: host)
        #expect(ledger.claims.isEmpty)
    }
}
