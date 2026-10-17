import Foundation
import Testing
@testable import SplitKitModel

// §9 DisplayPlacement.resolve over simulated configurations. AppKit global space: points, origin at the
// bottom-left of the primary display, y up. Visible frames leave room for a top menu bar.

/// External 2560×1440 pt to the right (1×); visible frame 2560×1415 (menu bar on every display).
private let externalRight = display("ext", CGRect(x: 1512, y: 0, width: 2560, height: 1440), menuBar: 25, scale: 1)

private func saved(_ frame: CGRect, on displayID: String?, offset: CGPoint?) -> SavedPlacement {
    SavedPlacement(intendedFrame: frame, displayID: displayID, relativeOrigin: offset)
}

/// 800×600 window at offset (100, 100) on the external display.
private let onExternal = saved(CGRect(x: 1612, y: 100, width: 800, height: 600), on: "ext", offset: CGPoint(x: 100, y: 100))

@Suite("§9 DisplayPlacement.resolve")
struct DisplayPlacementTests {
    let noMin = CGSize.zero

    // MARK: Target display and nil cases

    @Test("No displays → intendedFrame unchanged")
    func noDisplays() {
        #expect(DisplayPlacement.resolve(onExternal, minSize: CGSize(width: 2000, height: 2000), displays: []) == onExternal.intendedFrame)
    }

    @Test("Saved display present → exactly the saved frame")
    func savedDisplayPresent() {
        #expect(DisplayPlacement.resolve(onExternal, minSize: noMin, displays: [laptop, externalRight]) == onExternal.intendedFrame)
        // Display order doesn't matter when the ID matches.
        #expect(DisplayPlacement.resolve(onExternal, minSize: noMin, displays: [externalRight, laptop]) == onExternal.intendedFrame)
    }

