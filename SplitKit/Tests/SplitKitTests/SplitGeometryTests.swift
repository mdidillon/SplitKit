import CoreGraphics
import Foundation
import Testing
import SplitKitModel
@testable import SplitKit

/// §6.1.4 render-time geometry: fractions → frames, minimum sizes and compression, divider drags.
@Suite struct SplitGeometryTests {
    let a = PaneID(raw: UUID()), b = PaneID(raw: UUID()), c = PaneID(raw: UUID())
    let h = SplitID(raw: UUID()), v = SplitID(raw: UUID())

    /// §6.1.9 worked example shape: `H[A 0.5, V[B 0.5, C 0.5] 0.5]`.
    var workedExample: LayoutNode {
        .split(id: h, axis: .horizontal, children: [
            .pane(id: a, content: nil),
            .split(id: v, axis: .vertical, children: [.pane(id: b, content: nil), .pane(id: c, content: nil)],
                   fractions: [0.5, 0.5]),
        ], fractions: [0.5, 0.5])
    }

    func frames(_ layout: SplitGeometry.Layout) -> [PaneID: CGRect] {
        Dictionary(uniqueKeysWithValues: layout.panes.map { ($0.pane, $0.frame) })
    }

    // MARK: Lengths

    @Test func lengthsFollowFractionsWhenMinimumsFit() {
        #expect(SplitGeometry.lengths(fractions: [0.25, 0.75], minimums: [0, 0], available: 400) == [100, 300])
        #expect(SplitGeometry.lengths(fractions: [0.5, 0.5], minimums: [100, 100], available: 800) == [400, 400])
    }

    @Test func aPaneBelowItsMinimumIsRaisedAndTheOthersShareTheRest() {
        #expect(SplitGeometry.lengths(fractions: [0.1, 0.9], minimums: [100, 0], available: 400) == [100, 300])
        #expect(SplitGeometry.lengths(fractions: [0.1, 0.1, 0.8], minimums: [100, 100, 0], available: 400) == [100, 100, 200])
    }

    @Test func raisingOneMinimumCanPushAnotherBelowItsMinimum() {
        // Pass 1: 0.2 × 400 = 80 < 100 → fixed. Pass 2: 0.3 / 0.8 × 300 = 112.5 < 120 → fixed. Rest: 180.
        #expect(SplitGeometry.lengths(fractions: [0.2, 0.3, 0.5], minimums: [100, 120, 0], available: 400) == [100, 120, 180])
    }

    @Test func compressesProportionallyWhenSmallerThanTheSumOfMinimums() {
        #expect(SplitGeometry.lengths(fractions: [0.9, 0.1], minimums: [200, 100], available: 150) == [100, 50])
        #expect(SplitGeometry.lengths(fractions: [0.5, 0.5], minimums: [200, 100], available: 300) == [200, 100])
        #expect(SplitGeometry.lengths(fractions: [0.5, 0.5], minimums: [200, 100], available: 0) == [0, 0])
        #expect(SplitGeometry.lengths(fractions: [0.5, 0.5], minimums: [200, 100], available: -10) == [0, 0])
    }

    @Test func lengthsAlwaysSumToTheAvailableLength() {
        var random = SeededIDGenerator(seed: 42)
        for _ in 0..<1_000 {
            let count = Int(random.nextValue(below: 4)) + 2
            let raw = (0..<count).map { _ in Double(random.nextValue(below: 1_000) + 1) }
            let fractions = raw.map { $0 / raw.reduce(0, +) }
            let minimums = (0..<count).map { _ in CGFloat(random.nextValue(below: 300)) }
            let available = CGFloat(random.nextValue(below: 2_000))
            let lengths = SplitGeometry.lengths(fractions: fractions, minimums: minimums, available: available)
            #expect(abs(lengths.reduce(0, +) - available) < 1e-6)
            if available >= minimums.reduce(0, +) {
                #expect(zip(lengths, minimums).allSatisfy { $0 >= $1 - 1e-9 })
            }
        }
    }

    // MARK: Minimum sizes

