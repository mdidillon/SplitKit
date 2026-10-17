import Foundation
import Testing
@testable import SplitKitModel

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

@Suite("§6.1.9 tree arithmetic")
struct TreeArithmeticTests {
    @Test("Worked example: insert D right of A, close C, close D")
    func workedExample() throws {
        // H[A 0.5, V[B 0.5, C 0.5] 0.5]
        let s0 = session(mainWindow(1, h(1, [p(1, 1), v(2, [p(2, 2), p(3, 3)])]), active: 3))
        var ids = SequentialIDGenerator()
        let r1 = try SessionEngine.apply(.insert(new(4), at: pid(1), edge: .right, in: wid(1)), to: s0,
                                         runtime: WorkspaceRuntime(), ids: &ids)
        #expect(ids.count == 1, "draws exactly one PaneID")
        let d = drawnPane(1)
        #expect(r1.session.root == h(1, [p(1, 1), .pane(id: d, content: cid(4)), v(2, [p(2, 2), p(3, 3)])], [0.25, 0.25, 0.5]))
        #expect(r1.normalizations.isEmpty)

        let r2 = try close(pid(3), in: r1.session)
        #expect(r2.session.root == h(1, [p(1, 1), .pane(id: d, content: cid(4)), p(2, 2)], [0.25, 0.25, 0.5]))
        #expect(r2.normalizations == [.collapsed(sid(2))])
        #expect(r2.session.windows[0].activePane == pid(2), "C was active → nearest sibling B")
        #expect(r2.released == [cid(3)])

        let r3 = try close(d, in: r2.session)
        #expect(approxEqual(fractions(r3.session.root), [1.0 / 3, 2.0 / 3]))
        guard case let .split(_, _, children, _) = r3.session.root else { Issue.record("not a split"); return }
        #expect(children == [p(1, 1), p(2, 2)])
        #expect(r3.normalizations.isEmpty)
    }

    @Test("Edge → axis and before/after; draw order PaneID then SplitID",
          arguments: [(DropEdge.left, SplitAxis.horizontal, true), (.right, .horizontal, false),
                      (.top, .vertical, true), (.bottom, .vertical, false)])
    func edgeAxis(edge: DropEdge, axis: SplitAxis, before: Bool) throws {
        let s = session(mainWindow(1, p(1, 1)))
        let r = try apply(.insert(new(2), at: pid(1), edge: edge, in: wid(1)), to: s)
        let newPane = LayoutNode.pane(id: drawnPane(1), content: cid(2))
        let expected = LayoutNode.split(id: drawnSplit(2), axis: axis,
                                        children: before ? [newPane, p(1, 1)] : [p(1, 1), newPane], fractions: [0.5, 0.5])
        #expect(r.session.root == expected)
    }

    @Test("Edge insert into a same-axis parent halves the target's fraction")
    func edgeInsertJoinsParent() throws {
        let s = session(mainWindow(1, h(1, [p(1, 1), p(2, 2)])))
        let r = try apply(.insert(nil, at: pid(2), edge: .left, in: wid(1)), to: s)
        #expect(r.session.root == h(1, [p(1, 1), .pane(id: drawnPane(1), content: nil), p(2, 2)], [0.5, 0.25, 0.25]))
    }

    @Test("Edge insert on another axis replaces the target with a [0.5, 0.5] split")
    func edgeInsertNewSplit() throws {
        let s = session(mainWindow(1, h(1, [p(1, 1), p(2, 2)], [0.3, 0.7])))
        let r = try apply(.insert(nil, at: pid(2), edge: .bottom, in: wid(1)), to: s)
        let inner = LayoutNode.split(id: drawnSplit(2), axis: .vertical,
                                     children: [p(2, 2), .pane(id: drawnPane(1), content: nil)], fractions: [0.5, 0.5])
        #expect(r.session.root == h(1, [p(1, 1), inner], [0.3, 0.7]))
    }

    @Test("Removal redistributes proportionally: fᵢ / (1 − r)")
    func removalRedistributes() throws {
        let s = session(mainWindow(1, h(1, [p(1, 1), p(2, 2), p(3, 3)], [0.2, 0.3, 0.5])))
        let r = try close(pid(2), in: s)
        #expect(approxEqual(fractions(r.session.root), [0.2 / 0.7, 0.5 / 0.7]))
        #expect(r.normalizations.isEmpty)
    }

