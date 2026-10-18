import Foundation
import UniformTypeIdentifiers
import SplitKitModel

public enum RegistryError: Error, Sendable {
    case duplicateType(ContentType)                          // registering the same type twice → thrown, first stays
    case unknownType(ContentType)                            // make() for an unregistered type
    case creationFailed(ContentType, ContentError)
}

@MainActor public final class ContentRegistry {
    /// Static metadata of a registered type, for the SplitKit UI target (headers, picker, placeholders, minimum size,
    /// snapshot `stateVersion`). `package`, not `public`: the UI target lives in this package, so §5 gains no API.
    package struct Metadata: Sendable {
        package let type: ContentType
        package let displayName: String
        package let systemImage: String
        package let minimumSize: CGSize
        package let stateVersion: Int
        /// The file types the content opens; empty for a type that is not file-based (picker and Finder drops, §7.1, §9).
        package let accepts: [UTType]
    }

    private struct Entry {
        let metadata: Metadata
        let accepts: [UTType]
        let create: @MainActor (ContentID, URL?, Data?, Int?) throws(ContentError) -> any PaneContent
    }

    private var entries: [Entry] = []                        // registration order

    public init() {}

    public func register<C: PaneContent>(_ type: C.Type, accepts: [UTType] = []) throws(RegistryError) {
        let contentType = C.type
        guard !entries.contains(where: { $0.metadata.type == contentType }) else {
            throw .duplicateType(contentType)
        }
        entries.append(Entry(
            metadata: Metadata(
                type: contentType,
                displayName: C.displayName,
                systemImage: C.systemImage,
                minimumSize: C.minimumSize,
                stateVersion: C.stateVersion,
                accepts: accepts
            ),
            accepts: accepts,
            create: { (id, url, state, stateVersion) throws(ContentError) -> any PaneContent in
                try C(id: id, url: url, restoring: state, stateVersion: stateVersion)
            }
        ))
    }

    public var registeredTypes: [ContentType] { entries.map(\.metadata.type) }

    /// Matches by file extension only (no file system access), so the answer is deterministic. A type matches when the
    /// extension's `UTType` conforms to one of its `accepts`; the first registered match wins.
    public func type(for url: URL) -> ContentType? {
        guard let fileType = UTType(filenameExtension: url.pathExtension) else { return nil }
        return entries.first { entry in entry.accepts.contains { fileType.conforms(to: $0) } }?.metadata.type
    }

    /// Forwards `url` to `init`, which validates it; a `ContentError` thrown there becomes `.creationFailed` (spec §5, §6.5).
    public func make(_ type: ContentType, id: ContentID, url: URL?, state: Data?, stateVersion: Int?) throws(RegistryError) -> any PaneContent {
        guard let entry = entries.first(where: { $0.metadata.type == type }) else { throw .unknownType(type) }
        do {
            return try entry.create(id, url, state, stateVersion)
        } catch {
            throw .creationFailed(type, error)
        }
    }

    package func metadata(for type: ContentType) -> Metadata? {
        entries.first { $0.metadata.type == type }?.metadata
    }
}
