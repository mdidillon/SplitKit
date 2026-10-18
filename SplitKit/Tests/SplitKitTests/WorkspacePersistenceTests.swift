import Foundation
import os
import Testing
import SplitKitContent
import SplitKitModel
@testable import SplitKit

/// §8 restore pipeline, registry marking, Restore, autosave and snapshot rules on a `SplitKitWorkspace`.

private func decodeSession(_ data: Data?) throws -> Session {
    try Migrator.decode(#require(data)).0
}

private func fileNames(in directory: URL) throws -> [String] {
    try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()
}

private let unknownType = "vendor.unknown"

@MainActor
@Suite struct RestorePipelineTests {
    @Test func relaunchRestoresTheSessionAndTheContentState() async throws {
        try await withTemporaryDirectory { directory in
            let file = directory.appending(path: "SplitKit/session.json")
            let first = try makePersistentWorkspace(.file(file))
            _ = first.restoreOrOpenDefault()
            try await first.addContent(CounterContent.type, url: nil, into: nil)
            let a = try #require(first.session.contents.first?.id)
            try #require(first.store[a] as? CounterContent).count = 7
            try await first.addContent(CounterContent.type, besides: first.mainLeaves[0].pane, edge: .right)
            let b = try #require(first.session.contents.last?.id)
            try #require(first.store[b] as? CounterContent).count = 9
            try await first.perform(.setActive(first.mainLeaves[1].pane, in: first.mainLayout.id))
            try await first.saveNow()

            let second = try makePersistentWorkspace(.file(file), seed: 0xBEEF)
            let report = second.restoreOrOpenDefault()
            #expect(report == RestoreReport(source: .restoredFile))
            #expect(second.session.windows == first.session.windows)
            #expect(second.session.contents.map(\.id) == [a, b])
            let restoredA = try #require(second.store[a] as? CounterContent)
            #expect(restoredA.count == 7)
            #expect(restoredA.restoredStateVersion == CounterContent.stateVersion)
            #expect(restoredA.receivedURL == nil, "restore passes no URL")
            #expect((second.store[b] as? CounterContent)?.count == 9)
            #expect(second.mainLayout.activePane == second.mainLeaves[1].pane)
        }
    }

    @Test func theInsertSnapshotFillsStateAndStateVersion() async throws {
        let store = MemoryStore()
        let workspace = try makePersistentWorkspace(.custom(store))
        _ = await workspace.restoreOrOpenDefaultAsync()
        try await workspace.addContent(CounterContent.type, url: nil, into: nil)
        #expect(workspace.session.contents.first?.state == Data())     // not captured yet (§6.5)
        await workspace.settleAutosave()
        let record = try #require(decodeSession(store.data).contents.first)
        #expect(record.state == CounterContent.state(0))
        #expect(record.stateVersion == CounterContent.stateVersion)
        #expect(record.availability == .hosted)
    }

    @Test func aMissingFileOpensTheDefaultLayoutAndDisabledTouchesNothing() async throws {
        try await withTemporaryDirectory { directory in
            let workspace = try makePersistentWorkspace(.disabled)
            #expect(workspace.restoreOrOpenDefault() == RestoreReport(source: .persistenceDisabled))
            try await workspace.addContent(CounterContent.type, url: nil, into: nil)
            try await workspace.saveNow()
            await workspace.settleAutosave()
            #expect(workspace.lastSaveError == nil)
            #expect(try fileNames(in: directory).isEmpty)

            let file = directory.appending(path: "SplitKit/session.json")
            let enabled = try makePersistentWorkspace(.file(file))
            #expect(enabled.restoreOrOpenDefault() == RestoreReport(source: .noFile))
            #expect(!FileManager.default.fileExists(atPath: file.deletingLastPathComponent().path))   // restoring writes nothing
        }
    }

    // MARK: Fatal and unusable files

    @Test func aCorruptFileIsKeptAndTheDefaultLayoutReplacesIt() async throws {
        try await withTemporaryDirectory { directory in
            let file = directory.appending(path: "session.json")
            let garbage = Data("not json {".utf8)
            try garbage.write(to: file)
            let workspace = try makePersistentWorkspace(.file(file))
            let report = workspace.restoreOrOpenDefault()
            guard case .defaultAfterError(.unreadable) = report.source else { Issue.record("\(report.source)"); return }
            let kept = try #require(report.keptInvalidFile)
            #expect(kept.deletingLastPathComponent().standardizedFileURL == directory.standardizedFileURL)
            #expect(kept.lastPathComponent.wholeMatch(of: /session\.invalid-\d{8}T\d{6}Z\.json/) != nil)
            #expect(try Data(contentsOf: kept) == garbage)
            #expect(workspace.mainLeaves.isEmpty && workspace.mainWindow != nil)

            await workspace.settleAutosave()
            #expect(try decodeSession(Data(contentsOf: file)).windows.count == 1)
            #expect(try fileNames(in: directory).count == 2)
        }
    }

    @Test func aFatalInvalidFileIsKeptWithItsTimestampName() async throws {
        try await withTemporaryDirectory { directory in
            let file = directory.appending(path: "session.json")
            var (session, _, content) = try sessionFile(type: CounterContent.type.raw, availability: .hosted)
            session.contents = []                                             // the pane hosts a content with no record
            let bytes = try Migrator.encode(session)
            try bytes.write(to: file)
            let report = try makePersistentWorkspace(.file(file)).restoreOrOpenDefault()
            #expect(report.source == .defaultAfterError(.invalid([.missingContentRecord(content)])))
            #expect(try Data(contentsOf: #require(report.keptInvalidFile)) == bytes)
            #expect(try Data(contentsOf: file) == bytes)                     // until the default layout is saved
        }
    }

    @Test func aFutureVersionIsNeverOverwritten() async throws {
        try await withTemporaryDirectory { directory in
            let file = directory.appending(path: "session.json")
            let future = Data(#"{"version": 99, "windows": [], "contents": []}"#.utf8)
            try future.write(to: file)
            let workspace = try makePersistentWorkspace(.file(file))
            let report = workspace.restoreOrOpenDefault()
            #expect(report == RestoreReport(source: .defaultAfterError(.unsupportedFutureVersion(99))))
            #expect(workspace.mainWindow != nil)

            try await workspace.addContent(CounterContent.type, url: nil, into: nil)
            await workspace.settleAutosave()
            await #expect(throws: PersistenceError.unsupportedFutureVersion(99)) { try await workspace.saveNow() }
            await workspace.saveBeforeQuit()
            #expect(try Data(contentsOf: file) == future)
            #expect(try fileNames(in: directory) == ["session.json"])
        }
    }

    @Test func aStoreThatCannotBeReadIsNeverWrittenOver() async throws {
        let store = MemoryStore()
        store.failLoad()
        let workspace = try makePersistentWorkspace(.custom(store))
        let report = await workspace.restoreOrOpenDefaultAsync()
        guard case .defaultAfterError(.unreadable) = report.source else { Issue.record("\(report.source)"); return }
        try await workspace.addContent(CounterContent.type, url: nil, into: nil)
        await workspace.settleAutosave()
        await #expect(throws: PersistenceError.self) { try await workspace.saveNow() }
        #expect(store.started == 0)
    }

    @Test func aCustomStoreRestoresAsynchronouslyAndTheSynchronousFormBlocksWrites() async throws {
        let (_, bytes, content) = try sessionFile(type: CounterContent.type.raw, state: CounterContent.state(5), availability: .hosted)
        let store = MemoryStore(data: bytes)
        let workspace = try makePersistentWorkspace(.custom(store))
        #expect(await workspace.restoreOrOpenDefaultAsync().source == .restoredFile)
        #expect((workspace.store[content] as? CounterContent)?.count == 5)

        let blocked = try makePersistentWorkspace(.custom(store))
        guard case .defaultAfterError(.unreadable) = blocked.restoreOrOpenDefault().source else { Issue.record("sync custom restore"); return }
        await #expect(throws: PersistenceError.self) { try await blocked.saveNow() }
        #expect(store.started == 0)
    }

    @Test func aFileURLThatIsNoFileURLThrowsFromInit() throws {
        let configuration = SplitKitConfiguration(persistence: .file(URL(string: "https://example.com/session.json")!))
        #expect(throws: PersistenceError.self) { try SplitKitWorkspace(registry: ContentRegistry(), configuration: configuration) }
    }

    // MARK: Unavailable content

    @Test func anUnregisteredTypeBecomesAPlaceholderSavedBackByteIdentically() async throws {
        try await withTemporaryDirectory { directory in
            let file = directory.appending(path: "session.json")
            let (_, bytes, content) = try sessionFile(type: unknownType)
            try bytes.write(to: file)
            let workspace = try makePersistentWorkspace(.file(file))
            let report = workspace.restoreOrOpenDefault()
            #expect(report.source == .restoredFile)
            #expect(report.unavailable == [.init(id: content, type: ContentType(raw: unknownType), reason: .typeNotRegistered)])
            #expect(report.autoRestored.isEmpty)
            #expect(workspace.store[content] == nil)
            #expect(workspace.mainLeaves.first?.content == content)

            try await workspace.saveNow()
            #expect(try Data(contentsOf: file) == bytes)
        }
    }

    @Test func aHostedRecordOfAnUnregisteredTypeIsMarkedUnavailableAndKeepsEverythingElse() async throws {
        try await withTemporaryDirectory { directory in
            let file = directory.appending(path: "session.json")
            let (original, bytes, _) = try sessionFile(type: unknownType, availability: .hosted)
            try bytes.write(to: file)
            let workspace = try makePersistentWorkspace(.file(file))
            _ = workspace.restoreOrOpenDefault()
            await workspace.settleAutosave()                                   // marking is followed by a snapshot (§6.5)
            var expected = original
            expected.contents[0].availability = .unavailable
            #expect(try decodeSession(Data(contentsOf: file)) == expected)
        }
    }

    @Test func aTypeRegisteredNowIsRestoredAutomatically() async throws {
        try await withTemporaryDirectory { directory in
            let file = directory.appending(path: "session.json")
            let (_, bytes, content) = try sessionFile(type: CounterContent.type.raw, state: CounterContent.state(4), stateVersion: 1)
            try bytes.write(to: file)
            let workspace = try makePersistentWorkspace(.file(file))
            let report = workspace.restoreOrOpenDefault()
            #expect(report.autoRestored == [content])
            #expect(report.unavailable.isEmpty)
            let object = try #require(workspace.store[content] as? CounterContent)
            #expect(object.count == 4)
            #expect(object.restoredStateVersion == 1)

            await workspace.settleAutosave()
            let record = try #require(decodeSession(Data(contentsOf: file)).contents.first)
            #expect(record.availability == .hosted)
            #expect(record.stateVersion == CounterContent.stateVersion)
        }
    }

    @Test func restoreUnavailableHostsTheRecordOnceTheTypeIsRegistered() async throws {
        try await withTemporaryDirectory { directory in
            let file = directory.appending(path: "session.json")
            let (_, bytes, content) = try sessionFile(type: CounterContent.type.raw, state: CounterContent.state(4), stateVersion: 1)
            try bytes.write(to: file)
            let registry = ContentRegistry()
            let workspace = SplitKitWorkspace(registry: registry, configuration: SplitKitConfiguration(persistence: .file(file), autosaveDebounce: .milliseconds(10)),
                                              ids: SeededIDGenerator(seed: 1))
            #expect(workspace.restoreOrOpenDefault().unavailable.count == 1)
            #expect(throws: RegistryError.self) { try workspace.restoreUnavailable(content) }
            #expect(workspace.store[content] == nil)

            try registry.register(CounterContent.self)
            try workspace.restoreUnavailable(content)
            #expect((workspace.store[content] as? CounterContent)?.count == 4)
            #expect(workspace.unavailableReasons[content] == nil)
            await workspace.settleAutosave()
            let record = try #require(decodeSession(Data(contentsOf: file)).contents.first)
            #expect(record.availability == .hosted)
            #expect(record.state == CounterContent.state(4))
        }
    }

    @Test func aContentWhoseRestoreThrowsBecomesAPlaceholderWithARetry() async throws {
        try await withTemporaryDirectory { directory in
            let file = directory.appending(path: "session.json")
            let (_, bytes, content) = try sessionFile(type: FlakyRestoreContent.type.raw, state: Data([9]), stateVersion: 1, availability: .hosted)
            try bytes.write(to: file)
            FlakyRestoreContent.failing = true
            defer { FlakyRestoreContent.failing = false }
            let workspace = try makePersistentWorkspace(.file(file), types: [FlakyRestoreContent.self])
            let report = workspace.restoreOrOpenDefault()
            let entry = try #require(report.unavailable.first)
            guard case .restoreFailed = entry.reason else { Issue.record("\(entry.reason)"); return }
            #expect(report.autoRestored.isEmpty)
            #expect(workspace.store[content] == nil)

            await workspace.settleAutosave()
            let kept = try #require(decodeSession(Data(contentsOf: file)).contents.first)
            #expect((kept.type, kept.stateVersion, kept.state) == (FlakyRestoreContent.type, 1, Data([9])))
            #expect(kept.availability == .unavailable)

            #expect(throws: RegistryError.self) { try workspace.restoreUnavailable(content) }
            guard case .restoreFailed = workspace.unavailableReasons[content] else { Issue.record("reason after a failed retry"); return }

            FlakyRestoreContent.failing = false
            try workspace.restoreUnavailable(content)
            #expect(workspace.store[content] != nil)
            #expect(workspace.unavailableReasons[content] == nil)
        }
    }
}

@MainActor
@Suite struct AutosaveTests {
    private func emptyPane(_ workspace: SplitKitWorkspace) throws {
        if let pane = workspace.mainLeaves.last?.pane {
            try workspace.commit(.insert(nil, at: pane, edge: .right, in: workspace.mainLayout.id))
        } else {
            try workspace.commit(.insertIntoEmptyWindow(nil, in: workspace.mainLayout.id))
        }
    }

    @Test func snapshotPointsWithinTheDebounceAreOneWrite() async throws {
        let store = MemoryStore()
        let workspace = try makePersistentWorkspace(.custom(store), debounce: .milliseconds(100))
        _ = await workspace.restoreOrOpenDefaultAsync()
        for _ in 0..<4 { try emptyPane(workspace) }                            // no suspension point in between
        #expect(store.started == 0)                                            // nothing is written before the debounce
        await workspace.settleAutosave()
        #expect(store.started == 1)
        #expect(try decodeSession(store.data).windows[0].root?.leaves.count == 4)
    }

    @Test func oneWriteIsInFlightAndANewerSnapshotReplacesTheQueuedOne() async throws {
        let store = MemoryStore()
        store.block()
        let workspace = try makePersistentWorkspace(.custom(store), debounce: .milliseconds(5))
        _ = await workspace.restoreOrOpenDefaultAsync()
        try emptyPane(workspace)
        await waitUntil("the first write to start") { store.started == 1 }
        try emptyPane(workspace)
        try await Task.sleep(for: .milliseconds(60))
        try emptyPane(workspace)
        try await Task.sleep(for: .milliseconds(60))
        #expect(store.started == 1)                                            // the others wait behind the write in flight

        store.release()
        await workspace.settleAutosave()
        #expect(store.started == 2)                                            // 2nd snapshot was replaced by the 3rd
        #expect(store.peak == 1)
        #expect(try store.saved.map { try decodeSession($0).windows[0].root?.leaves.count } == [1, 3])
    }

    @Test func aFailedWriteSetsLastSaveErrorAndTheNextSnapshotPointRetries() async throws {
        let store = MemoryStore()
        let workspace = try makePersistentWorkspace(.custom(store))
        _ = await workspace.restoreOrOpenDefaultAsync()
        store.failSaves(1)
        await #expect(throws: PersistenceError.self) { try await workspace.saveNow() }
        #expect(workspace.lastSaveError != nil)
        #expect(store.data == nil)

        try emptyPane(workspace)
        await workspace.settleAutosave()
        #expect(workspace.lastSaveError == nil)
        #expect(try decodeSession(store.data).windows[0].root?.leaves.count == 1)
    }

    @Test func aFailingEncodeLeavesTheStoreAloneAndIsReported() async throws {
        let failing = OSAllocatedUnfairLock(initialState: true)
        let store = MemoryStore()
        let workspace = try makePersistentWorkspace(.custom(store), encode: {
            if failing.withLock({ $0 }) { throw MemoryStore.Failure() }
            return try Migrator.encode($0)
        })
        _ = await workspace.restoreOrOpenDefaultAsync()
        await #expect(throws: PersistenceError.self) { try await workspace.saveNow() }
        #expect(workspace.lastSaveError != nil)
        #expect(store.started == 0)

        failing.withLock { $0 = false }
        try await workspace.saveNow()
        #expect(workspace.lastSaveError == nil)
        #expect(store.saved.count == 1)
    }

    @Test func aContentThatCannotEncodeItsStateKeepsTheLastGoodState() async throws {
        let store = MemoryStore()
        let workspace = try makePersistentWorkspace(.custom(store))
        _ = await workspace.restoreOrOpenDefaultAsync()
        try await workspace.addContent(CounterContent.type, url: nil, into: nil)
        let id = try #require(workspace.session.contents.first?.id)
        let counter = try #require(workspace.store[id] as? CounterContent)
        counter.count = 5
        try await workspace.saveNow()

        counter.failsEncoding = true
        counter.count = 9
        try await workspace.saveNow()                                          // the save itself succeeds
        #expect(try decodeSession(store.data).contents.first?.state == CounterContent.state(5))
        #expect(workspace.stateEncodingErrors[id] != nil)

        counter.failsEncoding = false
        try await workspace.saveNow()
        #expect(try decodeSession(store.data).contents.first?.state == CounterContent.state(9))
        #expect(workspace.stateEncodingErrors.isEmpty)
    }

    @Test func aPendingCloseIsSavedAsOpen() async throws {
        let store = MemoryStore()
        let workspace = try makePersistentWorkspace(.custom(store))
        _ = await workspace.restoreOrOpenDefaultAsync()
        try await workspace.addContent(TestContent.type, url: nil, into: nil)
        try await workspace.addContent(TestContent.type, besides: workspace.mainLeaves[0].pane, edge: .right)
        let pane = workspace.mainLeaves[0].pane
        let content = try #require(workspace.mainLeaves[0].content)
        let object = try #require(workspace.store[content] as? TestContent)
        object.suspendsClose = true
        let closing = Task { try await workspace.perform(.closePane(pane)) }
        await waitUntil("the close to ask the content") { object.isAskingToClose }
        #expect(workspace.runtime.pendingCloses == [pane])

        try await workspace.saveNow()
        #expect(try decodeSession(store.data).windows[0].root?.leaves.map(\.pane) == workspace.mainLeaves.map(\.pane))
        object.answerClose(false)
        try await closing.value
    }

    @Test func committedCloseIsASnapshotPointAndPendingStagesAreNot() async throws {
        let store = MemoryStore()
        let workspace = try makePersistentWorkspace(.custom(store))
        _ = await workspace.restoreOrOpenDefaultAsync()
        try await workspace.addContent(TestContent.type, url: nil, into: nil)
        await workspace.settleAutosave()
        let before = store.started
        let pane = workspace.mainLeaves[0].pane
        try workspace.commit(.beginClose(pane))
        try workspace.commit(.cancelClose(pane))
        await workspace.settleAutosave()
        #expect(store.started == before)

        try await workspace.perform(.closePane(pane))
        await workspace.settleAutosave()
        #expect(store.started == before + 1)
        #expect(try decodeSession(store.data).contents.isEmpty)
    }

    @Test func saveBeforeQuitWaitsForTheWriteButNotLongerThanTheCap() async throws {
        let store = MemoryStore()
        let workspace = try makePersistentWorkspace(.custom(store))
        _ = await workspace.restoreOrOpenDefaultAsync()
        try emptyPane(workspace)
        await workspace.saveBeforeQuit()
        #expect(store.saved.count == 1)

        store.block()
        try emptyPane(workspace)
        let start = ContinuousClock.now
        await workspace.saveBeforeQuit(timeout: .milliseconds(100))            // the store never answers
        #expect(ContinuousClock.now - start < .seconds(2))
        store.release()
        await workspace.settleAutosave()
    }
}
