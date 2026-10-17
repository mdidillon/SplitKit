import CoreGraphics
import Foundation

/// The synthetic, test-only v0 schema (§8). It never shipped; it exists to exercise the migration chain.
///
/// `{ "root": LayoutNode?, "contents": [{ "id", "type", "stateVersion", "state" }] }` with no `version` key:
/// one main window, no placement, no focus fields, no `availability`.
enum V0 {
    struct Session: Decodable {
        var root: LayoutNode?
        var contents: [Record]
    }

    struct Record: Decodable {
        var id: ContentID
        var type: ContentType
        var stateVersion: Int
        var state: Data
    }

    /// The fixed main `WindowID` of every migrated v0 file, so migration stays pure and reproducible.
    static let mainWindowID = WindowID(raw: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!)

    /// Centred on the main display by §9 (`relativeOrigin == nil`).
    static let placement = SavedPlacement.defaultMainWindow

    /// v0 → v1: wraps the tree into one `.main` window, no focus, every record `.hosted`.
    static func migrateToV1(_ data: Data) throws(PersistenceError) -> Data {
        let v0: Session
        do {
            v0 = try Migrator.decodeJSON(Session.self, from: data)
        } catch {
            throw .migrationFailed(from: 0, reason: String(describing: error))
        }
        let window = WindowLayout(id: mainWindowID, kind: .main, root: v0.root,
                                  activePane: nil, focusModePane: nil, placement: placement)
        let v1 = SplitKitModel.Session(
            version: 1, windows: [window],
            contents: v0.contents.map {
                ContentRecord(id: $0.id, type: $0.type, stateVersion: $0.stateVersion, state: $0.state, availability: .hosted)
            })
        do {
            return try Migrator.encode(v1)
        } catch {
            throw .migrationFailed(from: 0, reason: String(describing: error))
        }
    }
}
