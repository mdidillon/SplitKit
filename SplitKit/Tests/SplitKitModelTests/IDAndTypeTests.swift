import Foundation
import Testing
@testable import SplitKitModel

@Suite("§5 / §6.1.9 ID generators")
struct IDGeneratorTests {
    @Test func sameSeedSameSequence() {
        var a = SeededIDGenerator(seed: 42), b = SeededIDGenerator(seed: 42)
        let first = (0..<100).map { _ in a.next() }
        #expect(first == (0..<100).map { _ in b.next() })
        #expect(Set(first).count == 100)
        var c = SeededIDGenerator(seed: 43)
        #expect(c.next() != first[0])
    }

    @Test("SplitMix64 reference vector (seed 0) mapped to UUID bytes")
    func referenceVector() {
        var raw = SeededIDGenerator(seed: 0)
        #expect(raw.nextUInt64() == 0xE220_A839_7B1D_CDAF)
        #expect(raw.nextUInt64() == 0x6E78_9E6A_A1B9_65F4)
        var g = SeededIDGenerator(seed: 0)
        // Byte 6 high nibble → 4 (version), byte 8 high bits → 10 (variant).
        #expect(g.next() == UUID(uuidString: "E220A839-7B1D-4DAF-AE78-9E6AA1B965F4"))
    }

    @Test func seededUUIDsAreVersion4Variant1() {
        var g = SeededIDGenerator(seed: 20_261_017)
        for _ in 0..<1000 {
            let u = g.next().uuid
            #expect(u.6 >> 4 == 4)
            #expect(u.8 >> 6 == 0b10)
        }
    }

    @Test func systemGeneratorProducesDistinctV4UUIDs() {
        var g = SystemIDGenerator()
        let a = g.next(), b = g.next()
        #expect(a != b)
        #expect(a.uuid.6 >> 4 == 4)
    }

    @Test func engineDrawsOnlyFromTheInjectedGenerator() throws {
        let s = session(mainWindow(1, p(1, 1)))
        var g1 = SeededIDGenerator(seed: 7), g2 = SeededIDGenerator(seed: 7)
        let r1 = try SessionEngine.apply(.insert(nil, at: pid(1), edge: .right, in: wid(1)), to: s, runtime: WorkspaceRuntime(), ids: &g1)
        let r2 = try SessionEngine.apply(.insert(nil, at: pid(1), edge: .right, in: wid(1)), to: s, runtime: WorkspaceRuntime(), ids: &g2)
        #expect(encoded(r1.session) == encoded(r2.session))
        var expected = SeededIDGenerator(seed: 7)
        let paneID = PaneID(raw: expected.next()), splitID = SplitID(raw: expected.next())
        #expect(r1.session.root == .split(id: splitID, axis: .horizontal, children: [p(1, 1), .pane(id: paneID, content: nil)], fractions: [0.5, 0.5]))
    }

    @Test func failedTransactionsDrawNothing() {
        var g = SequentialIDGenerator()
        _ = try? SessionEngine.apply(.insert(nil, at: pid(9), edge: .right, in: wid(1)), to: twoWindows, runtime: WorkspaceRuntime(), ids: &g)
        #expect(g.count == 0)
    }
}

@Suite("§5 types")
struct TypeTests {
    @Test func isFatalIsFalseOnlyForTheRecoverableCases() {
        #expect(!InvariantViolation.orphanRecord(cid(1)).isFatal)
        #expect(!InvariantViolation.danglingActivePane(wid(1)).isFatal)
        #expect(!InvariantViolation.danglingFocusModePane(wid(1)).isFatal)
        #expect(InvariantViolation.multipleMainWindows.isFatal)
    }

    @Test func dropEdgeArithmetic() {
        #expect(DropEdge.left.axis == .horizontal && DropEdge.right.axis == .horizontal)
        #expect(DropEdge.top.axis == .vertical && DropEdge.bottom.axis == .vertical)
        #expect(DropEdge.center.axis == nil)
        #expect(DropEdge.left.placesBefore && DropEdge.top.placesBefore)
        #expect(!DropEdge.right.placesBefore && !DropEdge.bottom.placesBefore)
    }

    @Test func recordDefaultsToHosted() {
        #expect(ContentRecord(id: cid(1), type: testType, stateVersion: 2, state: Data()).availability == .hosted)
    }

    @Test func runtimeIsEquatableAndDefaultsEmpty() {
        let drag = DragSessionID(raw: uuid(0x05, 1))
        #expect(WorkspaceRuntime() == WorkspaceRuntime(pendingCloses: [], pendingWindowCloses: [], activeDrag: nil))
        #expect(WorkspaceRuntime(activeDrag: drag) != WorkspaceRuntime())
    }

    @Test("Codable round trip; split axis key stays `axis`; geometry as nested arrays")
    func codableShape() throws {
        var s = twoWindows
        s.contents[1] = record(cid(2), state: Data([0xFF]), availability: .unavailable)
        let data = encoded(s)
        #expect(try JSONDecoder().decode(Session.self, from: data) == s)
        let json = String(decoding: data, as: UTF8.self)
        #expect(json.contains("\"axis\" : \"horizontal\""))
        #expect(json.contains("\"split\" : {"))
        #expect(json.contains("\"availability\" : \"unavailable\""))
        let frame = String(decoding: try JSONEncoder().encode(placement.intendedFrame), as: UTF8.self)
        #expect(frame == "[[0,0],[1200,800]]")
    }

    @Test func versionStartsAtCurrent() {
        #expect(Session().version == Session.currentVersion)
        #expect(Session.currentVersion == 1)
    }

    @Test func persistenceErrorIsEquatable() {
        #expect(PersistenceError.invalid([.multipleMainWindows]) == .invalid([.multipleMainWindows]))
    }
}
