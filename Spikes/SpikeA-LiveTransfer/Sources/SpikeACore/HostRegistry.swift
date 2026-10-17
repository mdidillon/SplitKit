import Foundation

public enum TransferError: Error, Equatable, Sendable {
    case unknownHost(HostID)
    case duplicateHost(HostID)
    case unknownContent(ContentID)
    case contentAlreadyHosted(ContentID, in: HostID)
    case hostOccupied(HostID, by: ContentID)
    case contentNotHosted(ContentID)
    case hostRejectsDrops(HostID)
    case transferInProgress(TransferSessionID)
    case noSuchTransfer(TransferSessionID)
    case noEmptyTargetInOtherWindow
}

/// What a valid drop does. A self-drop is always a no-op (spec §6.2).
public enum DropDecision: Equatable, Sendable {
    case move(ContentID, from: HostID, to: HostID)
    case selfDrop
}

/// Pure ownership model: ContentID → host, plus the in-flight transfer.
///
/// Every mutating call validates first and throws without touching state, so a failed
/// operation leaves the registry byte-identical (see `encodedSnapshot()`).
public struct HostRegistry: Equatable, Sendable {
    public struct HostInfo: Codable, Equatable, Sendable {
        public var window: WindowID
        public var acceptsDrops: Bool
    }

    public struct Transfer: Codable, Equatable, Sendable {
        public var id: TransferSessionID
        public var content: ContentID
        public var source: HostID
    }

    public private(set) var hosts: [HostID: HostInfo] = [:]
    public private(set) var placement: [ContentID: HostID] = [:]
    public private(set) var activeTransfer: Transfer?

    public init() {}

    public func host(of content: ContentID) -> HostID? { placement[content] }

    public func content(in host: HostID) -> ContentID? {
        placement.first { $0.value == host }?.key
    }

    public mutating func addHost(_ id: HostID, window: WindowID, acceptsDrops: Bool = true) throws(TransferError) {
        guard hosts[id] == nil else { throw .duplicateHost(id) }
        hosts[id] = HostInfo(window: window, acceptsDrops: acceptsDrops)
        checkInvariants()
    }

    /// The testable single-host API: hosting an already hosted content throws.
    public mutating func place(_ content: ContentID, in host: HostID) throws(TransferError) {
        guard hosts[host] != nil else { throw .unknownHost(host) }
        if let existing = placement[content] { throw .contentAlreadyHosted(content, in: existing) }
        if let occupant = self.content(in: host) { throw .hostOccupied(host, by: occupant) }
        placement[content] = host
        checkInvariants()
    }

    public mutating func beginTransfer(_ content: ContentID) throws(TransferError) -> Transfer {
        if let active = activeTransfer { throw .transferInProgress(active.id) }
        guard let source = placement[content] else { throw .contentNotHosted(content) }
        let transfer = Transfer(id: TransferSessionID(), content: content, source: source)
        activeTransfer = transfer
        checkInvariants()
        return transfer
    }

    /// Pure check used by drag destinations while hovering; never mutates.
    public func validateDrop(_ session: TransferSessionID, onto target: HostID) throws(TransferError) -> DropDecision {
        guard let transfer = activeTransfer, transfer.id == session else { throw .noSuchTransfer(session) }
        guard let info = hosts[target] else { throw .unknownHost(target) }
        if target == transfer.source { return .selfDrop }
        guard info.acceptsDrops else { throw .hostRejectsDrops(target) }
        // The spike only drops into empty panes; swap/edge-split semantics are SplitKitModel's job (P1 model, P3).
        if let occupant = content(in: target) { throw .hostOccupied(target, by: occupant) }
        return .move(transfer.content, from: transfer.source, to: target)
    }

    @discardableResult
    public mutating func completeTransfer(_ session: TransferSessionID, onto target: HostID) throws(TransferError) -> DropDecision {
        let decision = try validateDrop(session, onto: target)
        if case .move(let content, _, let to) = decision {
            placement[content] = to
        }
        activeTransfer = nil
        checkInvariants()
        return decision
    }

    /// Esc, drop outside, or a failed drop. Idempotent; returns whether a transfer was cancelled.
    @discardableResult
    public mutating func cancelTransfer(_ session: TransferSessionID) -> Bool {
        guard activeTransfer?.id == session else { return false }
        activeTransfer = nil
        return true
    }

    // MARK: Invariants and snapshots

    public func invariantViolations() -> [String] {
        var violations: [String] = []
        var seenHosts: [HostID: ContentID] = [:]
        for (content, host) in placement.sorted(by: { $0.key < $1.key }) {
            if hosts[host] == nil { violations.append("\(content) placed in unknown \(host)") }
            if let other = seenHosts[host] { violations.append("\(host) hosts both \(other) and \(content)") }
            seenHosts[host] = content
        }
        if let t = activeTransfer, placement[t.content] != t.source {
            violations.append("active \(t.id) source \(t.source) does not host \(t.content)")
        }
        return violations
    }

    private func checkInvariants() {
        let violations = invariantViolations()
        if !violations.isEmpty { SpikeInvariant.failure("HostRegistry: " + violations.joined(separator: "; ")) }
    }

    private struct Snapshot: Codable {
        struct Host: Codable { var id: HostID; var info: HostInfo }
        struct Entry: Codable { var content: ContentID; var host: HostID }
        var hosts: [Host]
        var placement: [Entry]
        var activeTransfer: Transfer?
    }

    /// Deterministic encoding (sorted) for byte-for-byte before/after comparisons.
    public func encodedSnapshot() -> Data {
        let snapshot = Snapshot(
            hosts: hosts.sorted { $0.key < $1.key }.map { .init(id: $0.key, info: $0.value) },
            placement: placement.sorted { $0.key < $1.key }.map { .init(content: $0.key, host: $0.value) },
            activeTransfer: activeTransfer
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        // Encoding plain Codable value types cannot fail.
        return try! encoder.encode(snapshot)
    }
}
