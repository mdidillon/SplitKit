import SwiftUI
import SplitKitContent
import SplitKitModel

/// The content picker (spec §7.1): the registered types in registry order, and what choosing one does.
/// Every Add Content (empty pane, empty window, pane menu, later the menu bar) is this one type; they
/// differ only in `Target`.
struct ContentPicker {
    enum Target: Equatable {
        /// The empty main window.
        case emptyWindow
        /// The empty pane.
        case emptyPane(PaneID)
        /// A new pane at `edge` of an occupied pane.
        case besides(PaneID, DropEdge)
    }

    struct Entry: Equatable {
        let type: ContentType
        let displayName: String
        let systemImage: String
    }

    let target: Target
    /// The registered content types, in registration order.
    let entries: [Entry]
    /// A two-stage close is waiting for the target's pane or window: nothing can be added (spec §6.3).
    let isPending: Bool

    /// Adding needs a registered type and a target that is not closing.
    var isEnabled: Bool { !isPending && !entries.isEmpty }

    /// Inserts a new `type` at the target. Failures leave the workspace unchanged (spec §6.2).
    @MainActor func choose(_ type: ContentType, in workspace: SplitKitWorkspace) async {
        guard isEnabled else { return }
        switch target {
        case .emptyWindow:
            try? await workspace.addContent(type, url: nil, into: nil)
        case let .emptyPane(pane):
            try? await workspace.addContent(type, url: nil, into: pane)
        case let .besides(pane, edge):
            try? await workspace.addContent(type, besides: pane, edge: edge)
        }
    }
}

extension SplitKitWorkspace {
    func contentPicker(for target: ContentPicker.Target) -> ContentPicker {
        let isPending = switch target {
        case .emptyWindow: mainWindow.map(isClosing(window:)) ?? false
        case let .emptyPane(pane), let .besides(pane, _): isClosing(pane: pane)
        }
        return ContentPicker(
            target: target,
            entries: registry.registeredTypes.compactMap { type in
                registry.metadata(for: type).map {
                    ContentPicker.Entry(type: type, displayName: $0.displayName, systemImage: $0.systemImage)
                }
            },
            isPending: isPending)
    }
}

/// One button per type, symbol and display name. Shown in the pane menu and in the picker popover.
struct ContentPickerButtons: View {
    let workspace: SplitKitWorkspace
    let picker: ContentPicker
    var onChoose: () -> Void = {}

    var body: some View {
        ForEach(picker.entries, id: \.type) { entry in
            Button {
                onChoose()
                Task { await picker.choose(entry.type, in: workspace) }
            } label: {
                Label(entry.displayName, systemImage: entry.systemImage)
            }
            .disabled(!picker.isEnabled)
        }
    }
}

extension View {
    /// The picker as a popover on this view (Add Content in an empty pane or window).
    func contentPicker(_ picker: ContentPicker, in workspace: SplitKitWorkspace, isPresented: Binding<Bool>) -> some View {
        popover(isPresented: isPresented) {
            VStack(alignment: .leading) {
                ContentPickerButtons(workspace: workspace, picker: picker) { isPresented.wrappedValue = false }
            }
            .buttonStyle(.borderless)
            .padding()
        }
    }
}
