import SwiftUI
import SplitKitContent

private typealias Constants = SplitKitStyleConstants

extension PaneToolbarItem {
    /// In the overflow menu a `.custom` item acts through its `fallbackAction`; without one it is disabled (spec §7.4).
    var isEnabledInOverflow: Bool {
        guard isEnabled else { return false }
        if case .custom = kind { return fallbackAction != nil }
        return true
    }
}

extension View {
    /// `shortcut` as this view's keyboard shortcut, if there is one.
    @ViewBuilder
    func optionalKeyboardShortcut(_ shortcut: KeyboardShortcut?) -> some View {
        if let shortcut {
            keyboardShortcut(shortcut)
        } else {
            self
        }
    }
}

/// One toolbar item in the header row: icon-only when it has a `systemImage` (the title stays its tooltip
/// and VoiceOver label), otherwise its title text (Docs/Design.md §6). Its keyboard shortcut is registered
/// only by the menu bar's Pane ▸ ‹Content name› ▸ entries, which exist for the active pane alone (§7.4).
struct PaneToolbarItemView: View {
    let item: PaneToolbarItem

    var body: some View {
        content
            .disabled(!item.isEnabled)
            .help(item.title)
    }

    @ViewBuilder private var content: some View {
        switch item.kind {
        case let .button(action):
            Button(action: action) { label }
        case let .toggle(isOn):
            Toggle(isOn: isOn) { label }
                .toggleStyle(.button)
        case let .menu(items):
            Menu {
                PaneToolbarMenuEntries(items: items)
            } label: {
                label
            }
        case let .custom(minWidth, view):
            view
                .frame(minWidth: minWidth)
                .accessibilityElement(children: .contain)
                .accessibilityLabel(item.title)
        }
    }

    @ViewBuilder private var label: some View {
        if let systemImage = item.systemImage {
            Label(item.title, systemImage: systemImage).labelStyle(.iconOnly)
        } else {
            Text(item.title)
        }
    }
}

/// Toolbar items as menu entries: the overflow ⋯ menu and the submenu of a `.menu` item (spec §7.4).
/// `.button`, `.toggle` and `.menu` map one to one; `.custom` becomes its `title` + `fallbackAction`.
/// With `shortcuts` (the menu bar) the items register their keyboard shortcuts, except one that collides
/// with a SplitKit shortcut: that one loses (spec §7.4).
struct PaneToolbarMenuEntries: View {
    let items: [PaneToolbarItem]
    var shortcuts: ShortcutMap?

    var body: some View {
        ForEach(items) { item in
            entry(item)
                .disabled(!item.isEnabledInOverflow)
                .optionalKeyboardShortcut(shortcuts?.contentShortcut(item.keyboardShortcut, itemTitle: item.title))
        }
    }

    @ViewBuilder private func entry(_ item: PaneToolbarItem) -> some View {
        switch item.kind {
        case let .button(action):
            Button(action: action) { title(item) }
        case let .toggle(isOn):
            Toggle(isOn: isOn) { title(item) }
        case let .menu(items):
            Menu {
                PaneToolbarMenuEntries(items: items, shortcuts: shortcuts)
            } label: {
                title(item)
            }
        case .custom:
            Button { item.fallbackAction?() } label: { title(item) }
        }
    }

    @ViewBuilder private func title(_ item: PaneToolbarItem) -> some View {
        if let systemImage = item.systemImage {
            Label(item.title, systemImage: systemImage)
        } else {
            Text(item.title)
        }
    }
}

/// The header's flexible region (Docs/Design.md §6): the title pill, then the content toolbar items right-aligned
/// with the overflow ⋯ after them. It measures the title, items and ⋯ in hidden copies, asks
/// `PaneToolbarLayout` what fits and draws only that.
struct PaneToolbarRegion: View {
    let items: [PaneToolbarItem]
    let title: AnyView
    /// The look's treatment of the item group (its glass capsule); supplied by the header style.
    let decorateToolbar: (AnyView) -> AnyView

    @State private var available: CGFloat = .infinity
    @State private var titleWidth: CGFloat = 0
    @State private var overflowWidth: CGFloat = 0
    @State private var itemWidths: [String: CGFloat] = [:]

    var body: some View {
        HStack(spacing: Constants.headerItemSpacing) {
            if layout.title != .hidden {
                title.frame(maxWidth: truncatedWidth)
            }
            Spacer(minLength: 0)
            if !items.isEmpty {
                decorateToolbar(AnyView(toolbar))
            }
        }
        .frame(maxWidth: .infinity)
        .font(Constants.Typography.toolbarLabel)
        .onGeometryChange(for: CGFloat.self, of: { $0.size.width }, action: { available = $0 })
        .background(alignment: .leading) { measurement }
    }

    // MARK: Layout

    private var layout: PaneToolbarLayout {
        PaneToolbarLayout.arrange(
            entries: items.map { .init(id: $0.id, priority: $0.priority, width: itemWidths[$0.id] ?? 0) },
            available: available, titleWidth: titleWidth, titleMinWidth: Constants.headerTitleMinWidth,
            overflowWidth: overflowWidth, spacing: Constants.headerItemSpacing)
    }

    private var truncatedWidth: CGFloat? {
        if case let .truncated(width) = layout.title { width } else { nil }
    }

    private func items(_ ids: [String]) -> [PaneToolbarItem] {
        ids.compactMap { id in items.first { $0.id == id } }
    }

    // MARK: Views

    private var toolbar: some View {
        let layout = layout
        return HStack(spacing: Constants.headerItemSpacing) {
            ForEach(items(layout.visible)) { PaneToolbarItemView(item: $0) }
            if !layout.overflow.isEmpty {
                overflowMenu(items(layout.overflow))
            }
        }
    }

    private func overflowMenu(_ items: [PaneToolbarItem]) -> some View {
        Menu {
            PaneToolbarMenuEntries(items: items)
        } label: {
            Label(Constants.Accessibility.overflowLabel, systemImage: Constants.Symbols.overflow)
                .labelStyle(.iconOnly)
        }
        .help(Constants.Accessibility.overflowLabel)
    }

    /// Hidden natural-size copies: nothing here is drawn, focusable or announced.
    private var measurement: some View {
        HStack(spacing: 0) {
            title
                .fixedSize()
                .onGeometryChange(for: CGFloat.self, of: { $0.size.width }, action: { titleWidth = $0 })
            ForEach(items) { item in
                PaneToolbarItemView(item: item)
                    .fixedSize()
                    .onGeometryChange(for: CGFloat.self, of: { $0.size.width }, action: { itemWidths[item.id] = $0 })
            }
            overflowMenu(items)
                .fixedSize()
                .onGeometryChange(for: CGFloat.self, of: { $0.size.width }, action: { overflowWidth = $0 })
        }
        .hidden()
        .allowsHitTesting(false)
    }
}
