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
