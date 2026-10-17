import Foundation

/// Reads and writes `Session` JSON (§8). Pure: never consults the registry and never touches the file system.
public enum Migrator {
    /// The schema version `encode` writes; the last step of the migration chain.
    public static var currentVersion: Int { Session.currentVersion }

    /// Stepwise vN→vN+1, then validate. Throws only for unreadable/future/failed migration or FATAL violations;
    /// recoverable violations are repaired and returned as normalisations. Never consults the registry.
    ///
    /// A file without a `version` key is v0 (§8). An explicit `version` below 1 names no schema and fails
    /// migration; one above `currentVersion` is `unsupportedFutureVersion`.
    public static func decode(_ data: Data) throws(PersistenceError) -> (Session, [Normalization]) {
        let fileVersion: Int?
        do {
            fileVersion = try decodeJSON(VersionProbe.self, from: data).version
        } catch {
            throw .unreadable(underlying: String(describing: error))
        }

        var payload = data
        switch fileVersion {
        case nil:
            for version in 0..<currentVersion { payload = try migrate(payload, from: version) }
        case let version? where version > currentVersion:
            throw .unsupportedFutureVersion(version)
        case let version? where version < 1:
            throw .migrationFailed(from: version, reason: "no schema has version \(version); a v0 file has no version key")
        case let version?:
            for step in version..<currentVersion { payload = try migrate(payload, from: step) }
        }

        let session: Session
        do {
            session = try decodeJSON(Session.self, from: payload)
        } catch {
            throw .unreadable(underlying: String(describing: error))
        }
        return try repair(session)
    }

    /// The one decoder setup used everywhere (§8): default `JSONDecoder`, the counterpart of `encode`.
    static func decodeJSON<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        try JSONDecoder().decode(type, from: data)
    }

    /// The one encoder setup used everywhere (§8): sorted keys, pretty printed, slashes unescaped, default
    /// `.base64` data and shortest round-trip numbers. Throws only for values JSON can't hold (non-finite numbers).
    public static func encode(_ s: Session) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
        return try encoder.encode(s)
    }

    /// One step of the chain: data in schema `version` → data in schema `version + 1`.
    static func migrate(_ data: Data, from version: Int) throws(PersistenceError) -> Data {
        switch version {
        case 0: try V0.migrateToV1(data)
        default: throw .migrationFailed(from: version, reason: "no migration step from version \(version)")
        }
    }

    /// Validates (§6.1). Fatal violations throw `.invalid` with the fatal list; recoverable ones are repaired in
    /// `validate` order and reported (§8).
    static func repair(_ session: Session) throws(PersistenceError) -> (Session, [Normalization]) {
        let violations = SessionEngine.validate(session)
        let fatal = violations.filter(\.isFatal)
        guard fatal.isEmpty else { throw .invalid(fatal) }

        var repaired = session
        var normalizations: [Normalization] = []
        for violation in violations {
            switch violation {
            case let .orphanRecord(id):
                repaired.contents.removeAll { $0.id == id }
                normalizations.append(.droppedOrphanRecord(id))
            case let .danglingActivePane(id):
                for i in repaired.windows.indices where repaired.windows[i].id == id { repaired.windows[i].activePane = nil }
                normalizations.append(.clearedActivePane(id))
            case let .danglingFocusModePane(id):
                for i in repaired.windows.indices where repaired.windows[i].id == id { repaired.windows[i].focusModePane = nil }
                normalizations.append(.clearedFocusModePane(id))
            default:
                preconditionFailure("fatal violation \(violation) after the fatal check")
            }
        }
        return (repaired, normalizations)
    }
}

/// Reads only `version`. A missing key means v0; a present key must be an integer (`null` is unreadable).
private struct VersionProbe: Decodable {
    var version: Int?

    enum CodingKeys: String, CodingKey { case version }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = container.contains(.version) ? try container.decode(Int.self, forKey: .version) : nil
    }
}
