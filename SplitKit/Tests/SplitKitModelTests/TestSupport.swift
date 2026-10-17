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

/// The §8 encoder setup (`Migrator.encode` is part 2), used for byte comparisons.
func encoded(_ s: Session) -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
    return try! encoder.encode(s)
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
