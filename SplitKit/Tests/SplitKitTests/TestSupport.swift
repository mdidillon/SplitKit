import Foundation
import Observation
import os
import SwiftUI
import Testing
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
    /// `shouldClose()` waits for `answerClose(_:)`, like a content showing a sheet.
    var suspendsClose = false
    @ObservationIgnored private var closeAnswer: CheckedContinuation<Bool, Never>?
    private(set) var shouldCloseCalls = 0
    private(set) var willReleaseCalls = 0
    private(set) var makeViewCalls = 0
    /// What `init` was given as `url`.
    let receivedURL: URL?

    init(id: ContentID, url: URL?, restoring state: Data?, stateVersion: Int?) throws(ContentError) {
        self.id = id
        receivedURL = url
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
        if suspendsClose { return await withCheckedContinuation { closeAnswer = $0 } }
        return acceptsClose
    }
    func willRelease() { willReleaseCalls += 1 }

    /// Whether `shouldClose()` is waiting for its answer.
    var isAskingToClose: Bool { closeAnswer != nil }

    func answerClose(_ accept: Bool) {
        closeAnswer?.resume(returning: accept)
        closeAnswer = nil
    }
}

/// A second succeeding content type, so tests can tell which type the picker inserted.
@MainActor @Observable
final class OtherContent: PaneContent {
    static let type = ContentType(raw: "test.other")
    static let displayName = "Other"
    static let systemImage = "circle"
    static let minimumSize = CGSize.zero
    static let stateVersion = 1

    let id: ContentID

    init(id: ContentID, url: URL?, restoring state: Data?, stateVersion: Int?) throws(ContentError) {
        self.id = id
    }

    var title: String { "Other" }
    var toolbarItems: [PaneToolbarItem] { [] }
    func makeView() -> AnyView { AnyView(Color.clear) }
    func encodeState() throws -> Data { Data() }
    func shouldClose() async -> Bool { true }
    func willRelease() {}
}

/// A content whose creation always fails.
@MainActor @Observable
final class FailingContent: PaneContent {
    static let type = ContentType(raw: "test.failing")
    static let displayName = "Failing"
    static let systemImage = "xmark.octagon"
    static let minimumSize = CGSize.zero
    static let stateVersion = 1

    init(id: ContentID, url: URL?, restoring state: Data?, stateVersion: Int?) throws(ContentError) {
        throw .other("always fails")
    }

    var title: String { "" }
    var toolbarItems: [PaneToolbarItem] { [] }
    func makeView() -> AnyView { AnyView(EmptyView()) }
    func encodeState() throws -> Data { Data() }
    func shouldClose() async -> Bool { true }
    func willRelease() {}
}

/// A file-based content (register it with `accepts: [.png]`): a file named `broken…` is unreadable.
@MainActor @Observable
final class FileContent: PaneContent {
    static let type = ContentType(raw: "test.file")
    static let displayName = "File"
    static let systemImage = "doc"
    static let minimumSize = CGSize.zero
    static let stateVersion = 1

    let receivedURL: URL?

    init(id: ContentID, url: URL?, restoring state: Data?, stateVersion: Int?) throws(ContentError) {
        if let url, url.lastPathComponent.hasPrefix("broken") { throw .unreadable(url) }
        receivedURL = url
    }

    var title: String { receivedURL?.lastPathComponent ?? "File" }
    var toolbarItems: [PaneToolbarItem] { [] }
    func makeView() -> AnyView { AnyView(Color.clear) }
    func encodeState() throws -> Data { Data() }
    func shouldClose() async -> Bool { true }
    func willRelease() {}
}

/// A content that validates its URL in `init`: any URL is an unsupported file, no URL is fine.
@MainActor @Observable
final class PickyContent: PaneContent {
    static let type = ContentType(raw: "test.picky")
    static let displayName = "Picky"
    static let systemImage = "hand.raised"
    static let minimumSize = CGSize.zero
    static let stateVersion = 1

    init(id: ContentID, url: URL?, restoring state: Data?, stateVersion: Int?) throws(ContentError) {
        if let url { throw .unsupportedFile(url, reason: "not supported") }
    }

    var title: String { "Picky" }
    var toolbarItems: [PaneToolbarItem] { [] }
    func makeView() -> AnyView { AnyView(Color.clear) }
    func encodeState() throws -> Data { Data() }
    func shouldClose() async -> Bool { true }
    func willRelease() {}
}

