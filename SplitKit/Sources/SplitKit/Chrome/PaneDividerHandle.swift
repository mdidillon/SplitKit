import SwiftUI
import SplitKitModel

/// The pointer and drag area of one split boundary, `metrics.dividerHitWidth` wide (the parent sizes it).
/// The `PaneDividerStyle` draws it; this view owns hover, the resize pointer and the drag.
struct PaneDividerHandle: View {
    let divider: SplitGeometry.Divider
    /// Live fractions while dragging.
    let onChange: ([Double]) -> Void
    /// Final fractions on mouse-up, or nil if the drag changed nothing.
    let onEnd: ([Double]?) -> Void
    @State private var isHovered = false
    /// The divider as laid out when the drag began; every step is measured from it, so nothing drifts.
    @State private var dragStart: SplitGeometry.Divider?
    @Environment(\.paneDividerStyle) private var style

    var body: some View {
        style.makeBody(configuration: PaneDividerConfiguration(axis: divider.axis.layoutAxis, isHovered: isHovered,
                                                               isDragging: dragStart != nil))
            .contentShape(Rectangle())
            .onHover { isHovered = $0 }
            .pointerStyle(divider.axis == .horizontal ? .columnResize : .rowResize)
            .gesture(drag)
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .onChanged { value in
                let start = dragStart ?? divider
                dragStart = start
                onChange(SplitGeometry.dragFractions(start, translation: translation(value)))
            }
            .onEnded { value in
                let start = dragStart ?? divider
                dragStart = nil
                let fractions = SplitGeometry.dragFractions(start, translation: translation(value))
                onEnd(fractions == start.fractions ? nil : fractions)
            }
    }

    private func translation(_ value: DragGesture.Value) -> CGFloat {
        divider.axis == .horizontal ? value.translation.width : value.translation.height
    }
}

extension SplitAxis {
    /// The SwiftUI axis along which a split of this axis lays out its children.
    var layoutAxis: Axis { self == .horizontal ? .horizontal : .vertical }
}
