import AppKit
import ImageIO
import Observation
import SwiftUI
import UniformTypeIdentifiers
import SplitKitContent
import SplitKitModel

/// Display-only image pane (spec §10): the image aspect-fit, no zoom, pan or rotation, no toolbar items.
///
/// Opens a file through `init(url:)` (picker file panel or a dropped image) and restores from its saved
/// state, the file's absolute path as JSON (`stateVersion` 1). Both go through one loader, which decodes the
/// image eagerly, so a file that can't be displayed never produces an object:
/// - an extension that is not an image type → `.unsupportedFile`
/// - a missing, unreadable or corrupt file → `.unreadable` (on restore too, which makes SplitKit show its
///   "couldn't be restored" placeholder)
/// - neither a url nor a saved state → `.other`: there is nothing to show.
@MainActor @Observable
public final class ImageViewerContent: PaneContent {
    public static let type = ContentType(raw: "com.mdidillon.splitkit.image")
    public static let displayName = "Image"
    public static let systemImage = "photo"
    public static let minimumSize = CGSize.zero             // SplitKitConfiguration.minimumPaneSize applies
    public static let stateVersion = 1

    /// The file types the viewer opens; what `register(in:)` passes as `accepts`.
    public static let acceptedTypes: [UTType] = [.image]

    /// Registers the viewer with the file types it opens (picker file panel, Finder drops).
    public static func register(in registry: ContentRegistry) throws(RegistryError) {
        try registry.register(self, accepts: acceptedTypes)
    }

    private struct State: Codable { var path: String }

    public let fileURL: URL
    private let image: NSImage

    public init(id: ContentID, url: URL?, restoring state: Data?, stateVersion: Int?) throws(ContentError) {
        let file: URL
        if let url {
            file = url
        } else if let state {
            guard stateVersion == Self.stateVersion, let decoded = try? JSONDecoder().decode(State.self, from: state) else {
                throw .stateIncompatible(version: stateVersion ?? 0)
            }
            file = URL(fileURLWithPath: decoded.path)
        } else {
            throw .other("ImageViewer needs an image file")
        }
        fileURL = file
        image = try Self.load(file)
    }

    public var title: String { fileURL.lastPathComponent }
    public var toolbarItems: [PaneToolbarItem] { [] }

    public func makeView() -> AnyView { AnyView(ImageViewerView(image: image, label: title)) }
    public func encodeState() throws -> Data { try JSONEncoder().encode(State(path: fileURL.standardizedFileURL.path)) }
    public func shouldClose() async -> Bool { true }
    public func willRelease() {}

    private static func load(_ url: URL) throws(ContentError) -> NSImage {
        guard let type = UTType(filenameExtension: url.pathExtension), type.conforms(to: .image) else {
            throw .unsupportedFile(url, reason: "not an image file")
        }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), CGImageSourceGetCount(source) > 0,
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw .unreadable(url)
        }
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }
}

private struct ImageViewerView: View {
    let image: NSImage
    let label: String

    var body: some View {
        Image(nsImage: image)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityLabel(label)
    }
}