/// A content with real state (a count, JSON-encoded) whose `encodeState()` can be made to throw.
@MainActor @Observable
final class CounterContent: PaneContent {
    static let type = ContentType(raw: "test.counter")
    static let displayName = "Counter"
    static let systemImage = "number"
    static let minimumSize = CGSize.zero
    static let stateVersion = 3

    struct State: Codable, Equatable { var count: Int }

    let id: ContentID
    var count = 0
    var failsEncoding = false
    /// What `init` was given as `stateVersion`; `nil` when the content was created new.
    let restoredStateVersion: Int?
    /// What `init` was given as `url`.
    let receivedURL: URL?

    init(id: ContentID, url: URL?, restoring state: Data?, stateVersion: Int?) throws(ContentError) {
        self.id = id
        receivedURL = url
        restoredStateVersion = stateVersion
        guard let state else { return }
        do {
            count = try JSONDecoder().decode(State.self, from: state).count
        } catch {
            throw .stateIncompatible(version: stateVersion ?? 0)
        }
    }

    var title: String { "Counter" }
    var toolbarItems: [PaneToolbarItem] { [] }
    func makeView() -> AnyView { AnyView(Color.clear) }
    func encodeState() throws -> Data {
        if failsEncoding { throw ContentError.other("encodeState fails") }
        return try JSONEncoder().encode(State(count: count))
    }
    func shouldClose() async -> Bool { true }
    func willRelease() {}

    static func state(_ count: Int) -> Data { try! JSONEncoder().encode(State(count: count)) }
}

/// A content whose `init(restoring:)` throws while `failing` is set. Only one test uses it.
@MainActor @Observable
final class FlakyRestoreContent: PaneContent {
    static let type = ContentType(raw: "test.flaky")
    static let displayName = "Flaky"
    static let systemImage = "bolt"
    static let minimumSize = CGSize.zero
    static let stateVersion = 1
    static var failing = false

    init(id: ContentID, url: URL?, restoring state: Data?, stateVersion: Int?) throws(ContentError) {
        if Self.failing { throw .other("flaky restore") }
    }

    var title: String { "Flaky" }
    var toolbarItems: [PaneToolbarItem] { [] }
    func makeView() -> AnyView { AnyView(Color.clear) }
    func encodeState() throws -> Data { Data() }
    func shouldClose() async -> Bool { true }
    func willRelease() {}
}

/// An in-memory `SessionStore` that records its saves and can fail or block them.
final class MemoryStore: SessionStore, @unchecked Sendable {
    struct Failure: Error {}
    private struct State {
        var data: Data?
        var saved: [Data] = []
        var failuresPending = 0
        var loadFails = false
        var blocking = false
        var waiters: [CheckedContinuation<Void, Never>] = []
        var started = 0, current = 0, peak = 0
    }
    private let state: OSAllocatedUnfairLock<State>

    init(data: Data? = nil) { state = OSAllocatedUnfairLock(initialState: State(data: data)) }

    var data: Data? { state.withLock { $0.data } }
    /// Every successful save, oldest first.
    var saved: [Data] { state.withLock { $0.saved } }
    var started: Int { state.withLock { $0.started } }
    /// The most saves that were ever running at once.
    var peak: Int { state.withLock { $0.peak } }

    func failSaves(_ count: Int = .max) { state.withLock { $0.failuresPending = count } }
    func failLoad() { state.withLock { $0.loadFails = true } }
    /// Saves wait in `save` until `release()`.
    func block() { state.withLock { $0.blocking = true } }
    func release() {
        let waiters = state.withLock { state in
            state.blocking = false
            defer { state.waiters = [] }
            return state.waiters
        }
        for waiter in waiters { waiter.resume() }
    }

    func load() async throws -> Data? {
        if state.withLock({ $0.loadFails }) { throw Failure() }
        return data
    }

    func save(_ data: Data) async throws {
        let blocking = state.withLock { state in
            state.started += 1
            state.current += 1
            state.peak = max(state.peak, state.current)
            return state.blocking
        }
        if blocking {
            await withCheckedContinuation { continuation in
                let resumeNow = state.withLock { state in
                    if state.blocking { state.waiters.append(continuation) }
                    return !state.blocking
                }
                if resumeNow { continuation.resume() }
            }
        }
        let failed = state.withLock { state in
            state.current -= 1
            if state.failuresPending > 0 {
                state.failuresPending -= 1
                return true
            }
            state.data = data
            state.saved.append(data)
            return false
        }
        if failed { throw Failure() }
    }
}

