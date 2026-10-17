import Foundation
import Testing
@testable import SplitKitModel

// §8 persistence: Migrator.encode/decode, the v0 → v1 chain, fatal vs recoverable validation, PersistenceError.

/// The decode error, or nil if `data` decoded.
private func decodeError(_ data: Data) -> PersistenceError? {
    do throws(PersistenceError) {
        _ = try Migrator.decode(data)
        return nil
    } catch {
        return error
    }
}

private func isUnreadable(_ e: PersistenceError?) -> Bool {
    if case .unreadable = e { true } else { false }
}

private func migrationFailedFrom(_ e: PersistenceError?) -> Int? {
    if case let .migrationFailed(from, reason) = e, !reason.isEmpty { from } else { nil }
}

/// Edits the encoded JSON of `s` as a dictionary and returns the re-serialised bytes.
private func editedJSON(_ s: Session, _ edit: (inout [String: Any]) -> Void) -> Data {
    var object = try! JSONSerialization.jsonObject(with: encoded(s)) as! [String: Any]
    edit(&object)
    return try! JSONSerialization.data(withJSONObject: object)
}

private func json(_ text: String) -> Data { Data(text.utf8) }

private let fixtureDirectory = URL(filePath: #filePath).deletingLastPathComponent().appending(path: "Fixtures")

private func fixture(_ name: String) throws -> Data {
    try Data(contentsOf: fixtureDirectory.appending(path: name))
}

/// What `Fixtures/session-v0.json` must migrate to (§8 v0 → v1).
private let migratedV0 = Session(
    version: 1,
    windows: [WindowLayout(
        id: WindowID(raw: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!), kind: .main,
        root: h(1, [p(1, 1), v(2, [p(2, 2), p(3)])], [0.25, 0.75]),
        activePane: nil, focusModePane: nil,
        placement: SavedPlacement(intendedFrame: CGRect(x: 0, y: 0, width: 1200, height: 800), displayID: nil, relativeOrigin: nil))],
    contents: [
        ContentRecord(id: cid(1), type: testType, stateVersion: 1, state: Data([1, 2, 3]), availability: .hosted),
        ContentRecord(id: cid(2), type: ContentType(raw: "splitkit.image"), stateVersion: 3, state: Data(), availability: .hosted),
    ])

@Suite("§8 Migrator.encode")
struct EncodeTests {
    @Test func currentVersionIsSessionVersion() {
        #expect(Migrator.currentVersion == Session.currentVersion)
        #expect(Migrator.currentVersion == 1)
    }

    @Test("Sorted keys, pretty printed, slashes unescaped, base64 data")
    func encoderSetup() throws {
        let s = Session(windows: [mainWindow(1, p(1, 1))], contents: [record(cid(1), state: Data([0xFF, 0xFF, 0xFF]))])
        let text = String(decoding: try Migrator.encode(s), as: UTF8.self)
        #expect(text.hasPrefix("{\n  \"contents\" : ["))
        #expect(text.contains("\"state\" : \"////\""))       // base64 of FF FF FF, '/' not escaped
        #expect(!text.contains("\\/"))
        let keys = ["\"contents\"", "\"version\"", "\"windows\""].map { text.range(of: $0)!.lowerBound }
        #expect(keys == keys.sorted())
        let recordKeys = ["\"availability\"", "\"id\"", "\"state\"", "\"stateVersion\"", "\"type\""].map { text.range(of: $0)!.lowerBound }
        #expect(recordKeys == recordKeys.sorted())
    }

    @Test("CoreGraphics geometry encodes as nested arrays; split axis key is `axis`")
    func geometryAsNestedArrays() throws {
        var window = mainWindow(1, h(1, [p(1, 1), p(2)]))
        window.placement = SavedPlacement(intendedFrame: CGRect(x: -10.5, y: 20, width: 300, height: 200),
                                          displayID: "display-2", relativeOrigin: CGPoint(x: 4, y: -8))
        let s = Session(windows: [window], contents: [record(cid(1))])
        let object = try JSONSerialization.jsonObject(with: try Migrator.encode(s)) as! [String: Any]
        let placement = ((object["windows"] as! [[String: Any]])[0]["placement"]) as! [String: Any]
        #expect(placement["intendedFrame"] as? [[Double]] == [[-10.5, 20], [300, 200]])
        #expect(placement["relativeOrigin"] as? [Double] == [4, -8])
        #expect(placement["displayID"] as? String == "display-2")
        let root = (object["windows"] as! [[String: Any]])[0]["root"] as! [String: Any]
        #expect((root["split"] as! [String: Any])["axis"] as? String == "horizontal")
        let text = String(decoding: try Migrator.encode(session(mainWindow(1, p(1, 1)))), as: UTF8.self)
        #expect(text.contains("\"intendedFrame\" : [\n"))
    }

    @Test("`.unavailable` records keep their availability on the wire")
    func unavailableEncoding() throws {
        var s = twoWindows
        s.contents[1] = record(cid(2), state: Data([0xFF]), availability: .unavailable)
        #expect(String(decoding: try Migrator.encode(s), as: UTF8.self).contains("\"availability\" : \"unavailable\""))
    }

    @Test("IDs encode with their synthesized form {\"raw\": UUID string}")
    func idEncoding() throws {
        let text = String(decoding: try Migrator.encode(session(mainWindow(1, p(1, 1)))), as: UTF8.self)
        #expect(text.contains("\"raw\" : \"04000000-0000-4000-8000-000000000001\""))
        #expect(text.contains("\"raw\" : \"splitkit.test\""))
    }

    @Test("Same session → byte-identical output across calls")
    func deterministic() throws {
        #expect(try Migrator.encode(twoWindows) == Migrator.encode(twoWindows))
    }

    @Test("Non-finite numbers can't be encoded: encode throws")
    func encodeThrowsOnNonFinite() {
        let s = session(mainWindow(1, h(1, [p(1, 1), p(2)], [.nan, 0.5])))
        #expect(throws: EncodingError.self) { try Migrator.encode(s) }
    }

    @Test("The migrated v0 fixture encodes to the committed v1 golden bytes")
    func goldenBytes() throws {
        let (session, _) = try Migrator.decode(try fixture("session-v0.json"))
        let golden = try fixture("session-v1-golden.json")
        #expect(try Migrator.encode(session) == golden)
        #expect(try Migrator.decode(golden) == (session, []))
    }
}

@Suite("§8 Migrator.decode")
struct DecodeTests {
    @Test("encode → decode is identity, including .unavailable records and every field")
    func roundTrip() throws {
        var s = twoWindows
        s.contents[1] = record(cid(2), state: Data([0xFF, 0x00]), availability: .unavailable)
        s.windows[0].activePane = pid(1)
        s.windows[0].focusModePane = pid(1)
        s.windows[0].placement = SavedPlacement(intendedFrame: CGRect(x: -1440.25, y: 12, width: 640, height: 480),
                                                displayID: "ext", relativeOrigin: CGPoint(x: 10, y: 0.5))
        let (decoded, normalizations) = try Migrator.decode(try Migrator.encode(s))
        #expect(decoded == s)
        #expect(normalizations.isEmpty)
    }

    @Test("Zero windows and an empty main window decode unchanged")
    func emptySessions() throws {
        #expect(try Migrator.decode(Migrator.encode(Session())) == (Session(), []))
        let empty = Session(windows: [mainWindow(1, nil)])
        #expect(try Migrator.decode(Migrator.encode(empty)) == (empty, []))
    }

    @Test("A missing `availability` key decodes as .hosted (§5 default)")
    func missingAvailabilityIsHosted() throws {
        var s = session(mainWindow(1, h(1, [p(1, 1), p(2, 2)])))
        s.contents[1].availability = .unavailable
        let data = editedJSON(s) { object in
            var records = object["contents"] as! [[String: Any]]
            for i in records.indices { records[i]["availability"] = nil }
            object["contents"] = records
        }
        #expect(!String(decoding: data, as: UTF8.self).contains("availability"))
        let (decoded, _) = try Migrator.decode(data)
        #expect(decoded.contents.map(\.availability) == [.hosted, .hosted])
    }

    @Test("Unknown keys are ignored")
    func unknownKeysIgnored() throws {
        let s = session(mainWindow(1, p(1, 1)))
        let data = editedJSON(s) { $0["futureField"] = ["x": 1] }
        #expect(try Migrator.decode(data) == (s, []))
    }

    // MARK: PersistenceError.unsupportedFutureVersion

    @Test("Future version → unsupportedFutureVersion", arguments: [2, 3, 99])
    func futureVersion(version: Int) {
        let data = editedJSON(session(mainWindow(1, p(1, 1)))) { $0["version"] = version }
        #expect(decodeError(data) == .unsupportedFutureVersion(version))
    }

    @Test("A future version is rejected before its body is read")
    func futureVersionWithUnknownBody() {
        #expect(decodeError(json(#"{"version": 2, "layout": "something new"}"#)) == .unsupportedFutureVersion(2))
    }

    // MARK: PersistenceError.unreadable

    @Test("Corrupt file → unreadable", arguments: [
        "", "{{", "not json", "[]", "42", "null",
        #"{"version": "1", "windows": [], "contents": []}"#,       // version not an integer
        #"{"version": null, "windows": [], "contents": []}"#,      // null is not a missing key
        #"{"version": 1.5, "windows": [], "contents": []}"#,
        #"{"version": 1, "contents": []}"#,                        // v1 without windows
        #"{"version": 1, "windows": []}"#,                         // v1 without contents
        #"{"version": 1, "windows": [{"id": {"raw": "not-a-uuid"}}], "contents": []}"#,
    ])
    func corrupt(text: String) {
        #expect(isUnreadable(decodeError(json(text))), "\(text)")
    }

    @Test("Truncated file → unreadable")
    func truncated() {
        let data = encoded(twoWindows)
        #expect(isUnreadable(decodeError(data.prefix(data.count / 2))))
    }

    @Test("Bad base64 state, unknown availability or window kind → unreadable")
    func badValues() {
        let s = session(mainWindow(1, p(1, 1)))
        let badState = editedJSON(s) { object in
            var records = object["contents"] as! [[String: Any]]
            records[0]["state"] = "%%% not base64"
            object["contents"] = records
        }
        #expect(isUnreadable(decodeError(badState)))
        let badAvailability = editedJSON(s) { object in
            var records = object["contents"] as! [[String: Any]]
            records[0]["availability"] = "maybe"
            object["contents"] = records
        }
        #expect(isUnreadable(decodeError(badAvailability)))
        let badKind = editedJSON(s) { object in
            var windows = object["windows"] as! [[String: Any]]
            windows[0]["kind"] = "floating"
            object["windows"] = windows
        }
        #expect(isUnreadable(decodeError(badKind)))
    }

    // MARK: PersistenceError.migrationFailed

    @Test("Explicit version below 1 → migrationFailed (v0 has no version key)", arguments: [0, -1])
    func versionBelowOne(version: Int) {
        let data = json(#"{"version": \#(version), "root": null, "contents": []}"#)
        #expect(migrationFailedFrom(decodeError(data)) == version)
    }

    @Test("A v0 file that doesn't match the v0 schema → migrationFailed(from: 0)", arguments: [
        #"{}"#,                                                     // no contents
        #"{"root": null}"#,
        #"{"root": null, "contents": [{"id": {"raw": "04000000-0000-4000-8000-000000000001"}}]}"#,
        #"{"root": {"leaf": {}}, "contents": []}"#,
        #"{"windows": [], "contents": {}}"#,                        // a v1-like body without its version key
    ])
    func v0SchemaMismatch(text: String) {
        #expect(migrationFailedFrom(decodeError(json(text))) == 0, "\(text)")
    }

    @Test("A chain step that doesn't exist → migrationFailed")
    func missingChainStep() {
        do throws(PersistenceError) {
            _ = try Migrator.migrate(Data(), from: Migrator.currentVersion)
            Issue.record("expected migrationFailed")
        } catch {
            #expect(migrationFailedFrom(error) == Migrator.currentVersion)
        }
    }
}

@Suite("§8 v0 → v1 migration")
struct MigrationTests {
    @Test("The committed v0 fixture has no version key and migrates to the §8 v1 shape")
    func fixtureMigrates() throws {
        let data = try fixture("session-v0.json")
        let object = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(object["version"] == nil)
        #expect(Set(object.keys) == ["root", "contents"])

        let (session, normalizations) = try Migrator.decode(data)
        #expect(session == migratedV0)
        #expect(normalizations.isEmpty)
        #expect(session.version == Session.currentVersion)
        #expect(SessionEngine.validate(session).isEmpty)
    }

    @Test("Migration is pure: the same v0 bytes always give byte-identical v1 output")
    func reproducible() throws {
        let data = try fixture("session-v0.json")
        let a = try Migrator.encode(Migrator.decode(data).0)
        let b = try Migrator.encode(Migrator.decode(data).0)
        #expect(a == b)
        #expect(try Migrator.decode(a) == (migratedV0, []))
    }

    @Test("Migrated placement resolves centred on the main display (§8 → §9)")
    func migratedPlacementIsCentred() {
        let laptop = DisplaySnapshot(id: "laptop", frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
                                     visibleFrame: CGRect(x: 0, y: 0, width: 1512, height: 950), scale: 2, isMain: true)
        let frame = DisplayPlacement.resolve(migratedV0.windows[0].placement, minSize: .zero, displays: [laptop])
        #expect(frame == CGRect(x: 156, y: 75, width: 1200, height: 800))
    }

    @Test("A v0 empty state (root null) becomes an empty main window")
    func v0EmptyState() throws {
        let (session, normalizations) = try Migrator.decode(json(#"{"root": null, "contents": []}"#))
        #expect(session.windows.count == 1)
        #expect(session.windows[0].kind == .main && session.windows[0].root == nil)
        #expect(session.windows[0].id == V0.mainWindowID)
        #expect(session.contents.isEmpty && normalizations.isEmpty)
        // A missing root key is the same as null (LayoutNode? in the v0 schema).
        #expect(try Migrator.decode(json(#"{"contents": []}"#)).0 == session)
    }

    @Test("A v0 orphan record is dropped after migration and reported")
    func v0Orphan() throws {
        let text = #"{"root": null, "contents": [{"id": {"raw": "04000000-0000-4000-8000-000000000009"}, "type": {"raw": "splitkit.test"}, "stateVersion": 1, "state": ""}]}"#
        let (session, normalizations) = try Migrator.decode(json(text))
        #expect(session.contents.isEmpty)
        #expect(normalizations == [.droppedOrphanRecord(cid(9))])
    }

    @Test("A v0 file with a fatal violation throws invalid after migration")
    func v0Fatal() {
        let text = #"{"root": {"pane": {"id": {"raw": "01000000-0000-4000-8000-000000000001"}, "content": {"raw": "04000000-0000-4000-8000-000000000001"}}}, "contents": []}"#
        #expect(decodeError(json(text)) == .invalid([.missingContentRecord(cid(1))]))
    }
}

/// One fatal violation per case, with the exact list `decode` must throw.
private struct FatalCase: CustomTestStringConvertible, Sendable {
    let name: String
    let session: Session
    let expected: [InvariantViolation]
    var testDescription: String { name }
}

private let fatalCases: [FatalCase] = [
    FatalCase(name: "duplicatePaneID", session: session(mainWindow(1, h(1, [p(1, 1), p(1, 2)]))),
              expected: [.duplicatePaneID(pid(1))]),
    FatalCase(name: "duplicateSplitID", session: session(mainWindow(1, h(1, [p(1, 1), v(1, [p(2, 2), p(3)])]))),
              expected: [.duplicateSplitID(sid(1))]),
    FatalCase(name: "duplicateWindowID", session: session(mainWindow(1, p(1, 1)), detachedWindow(1, p(2, 2))),
              expected: [.duplicateWindowID(wid(1))]),
    FatalCase(name: "duplicateContentID",
              session: Session(windows: [mainWindow(1, h(1, [p(1, 1), p(2, 1)]))], contents: [record(cid(1))]),
              expected: [.duplicateContentID(cid(1))]),
    FatalCase(name: "duplicateRecord",
              session: Session(windows: [mainWindow(1, p(1, 1))], contents: [record(cid(1)), record(cid(1))]),
              expected: [.duplicateRecord(cid(1))]),
    FatalCase(name: "missingContentRecord", session: Session(windows: [mainWindow(1, p(1, 1))], contents: []),
              expected: [.missingContentRecord(cid(1))]),
    FatalCase(name: "singleChildSplit", session: session(mainWindow(1, h(1, [p(1, 1)], [1]))),
              expected: [.singleChildSplit(sid(1))]),
    FatalCase(name: "fractionCountMismatch", session: session(mainWindow(1, h(1, [p(1, 1), p(2)], [1]))),
              expected: [.fractionCountMismatch(sid(1))]),
    FatalCase(name: "badFractions (sum)", session: session(mainWindow(1, h(1, [p(1, 1), p(2)], [0.5, 0.6]))),
              expected: [.badFractions(sid(1))]),
    FatalCase(name: "badFractions (≤ 0)", session: session(mainWindow(1, h(1, [p(1, 1), p(2)], [1.5, -0.5]))),
              expected: [.badFractions(sid(1))]),
    FatalCase(name: "sameAxisNesting", session: session(mainWindow(1, h(1, [p(1, 1), h(2, [p(2), p(3)])]))),
              expected: [.sameAxisNesting(sid(2))]),
    FatalCase(name: "nilRootInDetachedWindow", session: session(mainWindow(1, p(1, 1)), detachedWindow(2, nil)),
              expected: [.nilRootInDetachedWindow(wid(2))]),
    FatalCase(name: "detachedWindowWithoutContent", session: session(mainWindow(1, p(1, 1)), detachedWindow(2, p(2))),
              expected: [.detachedWindowWithoutContent(wid(2))]),
    FatalCase(name: "multipleMainWindows", session: session(mainWindow(1, p(1, 1)), mainWindow(2, p(2, 2))),
              expected: [.multipleMainWindows]),
]

@Suite("§8 fatal vs recoverable validation on load")
struct LoadValidationTests {
    @Test("Every fatal InvariantViolation throws invalid with exactly that violation", arguments: fatalCases)
    fileprivate func fatalThrows(c: FatalCase) {
        #expect(SessionEngine.validate(c.session) == c.expected)
        #expect(decodeError(encoded(c.session)) == .invalid(c.expected))
    }

    @Test("Every fatal case of InvariantViolation is covered")
    func allFatalCasesCovered() {
        let names = Set(fatalCases.flatMap(\.expected).map { String(describing: $0).prefix { $0 != "(" } })
        #expect(names == ["duplicatePaneID", "duplicateSplitID", "duplicateWindowID", "duplicateContentID", "duplicateRecord",
                          "missingContentRecord", "singleChildSplit", "fractionCountMismatch", "badFractions",
                          "sameAxisNesting", "nilRootInDetachedWindow", "detachedWindowWithoutContent", "multipleMainWindows"])
    }

    @Test("Orphan record → dropped, reported as droppedOrphanRecord")
    func orphanDropped() throws {
        var s = session(mainWindow(1, h(1, [p(1, 1), p(2)])))
        s.contents.insert(record(cid(8)), at: 0)
        s.contents.append(record(cid(9)))
        let (decoded, normalizations) = try Migrator.decode(encoded(s))
        #expect(decoded.contents.map(\.id) == [cid(1)])
        #expect(decoded.windows == s.windows)
        #expect(normalizations == [.droppedOrphanRecord(cid(8)), .droppedOrphanRecord(cid(9))])
    }

    @Test("Dangling activePane → cleared, reported as clearedActivePane")
    func danglingActive() throws {
        let s = session(mainWindow(1, p(1, 1), active: 7, focus: 1))
        let (decoded, normalizations) = try Migrator.decode(encoded(s))
        #expect(decoded.windows[0].activePane == nil)
        #expect(decoded.windows[0].focusModePane == pid(1))
        #expect(normalizations == [.clearedActivePane(wid(1))])
    }

    @Test("Dangling focusModePane → cleared, reported as clearedFocusModePane")
    func danglingFocus() throws {
        let s = session(mainWindow(1, p(1, 1), active: 1, focus: 7))
        let (decoded, normalizations) = try Migrator.decode(encoded(s))
        #expect(decoded.windows[0].activePane == pid(1))
        #expect(decoded.windows[0].focusModePane == nil)
        #expect(normalizations == [.clearedFocusModePane(wid(1))])
    }

    @Test("A pane in another window is dangling; an empty main window's focus is dangling")
    func danglingAcrossWindows() throws {
        let s = session(mainWindow(1, nil, active: 2, focus: 2), detachedWindow(2, p(2, 2), active: 2))
        let (decoded, normalizations) = try Migrator.decode(encoded(s))
        #expect(decoded.windows[0].activePane == nil && decoded.windows[0].focusModePane == nil)
        #expect(decoded.windows[1].activePane == pid(2))
        #expect(normalizations == [.clearedActivePane(wid(1)), .clearedFocusModePane(wid(1))])
    }

    @Test("All recoverable violations at once: repaired in validate order, result is valid")
    func allRecoverable() throws {
        var s = session(mainWindow(1, h(1, [p(1, 1), p(2)]), active: 5, focus: 6), detachedWindow(2, p(3, 3), focus: 9))
        s.contents.append(record(cid(4)))
        let (decoded, normalizations) = try Migrator.decode(encoded(s))
        #expect(normalizations == [.clearedActivePane(wid(1)), .clearedFocusModePane(wid(1)),
                                   .clearedFocusModePane(wid(2)), .droppedOrphanRecord(cid(4))])
        #expect(SessionEngine.validate(decoded).isEmpty)
        // Decoding the repaired session again reports nothing.
        #expect(try Migrator.decode(encoded(decoded)) == (decoded, []))
    }

    @Test("Fatal plus recoverable → invalid lists only the fatal ones; nothing is repaired")
    func fatalWinsOverRecoverable() {
        var s = session(mainWindow(1, h(1, [p(1, 1), p(2)], [0.9, 0.9]), active: 7), detachedWindow(2, p(3)))
        s.contents.append(record(cid(5)))
        #expect(SessionEngine.validate(s).contains(.orphanRecord(cid(5))))
        #expect(decodeError(encoded(s)) == .invalid([.badFractions(sid(1)), .detachedWindowWithoutContent(wid(2))]))
    }

    @Test("Several fatal violations are all listed, in validate order")
    func severalFatal() {
        let s = Session(windows: [mainWindow(1, h(1, [p(1, 1), p(1, 2)], [0.5])), mainWindow(2, nil)], contents: [record(cid(1))])
        #expect(decodeError(encoded(s)) == .invalid([.multipleMainWindows, .fractionCountMismatch(sid(1)),
                                                     .duplicatePaneID(pid(1)), .missingContentRecord(cid(2))]))
    }
}
