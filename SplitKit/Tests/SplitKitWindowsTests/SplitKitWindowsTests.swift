import AppKit
import CoreGraphics
import Testing
import SplitKitModel
@testable import SplitKitWindows

@Test func smoke() {
    #expect(SplitKitWindowsInfo.version == "0.0.0")
}

/// The pure parts of the window layer (§9): the screen adapter over injected screen data and the
/// write-back rule (user moves only, no drift). No window is created.

private let laptop = ScreenAdapter.Screen(id: "laptop", frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
                                          visibleFrame: CGRect(x: 0, y: 0, width: 1512, height: 944),
                                          backingScaleFactor: 2)
private let external = ScreenAdapter.Screen(id: "external", frame: CGRect(x: -1920, y: -200, width: 1920, height: 1080),
                                            visibleFrame: CGRect(x: -1920, y: -200, width: 1920, height: 1055),
                                            backingScaleFactor: 1)

@Suite struct ScreenAdapterTests {
    @Test func theFirstScreenIsTheMainDisplayAndEverythingElseIsCopied() {
        let displays = ScreenAdapter.displays([laptop, external])
        #expect(displays == [
            DisplaySnapshot(id: "laptop", frame: laptop.frame, visibleFrame: laptop.visibleFrame, scale: 2, isMain: true),
            DisplaySnapshot(id: "external", frame: external.frame, visibleFrame: external.visibleFrame, scale: 1, isMain: false),
        ])
        // Rearranged so the external display has the menu bar: it becomes the main display.
        #expect(ScreenAdapter.displays([external, laptop]).map(\.isMain) == [true, false])
        #expect(ScreenAdapter.displays([]).isEmpty)
    }

    @Test func theDisplayIDPrefersTheUUIDThenTheNumberThenTheName() {
        #expect(ScreenAdapter.displayID(uuid: "37D8832A-2D66-02CA-B9F7-8F30A301B230", number: 1, name: "Built-in")
                == "37D8832A-2D66-02CA-B9F7-8F30A301B230")
        #expect(ScreenAdapter.displayID(uuid: nil, number: 2, name: "Built-in") == "display-2")
        #expect(ScreenAdapter.displayID(uuid: nil, number: nil, name: "Built-in") == "Built-in")
    }

    @Test func theAdapterMatchesTheRealScreens() async {
        let displays = await ScreenAdapter.currentDisplays()
        #expect(displays.filter(\.isMain).count == (displays.isEmpty ? 0 : 1))
        #expect(Set(displays.map(\.id)).count == displays.count)
    }
}

@Suite struct PlacementWriteBackTests {
    private let one = ScreenAdapter.displays([laptop])
    private let two = ScreenAdapter.displays([laptop, external])
    private let frame = CGRect(x: 100, y: 120, width: 900, height: 600)

    @Test func aUserMoveIsWrittenWithTheWritingRule() {
        var writeBack = PlacementWriteBack(displays: two)
        let written = writeBack.frameChanged(to: frame, displays: two, applyingOwnFrame: false, userInteracting: false)
        #expect(written == DisplayPlacement.placement(writing: frame, displays: two))
        #expect(written?.displayID == "laptop")
    }

    @Test func theCoordinatorsOwnFrameIsNeverWritten() {
        var writeBack = PlacementWriteBack(displays: two)
        #expect(writeBack.frameChanged(to: frame, displays: two, applyingOwnFrame: true, userInteracting: false) == nil)
        #expect(writeBack.frameChanged(to: frame, displays: two, applyingOwnFrame: true, userInteracting: true) == nil)
    }

