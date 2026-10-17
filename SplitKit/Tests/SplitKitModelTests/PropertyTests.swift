import Foundation
import Testing
@testable import SplitKitModel

private enum TxKind: String, CaseIterable {
    case insert, insertIntoEmptyWindow, move, moveIntoEmptyWindow, reorder, resize
    case beginClose, commitClose, cancelClose, beginCloseWindow, commitCloseWindow, cancelCloseWindow
    case openMainWindow, setFocusMode, setActive, detach

    init(_ t: LayoutTransaction) {
        self = switch t {
        case .insert: .insert
        case .insertIntoEmptyWindow: .insertIntoEmptyWindow
        case .move: .move
        case .moveIntoEmptyWindow: .moveIntoEmptyWindow
        case .reorder: .reorder
        case .resize: .resize
        case .beginClose: .beginClose
        case .commitClose: .commitClose
        case .cancelClose: .cancelClose
        case .beginCloseWindow: .beginCloseWindow
        case .commitCloseWindow: .commitCloseWindow
        case .cancelCloseWindow: .cancelCloseWindow
        case .openMainWindow: .openMainWindow
        case .setFocusMode: .setFocusMode
        case .setActive: .setActive
        case .detach: .detach
        }
    }

    /// Changes no pane and no content placement.
    var keepsPlacement: Bool {
        [.reorder, .resize, .beginClose, .cancelClose, .beginCloseWindow, .cancelCloseWindow, .setFocusMode, .setActive].contains(self)
    }

    /// The errors §6.2/§6.3 allow for this transaction.
    func allows(_ e: LayoutError) -> Bool {
        switch (self, e) {
        case (.insert, .unknownWindow), (.insert, .unknownPane), (.insert, .windowClosePending), (.insert, .paneClosePending),
             (.insert, .contentAlreadyHosted), (.insert, .centerInsertIntoOccupiedPane): true
        case (.insertIntoEmptyWindow, .unknownWindow), (.insertIntoEmptyWindow, .windowClosePending),
             (.insertIntoEmptyWindow, .windowNotEmpty), (.insertIntoEmptyWindow, .contentAlreadyHosted): true
        case (.move, .unknownContent), (.move, .unknownWindow), (.move, .unknownPane), (.move, .windowClosePending),
             (.move, .paneClosePending): true
        case (.moveIntoEmptyWindow, .unknownContent), (.moveIntoEmptyWindow, .unknownWindow), (.moveIntoEmptyWindow, .windowClosePending),
             (.moveIntoEmptyWindow, .paneClosePending), (.moveIntoEmptyWindow, .windowNotEmpty): true
        case (.reorder, .unknownSplit), (.reorder, .windowClosePending), (.reorder, .paneClosePending), (.reorder, .indexOutOfRange): true
        case (.resize, .unknownSplit), (.resize, .windowClosePending), (.resize, .paneClosePending), (.resize, .invalidFractions): true
        case (.beginClose, .unknownPane), (.beginClose, .windowClosePending), (.beginClose, .paneClosePending): true
        case (.commitClose, .unknownPane), (.commitClose, .windowClosePending), (.commitClose, .noCloseInProgress),
             (.commitClose, .paneClosePending): true
        case (.cancelClose, .unknownPane), (.cancelClose, .windowClosePending), (.cancelClose, .noCloseInProgress): true
        case (.beginCloseWindow, .unknownWindow), (.beginCloseWindow, .windowClosePending), (.beginCloseWindow, .paneClosePending): true
        case (.commitCloseWindow, .unknownWindow), (.commitCloseWindow, .noWindowCloseInProgress): true
        case (.cancelCloseWindow, .unknownWindow), (.cancelCloseWindow, .noWindowCloseInProgress): true
        case (.openMainWindow, .mainWindowExists), (.openMainWindow, .windowIDInUse): true
        case (.setFocusMode, .unknownWindow), (.setFocusMode, .unknownPane), (.setFocusMode, .windowClosePending),
             (.setFocusMode, .paneClosePending): true
        case (.setActive, .unknownWindow), (.setActive, .unknownPane), (.setActive, .windowClosePending), (.setActive, .paneClosePending): true
        case (.detach, .unknownPane), (.detach, .windowClosePending), (.detach, .paneClosePending), (.detach, .unknownContent),
             (.detach, .windowIDInUse): true
        default: false
        }
    }
}

private struct Leaf { var pane: PaneID; var content: ContentID?; var window: WindowID }