    @Test func cellMinimumTakesTheLargerOfPaneAndContentPlusHeaderAndPadding() {
        let pane = CGSize(width: 160, height: 100)
        #expect(SplitGeometry.cellMinimum(minimumPaneSize: pane, contentMinimum: CGSize(width: 200, height: 120),
                                          headerHeight: 28, contentPadding: 4) == CGSize(width: 208, height: 156))
        #expect(SplitGeometry.cellMinimum(minimumPaneSize: pane, contentMinimum: CGSize(width: 50, height: 50),
                                          headerHeight: 28, contentPadding: 4) == CGSize(width: 168, height: 108))
        #expect(SplitGeometry.cellMinimum(minimumPaneSize: pane, contentMinimum: nil,
                                          headerHeight: 28, contentPadding: 0) == pane)
    }

    @Test func treeMinimumSumsAlongAndMaximisesAcrossEachAxis() {
        let minimum = SplitGeometry.minimumSize(of: workedExample) { _ in CGSize(width: 160, height: 100) }
        #expect(minimum == CGSize(width: 320, height: 200))
    }

    // MARK: Layout

    @Test func workedExampleLaysOutByFractions() {
        let layout = SplitGeometry.layout(workedExample, in: CGRect(x: 0, y: 0, width: 800, height: 600),
                                          dividerHitWidth: 8) { _ in .zero }
        #expect(layout.panes.map(\.pane) == [a, b, c])
        #expect(frames(layout) == [a: CGRect(x: 0, y: 0, width: 400, height: 600),
                                   b: CGRect(x: 400, y: 0, width: 400, height: 300),
                                   c: CGRect(x: 400, y: 300, width: 400, height: 300)])
        #expect(layout.dividers.map(\.id) == [.init(split: h, index: 0), .init(split: v, index: 0)])
        #expect(layout.dividers[0].hitArea == CGRect(x: 396, y: 0, width: 8, height: 600))
        #expect(layout.dividers[1].hitArea == CGRect(x: 400, y: 296, width: 400, height: 8))
        #expect(layout.dividers[1].axis == .vertical)
        #expect(layout.dividers[0].sizes == [400, 400])
        #expect(layout.dividers[0].minimums == [0, 0])
    }

    @Test func layoutHonoursAnOriginAndAnOverride() {
        let layout = SplitGeometry.layout(workedExample, in: CGRect(x: 10, y: 20, width: 800, height: 600),
                                          dividerHitWidth: 8, overrides: [h: [0.25, 0.75], v: [1]]) { _ in .zero }
        #expect(frames(layout)[a] == CGRect(x: 10, y: 20, width: 200, height: 600))
        // The `v` override has the wrong count and is ignored.
        #expect(frames(layout)[c] == CGRect(x: 210, y: 320, width: 600, height: 300))
        #expect(layout.dividers[0].fractions == [0.25, 0.75])
    }

    @Test func layoutRaisesPanesToTheirMinimum() {
        let skewed = LayoutNode.split(id: h, axis: .horizontal,
                                      children: [.pane(id: a, content: nil), .pane(id: b, content: nil)],
                                      fractions: [0.1, 0.9])
        let layout = SplitGeometry.layout(skewed, in: CGRect(x: 0, y: 0, width: 1000, height: 500),
                                          dividerHitWidth: 8) { _ in CGSize(width: 200, height: 100) }
        #expect(frames(layout)[a]?.width == 200)
        #expect(frames(layout)[b]?.width == 800)
    }

    @Test func layoutCompressesWhenTheWindowIsSmallerThanTheMinimums() {
        let layout = SplitGeometry.layout(workedExample, in: CGRect(x: 0, y: 0, width: 240, height: 150),
                                          dividerHitWidth: 8) { _ in CGSize(width: 160, height: 100) }
        #expect(frames(layout) == [a: CGRect(x: 0, y: 0, width: 120, height: 150),
                                   b: CGRect(x: 120, y: 0, width: 120, height: 75),
                                   c: CGRect(x: 120, y: 75, width: 120, height: 75)])
    }

    @Test func focusModeShowsOnlyTheFocusedPaneFillingTheWindow() {
        let bounds = CGRect(x: 0, y: 0, width: 800, height: 600)
        let layout = SplitGeometry.layout(workedExample, in: bounds, dividerHitWidth: 8) { _ in .zero }
        let focused = SplitGeometry.focusing(layout, on: b, in: bounds)
        #expect(focused.panes == [SplitGeometry.PaneFrame(pane: b, content: nil, frame: bounds)])
        #expect(focused.dividers.isEmpty)
        #expect(SplitGeometry.focusing(layout, on: nil, in: bounds) == layout)
        #expect(SplitGeometry.focusing(layout, on: PaneID(raw: UUID()), in: bounds) == layout)
    }

    // MARK: Divider drag

    func divider(fractions: [Double], sizes: [CGFloat], minimums: [CGFloat], index: Int = 0) -> SplitGeometry.Divider {
        SplitGeometry.Divider(split: h, axis: .horizontal, index: index, fractions: fractions, sizes: sizes,
                              minimums: minimums, hitArea: .zero)
    }

    @Test func dragMovesTheBoundaryByTheTranslation() {
        let d = divider(fractions: [0.5, 0.5], sizes: [400, 400], minimums: [100, 100])
        #expect(SplitGeometry.dragFractions(d, translation: 100) == [0.625, 0.375])
        #expect(SplitGeometry.dragFractions(d, translation: -200) == [0.25, 0.75])
        #expect(SplitGeometry.dragFractions(d, translation: 0) == [0.5, 0.5])
    }

    @Test func dragIsClampedByTheNeighboursMinimums() {
        let d = divider(fractions: [0.5, 0.5], sizes: [400, 400], minimums: [100, 150])
        #expect(SplitGeometry.dragFractions(d, translation: 1_000) == [0.8125, 0.1875])   // 650 : 150
        #expect(SplitGeometry.dragFractions(d, translation: -1_000) == [0.125, 0.875])    // 100 : 700
    }

    @Test func dragChangesOnlyTheTwoNeighbours() {
        let d = divider(fractions: [0.25, 0.25, 0.5], sizes: [200, 200, 400], minimums: [0, 0, 0], index: 1)
        #expect(SplitGeometry.dragFractions(d, translation: 100) == [0.25, 0.375, 0.375])
    }

    @Test func aCompressedPairDoesNotMove() {
        let d = divider(fractions: [0.5, 0.5], sizes: [75, 75], minimums: [100, 100])
        #expect(SplitGeometry.dragFractions(d, translation: 30) == [0.5, 0.5])
    }

    @Test func dragWithZeroMinimumsKeepsFractionsPositive() {
        let d = divider(fractions: [0.5, 0.5], sizes: [400, 400], minimums: [0, 0])
        let fractions = SplitGeometry.dragFractions(d, translation: 10_000)
        #expect(fractions.allSatisfy { $0 > 0 })
        #expect(abs(fractions[1] - Double(SplitGeometry.minimumDragLength / 800)) < 1e-12)   // 799 : 1
    }

    @Test func dragFractionsStayNormalised() {
        var random = SeededIDGenerator(seed: 7)
        for _ in 0..<1_000 {
            let raw = (0..<4).map { _ in Double(random.nextValue(below: 1_000) + 1) }
            let fractions = raw.map { $0 / raw.reduce(0, +) }
            let sizes = fractions.map { CGFloat($0) * 1_000 }
            let minimums = (0..<4).map { _ in CGFloat(random.nextValue(below: 100)) }
            let index = Int(random.nextValue(below: 3))
            let translation = CGFloat(Int(random.nextValue(below: 2_000)) - 1_000)
            let result = SplitGeometry.dragFractions(
                divider(fractions: fractions, sizes: sizes, minimums: minimums, index: index), translation: translation)
            #expect(abs(result.reduce(0, +) - 1) <= 1e-9)
            #expect(result.allSatisfy { $0 > 0 && $0.isFinite })
        }
    }
}