    @Test func aSystemMoveAfterADisplayChangeIsNotWrittenButTheNextUserMoveIs() {
        var writeBack = PlacementWriteBack(displays: two)
        // The external display goes away and the system pulls the window onto the laptop: no drift.
        #expect(writeBack.frameChanged(to: frame, displays: one, applyingOwnFrame: false, userInteracting: false) == nil)
        #expect(writeBack.knownDisplays == one)
        let moved = frame.offsetBy(dx: 10, dy: 0)
        #expect(writeBack.frameChanged(to: moved, displays: one, applyingOwnFrame: false, userInteracting: false)
                == DisplayPlacement.placement(writing: moved, displays: one))
    }

    @Test func aDragDuringADisplayChangeIsTheUsers() {
        var writeBack = PlacementWriteBack(displays: one)
        #expect(writeBack.frameChanged(to: frame, displays: two, applyingOwnFrame: false, userInteracting: true)
                == DisplayPlacement.placement(writing: frame, displays: two))
    }

    @Test func aWrittenPlacementResolvesBackToTheSameFrame() {
        var writeBack = PlacementWriteBack(displays: two)
        let onExternal = CGRect(x: -1500, y: 0, width: 800, height: 600)
        let written = writeBack.frameChanged(to: onExternal, displays: two, applyingOwnFrame: false, userInteracting: true)
        #expect(written.map { DisplayPlacement.resolve($0, minSize: .zero, displays: two) } == onExternal)
    }
}

/// Where a detached window opens (§9): the source frame offset by 24 pt, resolved with the content minimum.
@MainActor @Suite struct DetachPlacementTests {
    let displays = ScreenAdapter.displays([laptop, external])

    @Test func theSourceFrameIsOffsetBy24PointsDownAndRight() {
        let placement = DetachPlacement.placement(from: CGRect(x: 100, y: 300, width: 800, height: 600),
                                                  contentMinSize: CGSize(width: 200, height: 120), displays: displays)
        #expect(placement.intendedFrame == CGRect(x: 124, y: 276, width: 800, height: 600))
        #expect(placement.displayID == "laptop" && placement.relativeOrigin == CGPoint(x: 124, y: 276))
    }

    @Test func theFrameIsResolvedInsideTheVisibleFrame() {
        let placement = DetachPlacement.placement(from: CGRect(x: 600, y: 0, width: 800, height: 600),
                                                  contentMinSize: .zero, displays: displays)
        #expect(placement.intendedFrame == CGRect(x: 624, y: 0, width: 800, height: 600), "moved below the display, pulled back in")
        let right = DetachPlacement.placement(from: CGRect(x: 800, y: 300, width: 800, height: 600),
                                              contentMinSize: .zero, displays: displays)
        #expect(right.intendedFrame.maxX <= 1512, "pulled left to stay fully on the display")
    }

    @Test func theContentMinimumRaisesASmallSource() {
        let placement = DetachPlacement.placement(from: CGRect(x: 100, y: 300, width: 100, height: 100),
                                                  contentMinSize: CGSize(width: 400, height: 300), displays: displays)
        #expect(placement.intendedFrame.width == 400)
        #expect(placement.intendedFrame.height > 300, "the minimum is the content's: the title bar comes on top")
    }

    @Test func thePlacementResolvesToItselfAndNoDisplaysKeepTheOffsetFrame() {
        let placement = DetachPlacement.placement(from: CGRect(x: 100, y: 300, width: 800, height: 600),
                                                  contentMinSize: CGSize(width: 200, height: 120), displays: displays)
        #expect(DisplayPlacement.resolve(placement, minSize: .zero, displays: displays) == placement.intendedFrame)
        let none = DetachPlacement.placement(from: CGRect(x: 100, y: 300, width: 800, height: 600), contentMinSize: .zero, displays: [])
        #expect(none.intendedFrame == CGRect(x: 124, y: 276, width: 800, height: 600) && none.displayID == nil)
    }
}

/// The simulated-display matrix of §13 through the window layer: a real `WindowCoordinator` (windows placed,
/// never shown) over injected displays. After every display change the window is where `resolve` puts it,
/// its `intendedFrame` is what it was, nothing is written back, and reconnecting returns it to the intended frame.
@MainActor @Suite struct DisplayMatrixTests {
    /// A coordinator with one window and displays the test changes at will.
    @MainActor final class Rig {
        /// The screens the coordinator's adapter reads.
        final class Screens { var current: [ScreenAdapter.Screen]; init(_ current: [ScreenAdapter.Screen]) { self.current = current } }

        let screens: Screens
        let coordinator: WindowCoordinator
        let id = WindowID(raw: UUID())
        let intended: SavedPlacement
        var written: [SavedPlacement] = []

