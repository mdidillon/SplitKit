import CoreGraphics
import Foundation

// All geometry: AppKit global screen space, points, origin at the bottom-left of the primary display, y up (§9).

/// One display as `SplitKitWindows` sees it (`NSScreen → DisplaySnapshot`). Other displays may have negative coordinates.
public struct DisplaySnapshot: Equatable, Sendable {
    public var id: String
    public var frame, visibleFrame: CGRect
    public var scale: Double                  // metadata only; placement is in points (§4)
    public var isMain: Bool                   // primary display = NSScreen.screens[0], not NSScreen.main

    public init(id: String, frame: CGRect, visibleFrame: CGRect, scale: Double, isMain: Bool) {
        self.id = id
        self.frame = frame
        self.visibleFrame = visibleFrame
        self.scale = scale
        self.isMain = isMain
    }
}

public enum DisplayPlacement {
    /// Pure, §9. Returns the frame to show; never changes `p` (system re-placement must not overwrite `intendedFrame`).
    ///
    /// 1. Target display: `id == displayID`; else the `isMain` display; else `displays[0]`. No displays → `intendedFrame`.
    /// 2. Origin: `vf.origin + relativeOrigin`, or centred in `vf` with `intendedFrame.size` when `relativeOrigin` is nil.
    /// 3. Size: raised to `minSize` per axis, then clamped to `vf.size` (reachability wins over minimum size).
    /// 4. Translate fully inside `vf`. No rounding.
    public static func resolve(_ p: SavedPlacement, minSize: CGSize, displays: [DisplaySnapshot]) -> CGRect {
        guard let target = displays.first(where: { p.displayID != nil && $0.id == p.displayID })
                ?? displays.first(where: \.isMain)
                ?? displays.first
        else { return p.intendedFrame }

        let vf = target.visibleFrame
        let size = p.intendedFrame.size

        var x: CGFloat, y: CGFloat
        if let offset = p.relativeOrigin {
            x = vf.origin.x + offset.x
            y = vf.origin.y + offset.y
        } else {
            x = vf.midX - size.width / 2
            y = vf.midY - size.height / 2
        }

        let width = min(max(size.width, minSize.width), vf.width)
        let height = min(max(size.height, minSize.height), vf.height)

        x = min(max(x, vf.minX), vf.maxX - width)
        y = min(max(y, vf.minY), vf.maxY - height)
        return CGRect(x: x, y: y, width: width, height: height)
    }

    /// The placement to save after the user moved or resized a window to `frame` (§9, "Writing a placement").
    ///
    /// `displayID` is the display whose `frame` contains the largest part of the window (ties, including a window
    /// that touches no display, go to the earlier one in `displays`); `relativeOrigin` is `frame.origin` minus that
    /// display's `visibleFrame.origin`; `intendedFrame` is `frame`. No displays → no hint and no offset (centred).
    public static func placement(writing frame: CGRect, displays: [DisplaySnapshot]) -> SavedPlacement {
        var best: (display: DisplaySnapshot, area: CGFloat)?
        for display in displays {
            let overlap = display.frame.intersection(frame)
            let area = overlap.isNull ? 0 : overlap.width * overlap.height
            if best == nil || area > best!.area { best = (display, area) }
        }
        guard let target = best?.display else { return SavedPlacement(intendedFrame: frame) }
        let origin = target.visibleFrame.origin
        return SavedPlacement(intendedFrame: frame, displayID: target.id,
                              relativeOrigin: CGPoint(x: frame.origin.x - origin.x, y: frame.origin.y - origin.y))
    }
}