private extension Session {
    var allLeaves: [Leaf] {
        windows.flatMap { w in (w.root?.leaves ?? []).map { Leaf(pane: $0.pane, content: $0.content, window: w.id) } }
    }
    var allSplits: [(id: SplitID, count: Int)] {
        func collect(_ n: LayoutNode) -> [(SplitID, Int)] {
            guard case let .split(id, _, children, _) = n else { return [] }
            return [(id, children.count)] + children.flatMap(collect)
        }
        return windows.flatMap { $0.root.map(collect) ?? [] }
    }
    var allFractions: [[Double]] {
        func collect(_ n: LayoutNode) -> [[Double]] {
            guard case let .split(_, _, children, f) = n else { return [] }
            return [f] + children.flatMap(collect)
        }
        return windows.flatMap { $0.root.map(collect) ?? [] }
    }
}

/// Generates random transactions, mostly valid, some deliberately invalid, against the current state.
private struct Fuzzer {
    var rng: SplitMix64
    var serial = 0
    let maxPanes = 24

    init(seed: UInt64) { rng = SplitMix64(state: seed) }

    mutating func fresh(_ kind: UInt8) -> UUID {
        serial += 1
        return uuid(kind, serial)
    }

    mutating func edge() -> DropEdge { allEdges[rng.below(allEdges.count)] }

    mutating func target(_ s: Session) -> (PaneID, WindowID) {
        let leaves = s.allLeaves
        guard let leaf = rng.pick(leaves), !rng.chance(4) else {
            return (PaneID(raw: fresh(0x0B)), rng.pick(s.windows)?.id ?? WindowID(raw: fresh(0x0B)))
        }
        return (leaf.pane, rng.chance(4) ? rng.pick(s.windows)!.id : leaf.window)
    }

    mutating func window(_ s: Session, pending: Set<WindowID> = []) -> WindowID {
        if !pending.isEmpty, rng.chance(90) { return pending.sorted { $0.raw.uuidString < $1.raw.uuidString }[rng.below(pending.count)] }
        guard let w = rng.pick(s.windows), !rng.chance(4) else { return WindowID(raw: fresh(0x0B)) }
        return w.id
    }

    mutating func pendingPane(_ s: Session, _ rt: WorkspaceRuntime) -> PaneID {
        let pending = s.allLeaves.map(\.pane).filter(rt.pendingCloses.contains)
        if let p = rng.pick(pending), rng.chance(90) { return p }
        return target(s).0
    }

    mutating func newContent(_ s: Session) -> NewContent? {
        if rng.chance(20) { return nil }
        if rng.chance(4), let existing = rng.pick(s.contents) { return NewContent(id: existing.id, type: testType, stateVersion: 1) }
        return NewContent(id: ContentID(raw: fresh(0x0C)), type: testType, stateVersion: 1)
    }

    mutating func content(_ s: Session) -> ContentID {
        guard let c = rng.pick(s.contents), !rng.chance(4) else { return ContentID(raw: fresh(0x0B)) }
        return c.id
    }

    mutating func newWindow(_ s: Session) -> WindowID {
        if rng.chance(8), let w = rng.pick(s.windows) { return w.id }
        return WindowID(raw: fresh(0x0D))
    }

    mutating func fractionList(count: Int) -> [Double] {
        let n = rng.chance(5) ? max(0, count + (rng.chance(50) ? 1 : -1)) : count
        var values = (0..<n).map { _ in Double(rng.below(1000) + 1) / 1000 }
        if rng.chance(50) { values = values.map { $0 / values.reduce(0, +) } }
        if rng.chance(4), !values.isEmpty { values[rng.below(values.count)] = [.nan, 0, -0.5, .infinity][rng.below(4)] }
        return values
    }