    @Test("Missing display → same point offset on the main display")
    func missingDisplay() {
        #expect(DisplayPlacement.resolve(onExternal, minSize: noMin, displays: [laptop])
                == CGRect(x: 100, y: 100, width: 800, height: 600))
    }

    @Test("Missing display, offset too large for the main display → pulled fully inside")
    func missingDisplayPulledInside() {
        let p = saved(CGRect(x: 3512, y: 700, width: 800, height: 600), on: "ext", offset: CGPoint(x: 2000, y: 700))
        #expect(DisplayPlacement.resolve(p, minSize: noMin, displays: [laptop])
                == CGRect(x: 1512 - 800, y: 950 - 600, width: 800, height: 600))
    }

    @Test("displayID nil → main display, with its offset")
    func nilDisplayID() {
        let p = saved(CGRect(x: 1, y: 2, width: 400, height: 300), on: nil, offset: CGPoint(x: 40, y: 30))
        #expect(DisplayPlacement.resolve(p, minSize: noMin, displays: [externalRight, laptop])
                == CGRect(x: 40, y: 30, width: 400, height: 300))
    }

    @Test("No display marked main → displays[0]")
    func noMainDisplay() {
        var a = laptop, b = externalRight
        a.isMain = false
        b.isMain = false
        let p = saved(CGRect(x: 0, y: 0, width: 400, height: 300), on: "gone", offset: CGPoint(x: 10, y: 10))
        #expect(DisplayPlacement.resolve(p, minSize: noMin, displays: [b, a]) == CGRect(x: 1522, y: 10, width: 400, height: 300))
        #expect(DisplayPlacement.resolve(p, minSize: noMin, displays: [a, b]) == CGRect(x: 10, y: 10, width: 400, height: 300))
    }

    @Test("relativeOrigin nil → centred in the target's visible frame using intendedFrame.size")
    func centred() {
        let p = saved(CGRect(x: 9999, y: 9999, width: 800, height: 600), on: "ext", offset: nil)
        #expect(DisplayPlacement.resolve(p, minSize: noMin, displays: [laptop, externalRight])
                == CGRect(x: 1512 + 1280 - 400, y: 707.5 - 300, width: 800, height: 600))
        // Missing display, no offset → centred on main.
        let gone = saved(p.intendedFrame, on: "gone", offset: nil)
        #expect(DisplayPlacement.resolve(gone, minSize: noMin, displays: [laptop])
                == CGRect(x: 756 - 400, y: 475 - 300, width: 800, height: 600))
    }

    @Test("Centred with a raised size: centre uses intendedFrame.size, then the raised size is translated inside")
    func centredRaisedSize() {
        let p = saved(CGRect(x: 0, y: 0, width: 300, height: 200), on: nil, offset: nil)
        #expect(DisplayPlacement.resolve(p, minSize: CGSize(width: 480, height: 300), displays: [laptop])
                == CGRect(x: 756 - 150, y: 475 - 100, width: 480, height: 300))
    }

    // MARK: Simulated configurations (§13)

    @Test("Adding a display: windows on the main display don't move; a window saved there returns")
    func addingDisplay() {
        let onLaptop = saved(CGRect(x: 200, y: 150, width: 900, height: 700), on: "laptop", offset: CGPoint(x: 200, y: 150))
        let before = DisplayPlacement.resolve(onLaptop, minSize: noMin, displays: [laptop])
        let after = DisplayPlacement.resolve(onLaptop, minSize: noMin, displays: [laptop, externalRight])
        #expect(before == onLaptop.intendedFrame && after == before)
        // A window saved on the external display while it was attached goes back there when it's added again.
        #expect(DisplayPlacement.resolve(onExternal, minSize: noMin, displays: [laptop]) != onExternal.intendedFrame)
        #expect(DisplayPlacement.resolve(onExternal, minSize: noMin, displays: [laptop, externalRight]) == onExternal.intendedFrame)
    }

    @Test("Removing a display: its windows land on the main display, fully visible")
    func removingDisplay() {
        let big = saved(CGRect(x: 1612, y: 100, width: 2000, height: 1200), on: "ext", offset: CGPoint(x: 100, y: 100))
        #expect(DisplayPlacement.resolve(big, minSize: noMin, displays: [laptop]) == CGRect(x: 0, y: 0, width: 1512, height: 950))
    }

    @Test("Rearranging: external to the left (negative x) keeps the offset on that display")
    func rearrangeLeft() {
        let left = display("ext", CGRect(x: -2560, y: 0, width: 2560, height: 1440), menuBar: 25, scale: 1)
        #expect(DisplayPlacement.resolve(onExternal, minSize: noMin, displays: [laptop, left])
                == CGRect(x: -2460, y: 100, width: 800, height: 600))
    }

    @Test("Rearranging: external below and offset left (negative x and y)")
    func rearrangeBelow() {
        let below = display("ext", CGRect(x: -500, y: -1440, width: 2560, height: 1440), menuBar: 25, scale: 1)
        #expect(DisplayPlacement.resolve(onExternal, minSize: noMin, displays: [laptop, below])
                == CGRect(x: -400, y: -1340, width: 800, height: 600))
        // A negative offset on a negative display is pulled inside it.
        let p = saved(CGRect(x: 0, y: 0, width: 800, height: 600), on: "ext", offset: CGPoint(x: -300, y: -50))
        #expect(DisplayPlacement.resolve(p, minSize: noMin, displays: [laptop, below])
                == CGRect(x: -500, y: -1440, width: 800, height: 600))
    }

    @Test("Rearranging: external above the laptop")
    func rearrangeAbove() {
        let above = display("ext", CGRect(x: -524, y: 982, width: 2560, height: 1440), menuBar: 25, scale: 1)
        #expect(DisplayPlacement.resolve(onExternal, minSize: noMin, displays: [laptop, above])
                == CGRect(x: -424, y: 1082, width: 800, height: 600))
    }

    @Test("Resolution change to a smaller visible frame: same offset, translated inside")
    func resolutionSmaller() {
        let p = saved(CGRect(x: 600, y: 300, width: 800, height: 600), on: "laptop", offset: CGPoint(x: 600, y: 300))
        let lowRes = display("laptop", CGRect(x: 0, y: 0, width: 1024, height: 640), menuBar: 32, scale: 2, main: true)
        #expect(DisplayPlacement.resolve(p, minSize: noMin, displays: [lowRes]) == CGRect(x: 224, y: 8, width: 800, height: 600))
    }

    @Test("Resolution change to a larger visible frame: the saved frame is used as is")
    func resolutionLarger() {
        let p = saved(CGRect(x: 600, y: 300, width: 800, height: 600), on: "laptop", offset: CGPoint(x: 600, y: 300))
        let moreSpace = display("laptop", CGRect(x: 0, y: 0, width: 1800, height: 1169), menuBar: 32, scale: 2, main: true)
        #expect(DisplayPlacement.resolve(p, minSize: noMin, displays: [moreSpace]) == p.intendedFrame)
    }

    @Test("Scale change alone doesn't change the result (points, not pixels)", arguments: [1.0, 1.5, 2.0, 3.0])
    func scaleChange(scale: Double) {
        var ext = externalRight
        ext.scale = scale
        #expect(DisplayPlacement.resolve(onExternal, minSize: noMin, displays: [laptop, ext]) == onExternal.intendedFrame)
    }

    @Test("Main display switch: global coordinates move with the new primary")
    func mainDisplaySwitch() {
        // The external display becomes primary: it sits at the origin and the laptop moves to negative x.
        let extPrimary = display("ext", CGRect(x: 0, y: 0, width: 2560, height: 1440), menuBar: 25, scale: 1, main: true)
        let laptopSecondary = display("laptop", CGRect(x: -1512, y: 0, width: 1512, height: 982), menuBar: 32, scale: 2)
        let displays = [extPrimary, laptopSecondary]

        // A window saved on the laptop follows the laptop to its new coordinates.
        let onLaptop = saved(CGRect(x: 100, y: 50, width: 800, height: 600), on: "laptop", offset: CGPoint(x: 100, y: 50))
        #expect(DisplayPlacement.resolve(onLaptop, minSize: noMin, displays: displays)
                == CGRect(x: -1412, y: 50, width: 800, height: 600))
        // A centred window without a display hint goes to the new primary.
        let centred = saved(CGRect(x: 0, y: 0, width: 800, height: 600), on: nil, offset: nil)
        #expect(DisplayPlacement.resolve(centred, minSize: noMin, displays: displays)
                == CGRect(x: 1280 - 400, y: 707.5 - 300, width: 800, height: 600))
        // A window from a missing display goes to the new primary, not to the old one.
        let lost = saved(CGRect(x: 0, y: 0, width: 800, height: 600), on: "gone", offset: CGPoint(x: 10, y: 20))
        #expect(DisplayPlacement.resolve(lost, minSize: noMin, displays: displays) == CGRect(x: 10, y: 20, width: 800, height: 600))
    }

    @Test("Mixed Retina: a Retina primary and a 1× external resolve in the same point space")
    func mixedRetina() {
        let retina4K = display("ext", CGRect(x: 1512, y: -200, width: 1920, height: 1080), menuBar: 25, scale: 2)
        let oneX = display("side", CGRect(x: -1280, y: 0, width: 1280, height: 1024), menuBar: 25, scale: 1)
        let displays = [laptop, retina4K, oneX]
        let onRetina = saved(.zero, on: "ext", offset: CGPoint(x: 50, y: 60))
        let onOneX = saved(.zero, on: "side", offset: CGPoint(x: 50, y: 60))
        let size = CGSize(width: 640, height: 480)
        #expect(DisplayPlacement.resolve(onRetina, minSize: size, displays: displays) == CGRect(x: 1562, y: -140, width: 640, height: 480))
        #expect(DisplayPlacement.resolve(onOneX, minSize: size, displays: displays) == CGRect(x: -1230, y: 60, width: 640, height: 480))
    }

    @Test("A window spanning two displays is pulled fully inside its saved display")
    func spanningTwoDisplays() {
        // 800 pt wide at x = 1300: 212 pt on the laptop, 588 pt on the external → displayID "ext", offset −212.
        let spanning = saved(CGRect(x: 1300, y: 100, width: 800, height: 600), on: "ext", offset: CGPoint(x: -212, y: 100))
        #expect(DisplayPlacement.resolve(spanning, minSize: noMin, displays: [laptop, externalRight])
                == CGRect(x: 1512, y: 100, width: 800, height: 600))
        // Saved on the laptop instead: pulled back left onto the laptop.
        let onLaptop = saved(spanning.intendedFrame, on: "laptop", offset: CGPoint(x: 1300, y: 100))
        #expect(DisplayPlacement.resolve(onLaptop, minSize: noMin, displays: [laptop, externalRight])
                == CGRect(x: 712, y: 100, width: 800, height: 600))
    }

    @Test("Display smaller than the minimum size: clamped to the visible frame, below the minimum")
    func displaySmallerThanMinimum() {
        let tiny = display("tiny", CGRect(x: 0, y: 0, width: 640, height: 432), menuBar: 32, scale: 1, main: true)
        let p = saved(CGRect(x: 0, y: 0, width: 1000, height: 700), on: "tiny", offset: CGPoint(x: 50, y: 50))
        #expect(DisplayPlacement.resolve(p, minSize: CGSize(width: 800, height: 500), displays: [tiny])
                == CGRect(x: 0, y: 0, width: 640, height: 400))
        // Only one axis too small.
        let narrow = display("tiny", CGRect(x: 0, y: 0, width: 640, height: 1200), menuBar: 0, scale: 1, main: true)
        #expect(DisplayPlacement.resolve(p, minSize: CGSize(width: 800, height: 500), displays: [narrow])
                == CGRect(x: 0, y: 50, width: 640, height: 700))
    }

    @Test("Size is raised to minSize per axis first")
    func raisedToMinimum() {
        let p = saved(CGRect(x: 100, y: 100, width: 300, height: 700), on: "laptop", offset: CGPoint(x: 100, y: 100))
        #expect(DisplayPlacement.resolve(p, minSize: CGSize(width: 480, height: 300), displays: [laptop])
                == CGRect(x: 100, y: 100, width: 480, height: 700))
    }

    @Test("Hand-edited offsets far off-screen are pulled inside; no rounding of fractional points")
    func offscreenAndFractional() {
        let p = saved(CGRect(x: 0, y: 0, width: 400.5, height: 300.25), on: "laptop", offset: CGPoint(x: 5000, y: -3000))
        #expect(DisplayPlacement.resolve(p, minSize: noMin, displays: [laptop]) == CGRect(x: 1111.5, y: 0, width: 400.5, height: 300.25))
        let q = saved(CGRect(x: 0, y: 0, width: 400, height: 300), on: "laptop", offset: CGPoint(x: 10.25, y: 20.75))
        #expect(DisplayPlacement.resolve(q, minSize: noMin, displays: [laptop]) == CGRect(x: 10.25, y: 20.75, width: 400, height: 300))
    }

    // MARK: No drift

    @Test("Re-placement never changes intendedFrame; reconnecting returns the window to its spot")
    func noDrift() throws {
        var window = mainWindow(1, p(1, 1))
        window.placement = onExternal
        let s = session(window)
        let bytes = try Migrator.encode(s)

        let configurations: [[DisplaySnapshot]] = [
            [laptop],                                                                                  // unplugged
            [display("laptop", CGRect(x: 0, y: 0, width: 1024, height: 640), menuBar: 32, main: true)], // low resolution
            [laptop, display("ext", CGRect(x: -2560, y: 0, width: 2560, height: 1440), menuBar: 25)],  // rearranged
            [],
            [laptop, externalRight],                                                                   // reconnected
        ]
        var frames: [CGRect] = []
        for displays in configurations {
            frames.append(DisplayPlacement.resolve(s.windows[0].placement, minSize: CGSize(width: 320, height: 200), displays: displays))
            #expect(try Migrator.encode(s) == bytes)
        }
        #expect(s.windows[0].placement == onExternal)
        #expect(frames.last == onExternal.intendedFrame)
        #expect(frames[0] != onExternal.intendedFrame)
    }

    // MARK: Writing a placement (§9)

    @Test("Window on one display: that display, offset from its visibleFrame origin, frame kept")
    func writeOnOneDisplay() {
        let frame = CGRect(x: 1612, y: 100, width: 800, height: 600)
        #expect(DisplayPlacement.placement(writing: frame, displays: [laptop, externalRight]) == onExternal)
        #expect(DisplayPlacement.placement(writing: frame, displays: [externalRight, laptop]) == onExternal)
    }

    @Test("Window spanning two displays: the display with the larger part wins")
    func writeSpanning() {
        // 212 pt on the laptop, 588 pt on the external.
        let mostlyExternal = DisplayPlacement.placement(writing: CGRect(x: 1300, y: 100, width: 800, height: 600),
                                                        displays: [laptop, externalRight])
        #expect(mostlyExternal.displayID == "ext" && mostlyExternal.relativeOrigin == CGPoint(x: -212, y: 100))
        // 600 pt on the laptop, 200 pt on the external.
        let mostlyLaptop = DisplayPlacement.placement(writing: CGRect(x: 912, y: 100, width: 800, height: 600),
                                                      displays: [laptop, externalRight])
        #expect(mostlyLaptop.displayID == "laptop" && mostlyLaptop.relativeOrigin == CGPoint(x: 912, y: 100))
        #expect(DisplayPlacement.resolve(mostlyExternal, minSize: noMin, displays: [laptop, externalRight])
                == CGRect(x: 1512, y: 100, width: 800, height: 600))
    }

    @Test("Equal overlap → the earlier display in the list")
    func writeTie() {
        let frame = CGRect(x: 1412, y: 100, width: 200, height: 100)   // 100 pt on each side of x = 1512
        #expect(DisplayPlacement.placement(writing: frame, displays: [laptop, externalRight]).displayID == "laptop")
        #expect(DisplayPlacement.placement(writing: frame, displays: [externalRight, laptop]).displayID == "ext")
    }

    @Test("Overlap is measured against frame, the offset against visibleFrame; negative coordinates")
    func writeNegativeAndVisibleFrame() {
        let below = display("below", CGRect(x: -500, y: -1440, width: 2560, height: 1440), menuBar: 25, scale: 1)
        let frame = CGRect(x: -400, y: -1340, width: 800, height: 600)
        #expect(DisplayPlacement.placement(writing: frame, displays: [laptop, below])
                == SavedPlacement(intendedFrame: frame, displayID: "below", relativeOrigin: CGPoint(x: 100, y: 100)))
        // A visibleFrame origin that differs from the frame origin (Dock on the left and bottom).
        var docked = laptop
        docked.visibleFrame = CGRect(x: 70, y: 40, width: 1442, height: 910)
        #expect(DisplayPlacement.placement(writing: CGRect(x: 100, y: 100, width: 400, height: 300), displays: [docked]).relativeOrigin
                == CGPoint(x: 30, y: 60))
    }

    @Test("Touching no display → earlier display (all overlaps tie at zero); no displays → no hint")
    func writeNoOverlapAndNoDisplays() {
        let far = CGRect(x: 9000, y: 9000, width: 100, height: 100)
        #expect(DisplayPlacement.placement(writing: far, displays: [laptop, externalRight]).displayID == "laptop")
        // Sharing only an edge is zero area, not an overlap.
        #expect(DisplayPlacement.placement(writing: CGRect(x: 4072, y: 0, width: 100, height: 100),
                                           displays: [externalRight, laptop]).displayID == "ext")
        #expect(DisplayPlacement.placement(writing: far, displays: [])
                == SavedPlacement(intendedFrame: far, displayID: nil, relativeOrigin: nil))
    }

    @Test("A written placement resolves back to the written frame on the same displays")
    func writeThenResolve() {
        let frame = CGRect(x: 300.5, y: 120.25, width: 700, height: 500)
        let written = DisplayPlacement.placement(writing: frame, displays: [laptop, externalRight])
        #expect(DisplayPlacement.resolve(written, minSize: noMin, displays: [laptop, externalRight]) == frame)
    }

    @Test func snapshotIsEquatable() {
        #expect(laptop == laptop)
        #expect(laptop != externalRight)
    }
}
