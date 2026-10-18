import Foundation

/// The conformance suite every `SessionStore` must pass (§8, §13). Hosts call it from their own tests:
///
///     let problems = await SessionStoreConformance.check(makeStore: { MyStore(medium: .empty) },
///                                                        failNextSave: { ($0 as! MyStore).failNextWrite() })
///     #expect(problems.isEmpty, "\(problems)")
///
/// It returns what went wrong, one sentence per problem, and imports no test framework.
public enum SessionStoreConformance {
    /// - Parameters:
    ///   - makeStore: A store on a fresh, empty medium, on every call.
    ///   - failNextSave: Makes the next `save` of that store fail part-way (e.g. the write or the rename
    ///     throws). Without it the failure checks are skipped, which leaves atomicity unchecked.
    public static func check(makeStore: @Sendable () async throws -> any SessionStore,
                             failNextSave: (@Sendable (any SessionStore) async -> Void)? = nil) async -> [String] {
        var problems: [String] = []
        func expect(_ condition: Bool, _ message: @autoclosure () -> String) {
            if !condition { problems.append(message()) }
        }
        do {
            let store = try await makeStore()
            expect(try await store.load() == nil, "a fresh store must load nil")

            let first = Data(#"{"version":1,"padding":"\#(String(repeating: "x", count: 4096))"}"#.utf8)
            try await store.save(first)
            expect(try await store.load() == first, "load after the first save must return exactly what was saved")

            let second = Data("short".utf8)
            try await store.save(second)
            expect(try await store.load() == second, "a save must replace the previous data entirely, with no tail of a longer one")

            let binary = Data((0...255).map(UInt8.init))
            try await store.save(binary)
            expect(try await store.load() == binary, "a store must keep arbitrary bytes")

            for index in 0..<5 { try await store.save(Data("run \(index)".utf8)) }
            expect(try await store.load() == Data("run 4".utf8), "the last save must win")

            if let failNextSave {
                try await store.save(first)
                await failNextSave(store)
                var failed = false
                do { try await store.save(second) } catch { failed = true }
                expect(failed, "a save that fails must throw")
                expect(try await store.load() == first, "a failed save must leave the previous data untouched")
                try await store.save(second)
                expect(try await store.load() == second, "a store must save again after a failure")
            }

            let fresh = try await makeStore()
            if let failNextSave {
                await failNextSave(fresh)
                var failed = false
                do { try await fresh.save(first) } catch { failed = true }
                expect(failed, "a first save that fails must throw")
                expect(try await fresh.load() == nil, "a failed first save must leave the store empty")
            }
        } catch {
            problems.append("the store threw where it must not: \(error)")
        }
        return problems
    }
}
