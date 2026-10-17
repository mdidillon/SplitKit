import SwiftUI

/// One content toolbar entry (§7.4). Content declares items; SplitKit lays them out by priority, then declaration order.
public struct PaneToolbarItem: Identifiable {
    public enum Kind {
        case button(action: @MainActor () -> Void)
        case toggle(isOn: Binding<Bool>)
        case menu(items: [PaneToolbarItem])
        case custom(minWidth: CGFloat, view: AnyView)        // optional in milestone 1; requires title + fallback action
    }
    public enum Priority: Int, Comparable {
        case low, normal, high

        public static func < (lhs: Priority, rhs: Priority) -> Bool { lhs.rawValue < rhs.rawValue }
    }
    public let id: String
    public var title: String                                 // required: accessibility label, tooltip, overflow label
    public var systemImage: String?
    public var kind: Kind
    public var priority: Priority = .normal
    public var isEnabled: Bool = true
    public var keyboardShortcut: KeyboardShortcut? = nil
    public var fallbackAction: (@MainActor () -> Void)? = nil // used when .custom collapses into overflow

    /// The memberwise initialiser the §5 declaration implies, made public with the §5 defaults.
    public init(
        id: String,
        title: String,
        systemImage: String? = nil,
        kind: Kind,
        priority: Priority = .normal,
        isEnabled: Bool = true,
        keyboardShortcut: KeyboardShortcut? = nil,
        fallbackAction: (@MainActor () -> Void)? = nil
    ) {
        self.id = id
        self.title = title
        self.systemImage = systemImage
        self.kind = kind
        self.priority = priority
        self.isEnabled = isEnabled
        self.keyboardShortcut = keyboardShortcut
        self.fallbackAction = fallbackAction
    }
}