        /// `frame` is the intended frame of the window, saved with the writing rule against `screens` unless
        /// `placement` is given.
        init(screens initial: [ScreenAdapter.Screen], frame: CGRect, placement: SavedPlacement? = nil, contentMinSize: CGSize = .zero) {
            let screens = Screens(initial)
            self.screens = screens
            intended = placement ?? DisplayPlacement.placement(writing: frame, displays: ScreenAdapter.displays(initial))
            coordinator = WindowCoordinator(makeContentView: { _ in NSView() }, displays: { ScreenAdapter.displays(screens.current) })
            coordinator.showsWindows = false
            coordinator.open(id, placement: intended, contentMinSize: contentMinSize)
            coordinator.onUserPlacementChange = { [unowned self] _, placement in written.append(placement) }
        }

        /// Changes the displays and tells the coordinator, as the system does.
        func change(to new: [ScreenAdapter.Screen]) {
            screens.current = new
            coordinator.displaysDidChange()
            coordinator.flushPendingPlacements()
        }

        var frame: CGRect { coordinator.window(of: id)!.frame }

        /// The window is at `expected` and its placement and write-back are untouched.
        func expect(frame expected: CGRect, sourceLocation: SourceLocation = #_sourceLocation) {
            #expect(frame == expected, sourceLocation: sourceLocation)
            #expect(coordinator.placement(of: id) == intended, "intendedFrame never changes", sourceLocation: sourceLocation)
            #expect(written.isEmpty, "a display change is never written back", sourceLocation: sourceLocation)
        }
    }

    private func screen(_ id: String, _ frame: CGRect, menuBar: CGFloat = 0, scale: CGFloat = 2) -> ScreenAdapter.Screen {
        ScreenAdapter.Screen(id: id, frame: frame,
                             visibleFrame: CGRect(x: frame.minX, y: frame.minY, width: frame.width, height: frame.height - menuBar),
                             backingScaleFactor: scale)
    }

    private let both = [laptop, external]
    private let onExternal = CGRect(x: -1500, y: 100, width: 800, height: 600)

    @Test func aDisplayIsAddedAndTheWindowReturnsToIt() {
        let rig = Rig(screens: [laptop], frame: onExternal, placement: DisplayPlacement.placement(writing: onExternal, displays: ScreenAdapter.displays(both)))
        rig.expect(frame: CGRect(x: 420, y: 300, width: 800, height: 600))      // its display is not there: the main display
        rig.change(to: both)
        rig.expect(frame: onExternal)
    }

    @Test func aDisplayIsRemovedAndReconnected() {
        let rig = Rig(screens: both, frame: onExternal)
        rig.expect(frame: onExternal)
        rig.change(to: [laptop])
        rig.expect(frame: CGRect(x: 420, y: 300, width: 800, height: 600))
        rig.change(to: both)
        rig.expect(frame: onExternal)
    }

    @Test func removingEveryDisplayLeavesTheFrameAndReconnectingRestoresIt() {
        let rig = Rig(screens: both, frame: onExternal)
        rig.change(to: [])
        rig.expect(frame: onExternal)           // no displays: the intended frame
        rig.change(to: both)
        rig.expect(frame: onExternal)
    }

    @Test func displaysAreRearrangedIncludingNegativeCoordinates() {
        let rig = Rig(screens: both, frame: onExternal)
        // The external display moves to the right of the laptop, then below-left with negative y.
        let right = screen("external", CGRect(x: 1512, y: 0, width: 1920, height: 1080), menuBar: 25, scale: 1)
        rig.change(to: [laptop, right])
        rig.expect(frame: CGRect(x: 1932, y: 300, width: 800, height: 600))
        let belowLeft = screen("external", CGRect(x: -1920, y: -1080, width: 1920, height: 1080), menuBar: 25, scale: 1)
        rig.change(to: [laptop, belowLeft])
        rig.expect(frame: CGRect(x: -1500, y: -780, width: 800, height: 600))
        rig.change(to: both)
        rig.expect(frame: onExternal)
    }

