import Foundation
import Observation
import SplitKitContent
import SplitKitModel

/// The live workspace (§5): the `Session`, its `WorkspaceRuntime`, the registry and the live content
/// objects. Every layout change goes through `SessionEngine.apply` (pure); the result is committed and
/// its side effects run only after success, in the order of §6.2 (re-host → release).
@MainActor @Observable
public final class SplitKitWorkspace {
    let registry: ContentRegistry
    let configuration: SplitKitConfiguration
    /// The layout. Not in §5's public API; SplitKitView reads it.
    private(set) var session = Session()
    public private(set) var runtime = WorkspaceRuntime()
    /// The live `PaneContent` objects (§6.4).
    let store = ContentStore()
    /// Source of new PaneIDs, SplitIDs, ContentIDs and WindowIDs. Advancing it is not app state (§6.2).
    @ObservationIgnored private var ids: any IDGenerator

    public convenience init(registry: ContentRegistry, configuration: SplitKitConfiguration) throws(PersistenceError) {
        self.init(registry: registry, configuration: configuration, ids: SystemIDGenerator())
    }

    /// Tests inject a `SeededIDGenerator`.
    init(registry: ContentRegistry, configuration: SplitKitConfiguration, ids: some IDGenerator) {
        self.registry = registry
        self.configuration = configuration
        self.ids = ids
    }

    /// Persistence is a later Phase 2 task: for now this always opens the default layout, one `.main`
    /// window in its empty state (`root == nil`, §6.1.6), and reports `.persistenceDisabled` or `.noFile`.
    /// Live objects of a previous session are released.
    public func restoreOrOpenDefault() -> RestoreReport {
        for record in session.contents { store.release(record.id) }
        session = Session()
        runtime = WorkspaceRuntime()
        do {
            try commit(.openMainWindow(WindowID(raw: ids.next()), placement: .defaultMainWindow))
        } catch {
            preconditionFailure("openMainWindow failed on an empty session: \(error)")
        }
        switch configuration.persistence {
        case .disabled: return RestoreReport(source: .persistenceDisabled)
        case .file, .custom: return RestoreReport(source: .noFile)
        }
    }

    public func perform(_ command: SplitKitCommand) async throws(LayoutError) {
        switch command {
        case let .split(pane, edge):
            try commit(.insert(nil, at: pane, edge: edge, in: window(containing: pane)))
        case let .move(content, pane, edge):
            try commit(.move(content, to: pane, edge: edge, in: window(containing: pane)))
        case let .reorder(split, from, to):
            try commit(.reorder(splitID: split, from: from, to: to))
        case let .resize(split, fractions):
            try commit(.resize(splitID: split, fractions: fractions))
        case let .setActive(pane, window):
            try commit(.setActive(pane, in: window))
        case let .setFocusMode(pane, window):
            try commit(.setFocusMode(pane, in: window))
        case let .toggleFocusMode(pane):
            guard configuration.focusModeEnabled else { return }
            let window = try window(containing: pane)
            let current = windowLayout(window)?.focusModePane
            try commit(.setFocusMode(current == pane ? nil : pane, in: window))
        case let .closePane(pane):
            try await closePane(pane)
        case let .closeWindow(window):
            try await closeWindow(window)
        }
    }

