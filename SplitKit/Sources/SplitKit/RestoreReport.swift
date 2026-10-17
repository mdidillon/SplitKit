import Foundation
import SplitKitModel

/// Owned by the SplitKit (UI) target because it reflects the registry. Returned by restoreOrOpenDefault (§8).
public struct RestoreReport: Equatable, Sendable {
    public enum Source: Equatable, Sendable { case restoredFile, noFile, persistenceDisabled, defaultAfterError(PersistenceError) }
    public struct Unavailable: Equatable, Sendable {
        public enum Reason: Equatable, Sendable { case typeNotRegistered, restoreFailed(String) }
        public var id: ContentID; public var type: ContentType; public var reason: Reason

        public init(id: ContentID, type: ContentType, reason: Reason) {
            self.id = id
            self.type = type
            self.reason = reason
        }
    }
    public var source: Source
    public var keptInvalidFile: URL?               // session.invalid-<timestamp>.json, when one was written
    public var normalizations: [Normalization]     // from Migrator.decode
    public var unavailable: [Unavailable]          // placeholders after this restore
    public var autoRestored: [ContentID]           // .unavailable records whose type is registered now

    /// The memberwise initialiser the §5 declaration implies; everything but `source` defaults to empty.
    public init(source: Source, keptInvalidFile: URL? = nil, normalizations: [Normalization] = [],
                unavailable: [Unavailable] = [], autoRestored: [ContentID] = []) {
        self.source = source
        self.keptInvalidFile = keptInvalidFile
        self.normalizations = normalizations
        self.unavailable = unavailable
        self.autoRestored = autoRestored
    }
}