    @Test func theResolutionOrScaleChanges() {
        let frame = CGRect(x: 100, y: 40, width: 1400, height: 900)
        let rig = Rig(screens: [laptop], frame: frame)
        rig.expect(frame: frame)
        // A lower resolution: the window shrinks to the visible frame (points), and comes back.
        let small = screen("laptop", CGRect(x: 0, y: 0, width: 1280, height: 720), menuBar: 30, scale: 1)
        rig.change(to: [small])
        rig.expect(frame: CGRect(x: 0, y: 0, width: 1280, height: 690))
        rig.change(to: [laptop])
        rig.expect(frame: frame)
        // The scale alone does not change a frame in points.
        rig.change(to: [screen("laptop", laptop.frame, menuBar: 38, scale: 1)])
        rig.expect(frame: frame)
    }

    @Test func theMainDisplaySwitches() {
        let unplugged = SavedPlacement(intendedFrame: CGRect(x: 200, y: 200, width: 800, height: 600),
                                       displayID: "unplugged", relativeOrigin: CGPoint(x: 50, y: 60))
        let missing = Rig(screens: both, frame: .zero, placement: unplugged)
        missing.expect(frame: CGRect(x: 50, y: 60, width: 800, height: 600))       // the main display: the laptop
        let onLaptop = Rig(screens: both, frame: CGRect(x: 100, y: 100, width: 800, height: 600))
        // The external display becomes the primary one (menu bar there); the laptop sits to its right.
        let primary = screen("external", CGRect(x: 0, y: 0, width: 1920, height: 1080), menuBar: 25, scale: 1)
        let secondary = screen("laptop", CGRect(x: 1920, y: 0, width: 1512, height: 982), menuBar: 38)
        missing.change(to: [primary, secondary])
        missing.expect(frame: CGRect(x: 50, y: 60, width: 800, height: 600))       // now the external display's origin
        onLaptop.change(to: [primary, secondary])
        onLaptop.expect(frame: CGRect(x: 2020, y: 100, width: 800, height: 600))   // follows its display, not the primary one
        onLaptop.change(to: both)
        onLaptop.expect(frame: CGRect(x: 100, y: 100, width: 800, height: 600))
    }

    @Test func mixedRetinaAndNonRetinaDisplaysSwapScales() {
        let rig = Rig(screens: both, frame: onExternal)             // laptop 2x, external 1x
        let swapped = [screen("laptop", laptop.frame, menuBar: 38, scale: 1), screen("external", external.frame, menuBar: 25, scale: 2)]
        rig.change(to: swapped)
        rig.expect(frame: onExternal)                               // points, not pixels (§4)
        rig.change(to: both)
        rig.expect(frame: onExternal)
    }

    @Test func aWindowSpanningTwoDisplaysBelongsToTheOneWithMostOfIt() {
        let spanning = CGRect(x: -500, y: 100, width: 800, height: 600)   // 500 pt on the external display, 300 on the laptop
        let rig = Rig(screens: both, frame: spanning)
        #expect(rig.intended.displayID == "external")
        let pulledIn = CGRect(x: -800, y: 100, width: 800, height: 600)         // fully inside its display
        rig.expect(frame: pulledIn)
        rig.change(to: [laptop])
        rig.expect(frame: CGRect(x: 712, y: 300, width: 800, height: 600))   // pulled fully inside the laptop
        rig.change(to: both)
        rig.expect(frame: pulledIn)
    }

    @Test func aDisplaySmallerThanTheMinimumSizeShowsTheWholeDisplayAndComesBack() {
        let minimum = CGSize(width: 1000, height: 700)
        let rig = Rig(screens: [laptop], frame: CGRect(x: 100, y: 100, width: 1000, height: 700), contentMinSize: minimum)
        let before = rig.frame
        #expect(before.width == 1000 && before.height >= 700)
        let tiny = screen("laptop", CGRect(x: 0, y: 0, width: 800, height: 600), menuBar: 20, scale: 1)
        rig.change(to: [tiny])
        rig.expect(frame: CGRect(x: 0, y: 0, width: 800, height: 580))      // reachability wins over the minimum
        rig.change(to: [laptop])
        rig.expect(frame: before)
    }

    @Test func theScreenParametersNotificationReplacesTheWindow() {
        let rig = Rig(screens: both, frame: onExternal)
        rig.screens.current = [laptop]
        NotificationCenter.default.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
        rig.expect(frame: CGRect(x: 420, y: 300, width: 800, height: 600))
    }
}