    mutating func transaction(_ s: Session, _ rt: WorkspaceRuntime) -> LayoutTransaction {
        let crowded = s.allLeaves.count >= maxPanes
        let roll = rng.below(100)
        switch roll {
        case 0..<18 where !crowded:
            let (p, w) = target(s)
            return .insert(newContent(s), at: p, edge: edge(), in: w)
        case 18..<22 where !crowded:
            return .insertIntoEmptyWindow(newContent(s), in: window(s))
        case 0..<22:
            return .beginClose(target(s).0)
        case 22..<40:
            let (p, w) = target(s)
            return .move(content(s), to: p, edge: edge(), in: w)
        case 40..<44:
            return .moveIntoEmptyWindow(content(s), in: window(s))
        case 44..<50:
            guard let split = rng.pick(s.allSplits) else { return .reorder(splitID: SplitID(raw: fresh(0x0B)), from: 0, to: 1) }
            let bound = split.count + (rng.chance(5) ? 1 : 0)
            return .reorder(splitID: split.id, from: rng.below(bound), to: rng.below(bound))
        case 50..<56:
            guard let split = rng.pick(s.allSplits), !rng.chance(3) else { return .resize(splitID: SplitID(raw: fresh(0x0B)), fractions: [0.5, 0.5]) }
            return .resize(splitID: split.id, fractions: fractionList(count: split.count))
        case 56..<66:
            return .beginClose(target(s).0)
        case 66..<76:
            return .commitClose(pendingPane(s, rt))
        case 76..<79:
            return .cancelClose(pendingPane(s, rt))
        case 79..<81:
            return .beginCloseWindow(window(s))
        case 81..<83:
            return .commitCloseWindow(window(s, pending: rt.pendingWindowCloses))
        case 83..<85:
            return .cancelCloseWindow(window(s, pending: rt.pendingWindowCloses))
        case 85..<88:
            return .openMainWindow(newWindow(s), placement: placement)
        case 88..<91:
            let (p, w) = target(s)
            return .setFocusMode(rng.chance(15) ? nil : p, in: w)
        case 91..<94:
            let (p, w) = target(s)
            return .setActive(rng.chance(15) ? nil : p, in: w)
        default:
            return .detach(target(s).0, to: newWindow(s), placement: placement)
        }
    }
}

private struct RunSummary: Equatable {
    var finalSession: Data
    var outcomes: [String]          // per step: "kind ok" or "kind error"
    var successes: [String: Int] = [:]
    var errors: [String: Int] = [:]
    var transactions: Int { outcomes.count }
}

/// Applies `count` random transactions from `seed` (driving both the generator and `SeededIDGenerator`).
/// With `check`, asserts the §13 properties after every step.
private func propertyRun(seed: UInt64, count: Int, check: Bool) -> RunSummary {
    var fuzzer = Fuzzer(seed: seed)
    var ids = SeededIDGenerator(seed: seed)
    var s = Session(windows: [mainWindow(1, nil)])
    var rt = WorkspaceRuntime()
    var summary = RunSummary(finalSession: Data(), outcomes: [])
    summary.outcomes.reserveCapacity(count)

    for step in 0..<count {
        if check { checkSelfDrop(s, rt, &fuzzer, step: step) }
        let t = fuzzer.transaction(s, rt)
        let kind = TxKind(t)
        let before = s, runtimeBefore = rt
        do throws(LayoutError) {
            let r = try SessionEngine.apply(t, to: s, runtime: rt, ids: &ids)
            if check { checkSuccess(t, kind, before: before, r, step: step) }
            s = r.session
            rt = r.runtime
            summary.outcomes.append("\(kind) ok")
            summary.successes[kind.rawValue, default: 0] += 1
        } catch {
            if check {
                #expect(kind.allows(error), "step \(step): \(kind) threw \(error)")
                #expect(encoded(s) == encoded(before), "step \(step): thrown transaction changed the session")
                #expect(rt == runtimeBefore, "step \(step): thrown transaction changed the runtime")
            }
            summary.outcomes.append("\(kind) \(error)")
            summary.errors[String(describing: error).prefix { $0 != "(" }.description, default: 0] += 1
        }
        if check { checkRoundTrip(s, step: step) }
    }
    summary.finalSession = encoded(s)
    return summary
}

/// §13: encode → decode is identity (same session, no normalisations, same bytes on re-encode).
private func checkRoundTrip(_ s: Session, step: Int) {
    let bytes = encoded(s)
    do throws(PersistenceError) {
        let (decoded, normalizations) = try Migrator.decode(bytes)
        #expect(decoded == s, "step \(step): encode → decode changed the session")
        #expect(normalizations.isEmpty, "step \(step): decode normalised \(normalizations)")
        #expect(encoded(decoded) == bytes, "step \(step): re-encode changed the bytes")
    } catch {
        Issue.record("step \(step): decode threw \(error)")
    }
}

