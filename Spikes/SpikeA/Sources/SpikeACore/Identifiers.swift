import Foundation

/// The live content instance (spec §4). Kept identical across a move.
public struct ContentID: Hashable, Codable, Sendable, Comparable, CustomStringConvertible {
    public let raw: UUID
    public init(_ raw: UUID = UUID()) { self.raw = raw }
    public var description: String { "content-" + raw.uuidString.prefix(8) }
    public static func < (a: Self, b: Self) -> Bool { a.raw.uuidString < b.raw.uuidString }
}

/// A pane slot that can host one content (the spike's stand-in for `PaneID`).
public struct HostID: Hashable, Codable, Sendable, Comparable, CustomStringConvertible {
    public let raw: UUID
    public init(_ raw: UUID = UUID()) { self.raw = raw }
    public var description: String { "host-" + raw.uuidString.prefix(8) }
    public static func < (a: Self, b: Self) -> Bool { a.raw.uuidString < b.raw.uuidString }
}

public struct WindowID: Hashable, Codable, Sendable, Comparable, CustomStringConvertible {
    public let raw: UUID
    public init(_ raw: UUID = UUID()) { self.raw = raw }
    public var description: String { "window-" + raw.uuidString.prefix(8) }
    public static func < (a: Self, b: Self) -> Bool { a.raw.uuidString < b.raw.uuidString }
}

/// One drag (or command) transfer, from begin to drop/cancel (spec §5 `DragSessionID`).
public struct TransferSessionID: Hashable, Codable, Sendable, CustomStringConvertible {
    public let raw: UUID
    public init(_ raw: UUID = UUID()) { self.raw = raw }
    public var description: String { "transfer-" + raw.uuidString.prefix(8) }
}

/// Programmer-error path (spec §12): `preconditionFailure` in debug, logged + safe fallback in release.
enum SpikeInvariant {
    static func failure(_ message: @autoclosure () -> String, file: StaticString = #file, line: UInt = #line) {
        #if DEBUG
        preconditionFailure(message(), file: file, line: line)
        #else
        NSLog("SpikeA invariant violated: %@", message())
        #endif
    }
}
