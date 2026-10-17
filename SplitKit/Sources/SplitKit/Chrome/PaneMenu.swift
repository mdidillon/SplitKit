import SwiftUI
import SplitKitContent
import SplitKitModel

/// What the pane menu offers for one pane and what each entry does (spec §7.1). The title ▾ and the
/// right-click menu both render this model through `PaneMenu`; the actions only call existing workspace
/// commands.
struct PaneMenuModel {
    enum Action: Equatable {
        /// A new content of this type: in the pane when it is empty, otherwise in a new pane to its right.
        case addContent(ContentType)
        case split(DropEdge)
        /// Phase 3: always disabled until then.
        case detach
        /// Phase 3: always disabled until then.
        case moveToWindow
        case close
    }

    struct TypeEntry: Equatable {
        let type: ContentType
        let displayName: String
        let systemImage: String
    }

    let pane: PaneID
    let isEmpty: Bool
    /// A two-stage close is waiting for this pane: every action that touches it is disabled (spec §6.3).
    let isPending: Bool
    /// The registered content types, in registration order.
    let types: [TypeEntry]

    /// Adding needs a registered type and a pane that is not closing.
    var canAdd: Bool { !isPending && !types.isEmpty }

    func isEnabled(_ action: Action) -> Bool {
        switch action {
        case .detach, .moveToWindow: false
        case .addContent: canAdd
        case .split, .close: !isPending
        }
    }

    /// Runs `action` if it is enabled. Failures leave the workspace unchanged (spec §6.2).
    @MainActor func run(_ action: Action, in workspace: SplitKitWorkspace) async {
        guard isEnabled(action) else { return }
        switch action {
        case let .addContent(type):
            if isEmpty {
                try? await workspace.addContent(type, url: nil, into: pane)
            } else {
                try? await workspace.addContent(type, besides: pane, edge: .right)
            }
        case let .split(edge):
            try? await workspace.perform(.split(pane, edge: edge))
        case .close:
            try? await workspace.perform(.closePane(pane))
        case .detach, .moveToWindow:
            break
        }
    }
}

extension SplitKitWorkspace {
    func paneMenuModel(for pane: PaneID, content: ContentID?) -> PaneMenuModel {
        PaneMenuModel(
            pane: pane, isEmpty: content == nil, isPending: runtime.pendingCloses.contains(pane),
            types: registry.registeredTypes.compactMap { type in
                registry.metadata(for: type).map {
                    PaneMenuModel.TypeEntry(type: type, displayName: $0.displayName, systemImage: $0.systemImage)
                }
            })
    }
}

/// The pane menu items (content picker part, Add, Split Right, Split Down, Detach, Move to Window, Close).
struct PaneMenu: View {
    let workspace: SplitKitWorkspace
    let model: PaneMenuModel

    var body: some View {
        if model.isEmpty {
            // The empty pane's title is "Add Content": its menu lists the types directly.
            addButtons
        } else {
            Menu(ChromeText.add) { addButtons }
                .disabled(!model.canAdd)
        }
        Divider()
        entry(ChromeText.splitRight, .split(.right))
        entry(ChromeText.splitDown, .split(.bottom))
        Divider()
        entry(ChromeText.detach, .detach)
        Menu(ChromeText.moveToWindow) {}
            .disabled(!model.isEnabled(.moveToWindow))
        Divider()
        entry(SplitKitStyleConstants.Accessibility.closeLabel, .close)
    }

    private var addButtons: some View {
        ForEach(model.types, id: \.type) { entry in
            Button {
                run(.addContent(entry.type))
            } label: {
                Label(entry.displayName, systemImage: entry.systemImage)
            }
            .disabled(!model.isEnabled(.addContent(entry.type)))
        }
    }

    private func entry(_ title: String, _ action: PaneMenuModel.Action) -> some View {
        Button(title) { run(action) }
            .disabled(!model.isEnabled(action))
    }

    private func run(_ action: PaneMenuModel.Action) {
        Task { await model.run(action, in: workspace) }
    }
}
