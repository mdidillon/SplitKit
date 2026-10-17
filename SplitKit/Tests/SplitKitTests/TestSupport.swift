import Foundation
import Observation
import SwiftUI
import SplitKitContent
import SplitKitModel
@testable import SplitKit

/// A content that records what the workspace does with it: `shouldClose()` answers `acceptsClose`.
@MainActor @Observable
final class TestContent: PaneContent {
    static let type = ContentType(raw: "test.content")
    static let displayName = "Test"
    static let systemImage = "square"
    static let minimumSize = CGSize(width: 200, height: 120)
    static let stateVersion = 2

    let id: ContentID
    var acceptsClose = true
    private(set) var shouldCloseCalls = 0
    private(set) var willReleaseCalls = 0
    private(set) var makeViewCalls = 0

    init(id: ContentID, restoring state: Data?, stateVersion: Int?) throws(ContentError) {
        self.id = id
    }

    var title: String { "Test \(id.raw.uuidString.prefix(4))" }
    var toolbarItems: [PaneToolbarItem] = []
    func makeView() -> AnyView {
        makeViewCalls += 1
        return AnyView(Color.clear)
    }
    func encodeState() throws -> Data { Data() }
    func shouldClose() async -> Bool {
        shouldCloseCalls += 1
        return acceptsClose
    }
    func willRelease() { willReleaseCalls += 1 }
}

/// A content whose creation always fails.
@MainActor @Observable
final class FailingContent: PaneContent {
    static let type = ContentType(raw: "test.failing")
    static let displayName = "Failing"
    static let systemImage = "xmark.octagon"
    static let minimumSize = CGSize.zero
    static let stateVersion = 1

    init(id: ContentID, restoring state: Data?, stateVersion: Int?) throws(ContentError) {
        throw .other("always fails")
    }

    var title: String { "" }
    var toolbarItems: [PaneToolbarItem] { [] }
    func makeView() -> AnyView { AnyView(EmptyView()) }
    func encodeState() throws -> Data { Data() }
    func shouldClose() async -> Bool { true }
    func willRelease() {}
}

extension SeededIDGenerator {
    /// A deterministic value in `0..<bound`, from the first 8 bytes of the next UUID.
    mutating func nextValue(below bound: UInt64) -> UInt64 {
        let u = next().uuid
        return [u.0, u.1, u.2, u.3, u.4, u.5, u.6, u.7].reduce(0) { $0 << 8 | UInt64($1) } % bound
    }
}

/// A workspace with `TestContent` and `FailingContent` registered, seeded IDs, persistence disabled and
/// the default layout open.
@MainActor
func makeWorkspace(seed: UInt64 = 0x5EED, persistence: SplitKitConfiguration.Persistence = .disabled,
                   focusModeEnabled: Bool = true) throws -> SplitKitWorkspace {
    let registry = ContentRegistry()
    try registry.register(TestContent.self)
    try registry.register(FailingContent.self)
    let workspace = SplitKitWorkspace(registry: registry, configuration: SplitKitConfiguration(persistence: persistence, focusModeEnabled: focusModeEnabled),
                                      ids: SeededIDGenerator(seed: seed))
    _ = workspace.restoreOrOpenDefault()
    return workspace
}

extension SplitKitWorkspace {
    /// The main window's layout.
    var mainLayout: WindowLayout { windowLayout(mainWindow!)! }
    /// The main window's panes with their contents, in tree order.
    var mainLeaves: [(pane: PaneID, content: ContentID?)] { mainLayout.root?.leaves ?? [] }
}

/// A toolbar layout entry.
func toolbarEntry(_ id: String, _ priority: PaneToolbarItem.Priority, _ width: CGFloat = 30) -> PaneToolbarLayout.Entry {
    .init(id: id, priority: priority, width: width)
}

/// Hosts `view` in an `NSHostingView` of `size` and lays it out, so SwiftUI evaluates its body.
@MainActor @discardableResult
func host(_ view: some View, size: CGSize = CGSize(width: 400, height: 300)) -> NSHostingView<AnyView> {
    let hosting = NSHostingView(rootView: AnyView(view))
    hosting.frame = CGRect(origin: .zero, size: size)
    hosting.layoutSubtreeIfNeeded()
    return hosting
}

/// A header configuration with test defaults; override only the state under test.
@MainActor
func headerConfiguration(title: String = "Counter", systemImage: String? = "number",
                         isActive: Bool = false, isHovered: Bool = false, isDropTarget: Bool = false,
                         isDraggedSource: Bool = false, isPendingClose: Bool = false, isEmpty: Bool = false,
                         isFocusMode: Bool = false,
                         toggleFocusMode: @escaping @MainActor () -> Void = {},
                         close: @escaping @MainActor () -> Void = {}) -> PaneHeaderConfiguration {
    PaneHeaderConfiguration(title: title, systemImage: systemImage, isActive: isActive, isHovered: isHovered,
                            isDropTarget: isDropTarget, isDraggedSource: isDraggedSource,
                            isPendingClose: isPendingClose, isEmpty: isEmpty, isFocusMode: isFocusMode,
                            menu: AnyView(Button("Split Right") {}),
                            region: { title, decorate in
                                AnyView(HStack { title; decorate(.init(content: AnyView(Button("Reset Camera") {}))) })
                            },
                            toggleFocusMode: toggleFocusMode, close: close)
}

/// An empty-pane configuration of `kind` with Add Content, or Restore + Close for the placeholder.
func emptyConfiguration(_ kind: EmptyPaneConfiguration.Kind) -> EmptyPaneConfiguration {
    switch kind {
    case .emptyPane, .emptyWindow:
        EmptyPaneConfiguration(kind: kind, title: "No Content", message: nil,
                               primaryAction: .init(title: "Add Content") {})
    case .unavailable:
        EmptyPaneConfiguration(kind: kind, title: nil, message: "Model isn't available in this app",
                               primaryAction: .init(title: "Restore", isEnabled: false) {},
                               secondaryAction: .init(title: "Close") {})
    }
}
