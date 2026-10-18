import Foundation
import SplitKitContent
import SplitKitModel
@testable import ModelViewer3D

/// The shared fixtures of the ModelViewer3D tests (Tests/Fixtures/Models/, licences in Tests/Fixtures/LICENSES.md).
enum Fixtures {
    static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "Fixtures/Models", directoryHint: .isDirectory)

    static func url(_ path: String) -> URL { root.appending(path: path) }
    static func exists(_ path: String) -> Bool { FileManager.default.fileExists(atPath: url(path).path) }

    static let box = "Box/glTF/Box.gltf"
    static let helmet = "DamagedHelmet/glTF-Binary/DamagedHelmet.glb"
    static let malformed = "Errors/malformed.gltf"
    static let fbx = "Errors/fake.fbx"
    static let missingBuffer = "Errors/missing-buffer.gltf"
    static let dracoBox = "Box/glTF-Draco/Box.gltf"
}

/// One machine-greppable line per measurement, summarised in spec §11.2 "P4 corpus results".
func record(_ fields: KeyValuePairs<String, String>) {
    print("P4B-RESULT " + fields.map { "\($0.key)=\($0.value)" }.joined(separator: " "))
}

/// A directory under the temporary directory that is removed when `body` returns.
nonisolated(nonsending) func withTemporaryDirectory<T>(_ body: (URL) async throws -> T) async throws -> T {
    let dir = FileManager.default.temporaryDirectory.appending(path: "ModelViewer3DTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    return try await body(dir)
}

@MainActor func makeViewer(url: URL?, state: Data? = nil, stateVersion: Int? = nil) throws(ContentError) -> ModelViewer3DContent {
    try ModelViewer3DContent(id: ContentID(raw: UUID()), url: url, restoring: state, stateVersion: stateVersion)
}

/// The `ContentError` `body` throws, or nil when it doesn't throw.
@MainActor func contentError(_ body: () throws(ContentError) -> Void) -> ContentError? {
    do { try body() } catch { return error }
    return nil
}

/// The `ModelLoadError` the preflight throws for `url`, or nil when the file passes.
func preflightError(_ url: URL) -> ModelLoadError? {
    do { _ = try GLTFPreflight.check(url: url) } catch { return error }
    return nil
}
