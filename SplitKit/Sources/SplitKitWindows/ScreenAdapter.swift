import AppKit
import SplitKitModel

/// The `NSScreen → DisplaySnapshot` adapter (§9). The mapping is pure over `Screen` values, so tests inject
/// screen data; only `screen(_:)` and `currentDisplays()` read AppKit.
enum ScreenAdapter {
    /// What the adapter reads from one `NSScreen`.
    struct Screen: Equatable, Sendable {
        var id: String
        var frame: CGRect
        var visibleFrame: CGRect
        var backingScaleFactor: CGFloat
    }

    /// One snapshot per screen, in `NSScreen.screens` order. The first screen is the primary display (the one
    /// with the menu bar, §9), so it alone is `isMain`; `NSScreen.main` follows the key window and is not used.
    static func displays(_ screens: [Screen]) -> [DisplaySnapshot] {
        screens.enumerated().map { index, screen in
            DisplaySnapshot(id: screen.id, frame: screen.frame, visibleFrame: screen.visibleFrame,
                            scale: Double(screen.backingScaleFactor), isMain: index == 0)
        }
    }

    /// The display ID saved in a `SavedPlacement` (a hint only, §9): the display's UUID, which survives
    /// reconnection and reboots; else its `CGDirectDisplayID`; else its name.
    static func displayID(uuid: String?, number: UInt32?, name: String) -> String {
        if let uuid { return uuid }
        if let number { return "display-\(number)" }
        return name
    }

    @MainActor static func screen(_ screen: NSScreen) -> Screen {
        let number = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
        let uuid = number.flatMap { CGDisplayCreateUUIDFromDisplayID($0)?.takeRetainedValue() }
            .flatMap { CFUUIDCreateString(nil, $0) as String? }
        return Screen(id: displayID(uuid: uuid, number: number, name: screen.localizedName),
                      frame: screen.frame, visibleFrame: screen.visibleFrame,
                      backingScaleFactor: screen.backingScaleFactor)
    }

    @MainActor static func currentDisplays() -> [DisplaySnapshot] {
        displays(NSScreen.screens.map(screen))
    }
}

/// Decides which frame changes of one coordinator window are the user's (§9 "No drift"). Only those are
/// written back as the window's `SavedPlacement`; the coordinator's own placement and the system's
/// re-placement after a display change never overwrite `intendedFrame`.
struct PlacementWriteBack {
    /// The displays at the window's previous frame change.
    private(set) var knownDisplays: [DisplaySnapshot]

    init(displays: [DisplaySnapshot]) {
        knownDisplays = displays
    }

    /// The placement to save for a window that now has `frame`, or nil when the change is not the user's:
    /// the coordinator set the frame itself (`applyingOwnFrame`), or the displays changed since the last
    /// change and the user is not dragging or resizing (`userInteracting`), i.e. the system moved it.
    mutating func frameChanged(to frame: CGRect, displays: [DisplaySnapshot], applyingOwnFrame: Bool,
                               userInteracting: Bool) -> SavedPlacement? {
        let displaysChanged = displays != knownDisplays
        knownDisplays = displays
        guard !applyingOwnFrame, userInteracting || !displaysChanged else { return nil }
        return DisplayPlacement.placement(writing: frame, displays: displays)
    }
}