private func checkSelfDrop(_ s: Session, _ rt: WorkspaceRuntime, _ fuzzer: inout Fuzzer, step: Int) {
    guard let leaf = fuzzer.rng.pick(s.allLeaves.filter { $0.content != nil }) else { return }
    let edge = fuzzer.edge()
    var scratch = SequentialIDGenerator()
    let r = try? SessionEngine.apply(.move(leaf.content!, to: leaf.pane, edge: edge, in: leaf.window), to: s, runtime: rt, ids: &scratch)
    #expect(r?.isIdentity(of: s, rt) == true, "step \(step): self-drop \(edge) was not identity")
    #expect(scratch.count == 0)
}

private func checkSuccess(_ t: LayoutTransaction, _ kind: TxKind, before: Session, _ r: TransactionResult, step: Int) {
    let after = r.session
    // Tree validity, unique ownership, records (validate covers §6.1 entirely).
    let violations = SessionEngine.validate(after)
    #expect(violations.isEmpty, "step \(step): \(kind) produced \(violations)")
    // Fractions finite, positive, sum within 1 ± 1e-9.
    for f in after.allFractions {
        #expect(f.allSatisfy { $0.isFinite && $0 > 0 }, "step \(step): bad fraction \(f)")
        #expect(abs(f.reduce(0, +) - 1) <= 1e-9, "step \(step): sum \(f.reduce(0, +))")
    }
    // Ownership: each content in at most one pane.
    let hosted = after.allLeaves.compactMap(\.content)
    #expect(Set(hosted).count == hosted.count, "step \(step): content hosted twice")

    // Identity: records survive unchanged; only inserts add and only closes release.
    var inserted: [ContentID] = []
    switch t {
    case let .insert(c?, _, _, _), let .insertIntoEmptyWindow(c?, _): inserted = [c.id]
    default: break
    }
    let beforeIDs = before.contents.map(\.id), afterIDs = after.contents.map(\.id)
    let surviving = beforeIDs.filter { !r.released.contains($0) }
    #expect(afterIDs == surviving + inserted.filter { !beforeIDs.contains($0) }, "step \(step): \(kind) record identity")
    #expect(Set(r.released).isSubset(of: beforeIDs))
    for record in after.contents {
        if let old = before.contents.first(where: { $0.id == record.id }) { #expect(old == record, "step \(step): record changed") }
    }
    // Windows: closed ones removed in place, created ones appended.
    #expect(after.windows.map(\.id) == before.windows.map(\.id).filter { !r.windowsClosed.contains($0) } + r.windowsCreated,
            "step \(step): window order")
    // Pending state refers to existing panes/windows only.
    #expect(r.runtime.pendingCloses.isSubset(of: after.allLeaves.map(\.pane)))
    #expect(r.runtime.pendingWindowCloses.isSubset(of: after.windows.map(\.id)))
    // Non-structural transactions keep every pane and its content.
    if kind.keepsPlacement {
        #expect(Set(after.allLeaves.map { "\($0.pane)\(String(describing: $0.content))" })
                    == Set(before.allLeaves.map { "\($0.pane)\(String(describing: $0.content))" }), "step \(step): \(kind) moved panes")
    }
    if case let .move(c, _, _, _) = t { #expect(hosted.contains(c), "step \(step): moved content lost") }
}

@Suite("§13 property tests")
struct PropertyTests {
    /// Recorded seed for CI runs (§13). Drives the transaction generator and `SeededIDGenerator`.
    static let seed: UInt64 = 0x5EED_2026_1017
    static let count = 10_000

    @Test("10,000 random transactions keep every invariant")
    func randomTransactions() {
        let summary = propertyRun(seed: Self.seed, count: Self.count, check: true)
        #expect(summary.transactions == Self.count)
        for kind in TxKind.allCases { #expect(summary.successes[kind.rawValue, default: 0] > 0, "\(kind) never succeeded") }
        #expect(summary.errors.values.reduce(0, +) > 0)
        print("property seed \(String(Self.seed, radix: 16)): \(Self.count) transactions, ok \(summary.successes.values.reduce(0, +)), thrown \(summary.errors.values.reduce(0, +))")
        print("  successes: \(summary.successes.sorted { $0.key < $1.key })")
        print("  errors: \(summary.errors.sorted { $0.key < $1.key })")
    }

    @Test("Same seed twice → byte-identical sessions and identical outcomes")
    func sameSeedSameBytes() {
        let a = propertyRun(seed: Self.seed, count: Self.count, check: false)
        let b = propertyRun(seed: Self.seed, count: Self.count, check: false)
        #expect(a == b)
        let other = propertyRun(seed: Self.seed &+ 1, count: 500, check: false)
        #expect(other.finalSession != a.finalSession)
    }
}
