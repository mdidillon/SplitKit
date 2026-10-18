import Foundation
import Testing
import SplitKitContent
import SplitKitModel
@testable import SplitKit

/// The geometric neighbour rule for ⌥⌘-arrows and ⌃⌥⌘-arrows (spec §7.5), and the acceptance criterion of
/// §11 P2: a 2×2 and a 3-level mixed tree built by keyboard only, through the model the menus use.
@MainActor @Suite struct KeyboardOnlyTests {
    // MARK: Neighbour rule

    func leaf(_ id: PaneID) -> LayoutNode { .pane(id: id, content: nil) }
    func split(_ axis: SplitAxis, _ children: [LayoutNode], _ fractions: [Double]) -> LayoutNode {
        .split(id: SplitID(raw: UUID()), axis: axis, children: children, fractions: fractions)
    }
    func ids(_ count: Int) -> [PaneID] { (0..<count).map { _ in PaneID(raw: UUID()) } }

    func neighbours(of pane: PaneID, in root: LayoutNode) -> [FocusDirection: PaneID?] {
        Dictionary(uniqueKeysWithValues: FocusDirection.allCases.map { ($0, SplitGeometry.neighbour(of: pane, toward: $0, in: root)) })
    }

    @Test func aSinglePaneHasNoNeighbours() {
        let p = ids(1)
        #expect(neighbours(of: p[0], in: leaf(p[0])).values.allSatisfy { $0 == nil })
    }

    @Test func anUnknownPaneHasNoNeighbours() {
        let p = ids(2)
        #expect(SplitGeometry.neighbour(of: PaneID(raw: UUID()), toward: .right, in: split(.horizontal, [leaf(p[0]), leaf(p[1])], [0.5, 0.5])) == nil)
    }

    @Test func theNearestPaneInARowWins() {
        let p = ids(3)
        let root = split(.horizontal, [leaf(p[0]), leaf(p[1]), leaf(p[2])], [0.3, 0.3, 0.4])
        #expect(SplitGeometry.neighbour(of: p[0], toward: .right, in: root) == p[1])
        #expect(SplitGeometry.neighbour(of: p[2], toward: .left, in: root) == p[1])
        #expect(SplitGeometry.neighbour(of: p[1], toward: .left, in: root) == p[0])
        #expect(SplitGeometry.neighbour(of: p[1], toward: .up, in: root) == nil)
        #expect(SplitGeometry.neighbour(of: p[1], toward: .down, in: root) == nil)
    }

    @Test func theLargestOverlapWins() {
        let p = ids(3)   // A | (B over C), B small
        let root = split(.horizontal, [leaf(p[0]), split(.vertical, [leaf(p[1]), leaf(p[2])], [0.3, 0.7])], [0.5, 0.5])
        #expect(SplitGeometry.neighbour(of: p[0], toward: .right, in: root) == p[2])
        #expect(SplitGeometry.neighbour(of: p[1], toward: .left, in: root) == p[0])
        #expect(SplitGeometry.neighbour(of: p[1], toward: .down, in: root) == p[2])
        #expect(SplitGeometry.neighbour(of: p[2], toward: .up, in: root) == p[1])
    }

    @Test func anEqualOverlapGoesToTheFirstInTreeOrder() {
        let p = ids(3)
        let root = split(.horizontal, [leaf(p[0]), split(.vertical, [leaf(p[1]), leaf(p[2])], [0.5, 0.5])], [0.5, 0.5])
        #expect(SplitGeometry.neighbour(of: p[0], toward: .right, in: root) == p[1])
        let flipped = split(.horizontal, [split(.vertical, [leaf(p[1]), leaf(p[2])], [0.5, 0.5]), leaf(p[0])], [0.5, 0.5])
        #expect(SplitGeometry.neighbour(of: p[0], toward: .left, in: flipped) == p[1])
    }

    @Test func aTwoByTwoGrid() {
        let p = ids(4)   // A B / C D
        let root = split(.horizontal, [split(.vertical, [leaf(p[0]), leaf(p[2])], [0.5, 0.5]),
                                       split(.vertical, [leaf(p[1]), leaf(p[3])], [0.5, 0.5])], [0.5, 0.5])
        let grid: [(PaneID, FocusDirection, PaneID?)] = [
            (p[0], .right, p[1]), (p[0], .down, p[2]), (p[0], .left, nil), (p[0], .up, nil),
            (p[1], .left, p[0]), (p[1], .down, p[3]), (p[2], .right, p[3]), (p[2], .up, p[0]),
            (p[3], .left, p[2]), (p[3], .up, p[1]), (p[3], .right, nil), (p[3], .down, nil),
        ]
        for (from, direction, expected) in grid {
            #expect(SplitGeometry.neighbour(of: from, toward: direction, in: root) == expected, "\(direction)")
        }
    }

