import AppKit
import SwiftUI

/// Structural census of one window's view hierarchy, used to prove "no residue".
public struct WindowResidue: Equatable, Sendable, CustomStringConvertible {
    public var title: String
    public var hostingViews = 0
    public var contentContainers = 0
    public var placeholders = 0
    public var highlights = 0
    public var hostedContents: [ContentID] = []
    public var totalViews = 0

    @MainActor public init(window: NSWindow) {
        title = window.title
        if let root = window.contentView { visit(root) }
    }

    @MainActor private mutating func visit(_ view: NSView) {
        // The shared field editor's subtree (insertion-point indicator etc.) churns on its own
        // while a text field is being edited; it is AppKit's, not ours, so it is not counted.
        if let editor = view as? NSTextView, editor.isFieldEditor { return }
        totalViews += 1
        switch view {
        case is NSHostingView<AnyView>: hostingViews += 1
        case let c as ContentHostContainer:
            contentContainers += 1
            hostedContents.append(c.contentID)
        case is DragPlaceholderView: placeholders += 1
        case is DropHighlightView: highlights += 1
        default: break
        }
        for sub in view.subviews { visit(sub) }
    }

    public var description: String {
        "\(title): hosting=\(hostingViews) containers=\(contentContainers) placeholders=\(placeholders) highlights=\(highlights) views=\(totalViews) contents=\(hostedContents)"
    }
}

public struct ResidueReport: Equatable, Sendable, CustomStringConvertible {
    public var windows: [WindowResidue]
    public var registrySnapshot: Data
    public var ledger: [String]
    public var attachmentCounts: [Int]

    public var description: String {
        (windows.map(\.description) + [
            "registry: " + (String(data: registrySnapshot, encoding: .utf8) ?? "?"),
            "ledger: \(ledger)",
            "attachmentCounts: \(attachmentCounts)",
        ]).joined(separator: "\n")
    }
}
