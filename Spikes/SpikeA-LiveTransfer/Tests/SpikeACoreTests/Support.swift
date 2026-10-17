import AppKit
import Testing
@testable import SpikeACore

/// Two real NSWindows (never ordered on screen) with the demo's pane layout.
@MainActor final class TwoWindowFixture {
    let coordinator = TransferCoordinator()
    let a1, a2, b1, b2, locked: PaneHostView
    let windowA, windowB: NSWindow
    let counter: CounterContent
    let spinner: SpinnerContent

    init(autoRotate: Bool = false) throws {
        _ = NSApplication.shared
        coordinator.activatesDestinationWindow = false
        let idA = WindowID(), idB = WindowID()
        a1 = try coordinator.makePane(in: idA)
        a2 = try coordinator.makePane(in: idA)
        b1 = try coordinator.makePane(in: idB)
        b2 = try coordinator.makePane(in: idB)
        locked = try coordinator.makePane(in: idB, acceptsDrops: false)
        windowA = SpikeWindow.make(title: "A", panes: [a1, a2])
        windowB = SpikeWindow.make(title: "B", panes: [b1, b2, locked])
        counter = CounterContent(count: 0)
        spinner = SpinnerContent(autoRotate: autoRotate)
        try coordinator.add(counter, to: a1.hostID)
        try coordinator.add(spinner, to: a2.hostID)
        layout()
    }

    var windows: [NSWindow] { [windowA, windowB] }

    func residue() -> ResidueReport { coordinator.residue(windows: windows) }

    /// Lets AppKit/SwiftUI finish layout and deferred work. Suspends (rather than spinning a nested
    /// run loop) so main-actor tasks run and the main queue's autorelease pools drain.
    func settle(_ seconds: Double = 0.05) async {
        for w in windows { w.contentView?.layoutSubtreeIfNeeded() }
        try? await Task.sleep(for: .seconds(seconds))
        for w in windows { w.contentView?.layoutSubtreeIfNeeded() }
    }

    /// Synchronous variant for use right after setup.
    func layout() {
        for w in windows { w.contentView?.layoutSubtreeIfNeeded() }
    }

    func close() {
        for w in windows { w.close() }
    }
}

/// Stand-in for AppKit's dragging info so tests can drive the real NSDraggingDestination methods.
@MainActor final class FakeDraggingInfo: NSObject, @MainActor NSDraggingInfo {
    let draggingPasteboard: NSPasteboard
    let draggingDestinationWindow: NSWindow?

    init(payload: DragPayload, window: NSWindow?) {
        draggingPasteboard = NSPasteboard.withUniqueName()
        draggingPasteboard.clearContents()
        draggingPasteboard.setString(payload.encoded, forType: .spikeATransfer)
        draggingDestinationWindow = window
    }

    var draggingSourceOperationMask: NSDragOperation { .move }
    var draggingLocation: NSPoint { .zero }
    var draggedImageLocation: NSPoint { .zero }
    var draggedImage: NSImage? { nil }
    var draggingSource: Any? { nil }
    var draggingSequenceNumber: Int { 1 }
    func slideDraggedImage(to screenPoint: NSPoint) {}
    var draggingFormation: NSDraggingFormation = .default
    var animatesToDestination = false
    var numberOfValidItemsForDrop = 1
    func enumerateDraggingItems(
        options enumOpts: NSDraggingItemEnumerationOptions = [],
        for view: NSView?,
        classes classArray: [AnyClass],
        searchOptions: [NSPasteboard.ReadingOptionKey: Any] = [:],
        using block: (NSDraggingItem, Int, UnsafeMutablePointer<ObjCBool>) -> Void
    ) {}
    var springLoadingHighlight: NSSpringLoadingHighlight { .none }
    func resetSpringLoading() {}
}