    @Test func aTallPaneSeesTheOneOfTheSideThatTouchesIt() {
        let p = ids(3)   // (A over C) | B
        let root = split(.horizontal, [split(.vertical, [leaf(p[0]), leaf(p[1])], [0.5, 0.5]), leaf(p[2])], [0.5, 0.5])
        #expect(SplitGeometry.neighbour(of: p[1], toward: .right, in: root) == p[2])
        #expect(SplitGeometry.neighbour(of: p[2], toward: .left, in: root) == p[0])
    }

    @Test func theRuleUsesFractionsNotMinimumSizes() {
        let p = ids(3)
        let root = split(.horizontal, [leaf(p[0]), split(.vertical, [leaf(p[1]), leaf(p[2])], [0.9, 0.1])], [0.5, 0.5])
        #expect(SplitGeometry.neighbour(of: p[0], toward: .right, in: root) == p[1])
    }

    // MARK: Keyboard only

    let workspace: SplitKitWorkspace
    let main: WindowID

    init() throws {
        workspace = try makeWorkspace()
        main = workspace.mainLayout.id
    }

    var shape: String? { workspace.mainLayout.root?.shape }
    var activeIsEmpty: Bool { workspace.mainLeaves.first { $0.pane == workspace.mainLayout.activePane }?.content == nil }