/// A window layer that records what the workspace asks of it, in order, and can hold back placements
/// like the coordinator's coalescing.
@MainActor
final class RecordingWindowHost: WorkspaceWindowHost {
    enum Call: Equatable {
        case open([WindowID]), close([WindowID]), bringForward(WindowID)
    }

    /// Every non-empty call, oldest first.
    private(set) var calls: [Call] = []
    /// What `flushPendingPlacements()` hands to `deliver`.
    var pendingPlacements: [(WindowID, SavedPlacement)] = []
    var deliver: ((WindowID, SavedPlacement) -> Void)?

    func open(_ windows: [WindowID]) { if !windows.isEmpty { calls.append(.open(windows)) } }
    func close(_ windows: [WindowID]) { if !windows.isEmpty { calls.append(.close(windows)) } }
    func bringForward(_ window: WindowID) { calls.append(.bringForward(window)) }
    func flushPendingPlacements() {
        let pending = pendingPlacements
        pendingPlacements = []
        for (window, placement) in pending { deliver?(window, placement) }
    }
}

/// Runs `body` with a fresh temporary directory and deletes it afterwards.
nonisolated(nonsending) func withTemporaryDirectory<T>(_ body: (URL) async throws -> T) async throws -> T {
    let directory = FileManager.default.temporaryDirectory.appending(path: "SplitKitTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    return try await body(directory)
}

/// Polls `condition` every 5 ms until it holds; records an issue after `timeout`.
@MainActor
func waitUntil(_ comment: String, timeout: Duration = .seconds(5), _ condition: @MainActor () -> Bool) async {
    let deadline = ContinuousClock.now + timeout
    while !condition() {
        if ContinuousClock.now > deadline {
            Issue.record("timed out waiting for \(comment)")
            return
        }
        try? await Task.sleep(for: .milliseconds(5))
    }
}

/// A workspace over `persistence` that has not restored yet; its registry has `TestContent`, `CounterContent`
/// and the `extra` types. Autosave is debounced at `debounce`.
@MainActor
func makePersistentWorkspace(_ persistence: SplitKitConfiguration.Persistence, seed: UInt64 = 0x5EED,
                             debounce: Duration = .milliseconds(10), types: [any PaneContent.Type] = [CounterContent.self],
                             detach: SplitKitConfiguration.Detach = .enabled,
                             encode: @escaping SessionWriter.Encode = { try Migrator.encode($0) }) throws -> SplitKitWorkspace {
    let registry = ContentRegistry()
    try registry.register(TestContent.self)
    for type in types { try registry.register(type) }
    let workspace = SplitKitWorkspace(registry: registry,
                                      configuration: SplitKitConfiguration(persistence: persistence, detach: detach, autosaveDebounce: debounce),
                                      ids: SeededIDGenerator(seed: seed), encode: encode)
    workspace.displays = { [testDisplay] }
    return workspace
}

/// The one display detached windows are placed on in tests: 1600×1000 pt with a 32 pt menu bar.
let testDisplay = DisplaySnapshot(id: "test", frame: CGRect(x: 0, y: 0, width: 1600, height: 1000),
                                  visibleFrame: CGRect(x: 0, y: 0, width: 1600, height: 968), scale: 2, isMain: true)

/// A `makePersistentWorkspace` with a recording window layer: no window is shown.
@MainActor
func hostedWorkspace(_ persistence: SplitKitConfiguration.Persistence = .disabled, debounce: Duration = .milliseconds(10),
                     types: [any PaneContent.Type] = [CounterContent.self],
                     detach: SplitKitConfiguration.Detach = .enabled) throws -> (SplitKitWorkspace, RecordingWindowHost) {
    let workspace = try makePersistentWorkspace(persistence, debounce: debounce, types: types, detach: detach)
    let host = RecordingWindowHost()
    workspace.windowHost = host
    return (workspace, host)
}

/// A one-window session with one pane hosting a record of `type`, and its encoded bytes.
func sessionFile(type: String, state: Data = Data([1, 2, 3]), stateVersion: Int = 7,
                 availability: ContentRecord.Availability = .unavailable) throws -> (session: Session, bytes: Data, content: ContentID) {
    let content = ContentID(raw: UUID())
    let window = WindowLayout(id: WindowID(raw: UUID()), kind: .main, root: .pane(id: PaneID(raw: UUID()), content: content),
                              placement: .defaultMainWindow)
    let session = Session(windows: [window], contents: [ContentRecord(id: content, type: ContentType(raw: type), stateVersion: stateVersion,
                                                                       state: state, availability: availability)])
    return (session, try Migrator.encode(session), content)
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
    /// Registers the pane cells `window`'s split view would lay out in `size` with the `.glass` tokens, so a
    /// drop can be hit-tested without a rendered window (what `SplitLayoutView` does on appear).
    @discardableResult
    func registerPaneCells(of window: WindowID, size: CGSize = CGSize(width: 800, height: 600)) -> PaneCells {
        let tokens = SplitKitTokens.glass
        let cells = PaneCells(
            cells: windowLayout(window)?.root.map {
                SplitGeometry.layout($0, in: CGRect(origin: .zero, size: size), dividerHitWidth: tokens.metrics.dividerHitWidth,
                                     paneMinimum: { self.paneMinimum($0, tokens: tokens) }).panes
            } ?? [],
            contentPadding: tokens.metrics.contentPadding, headerHeight: tokens.metrics.headerHeight)
        paneCells[window] = cells
        return cells
    }

    /// The main window's layout.
    var mainLayout: WindowLayout { windowLayout(mainWindow!)! }
    /// The main window's panes with their contents, in tree order.
    var mainLeaves: [(pane: PaneID, content: ContentID?)] { mainLayout.root?.leaves ?? [] }

    /// Adds an unavailable placeholder (a record whose type has no live object, spec §8) in a new pane to
    /// the right of `pane`, or into the empty main window when `pane` is nil.
    @discardableResult
    func addPlaceholder(besides pane: PaneID? = nil, type: ContentType = ContentType(raw: "test.missing")) throws -> (pane: PaneID, content: ContentID) {
        let content = NewContent(id: ContentID(raw: UUID()), type: type, stateVersion: 1)
        let before = Set(mainLeaves.map(\.pane))
        if let pane {
            try commit(.insert(content, at: pane, edge: .right, in: try window(containing: pane)))
        } else {
            try commit(.insertIntoEmptyWindow(content, in: mainLayout.id))
        }
        let added = try #require(mainLeaves.first { !before.contains($0.pane) }?.pane)
        return (added, content.id)
    }

    /// Performs `command` and answers the close prompt it shows with `confirmed`. Returns that prompt, or
    /// nil if the command finished without one.
    @discardableResult
    func perform(_ command: SplitKitCommand, answering confirmed: Bool) async throws -> ClosePrompt? {
        let task = Task { try await self.perform(command) }
        var shown: ClosePrompt?
        for _ in 0..<100 where shown == nil {
            if let prompt = closePrompt {
                shown = prompt
                answer(prompt, confirmed: confirmed)
            } else {
                try await Task.sleep(for: .milliseconds(10))
            }
        }
        try await task.value
        return shown
    }
}

extension LayoutNode {
    /// The tree as text: `p` per pane, `H(…)` / `V(…)` per split with its children in order.
    var shape: String {
        switch self {
        case .pane: "p"
        case let .split(_, axis, children, _): (axis == .horizontal ? "H" : "V") + "(" + children.map(\.shape).joined(separator: ",") + ")"
        }
    }
}

extension SplitKitWorkspace {
    /// Runs `action` as the menu bar would: the model of the active pane of `window`.
    func key(_ action: PaneMenuModel.Action, in window: WindowID) async {
        await activePaneMenuModel(in: window).run(action, in: self)
    }

    /// File ▸ Add Content… (⇧⌘N), then Return on the first row of the type list (or on `type`'s row, reached
    /// with ↓): the same path as the popover.
    func addContentByKeyboard(_ type: ContentType = TestContent.type, in window: WindowID) async {
        await key(.chooseContent, in: window)
        guard addContentRequest == window else { Issue.record("⇧⌘N did not open the type list"); return }
        let picker = contentPicker(for: addContentTarget(in: window))
        var highlighted = picker.moving(nil, by: 1)
        while let current = highlighted, current != type, let next = picker.moving(current, by: 1), next != current {
            highlighted = next
        }
        guard let highlighted else { Issue.record("empty type list"); return }
        await chooseRequestedContent(highlighted, in: window)
    }
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
