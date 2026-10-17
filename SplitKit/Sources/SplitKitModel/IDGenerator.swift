import Foundation

/// Source of every new PaneID/SplitID the engine creates. WindowIDs and ContentIDs are supplied by the caller.
public protocol IDGenerator { mutating func next() -> UUID }

/// `UUID()`, used by `SplitKitWorkspace`.
public struct SystemIDGenerator: IDGenerator, Sendable {
    public init() {}
    public mutating func next() -> UUID { UUID() }
}

/// SplitMix64 → RFC 4122 v4 bits; tests only.
///
/// Each `next()` draws two SplitMix64 outputs. The first fills bytes 0–7 and the second bytes 8–15,
/// most significant byte first. Then the version nibble (byte 6, high 4 bits) is set to `0100` and the
/// variant (byte 8, high 2 bits) to `10`. The same seed always yields the same UUID sequence.
public struct SeededIDGenerator: IDGenerator, Sendable {
    private var state: UInt64

    public init(seed: UInt64) { state = seed }

    /// One SplitMix64 step (Steele, Lea, Flood 2014; constants from Vigna's reference `splitmix64.c`).
    mutating func nextUInt64() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    public mutating func next() -> UUID {
        let high = nextUInt64(), low = nextUInt64()
        var b = [UInt8](repeating: 0, count: 16)
        for i in 0..<8 {
            b[i] = UInt8(truncatingIfNeeded: high >> (56 - 8 * UInt64(i)))
            b[8 + i] = UInt8(truncatingIfNeeded: low >> (56 - 8 * UInt64(i)))
        }
        b[6] = (b[6] & 0x0F) | 0x40
        b[8] = (b[8] & 0x3F) | 0x80
        return UUID(uuid: (b[0], b[1], b[2], b[3], b[4], b[5], b[6], b[7],
                           b[8], b[9], b[10], b[11], b[12], b[13], b[14], b[15]))
    }
}