    @Test("Collapse then flatten into a same-axis grandparent")
    func collapseThenFlatten() throws {
        // H[A 0.5, V[B 0.5, H'[C 0.5, D 0.5] 0.5] 0.5]; closing B collapses V into H', which flattens into H.
        let s = session(mainWindow(1, h(1, [p(1, 1), v(2, [p(2, 2), h(3, [p(3, 3), p(4, 4)])])])))
        let r = try close(pid(2), in: s)
        #expect(r.session.root == h(1, [p(1, 1), p(3, 3), p(4, 4)], [0.5, 0.25, 0.25]))
        #expect(r.normalizations == [.collapsed(sid(2)), .flattened(sid(3))])
    }

    @Test("Collapse at the root replaces the split by its last child")
    func collapseAtRoot() throws {
        let s = session(mainWindow(1, h(1, [p(1, 1), v(2, [p(2, 2), p(3, 3)])])))
        let r = try close(pid(1), in: s)
        #expect(r.session.root == v(2, [p(2, 2), p(3, 3)]))
        #expect(r.normalizations == [.collapsed(sid(1))])
    }

    @Test("Reorder: `to` is the final index; fractions move with their child")
    func reorderFinalIndex() throws {
        let s = session(mainWindow(1, h(1, [p(1, 1), p(2, 2), p(3, 3)], [0.125, 0.25, 0.625])))
        let forward = try apply(.reorder(splitID: sid(1), from: 0, to: 2), to: s)
        #expect(forward.session.root == h(1, [p(2, 2), p(3, 3), p(1, 1)], [0.25, 0.625, 0.125]))
        let backward = try apply(.reorder(splitID: sid(1), from: 2, to: 0), to: s)
        #expect(backward.session.root == h(1, [p(3, 3), p(1, 1), p(2, 2)], [0.625, 0.125, 0.25]))
        let same = try apply(.reorder(splitID: sid(1), from: 1, to: 1), to: s)
        #expect(same.isIdentity(of: s, WorkspaceRuntime()))
    }

    @Test("Nearest sibling: first leaf of the following sibling, else last leaf of the preceding one",
          arguments: [(1, 2), (4, 3), (3, 2), (2, 3)])
    func nearestSibling(closed: Int, expectedActive: Int) throws {
        // H[A, V[B, C], D]
        let s = session(mainWindow(1, h(1, [p(1, 1), v(2, [p(2, 2), p(3, 3)]), p(4, 4)]), active: closed))
        let r = try close(pid(closed), in: s)
        #expect(r.session.windows[0].activePane == pid(expectedActive))
    }

    @Test("Nearest sibling of the only pane is nil; a non-active close keeps activePane")
    func nearestSiblingEdgeCases() throws {
        let single = try close(pid(1), in: session(mainWindow(1, p(1, 1), active: 1)))
        #expect(single.session.windows[0].root == nil)
        #expect(single.session.windows[0].activePane == nil)

        let other = try close(pid(1), in: session(mainWindow(1, h(1, [p(1, 1), p(2, 2), p(3, 3)]), active: 3)))
        #expect(other.session.windows[0].activePane == pid(3))
    }

    @Test("Closing the focus-mode pane clears focus mode and moves activePane to the nearest sibling")
    func closeFocusedPane() throws {
        let s = session(mainWindow(1, h(1, [p(1, 1), p(2, 2), p(3, 3)]), active: 1, focus: 2))
        let r = try close(pid(2), in: s)
        #expect(r.session.windows[0].focusModePane == nil)
        #expect(r.session.windows[0].activePane == pid(3))
    }

    @Test("Removing a pane with a tiny fraction keeps the sum within 1 ± 1e-9")
    func sumStaysNormalised() throws {
        let s = session(mainWindow(1, h(1, [p(1, 1), p(2, 2), p(3, 3)], [0.1, 0.2, 0.7])))
        let r = try close(pid(1), in: s)
        #expect(abs(fractions(r.session.root).reduce(0, +) - 1) <= 1e-9)
        #expect(SessionEngine.validate(r.session).isEmpty)
    }
}