    /// Adds a new `type` content into the empty pane `into`, or into the empty main window when `into` is nil
    /// (§6.2 centre insert / insert into empty window). The transaction is computed first; only on success
    /// is the object created (§6.5). If creation throws, nothing changes.
    ///
    /// §5 gives this method only `RegistryError`, but the insert can fail with a `LayoutError` (occupied
    /// pane, pending close, no empty main window). Until Marc decides (deviation candidate), such a
    /// failure is thrown as `.creationFailed(type, .other("layout: …"))`, with nothing changed.
    public func addContent(_ type: ContentType, url: URL?, into pane: PaneID?) async throws(RegistryError) {
        guard let metadata = registry.metadata(for: type) else { throw .unknownType(type) }
        let content = NewContent(id: ContentID(raw: ids.next()), type: type, stateVersion: metadata.stateVersion)
        let transaction: LayoutTransaction
        if let pane {
            do {
                transaction = .insert(content, at: pane, edge: .center, in: try window(containing: pane))
            } catch {
                throw .creationFailed(type, .other("layout: \(error)"))
            }
        } else if let main = mainWindow {
            transaction = .insertIntoEmptyWindow(content, in: main)
        } else {
            throw .creationFailed(type, .other("layout: no main window"))
        }
        let result: TransactionResult
        do {
            result = try apply(transaction)
        } catch {
            throw .creationFailed(type, .other("layout: \(error)"))
        }
        let object = try registry.make(type, id: content.id, url: url, state: nil, stateVersion: nil)
        store.insert(object, for: content.id)
        commit(result)
    }

    // MARK: Lookups

    func windowLayout(_ id: WindowID) -> WindowLayout? {
        session.windows.first { $0.id == id }
    }

    var mainWindow: WindowID? {
        session.windows.first { $0.kind == .main }?.id
    }

    func window(containing pane: PaneID) throws(LayoutError) -> WindowID {
        guard let window = session.windows.first(where: { $0.root?.leaves.contains { $0.pane == pane } ?? false }) else {
            throw .unknownPane(pane)
        }
        return window.id
    }

    func record(_ id: ContentID) -> ContentRecord? {
        session.contents.first { $0.id == id }
    }

    /// The registry metadata of a content's type; nil if the type isn't registered.
    func metadata(of content: ContentID) -> ContentRegistry.Metadata? {
        record(content).flatMap { registry.metadata(for: $0.type) }
    }

    // MARK: Transactions

    /// Pure: the result of `transaction` on the current state; nothing is committed.
    func apply(_ transaction: LayoutTransaction) throws(LayoutError) -> TransactionResult {
        try SessionEngine.apply(transaction, to: session, runtime: runtime, ids: &ids)
    }

    /// Applies and commits `transaction`; on throw, session, runtime and contents are unchanged.
    @discardableResult
    func commit(_ transaction: LayoutTransaction) throws(LayoutError) -> TransactionResult {
        let result = try apply(transaction)
        commit(result)
        return result
    }

    /// Commits a successful result, then runs its side effects: the views re-host from the new session,
    /// then released contents get `willRelease()` and are dropped (§6.2, §6.3.2).
    private func commit(_ result: TransactionResult) {
        session = result.session
        runtime = result.runtime
        for id in result.released { store.release(id) }
    }

    // MARK: Two-stage close (§6.3)

    /// `beginClose`, then the content's `shouldClose()`; accepted → `commitClose` (release), declined →
    /// `cancelClose`. Empty panes and unavailable placeholders (no object) commit without asking; the
    /// placeholder's own confirmation is part of the close UI task.
    private func closePane(_ pane: PaneID) async throws(LayoutError) {
        let window = try window(containing: pane)
        let content = windowLayout(window)?.root?.leaves.first { $0.pane == pane }?.content
        try commit(.beginClose(pane))
        var accepted = true
        if let content, let object = store[content] {
            accepted = await object.shouldClose()
        }
        try commit(accepted ? .commitClose(pane) : .cancelClose(pane))
    }

    /// `beginCloseWindow`, then every hosted content in tree order; the first decline cancels and nothing
    /// is closed. The combined "Close window with N panes?" prompt is part of the close UI task.
    private func closeWindow(_ window: WindowID) async throws(LayoutError) {
        try commit(.beginCloseWindow(window))
        for leaf in windowLayout(window)?.root?.leaves ?? [] {
            guard let content = leaf.content, let object = store[content] else { continue }
            let accepted = await object.shouldClose()
            if !accepted {
                try commit(.cancelCloseWindow(window))
                return
            }
        }
        try commit(.commitCloseWindow(window))
    }
}
