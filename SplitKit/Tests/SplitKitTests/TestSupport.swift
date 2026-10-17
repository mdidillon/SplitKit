import SwiftUI
@testable import SplitKit

/// A header configuration with test defaults; override only the state under test.
@MainActor
func headerConfiguration(title: String = "Counter", systemImage: String? = "number",
                         isActive: Bool = false, isHovered: Bool = false, isDropTarget: Bool = false,
                         isDraggedSource: Bool = false, isPendingClose: Bool = false, isEmpty: Bool = false,
                         isFocusMode: Bool = false,
                         toggleFocusMode: @escaping @MainActor () -> Void = {},
                         close: @escaping @MainActor () -> Void = {}) -> PaneHeaderConfiguration {
    PaneHeaderConfiguration(title: title, systemImage: systemImage, isActive: isActive, isHovered: isHovered,
                            isDropTarget: isDropTarget, isDraggedSource: isDraggedSource,
                            isPendingClose: isPendingClose, isEmpty: isEmpty, isFocusMode: isFocusMode,
                            menu: AnyView(Button("Split Right") {}), toolbar: AnyView(Button("Reset Camera") {}),
                            toggleFocusMode: toggleFocusMode, close: close)
}

/// An empty-pane configuration of `kind` with Add Content, or Restore + Close for the placeholder.
func emptyConfiguration(_ kind: EmptyPaneConfiguration.Kind) -> EmptyPaneConfiguration {
    switch kind {
    case .emptyPane, .emptyWindow:
        EmptyPaneConfiguration(kind: kind, title: "No Content", message: nil,
                               primaryAction: .init(title: "Add Content") {})
    case .unavailable:
        EmptyPaneConfiguration(kind: kind, title: nil, message: "Model isn't available in this app",
                               primaryAction: .init(title: "Restore", isEnabled: false) {},
                               secondaryAction: .init(title: "Close") {})
    }
}
