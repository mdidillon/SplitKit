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
    /// An item's keyboard shortcut is live only while its pane is active (spec §7.4, §7.5).
    @ViewBuilder
    fileprivate func paneShortcut(_ shortcut: KeyboardShortcut?, isActive: Bool) -> some View {
        if isActive, let shortcut {
            keyboardShortcut(shortcut)
        } else {
            self
        }
    }
}

/// One toolbar item in the header row: icon-only when it has a `systemImage` (the title stays its tooltip
/// and VoiceOver label), otherwise its title text (Docs/Design.md §6).
struct PaneToolbarItemView: View {
    let item: PaneToolbarItem
    let isActive: Bool

    var body: some View {
        content
            .disabled(!item.isEnabled)
            .help(item.title)
            .paneShortcut(item.keyboardShortcut, isActive: isActive)
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
                PaneToolbarMenuEntries(items: items, isActive: false)
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
struct PaneToolbarMenuEntries: View {
    let items: [PaneToolbarItem]
    let isActive: Bool

    var body: some View {
        ForEach(items) { item in
            entry(item)
                .disabled(!item.isEnabledInOverflow)
                .paneShortcut(item.keyboardShortcut, isActive: isActive)
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
                PaneToolbarMenuEntries(items: items, isActive: isActive)
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
    let isActive: Bool
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
            ForEach(items(layout.visible)) { PaneToolbarItemView(item: $0, isActive: isActive) }
            if !layout.overflow.isEmpty {
                overflowMenu(items(layout.overflow), isActive: isActive)
            }
        }
    }

    private func overflowMenu(_ items: [PaneToolbarItem], isActive: Bool) -> some View {
        Menu {
            PaneToolbarMenuEntries(items: items, isActive: isActive)
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
                PaneToolbarItemView(item: item, isActive: false)
                    .fixedSize()
                    .onGeometryChange(for: CGFloat.self, of: { $0.size.width }, action: { itemWidths[item.id] = $0 })
            }
            overflowMenu(items, isActive: false)
                .fixedSize()
                .onGeometryChange(for: CGFloat.self, of: { $0.size.width }, action: { overflowWidth = $0 })
        }
        .hidden()
        .allowsHitTesting(false)
    }
}
