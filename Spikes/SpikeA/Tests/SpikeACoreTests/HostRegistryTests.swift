import Foundation
import Testing
@testable import SpikeACore

/// Pure ownership model: single host, failed/cancelled transfers leave it byte-identical.
@Suite struct HostRegistryTests {
    let windowA = WindowID(), windowB = WindowID()
    let a1 = HostID(), b1 = HostID(), b2 = HostID(), locked = HostID()
    let counter = ContentID(), spinner = ContentID()

    func makeRegistry() throws -> HostRegistry {
        var r = HostRegistry()
        try r.addHost(a1, window: windowA)
        try r.addHost(b1, window: windowB)
        try r.addHost(b2, window: windowB)
        try r.addHost(locked, window: windowB, acceptsDrops: false)
        try r.place(counter, in: a1)
        return r
    }

    @Test func moveKeepsContentIDAndSingleHost() throws {
        var r = try makeRegistry()
        let t = try r.beginTransfer(counter)
        let decision = try r.completeTransfer(t.id, onto: b1)
        #expect(decision == .move(counter, from: a1, to: b1))
        #expect(r.host(of: counter) == b1)
        #expect(r.content(in: a1) == nil)
        #expect(r.placement.count == 1)
        #expect(r.activeTransfer == nil)
        #expect(r.invariantViolations().isEmpty)
    }

    @Test func doubleHostThrows() throws {
        var r = try makeRegistry()
        let before = r.encodedSnapshot()
        expectError(.contentAlreadyHosted(counter, in: a1)) { () throws(TransferError) in try r.place(counter, in: b1) }
        expectError(.contentAlreadyHosted(counter, in: a1)) { () throws(TransferError) in try r.place(counter, in: a1) }
        #expect(r.encodedSnapshot() == before)
    }

    @Test func occupiedHostThrows() throws {
        var r = try makeRegistry()
        expectError(.hostOccupied(a1, by: counter)) { () throws(TransferError) in try r.place(spinner, in: a1) }
    }

    @Test func cancelledTransferLeavesRegistryByteIdentical() throws {
        var r = try makeRegistry()
        let before = r.encodedSnapshot()
        let copy = r
        let t = try r.beginTransfer(counter)
        #expect(r.encodedSnapshot() != before)
        let cancelled = r.cancelTransfer(t.id)
        #expect(cancelled)
        #expect(r.encodedSnapshot() == before)
        #expect(r == copy)
        // Idempotent: a second cancel (AppKit end after our cancel) changes nothing.
        let cancelledAgain = r.cancelTransfer(t.id)
        #expect(!cancelledAgain)
        #expect(r.encodedSnapshot() == before)
    }

    @Test(arguments: ["locked", "occupied", "unknown", "stale"])
    func failedDropLeavesRegistryUnchanged(target kind: String) throws {
        var r = try makeRegistry()
        try r.place(spinner, in: b2)
        let beforeBegin = r.encodedSnapshot()
        let t = try r.beginTransfer(counter)
        let duringDrag = r.encodedSnapshot()
        let expected: TransferError
        let session: TransferSessionID
        let target: HostID
        switch kind {
        case "locked": (session, target, expected) = (t.id, locked, .hostRejectsDrops(locked))
        case "occupied": (session, target, expected) = (t.id, b2, .hostOccupied(b2, by: spinner))
        case "unknown":
            let ghost = HostID()
            (session, target, expected) = (t.id, ghost, .unknownHost(ghost))
        default:
            let stale = TransferSessionID()
            (session, target, expected) = (stale, b1, .noSuchTransfer(stale))
        }
        expectError(expected) { () throws(TransferError) in try r.completeTransfer(session, onto: target) }
        #expect(r.encodedSnapshot() == duringDrag)
        r.cancelTransfer(t.id)
        #expect(r.encodedSnapshot() == beforeBegin)
    }

    @Test func selfDropIsNoOp() throws {
        var r = try makeRegistry()
        let before = r.encodedSnapshot()
        let t = try r.beginTransfer(counter)
        #expect(try r.completeTransfer(t.id, onto: a1) == .selfDrop)
        #expect(r.encodedSnapshot() == before)
    }

    @Test func secondTransferWhileActiveThrows() throws {
        var r = try makeRegistry()
        try r.place(spinner, in: b2)
        let t = try r.beginTransfer(counter)
        expectError(.transferInProgress(t.id)) { () throws(TransferError) in try r.beginTransfer(spinner) }
    }

    @Test func rapidRandomTransfersKeepOneHost() throws {
        var r = try makeRegistry()
        try r.place(spinner, in: b2)
        let hosts = [a1, b1, b2, locked]
        var rng = SplitMix64(seed: 0x5A11_7A)
        var moves = 0
        for _ in 0..<5_000 {
            let content = rng.next() % 2 == 0 ? counter : spinner
            let target = hosts[Int(rng.next() % UInt64(hosts.count))]
            let t = try r.beginTransfer(content)
            if rng.next() % 5 == 0 {
                r.cancelTransfer(t.id)
            } else if (try? r.completeTransfer(t.id, onto: target)) == nil {
                r.cancelTransfer(t.id)
            } else {
                moves += 1
            }
            #expect(r.invariantViolations().isEmpty)
            #expect(r.placement.count == 2)
            #expect(Set(r.placement.values).count == 2)
            #expect(r.activeTransfer == nil)
        }
        #expect(moves > 1_000)
    }
}

/// `#expect(throws:)` cannot mutate a captured `var`; this non-escaping helper can.
func expectError<T>(
    _ expected: TransferError,
    sourceLocation: SourceLocation = #_sourceLocation,
    _ body: () throws(TransferError) -> T
) {
    do {
        _ = try body()
        Issue.record("expected \(expected), nothing was thrown", sourceLocation: sourceLocation)
    } catch {
        #expect(error == expected, sourceLocation: sourceLocation)
    }
}

/// Deterministic generator (seed recorded in the test) for reproducible sequences.
struct SplitMix64: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
