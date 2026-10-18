import Foundation
import Observation
import SplitKitContent
import SplitKitModel
import SplitKitWindows

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
    @ObservationIgnored var ids: any IDGenerator
    /// The confirmation the close UI shows now (the first of the queue); runtime-only, never persisted.
    private(set) var closePrompt: ClosePrompt?
    @ObservationIgnored private var closePrompts: [(prompt: ClosePrompt, answer: CheckedContinuation<ClosePrompt.Answer, Never>)] = []
    @ObservationIgnored private var closePromptCount = 0
    /// The window whose content picker (Add Content…, ⇧⌘N, or Replace Content…) is open; runtime-only, never persisted.
    private(set) var addContentRequest: WindowID?
    /// The pane the open picker replaces the content of; nil when it adds (§6.3.6). Set only with `addContentRequest`.
    private(set) var replaceContentRequest: PaneID?
    /// The displays a detached window is placed on (§9); tests inject their own.
    @ObservationIgnored var displays: @MainActor () -> [DisplaySnapshot] = DetachPlacement.currentDisplays

    /// The newest failed save, or nil after a successful one; a failed save is retried at the next snapshot
    /// point (§8).
    public private(set) var lastSaveError: PersistenceError?
    /// Why each placeholder is one; the pane shows it. Runtime-only.
    private(set) var unavailableReasons: [ContentID: RestoreReport.Unavailable.Reason] = [:]
    /// The `encodeState()` errors of the newest snapshot, per content; the content keeps its last good state.
    private(set) var stateEncodingErrors: [ContentID: String] = [:]
    /// The newest successfully captured state per live content (§6.5): what a snapshot falls back to when
    /// `encodeState()` throws. Not observed: a snapshot must not re-render the views.
    @ObservationIgnored private var capturedStates: [ContentID: (stateVersion: Int, state: Data)] = [:]
    @ObservationIgnored private var writer: SessionWriter?
    /// Set when the file must not be overwritten (future version, unreadable store): no snapshot is written.
    @ObservationIgnored private var writeBlock: PersistenceError?
    @ObservationIgnored private var autosaveTask: Task<Void, Never>?
    @ObservationIgnored private let clock: any Clock<Duration>
    @ObservationIgnored private let encode: SessionWriter.Encode
    /// The window layer: `CoordinatedWindows` (in `.host` mode it opens detached windows only, the host owns
    /// its main windows, §9). Tests that use the internal initialiser show no windows unless they set one.
    @ObservationIgnored var windowHost: (any WorkspaceWindowHost)?
    /// The coordinator window that is key; runtime-only. The menu bar acts in it when no `SplitKitView`
    /// publishes its window as the focused scene value.
    private(set) var keyWindow: WindowID?

    public convenience init(registry: ContentRegistry, configuration: SplitKitConfiguration) throws(PersistenceError) {
        if case let .file(url) = configuration.persistence, !url.isFileURL {
            throw .unreadable(underlying: "persistence file \(url) is not a file URL")
        }
        self.init(registry: registry, configuration: configuration, ids: SystemIDGenerator())
        windowHost = CoordinatedWindows(workspace: self)
    }

    /// Tests inject a `SeededIDGenerator`, a clock for the autosave debounce and a failing encoder.
    init(registry: ContentRegistry, configuration: SplitKitConfiguration, ids: some IDGenerator,
         clock: any Clock<Duration> = ContinuousClock(),
         encode: @escaping SessionWriter.Encode = { try Migrator.encode($0) }) {
        self.registry = registry
        self.configuration = configuration
        self.ids = ids
        self.clock = clock
        self.encode = encode
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
        case .newWindow:
            if let main = mainWindow {
                windowHost?.bringForward(main)
            } else {
                try commit(.openMainWindow(WindowID(raw: ids.next()), placement: .defaultMainWindow))
            }
        case let .detach(pane):
            try detach(pane)
        case let .moveToWindow(pane, window):
            try moveToWindow(pane, window)
        case let .dockBack(window):
            try dockBack(window)
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

    /// Replaces the content of `pane` with a new `type` content (*Pane ▸ Replace Content…*, §6.3.6). The new
    /// object is created first (`make(…, url:)` validates the file; a failure throws and changes nothing). Then
    /// the two-stage close runs as for *Close Pane*: `beginClose`, the old content's `shouldClose()` (or SplitKit's
    /// own confirmation for a placeholder). Declined → `cancelClose`, the new object is dropped without
    /// `willRelease()` and false is returned. Accepted → `commitReplace`: `pane` keeps its ID, position and
    /// fraction, the old content is released, one snapshot, true.
    ///
    /// As for `addContent`, a `LayoutError` (unknown pane, empty pane, pending close) is thrown as
    /// `.creationFailed(type, .other("layout: …"))` with nothing changed (approved deviation 3).
    @discardableResult
    public func replaceContent(_ pane: PaneID, with type: ContentType, url: URL?) async throws(RegistryError) -> Bool {
        guard let metadata = registry.metadata(for: type) else { throw .unknownType(type) }
        let old: ContentID?
        do {
            let window = try window(containing: pane)
            old = windowLayout(window)?.root?.leaves.first { $0.pane == pane }?.content
            guard old != nil else { throw LayoutError.unknownContent(.emptyPane) }
        } catch {
            throw .creationFailed(type, .other("layout: \(error)"))
        }
        let content = NewContent(id: ContentID(raw: ids.next()), type: type, stateVersion: metadata.stateVersion)
        let object = try registry.make(type, id: content.id, url: url, state: nil, stateVersion: nil)
        let accepted: Bool
        do {
            accepted = try await askToClose(pane)
        } catch {
            throw .creationFailed(type, .other("layout: \(error)"))
        }
        guard accepted else {
            _ = try? commit(.cancelClose(pane))
            return false
        }
        do {
            let result = try apply(.commitReplace(pane, with: content))
            store.insert(object, for: content.id)
            commit(result)
        } catch {
            _ = try? commit(.cancelClose(pane))
            throw .creationFailed(type, .other("layout: \(error)"))
        }
        return true
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

    /// Where the picker of `window` acts: the pane being replaced while Replace Content… is open, else where
    /// Add Content goes: the active pane, or the empty window.
    func addContentTarget(in window: WindowID) -> ContentPicker.Target {
        guard let layout = windowLayout(window) else { return .none }
        if addContentRequest == window, let pane = replaceContentRequest { return .replacing(pane) }
        guard let root = layout.root else { return layout.kind == .main ? .emptyWindow : .none }
        guard let leaf = root.leaves.first(where: { $0.pane == layout.activePane }) else { return .none }
        return .adding(to: leaf.pane, hosting: leaf.content)
    }

    /// Opens the type list of `window` (File ▸ Add Content…).
    func requestAddContent(in window: WindowID) {
        addContentRequest = window
        replaceContentRequest = nil
    }

    /// Opens the same type list in replace mode for `pane` (Pane ▸ Replace Content…, §6.3.6).
    func requestReplaceContent(of pane: PaneID) {
        guard let window = try? window(containing: pane) else { return }
        addContentRequest = window
        replaceContentRequest = pane
    }

    /// Closes the type list of `window` without adding or replacing anything.
    func cancelAddContent(in window: WindowID) {
        guard addContentRequest == window else { return }
        addContentRequest = nil
        replaceContentRequest = nil
    }

    /// Chooses `type` in the open type list of `window`: closes the list, then adds at the target the
    /// window has now. The one path for the popover's rows, its Return key and the tests.
    func chooseRequestedContent(_ type: ContentType, in window: WindowID) async {
        let picker = contentPicker(for: addContentTarget(in: window))
        cancelAddContent(in: window)
        await picker.choose(type, in: self)
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
        commit(result, isSnapshotPoint: transaction.changesSession)
        return result
    }

    /// Commits a successful result, then runs its side effects in the §6.2 order: new windows open, the views
    /// re-host from the new session, released contents get `willRelease()` and are dropped (§6.3.2), closed
    /// windows close, then the snapshot: debounced, or at once when a window closed (§8).
    func commit(_ result: TransactionResult, isSnapshotPoint: Bool = true) {
        session = result.session
        runtime = result.runtime
        windowHost?.open(result.windowsCreated)
        for id in result.released {
            store.release(id)
            unavailableReasons[id] = nil
        }
        windowHost?.close(result.windowsClosed)
        guard isSnapshotPoint else { return }
        if result.windowsClosed.isEmpty { scheduleAutosave() } else { enqueueSnapshot() }
    }

    // MARK: Windows (§9)

    /// A user move or resize of a window SplitKit placed: its new placement, saved with the next snapshot.
    /// The coordinator's own placement and the system's re-placement never arrive here (no drift).
    func userPlaced(_ window: WindowID, _ placement: SavedPlacement) {
        guard let index = session.windows.firstIndex(where: { $0.id == window }),
              session.windows[index].placement != placement else { return }
        session.windows[index].placement = placement
        scheduleAutosave()
    }

    func keyWindowChanged(_ window: WindowID?) {
        keyWindow = window
    }

    // MARK: Two-stage close (§6.3)

    /// `beginClose`, then the content's `shouldClose()`; accepted → `commitClose` (release), declined →
    /// `cancelClose`. Empty panes commit without asking. An unavailable placeholder has no object: SplitKit's
    /// own confirmation replaces `shouldClose()`, and nothing is released (§6.3.2).
    private func closePane(_ pane: PaneID) async throws(LayoutError) {
        let accepted = try await askToClose(pane)
        try commit(accepted ? .commitClose(pane) : .cancelClose(pane))
    }

    /// Stage 1 of §6.3 for `pane`: `beginClose`, then the content's `shouldClose()` (SplitKit's own confirmation
    /// for a placeholder; empty panes accept). The pane stays pending: the caller commits or cancels. The one
    /// path of Close Pane and Replace Content….
    private func askToClose(_ pane: PaneID) async throws(LayoutError) -> Bool {
        let window = try window(containing: pane)
        let content = windowLayout(window)?.root?.leaves.first { $0.pane == pane }?.content
        try commit(.beginClose(pane))
        guard let content else { return true }
        if let object = store[content] { return await object.shouldClose() }
        return await confirm(.placeholder(typeName: typeName(of: content) ?? ""), in: window) == .confirm
    }

    /// `beginCloseWindow`, then the one window prompt when it applies (`closePromptKind(forWindow:)`), then
    /// every hosted content in tree order; the first decline, or Cancel, cancels and nothing is closed.
    /// *Dock Back Instead* cancels the close and docks the window back (§9).
    private func closeWindow(_ window: WindowID) async throws(LayoutError) {
        try commit(.beginCloseWindow(window))
        if let kind = closePromptKind(forWindow: window) {
            switch await confirm(kind, in: window) {
            case .confirm:
                break
            case .cancel:
                try commit(.cancelCloseWindow(window))
                return
            case .dockBack:
                try commit(.cancelCloseWindow(window))
                try dockBack(window)
                return
            }
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
    private func confirm(_ kind: ClosePrompt.Kind, in window: WindowID) async -> ClosePrompt.Answer {
        closePromptCount += 1
        let prompt = ClosePrompt(id: closePromptCount, window: window, kind: kind)
        return await withCheckedContinuation { continuation in
            closePrompts.append((prompt, continuation))
            closePrompt = closePrompts.first?.prompt
        }
    }

    /// Answers `prompt` (the one being shown; anything else is ignored) and shows the next one, if any.
    func answer(_ prompt: ClosePrompt, _ answer: ClosePrompt.Answer) {
        guard let first = closePrompts.first, first.prompt == prompt else { return }
        closePrompts.removeFirst()
        closePrompt = closePrompts.first?.prompt
        first.answer.resume(returning: answer)
    }

    /// `answer(_:_:)` with the confirm button (`confirmed`) or Cancel.
    func answer(_ prompt: ClosePrompt, confirmed: Bool) {
        answer(prompt, confirmed ? .confirm : .cancel)
    }
}

// MARK: Persistence (§8)

extension LayoutTransaction {
    /// False for the transactions that change only runtime state (stage 1 and cancel of a close, §6.3):
    /// a pending close is saved as open, so these are no snapshot points.
    var changesSession: Bool {
        switch self {
        case .beginClose, .cancelClose, .beginCloseWindow, .cancelCloseWindow: false
        default: true
        }
    }
}

extension SplitKitWorkspace {
    /// Restores the saved session, or opens the default layout (one `.main` window in its empty state,
    /// `root == nil`, §6.1.6) when persistence is disabled, there is no file, or the file can't be used.
    /// Live objects of a previous session are released.
    ///
    /// Reads a `.file` synchronously. A `.custom` store loads asynchronously (`SessionStore.load` is
    /// `async`), so here it opens the default layout and blocks writes; use `restoreOrOpenDefaultAsync()`
    /// (deviation candidate: §5 declares only this synchronous form).
    public func restoreOrOpenDefault() -> RestoreReport {
        switch configuration.persistence {
        case .disabled:
            resetForRestore()
            openDefaultLayout()
            return RestoreReport(source: .persistenceDisabled)
        case let .file(url):
            let store = FileSessionStore(url: url)
            return restore(Result { try store.loadSynchronously() }, from: store)
        case .custom:
            resetForRestore()
            openDefaultLayout()
            let error = PersistenceError.unreadable(underlying: "a custom SessionStore loads asynchronously: call restoreOrOpenDefaultAsync()")
            writeBlock = error
            return RestoreReport(source: .defaultAfterError(error))
        }
    }

    /// `restoreOrOpenDefault()` for every `persistence` mode, awaiting `SessionStore.load()`.
    public func restoreOrOpenDefaultAsync() async -> RestoreReport {
        switch configuration.persistence {
        case .disabled, .file: return restoreOrOpenDefault()
        case let .custom(store):
            let loaded: Result<Data?, any Error>
            do { loaded = .success(try await store.load()) } catch { loaded = .failure(error) }
            return restore(loaded, from: store)
        }
    }

    /// Restores the content of a placeholder: creates its object from the retained record (type, state version
    /// and state, verbatim) and marks the record `.hosted`. Throws `RegistryError.unknownType` while the type
    /// isn't registered, and `.creationFailed` when `init(restoring:)` throws again, which keeps the
    /// placeholder and the record (retry later). An unknown ID throws `.creationFailed` with an empty type.
    public func restoreUnavailable(_ id: ContentID) throws(RegistryError) {
        guard let index = session.contents.firstIndex(where: { $0.id == id }) else {
            throw .creationFailed(ContentType(raw: ""), .other("no content \(id)"))
        }
        guard store[id] == nil else { return }
        let record = session.contents[index]
        let object: any PaneContent
        do {
            object = try makeObject(for: record)
        } catch {
            if case .creationFailed = error { unavailableReasons[id] = .restoreFailed(String(describing: error)) }
            throw error
        }
        store.insert(object, for: id)
        capture(record)
        session.contents[index].availability = .hosted
        unavailableReasons[id] = nil
        scheduleAutosave()
    }

    /// Writes a snapshot now and returns when it is written (§5). Throws what the write failed with, or the
    /// reason the file must not be overwritten (e.g. `unsupportedFutureVersion`). Does nothing for `.disabled`.
    public func saveNow() async throws(PersistenceError) {
        if let writeBlock { throw writeBlock }
        guard let writer else { return }
        enqueueSnapshot()
        await writer.idle()
        if let lastSaveError { throw lastSaveError }
    }

    /// For `applicationShouldTerminate` and a closing window: `saveNow()`, but returns after `timeout` (§8: 2 s)
    /// even if the store hasn't finished. Errors stay in `lastSaveError`.
    public func saveBeforeQuit(timeout: Duration = .seconds(2)) async {
        let (finished, signal) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let save = Task { try? await saveNow(); signal.yield() }
        let timer = Task { [clock] in try? await clock.sleep(for: timeout); signal.yield() }
        for await _ in finished { break }
        timer.cancel()
        _ = save
    }

    /// Returns when no autosave is waiting and no write is in flight. For tests.
    func settleAutosave() async {
        while let task = autosaveTask { await task.value }
        await writer?.idle()
    }

    // MARK: Restore pipeline

    private func resetForRestore() {
        windowHost?.close(session.windows.map(\.id))
        keyWindow = nil
        autosaveTask?.cancel()
        autosaveTask = nil
        writer = nil
        writeBlock = nil
        lastSaveError = nil
        for record in session.contents { store.release(record.id) }
        session = Session()
        runtime = WorkspaceRuntime()
        addContentRequest = nil
        replaceContentRequest = nil
        unavailableReasons = [:]
        stateEncodingErrors = [:]
        capturedStates = [:]
    }

    private func openDefaultLayout() {
        do {
            try commit(.openMainWindow(WindowID(raw: ids.next()), placement: .defaultMainWindow))
        } catch {
            preconditionFailure("openMainWindow failed on an empty session: \(error)")
        }
    }

    /// Both layers of §8 validation, then the live objects; a fatal file opens the default layout.
    private func restore(_ loaded: Result<Data?, any Error>, from store: any SessionStore) -> RestoreReport {
        resetForRestore()
        var report: RestoreReport
        var needsSnapshot = false
        switch loaded {
        case let .failure(error):
            // Whatever is there couldn't be read: never write over it.
            let failure = PersistenceError.unreadable(underlying: "load failed: \(error)")
            openDefaultLayout()
            writeBlock = failure
            report = RestoreReport(source: .defaultAfterError(failure))
        case .success(nil):
            openDefaultLayout()
            report = RestoreReport(source: .noFile)
        case let .success(data?):
            do {
                let decoded = try Migrator.decode(data)
                (report, needsSnapshot) = adopt(decoded.0, normalizations: decoded.1)
            } catch {
                openDefaultLayout()
                report = RestoreReport(source: .defaultAfterError(error))
                if case .unsupportedFutureVersion = error {
                    writeBlock = error               // a newer app's file is never overwritten
                } else if let kept = try? (store as? FileSessionStore)?.keepInvalid(data) {
                    report.keptInvalidFile = kept
                    needsSnapshot = true             // the default layout replaces the unusable file
                } else {
                    writeBlock = error               // no copy was kept: leave the original alone
                }
            }
        }
        writer = SessionWriter(store: store, encode: encode) { [weak self] in self?.lastSaveError = $0 }
        if needsSnapshot { scheduleAutosave() }
        return report
    }

    /// The SplitKit layer of validation (§8): marks `.hosted` records of unregistered types `.unavailable`,
    /// restores `.unavailable` records of registered types, and creates the live objects. Returns whether
    /// anything changed that a snapshot has to save (§6.5).
    private func adopt(_ decoded: Session, normalizations: [Normalization]) -> (RestoreReport, needsSnapshot: Bool) {
        var restored = decoded
        var report = RestoreReport(source: .restoredFile, normalizations: normalizations)
        var needsSnapshot = !normalizations.isEmpty
        for index in restored.contents.indices {
            let record = restored.contents[index]
            let wasUnavailable = record.availability == .unavailable
            func keepUnavailable(_ reason: RestoreReport.Unavailable.Reason) {
                if !wasUnavailable { needsSnapshot = true }
                restored.contents[index].availability = .unavailable
                unavailableReasons[record.id] = reason
                report.unavailable.append(.init(id: record.id, type: record.type, reason: reason))
            }
            guard registry.metadata(for: record.type) != nil else {
                keepUnavailable(.typeNotRegistered)
                continue
            }
            do {
                store.insert(try makeObject(for: record), for: record.id)
            } catch {
                keepUnavailable(.restoreFailed(String(describing: error)))
                continue
            }
            capture(record)
            if wasUnavailable {
                restored.contents[index].availability = .hosted
                report.autoRestored.append(record.id)
                needsSnapshot = true
            }
        }
        session = restored
        windowHost?.open(restored.windows.map(\.id))
        return (report, needsSnapshot)
    }

    /// The object of `record`, restored from its state; an empty state is "not captured yet" (§6.5).
    private func makeObject(for record: ContentRecord) throws(RegistryError) -> any PaneContent {
        let hasState = !record.state.isEmpty
        return try registry.make(record.type, id: record.id, url: nil,
                                 state: hasState ? record.state : nil, stateVersion: hasState ? record.stateVersion : nil)
    }

    /// Seeds the last good state of a restored content with the record's own.
    private func capture(_ record: ContentRecord) {
        if !record.state.isEmpty { capturedStates[record.id] = (record.stateVersion, record.state) }
    }

    // MARK: Snapshots

    /// A consistent snapshot (§8): the session and every live content's `encodeState()` in one pass on the main
    /// actor. `.hosted` records get the new `state` and `stateVersion`; a content whose `encodeState()` throws
    /// keeps its last good state and the error lands in `stateEncodingErrors`; `.unavailable` records and
    /// records without an object are written back verbatim (§6.5). Pending closes are runtime-only, so they
    /// are saved as open.
    func snapshot() -> Session {
        var snapshot = session
        stateEncodingErrors = [:]
        for index in snapshot.contents.indices {
            let record = snapshot.contents[index]
            guard record.availability == .hosted, let object = store[record.id] else { continue }
            do {
                capturedStates[record.id] = (type(of: object).stateVersion, try object.encodeState())
            } catch {
                stateEncodingErrors[record.id] = String(describing: error)
            }
            if let captured = capturedStates[record.id] {
                snapshot.contents[index].stateVersion = captured.stateVersion
                snapshot.contents[index].state = captured.state
            }
        }
        let live = Set(snapshot.contents.map(\.id))
        capturedStates = capturedStates.filter { live.contains($0.key) }
        return snapshot
    }

    /// A snapshot point (§8): the snapshot is taken and written `autosaveDebounce` after the newest one.
    func scheduleAutosave() {
        guard writer != nil, writeBlock == nil else { return }
        autosaveTask?.cancel()
        let delay = configuration.autosaveDebounce
        autosaveTask = Task { [weak self, clock] in
            do { try await clock.sleep(for: delay) } catch { return }
            guard !Task.isCancelled, let self else { return }
            autosaveTask = nil
            enqueueSnapshot()
        }
    }

    /// Takes a snapshot and queues it for writing now, replacing a waiting autosave. Pending window
    /// placements are handed over first, so the snapshot has them.
    private func enqueueSnapshot() {
        guard let writer, writeBlock == nil else { return }
        windowHost?.flushPendingPlacements()
        autosaveTask?.cancel()
        autosaveTask = nil
        writer.enqueue(snapshot())
    }
}
