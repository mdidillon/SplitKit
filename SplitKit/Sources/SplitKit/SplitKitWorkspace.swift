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
    /// The confirmation the close UI shows now (the first of the queue); runtime-only, never persisted.
    private(set) var closePrompt: ClosePrompt?
    @ObservationIgnored private var closePrompts: [(prompt: ClosePrompt, answer: CheckedContinuation<Bool, Never>)] = []
    @ObservationIgnored private var closePromptCount = 0
    /// The window whose Add Content… type list (⇧⌘N) is open; runtime-only, never persisted.
    private(set) var addContentRequest: WindowID?

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
        addContentRequest = nil
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

    /// Adds a new `type` content in a new pane next to `pane`: `split` (an empty pane at `edge`), then
    /// `addContent` into it. Composition of the two existing commands; if the add fails the empty pane stays.
    func addContent(_ type: ContentType, besides pane: PaneID, edge: DropEdge) async throws(RegistryError) {
        let before = Set(allLeaves.map(\.pane))
        do {
            try await perform(.split(pane, edge: edge))
        } catch {
            throw .creationFailed(type, .other("layout: \(error)"))
        }
        guard let new = allLeaves.first(where: { !before.contains($0.pane) })?.pane else {
            throw .creationFailed(type, .other("layout: no new pane"))
        }
        try await addContent(type, url: nil, into: new)
    }

    // MARK: Add Content… and focus mode (§7.3, §7.5)

    /// Where Add Content goes in `window`: its active pane, or the empty window.
    func addContentTarget(in window: WindowID) -> ContentPicker.Target {
        guard let layout = windowLayout(window) else { return .none }
        guard let root = layout.root else { return layout.kind == .main ? .emptyWindow : .none }
        guard let leaf = root.leaves.first(where: { $0.pane == layout.activePane }) else { return .none }
        return .adding(to: leaf.pane, hosting: leaf.content)
    }

    /// Opens the type list of `window` (File ▸ Add Content…).
    func requestAddContent(in window: WindowID) {
        addContentRequest = window
    }

    /// Closes the type list of `window` without adding anything.
    func cancelAddContent(in window: WindowID) {
        if addContentRequest == window { addContentRequest = nil }
    }

    /// Chooses `type` in the open type list of `window`: closes the list, then adds at the target the
    /// window has now. The one path for the popover's rows, its Return key and the tests.
    func chooseRequestedContent(_ type: ContentType, in window: WindowID) async {
        cancelAddContent(in: window)
        await contentPicker(for: addContentTarget(in: window)).choose(type, in: self)
    }

    /// What Esc does in `window`: leave focus mode. Nil when the window isn't in focus mode, so SplitKit
    /// doesn't take Esc from anything else.
    func exitFocusModeAction(in window: WindowID) -> (@MainActor () -> Void)? {
        guard windowLayout(window)?.focusModePane != nil else { return nil }
        return { [self] in send(.setFocusMode(nil, in: window)) }
    }

    /// The pane that hosts `content` and its window.
    func host(of content: ContentID) -> (pane: PaneID, window: WindowID)? {
        for window in session.windows {
            if let leaf = window.root?.leaves.first(where: { $0.content == content }) { return (leaf.pane, window.id) }
        }
        return nil
    }

    // MARK: Lookups

    private var allLeaves: [(pane: PaneID, content: ContentID?)] {
        session.windows.flatMap { $0.root?.leaves ?? [] }
    }

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

    /// The display name of a content's type, or its raw type name when the type isn't registered.
    func typeName(of content: ContentID) -> String? {
        metadata(of: content)?.displayName ?? record(content)?.type.raw
    }

    /// A close of `pane`, or of the window it is in, is waiting for an answer (§6.3).
    func isClosing(pane: PaneID) -> Bool {
        runtime.pendingCloses.contains(pane) || (try? window(containing: pane)).map(isClosing(window:)) == true
    }

    func isClosing(window: WindowID) -> Bool {
        runtime.pendingWindowCloses.contains(window)
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
    /// `cancelClose`. Empty panes commit without asking. An unavailable placeholder has no object: SplitKit's
    /// own confirmation replaces `shouldClose()`, and nothing is released (§6.3.2).
    private func closePane(_ pane: PaneID) async throws(LayoutError) {
        let window = try window(containing: pane)
        let content = windowLayout(window)?.root?.leaves.first { $0.pane == pane }?.content
        try commit(.beginClose(pane))
        var accepted = true
        if let content {
            if let object = store[content] {
                accepted = await object.shouldClose()
            } else {
                accepted = await confirm(.placeholder(typeName: typeName(of: content) ?? ""), in: window)
            }
        }
        try commit(accepted ? .commitClose(pane) : .cancelClose(pane))
    }

    /// `beginCloseWindow`, then the one window prompt when it applies (`closePromptKind(forWindow:)`), then
    /// every hosted content in tree order; the first decline, or Cancel, cancels and nothing is closed.
    private func closeWindow(_ window: WindowID) async throws(LayoutError) {
        try commit(.beginCloseWindow(window))
        if let kind = closePromptKind(forWindow: window), !(await confirm(kind, in: window)) {
            try commit(.cancelCloseWindow(window))
            return
        }
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

    // MARK: Close confirmations (§7.5, §8)

    /// Shows a prompt of `kind` on `window` and returns the user's answer. Prompts are queued, one at a time.
    private func confirm(_ kind: ClosePrompt.Kind, in window: WindowID) async -> Bool {
        closePromptCount += 1
        let prompt = ClosePrompt(id: closePromptCount, window: window, kind: kind)
        return await withCheckedContinuation { continuation in
            closePrompts.append((prompt, continuation))
            closePrompt = closePrompts.first?.prompt
        }
    }

    /// Answers `prompt` (the one being shown; anything else is ignored) and shows the next one, if any.
    func answer(_ prompt: ClosePrompt, confirmed: Bool) {
        guard let first = closePrompts.first, first.prompt == prompt else { return }
        closePrompts.removeFirst()
        closePrompt = closePrompts.first?.prompt
        first.answer.resume(returning: confirmed)
    }
}
