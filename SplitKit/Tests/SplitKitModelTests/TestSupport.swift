import Foundation
import Testing
@testable import SplitKitModel

// Fixture IDs: small integers in the last UUID group, distinct per kind by the first group.

func uuid(_ kind: UInt8, _ n: Int) -> UUID {
    UUID(uuidString: String(format: "%02X000000-0000-4000-8000-%012X", kind, n))!
}

func pid(_ n: Int) -> PaneID { PaneID(raw: uuid(0x01, n)) }
func sid(_ n: Int) -> SplitID { SplitID(raw: uuid(0x02, n)) }
func wid(_ n: Int) -> WindowID { WindowID(raw: uuid(0x03, n)) }
func cid(_ n: Int) -> ContentID { ContentID(raw: uuid(0x04, n)) }

let testType = ContentType(raw: "splitkit.test")
let placement = SavedPlacement(intendedFrame: CGRect(x: 0, y: 0, width: 1200, height: 800))

func new(_ n: Int) -> NewContent { NewContent(id: cid(n), type: testType, stateVersion: 1) }

/// A pane `n`, hosting content `c` if given.
func p(_ n: Int, _ c: Int? = nil) -> LayoutNode { .pane(id: pid(n), content: c.map(cid)) }
func h(_ n: Int, _ children: [LayoutNode], _ fractions: [Double]? = nil) -> LayoutNode {
    .split(id: sid(n), axis: .horizontal, children: children,
           fractions: fractions ?? Array(repeating: 1 / Double(children.count), count: children.count))
}
func v(_ n: Int, _ children: [LayoutNode], _ fractions: [Double]? = nil) -> LayoutNode {
    .split(id: sid(n), axis: .vertical, children: children,
           fractions: fractions ?? Array(repeating: 1 / Double(children.count), count: children.count))
}

func mainWindow(_ n: Int, _ root: LayoutNode?, active: Int? = nil, focus: Int? = nil) -> WindowLayout {
    WindowLayout(id: wid(n), kind: .main, root: root, activePane: active.map(pid), focusModePane: focus.map(pid), placement: placement)
}
func detachedWindow(_ n: Int, _ root: LayoutNode?, active: Int? = nil, focus: Int? = nil) -> WindowLayout {
    WindowLayout(id: wid(n), kind: .detached, root: root, activePane: active.map(pid), focusModePane: focus.map(pid), placement: placement)
}

func record(_ c: ContentID, state: Data = Data(), availability: ContentRecord.Availability = .hosted) -> ContentRecord {
    ContentRecord(id: c, type: testType, stateVersion: 1, state: state, availability: availability)
}

/// A session whose records are derived from the hosted contents, in tree order.
func session(_ windows: WindowLayout...) -> Session {
    let hosted = windows.flatMap { $0.root?.leaves.compactMap(\.content) ?? [] }
    return Session(windows: windows, contents: hosted.map { record($0, state: Data([1, 2, 3])) })
}

/// H[A(c1), B(c2)] in main window 1, plus detached window 2 with C(c3).
let twoWindows = session(mainWindow(1, h(1, [p(1, 1), p(2, 2)]), active: 1, focus: 1), detachedWindow(2, p(3, 3)))

/// Hands out `uuid(0xF0, 1)`, `uuid(0xF0, 2)`, … so tests can name the IDs the engine draws.
struct SequentialIDGenerator: IDGenerator {
    var count = 0
    mutating func next() -> UUID {
        count += 1
        return uuid(0xF0, count)
    }
}
func drawnPane(_ n: Int) -> PaneID { PaneID(raw: uuid(0xF0, n)) }
func drawnSplit(_ n: Int) -> SplitID { SplitID(raw: uuid(0xF0, n)) }

/// `Migrator.encode`, the one §8 encoder setup, used for every byte comparison.
func encoded(_ s: Session) -> Data {
    try! Migrator.encode(s)
}

