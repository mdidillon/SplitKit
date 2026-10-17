import Foundation

// Errors (§12)

public enum LayoutError: Error, Equatable, Sendable {
    case unknownPane(PaneID), unknownSplit(SplitID), unknownWindow(WindowID), unknownContent(ContentID)
    case contentAlreadyHosted(ContentID), centerInsertIntoOccupiedPane
    case invalidFractions(reason: String), indexOutOfRange
    case paneClosePending(PaneID), noCloseInProgress(PaneID)
    case windowClosePending(WindowID), noWindowCloseInProgress(WindowID)
    case windowNotEmpty(WindowID), mainWindowExists(WindowID), windowIDInUse(WindowID)
}

/// Thrown by `Migrator.decode` (§8).
public enum PersistenceError: Error, Equatable, Sendable {
    case unreadable(underlying: String), unsupportedFutureVersion(Int), migrationFailed(from: Int, reason: String)
    case invalid([InvariantViolation])        // fatal violations only
}

/// Model-level only. `isFatal` decides restore behaviour (§8). After a transaction, ANY violation is an engine bug (§12).
public enum InvariantViolation: Equatable, Sendable {
    // fatal
    case duplicatePaneID(PaneID), duplicateSplitID(SplitID), duplicateWindowID(WindowID)
    case duplicateContentID(ContentID)        // hosted in more than one pane
    case duplicateRecord(ContentID)           // two ContentRecords with one ID
    case missingContentRecord(ContentID)      // a pane hosts an ID with no record
    case singleChildSplit(SplitID)            // fewer than 2 children
    case fractionCountMismatch(SplitID)
    case badFractions(SplitID)                // non-finite, ≤ 0, or sum outside 1 ± 1e-9
    case sameAxisNesting(SplitID)             // the child split
    case nilRootInDetachedWindow(WindowID)
    case detachedWindowWithoutContent(WindowID)
    case multipleMainWindows
    // recoverable (repaired by Migrator.decode, reported as Normalization)
    case orphanRecord(ContentID)
    case danglingActivePane(WindowID), danglingFocusModePane(WindowID)

    /// False only for the three recoverable cases.
    public var isFatal: Bool {
        switch self {
        case .orphanRecord, .danglingActivePane, .danglingFocusModePane: false
        default: true
        }
    }
}
