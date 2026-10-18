import Foundation
import os
import Testing
import SplitKitContent
import SplitKitModel
@testable import SplitKit

/// §8 persistence in the SplitKit layer: the file store, the restore pipeline, registry marking, Restore,
/// autosave and the snapshot rules, with fault injection.

// MARK: File store (atomic writes)

/// Fails the next call of the armed file system steps.
final class FileFaults: @unchecked Sendable {
    enum Step { case createDirectory, write, move, replace }
    private let armed = OSAllocatedUnfairLock(initialState: Set<Step>())

    func arm(_ steps: Step...) { armed.withLock { $0.formUnion(steps) } }
    func fire(_ step: Step) throws {
        if armed.withLock({ $0.remove(step) != nil }) { throw CocoaError(.fileWriteUnknown) }
    }

    var operations: FileSessionStore.Operations {
        var live = FileSessionStore.Operations.live
        let (create, write, move, replace) = (live.createDirectory, live.write, live.move, live.replace)
        live.createDirectory = { try self.fire(.createDirectory); try create($0) }
        live.write = { data, url in try self.fire(.write); try write(data, url) }
        live.move = { try self.fire(.move); try move($0, $1) }
        live.replace = { try self.fire(.replace); try replace($0, $1) }
        return live
    }
}

nonisolated(nonsending) func expectFailure(_ body: () async throws -> Void) async {
    do { try await body(); Issue.record("expected a failure") } catch {}
}

/// Not atomic: a save that fails has already destroyed the previous data.
private final class DestructiveStore: SessionStore, @unchecked Sendable {
    let data = OSAllocatedUnfairLock<Data?>(initialState: nil)
    let failNext = OSAllocatedUnfairLock(initialState: false)
    func load() async throws -> Data? { data.withLock { $0 } }
    func save(_ new: Data) async throws {
        data.withLock { $0 = nil }
        if failNext.withLock({ let value = $0; $0 = false; return value }) { throw MemoryStore.Failure() }
        data.withLock { $0 = new }
    }
}

@MainActor
@Suite struct FileSessionStoreTests {
    private func names(in directory: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()
    }

    @Test func firstSaveCreatesTheDirectoryAndLaterSavesReplace() async throws {
        try await withTemporaryDirectory { directory in
            let file = directory.appending(path: "nested/SplitKit/session.json")
            let store = FileSessionStore(url: file)
            #expect(try await store.load() == nil)
            try await store.save(Data("one".utf8))
            try await store.save(Data("two".utf8))
            #expect(try await store.load() == Data("two".utf8))
            #expect(try names(in: file.deletingLastPathComponent()) == ["session.json"])
        }
    }

    @Test(arguments: [FileFaults.Step.createDirectory, .write, .move])
    func aFailedFirstSaveLeavesNoFileAndNoTempFile(step: FileFaults.Step) async throws {
        try await withTemporaryDirectory { directory in
            let faults = FileFaults()
            let store = FileSessionStore(url: directory.appending(path: "session.json"), operations: faults.operations)
            faults.arm(step)
            await expectFailure { try await store.save(Data("one".utf8)) }
            let leftovers = try names(in: directory)
            let loaded = try await store.load()
            #expect(leftovers.isEmpty)
            #expect(loaded == nil)
        }
    }

    @Test(arguments: [FileFaults.Step.write, .replace])
    func aFailedLaterSaveLeavesThePreviousFileAndNoTempFile(step: FileFaults.Step) async throws {
        try await withTemporaryDirectory { directory in
            let faults = FileFaults()
            let store = FileSessionStore(url: directory.appending(path: "session.json"), operations: faults.operations)
            try await store.save(Data("good".utf8))
            faults.arm(step)
            await expectFailure { try await store.save(Data("bad".utf8)) }
            #expect(try await store.load() == Data("good".utf8))
            #expect(try names(in: directory) == ["session.json"])
            try await store.save(Data("again".utf8))
            #expect(try await store.load() == Data("again".utf8))
        }
    }

    @Test func conformanceSuitePassesForTheFileStoreUnderEveryFault() async throws {
        for steps in [[FileFaults.Step.write], [.move, .replace]] {
            try await withTemporaryDirectory { directory in
                let faults = FileFaults()
                let problems = await SessionStoreConformance.check(
                    makeStore: { FileSessionStore(url: directory.appending(path: "\(UUID().uuidString)/session.json"), operations: faults.operations) },
                    failNextSave: { _ in for step in steps { faults.arm(step) } })
                #expect(problems.isEmpty, "\(problems)")
            }
        }
    }

    @Test func conformanceSuitePassesForTheMemoryStoreAndCatchesBrokenOnes() async {
        #expect(await SessionStoreConformance.check(makeStore: { MemoryStore() }, failNextSave: { ($0 as! MemoryStore).failSaves(1) }).isEmpty)
        let problems = await SessionStoreConformance.check(makeStore: { DestructiveStore() },
                                                           failNextSave: { ($0 as! DestructiveStore).failNext.withLock { $0 = true } })
        #expect(problems.contains { $0.contains("previous data untouched") })
    }

    @Test func keepInvalidNeverOverwritesAnExistingCopy() async throws {
        try await withTemporaryDirectory { directory in
            let store = FileSessionStore(url: directory.appending(path: "session.json"))
            let date = Date(timeIntervalSince1970: 1_800_000_000)
            let first = try store.keepInvalid(Data("a".utf8), at: date)
            let second = try store.keepInvalid(Data("b".utf8), at: date)
            #expect(first != second)
            #expect(try Data(contentsOf: first) == Data("a".utf8))
            #expect(first.lastPathComponent.wholeMatch(of: /session\.invalid-\d{8}T\d{6}Z\.json/) != nil)
        }
    }
}
