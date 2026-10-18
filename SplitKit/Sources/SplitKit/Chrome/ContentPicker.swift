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
        /// Nowhere to add: a window with panes but no active pane.
        case none

        /// Where Add Content goes for `pane` (hosting `content`): into it when empty, otherwise into a new
        /// pane to its right. The one rule for the pane menu, the empty pane and the menu bar.
        static func adding(to pane: PaneID, hosting content: ContentID?) -> Target {
            content == nil ? .emptyPane(pane) : .besides(pane, .right)
        }
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
    var isEnabled: Bool { target != .none && !isPending && !entries.isEmpty }

    /// The type one step up (`-1`) or down (`1`) the list from `current`, stopping at the ends; with no
    /// current type, the first (down) or last (up). Nil without entries. Arrow keys in the type list.
    func moving(_ current: ContentType?, by step: Int) -> ContentType? {
        guard !entries.isEmpty else { return nil }
        guard let index = entries.firstIndex(where: { $0.type == current }) else {
            return entries[step > 0 ? 0 : entries.count - 1].type
        }
        return entries[min(max(index + step, 0), entries.count - 1)].type
    }

    /// Inserts a new `type` at the target. Failures leave the workspace unchanged (spec §6.2).
    @MainActor func choose(_ type: ContentType, in workspace: SplitKitWorkspace) async {
        guard isEnabled else { return }
        switch target {
        case .none:
            break
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
        case .none: false
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

/// One button per type, symbol and display name. Shown in the pane menu and in the picker popover, where
/// `highlighted` marks the type Return would choose.
struct ContentPickerButtons: View {
    let workspace: SplitKitWorkspace
    let picker: ContentPicker
    var highlighted: ContentType?
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
            .background { if highlighted == entry.type { Rectangle().fill(.selection) } }
        }
    }
}

/// The popover's type list: ↑ ↓ move the highlight, Return chooses it, Esc closes the popover.
private struct ContentPickerList: View {
    let workspace: SplitKitWorkspace
    let picker: ContentPicker
    let onChoose: () -> Void
    @State private var highlighted: ContentType?
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading) {
            ContentPickerButtons(workspace: workspace, picker: picker, highlighted: highlighted, onChoose: onChoose)
        }
        .buttonStyle(.borderless)
        .padding()
        .focusable()
        .focused($isFocused)
        .focusEffectDisabled()
        .onKeyPress(.upArrow) { highlighted = picker.moving(highlighted, by: -1); return .handled }
        .onKeyPress(.downArrow) { highlighted = picker.moving(highlighted, by: 1); return .handled }
        .onKeyPress(.return) {
            guard let highlighted else { return .ignored }
            onChoose()
            Task { await picker.choose(highlighted, in: workspace) }
            return .handled
        }
        .onAppear {
            highlighted = picker.entries.first?.type
            isFocused = true
        }
    }
}

extension View {
    /// The picker as a keyboard-navigable popover on this view (Add Content in an empty pane or window, and
    /// File ▸ Add Content…).
    func contentPicker(_ picker: ContentPicker, in workspace: SplitKitWorkspace, isPresented: Binding<Bool>) -> some View {
        popover(isPresented: isPresented) {
            ContentPickerList(workspace: workspace, picker: picker) { isPresented.wrappedValue = false }
        }
    }
}