/// Applies `t` with a fresh sequential generator.
func apply(_ t: LayoutTransaction, to s: Session, runtime: WorkspaceRuntime = WorkspaceRuntime()) throws(LayoutError) -> TransactionResult {
    var ids = SequentialIDGenerator()
    return try SessionEngine.apply(t, to: s, runtime: runtime, ids: &ids)
}

/// Asserts `t` throws `expected` and that session (byte-identical) and runtime are unchanged.
func expectFailure(_ t: LayoutTransaction, on s: Session, runtime: WorkspaceRuntime = WorkspaceRuntime(),
                   _ expected: LayoutError, sourceLocation: SourceLocation = #_sourceLocation) {
    let bytes = encoded(s), runtimeBefore = runtime
    var ids = SequentialIDGenerator()
    do throws(LayoutError) {
        _ = try SessionEngine.apply(t, to: s, runtime: runtime, ids: &ids)
        Issue.record("expected \(expected), got success", sourceLocation: sourceLocation)
    } catch {
        #expect(error == expected, sourceLocation: sourceLocation)
    }
    #expect(encoded(s) == bytes, sourceLocation: sourceLocation)
    #expect(runtime == runtimeBefore, sourceLocation: sourceLocation)
}

extension TransactionResult {
    /// True if nothing changed and nothing is reported.
    func isIdentity(of s: Session, _ runtime: WorkspaceRuntime) -> Bool {
        session == s && self.runtime == runtime && windowsCreated.isEmpty && windowsClosed.isEmpty
            && released.isEmpty && normalizations.isEmpty
    }
}

extension Session {
    func window(_ id: WindowID) -> WindowLayout? { windows.first { $0.id == id } }
    var root: LayoutNode? { windows.first?.root }
}

let allEdges: [DropEdge] = [.left, .right, .top, .bottom, .center]
func pendingPane(_ n: Int) -> WorkspaceRuntime { WorkspaceRuntime(pendingCloses: [pid(n)]) }
func pendingWindow(_ n: Int) -> WorkspaceRuntime { WorkspaceRuntime(pendingWindowCloses: [wid(n)]) }

func approxEqual(_ a: [Double], _ b: [Double], tolerance: Double = 1e-12) -> Bool {
    a.count == b.count && zip(a, b).allSatisfy { abs($0 - $1) <= tolerance }
}

func fractions(_ node: LayoutNode?) -> [Double] {
    if case let .split(_, _, _, f) = node { return f }
    return []
}

/// Removes a pane through the public two-stage close.
func close(_ pane: PaneID, in s: Session) throws(LayoutError) -> TransactionResult {
    let begun = try apply(.beginClose(pane), to: s)
    return try apply(.commitClose(pane), to: begun.session, runtime: begun.runtime)
}

/// SplitMix64 driving the transaction generator. Choices use `next() % n` (not `Int.random(in:using:)`),
/// so a seed reproduces the same sequence independently of the standard library's sampling algorithm.
struct SplitMix64 {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
    mutating func below(_ n: Int) -> Int { Int(next() % UInt64(n)) }
    mutating func chance(_ percent: Int) -> Bool { below(100) < percent }
    mutating func pick<T>(_ items: [T]) -> T? { items.isEmpty ? nil : items[below(items.count)] }
}

// §9 display fixtures: AppKit global space, points, origin at the bottom-left of the primary display, y up.

func display(_ id: String, _ frame: CGRect, menuBar: CGFloat = 0, scale: Double = 2, main: Bool = false) -> DisplaySnapshot {
    DisplaySnapshot(id: id, frame: frame,
                    visibleFrame: CGRect(x: frame.minX, y: frame.minY, width: frame.width, height: frame.height - menuBar),
                    scale: scale, isMain: main)
}

/// MacBook 1512×982 pt (Retina), primary display; visible frame 1512×950.
let laptop = display("laptop", CGRect(x: 0, y: 0, width: 1512, height: 982), menuBar: 32, scale: 2, main: true)