    /// The key presses of the 2×2 plan, each a menu-bar action.
    @Test func aTwoByTwoByKeyboardOnly() async throws {
        await workspace.addContentByKeyboard(in: main)      // ⇧⌘N, Return: A
        #expect(shape == "p")
        await workspace.key(.split(.right), in: main)       // ⌘D
        #expect(shape == "H(p,p)")
        await workspace.key(.focusNeighbour(.right), in: main)  // ⌥⌘→
        #expect(activeIsEmpty)
        await workspace.addContentByKeyboard(in: main)      // ⇧⌘N into the new empty pane: B
        await workspace.key(.focusNeighbour(.left), in: main)
        await workspace.key(.split(.bottom), in: main)      // ⇧⌘D
        #expect(shape == "H(V(p,p),p)")
        await workspace.key(.focusNeighbour(.down), in: main)
        await workspace.addContentByKeyboard(in: main)      // C
        await workspace.key(.focusNeighbour(.right), in: main)
        await workspace.key(.split(.bottom), in: main)
        await workspace.key(.focusNeighbour(.down), in: main)
        await workspace.addContentByKeyboard(in: main)      // D

        #expect(shape == "H(V(p,p),V(p,p))")
        #expect(workspace.mainLeaves.count == 4 && workspace.mainLeaves.allSatisfy { $0.content != nil })
        guard case let .split(_, _, columns, fractions) = try #require(workspace.mainLayout.root) else { Issue.record("not a split"); return }
        #expect(fractions == [0.5, 0.5])
        for case let .split(_, _, _, rows) in columns { #expect(rows == [0.5, 0.5]) }
        #expect(workspace.session.contents.count == 4)
        #expect(workspace.mainLayout.activePane == workspace.mainLeaves.last?.pane)
    }

    @Test func aThreeLevelMixedTreeByKeyboardOnly() async throws {
        await workspace.addContentByKeyboard(in: main)      // A
        await workspace.key(.split(.right), in: main)
        await workspace.key(.focusNeighbour(.right), in: main)
        await workspace.addContentByKeyboard(in: main)      // B
        await workspace.key(.split(.bottom), in: main)
        await workspace.key(.focusNeighbour(.down), in: main)
        await workspace.addContentByKeyboard(in: main)      // C
        await workspace.key(.split(.right), in: main)
        await workspace.key(.focusNeighbour(.right), in: main)
        await workspace.addContentByKeyboard(in: main)      // D

        #expect(shape == "H(p,V(p,H(p,p)))")
        #expect(workspace.mainLeaves.count == 4 && workspace.mainLeaves.allSatisfy { $0.content != nil })
        #expect(SessionEngine.validate(workspace.session).isEmpty)
    }

    @Test func addContentIntoAnOccupiedActivePaneSplitsToItsRight() async throws {
        await workspace.addContentByKeyboard(in: main)
        await workspace.addContentByKeyboard(in: main)
        #expect(shape == "H(p,p)")
        #expect(workspace.mainLeaves.allSatisfy { $0.content != nil })
    }

    @Test func theTypeListOpensForTheEmptyWindowAndClosesAfterChoosing() async throws {
        await workspace.key(.chooseContent, in: main)
        #expect(workspace.addContentRequest == main)
        await workspace.chooseRequestedContent(TestContent.type, in: main)
        #expect(workspace.addContentRequest == nil)
        #expect(shape == "p")
    }

    @Test func cancellingTheTypeListAddsNothing() async throws {
        await workspace.key(.chooseContent, in: main)
        workspace.cancelAddContent(in: main)
        #expect(workspace.addContentRequest == nil)
        #expect(workspace.mainLayout.root == nil)
    }

    @Test func pickerArrowKeysStopAtTheEnds() throws {
        let picker = workspace.contentPicker(for: .emptyWindow)
        let types = picker.entries.map(\.type)
        #expect(types.count >= 2)
        #expect(picker.moving(nil, by: 1) == types.first)
        #expect(picker.moving(nil, by: -1) == types.last)
        #expect(picker.moving(types.first, by: -1) == types.first)
        #expect(picker.moving(types.last, by: 1) == types.last)
        #expect(picker.moving(types[0], by: 1) == types[1])
    }

    @Test func addContentIsOffNowhereWhenAWindowHasPanesButNoActiveOne() async throws {
        await workspace.addContentByKeyboard(in: main)
        try await workspace.perform(.setActive(nil, in: main))
        let model = workspace.activePaneMenuModel(in: main)
        #expect(!model.isEnabled(.chooseContent) && !model.isEnabled(.split(.right)))
        #expect(workspace.addContentTarget(in: main) == .none)
    }

    // MARK: Move pane to edge

    @Test func movePaneToTheEdgeOfItsNeighbourSwapsTheOrderAndKeepsTheContentActive() async throws {
        await workspace.addContentByKeyboard(in: main)
        await workspace.key(.split(.right), in: main)
        await workspace.key(.focusNeighbour(.right), in: main)
        await workspace.addContentByKeyboard(in: main)
        await workspace.key(.focusNeighbour(.left), in: main)
        let moved = try #require(workspace.mainLeaves.first?.content)
        let other = try #require(workspace.mainLeaves.last?.content)
        let object = try #require(workspace.store[moved])

        await workspace.key(.moveToEdge(.right), in: main)  // ⌃⌥⌘→

        #expect(shape == "H(p,p)")
        #expect(workspace.mainLeaves.map(\.content) == [other, moved])
        #expect(workspace.store[moved] === object, "same object, no release")
        #expect(workspace.mainLayout.activePane == workspace.mainLeaves.last?.pane)
        #expect(SessionEngine.validate(workspace.session).isEmpty)
    }

    @Test func movePaneDownIntoAnotherAxisNestsIt() async throws {
        await workspace.addContentByKeyboard(in: main)
        await workspace.key(.split(.right), in: main)
        await workspace.key(.focusNeighbour(.right), in: main)
        await workspace.addContentByKeyboard(in: main)
        await workspace.key(.split(.bottom), in: main)
        await workspace.key(.focusNeighbour(.down), in: main)
        await workspace.addContentByKeyboard(in: main)      // H(A, V(B, C))
        await workspace.key(.focusNeighbour(.left), in: main)
        let a = try #require(workspace.mainLeaves.first?.content)

        // A leaves the row (V(B, C) remains) and lands at the right edge of its neighbour B.
        await workspace.key(.moveToEdge(.right), in: main)
        #expect(shape == "V(H(p,p),p)")
        #expect(workspace.mainLeaves.map(\.content).contains(a))
        #expect(workspace.mainLeaves.count == 3)
        #expect(SessionEngine.validate(workspace.session).isEmpty)
    }

    @Test func moveIsOffWithoutANeighbourAndForEmptyPanes() async throws {
        await workspace.addContentByKeyboard(in: main)
        #expect(FocusDirection.allCases.allSatisfy { !workspace.activePaneMenuModel(in: main).isEnabled(.moveToEdge($0)) })
        await workspace.key(.split(.right), in: main)
        await workspace.key(.focusNeighbour(.right), in: main)
        #expect(activeIsEmpty)
        #expect(!workspace.activePaneMenuModel(in: main).isEnabled(.moveToEdge(.left)), "an empty pane has no content to move")
        #expect(workspace.activePaneMenuModel(in: main).isEnabled(.focusNeighbour(.left)))
    }
}
