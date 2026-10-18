import Foundation
import SplitKitModel

/// Writes snapshots to a `SessionStore`, one at a time (§8): a snapshot that arrives while a write is in
/// flight replaces the one queued behind it. Encoding and the store call run off the main actor.
@MainActor
final class SessionWriter {
    typealias Encode = @Sendable (Session) throws -> Data

    private let store: any SessionStore
    private let encode: Encode
    /// Called on the main actor after each write: nil on success, the error otherwise.
    private let didWrite: @MainActor (PersistenceError?) -> Void
    private var queued: Session?
    private var inFlight: Task<Void, Never>?

    init(store: any SessionStore, encode: @escaping Encode, didWrite: @escaping @MainActor (PersistenceError?) -> Void) {
        self.store = store
        self.encode = encode
        self.didWrite = didWrite
    }

    func enqueue(_ snapshot: Session) {
        queued = snapshot
        guard inFlight == nil else { return }
        inFlight = Task { await drain() }
    }

    /// Returns when nothing is queued or in flight.
    func idle() async {
        while let task = inFlight { await task.value }
    }

    private func drain() async {
        while let next = queued {
            queued = nil
            didWrite(await Self.write(next, to: store, encode: encode))
        }
        inFlight = nil
    }

    /// A save failure has no `PersistenceError` case of its own in §5, so it is reported as `.unreadable`
    /// with a "save failed" description (deviation candidate).
    private nonisolated static func write(_ snapshot: Session, to store: any SessionStore, encode: Encode) async -> PersistenceError? {
        do {
            try await store.save(try encode(snapshot))
            return nil
        } catch {
            return .unreadable(underlying: "save failed: \(error)")
        }
    }
}
