import SwiftUI
import SplitKitContent
import SplitKitModel

/// An add or replace that failed in the content picker or a file drop (spec §6.5; Docs/Design.md §7
/// "Creation error"): where to show it and what it says. The layout is unchanged.
struct CreationFailure: Equatable {
    enum Site: Equatable {
        case pane(PaneID)
        case window(WindowID)
    }

    var site: Site
    var message: String
}

extension SplitKitWorkspace {
    /// The failure of an insert at `target`, shown in the target's pane, or in the main window for an empty window.
    func failure(_ error: RegistryError, at target: ContentPicker.Target) -> CreationFailure? {
        let site: CreationFailure.Site
        switch target {
        case .none: return nil
        case .emptyWindow:
            guard let main = mainWindow else { return nil }
            site = .window(main)
        case let .emptyPane(pane), let .besides(pane, _), let .replacing(pane):
            site = .pane(pane)
        }
        return CreationFailure(site: site, message: ChromeText.creationFailed(error))
    }
}

/// The inline, dismissible message over the bottom of a pane body or an empty window (Docs/Design.md §7).
/// Shows only the failure of `site`; the content below keeps its layout.
struct CreationFailureBanner: ViewModifier {
    let workspace: SplitKitWorkspace
    let site: CreationFailure.Site

    @Environment(\.splitKitTokens) private var tokens
    private typealias Constants = SplitKitStyleConstants

    func body(content: Content) -> some View {
        content.overlay(alignment: .bottom) {
            if let failure = workspace.creationFailure, failure.site == site {
                HStack(spacing: Constants.errorMessagePadding) {
                    Image(systemName: Constants.Symbols.creationError)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    Text(failure.message)
                        .font(Constants.Typography.errorMessage)
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button {
                        workspace.creationFailure = nil
                    } label: {
                        Image(systemName: Constants.Symbols.close)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(Constants.Accessibility.dismissErrorLabel)
                }
                .padding(Constants.errorMessagePadding)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: tokens.metrics.cornerRadius, style: .continuous))
                .padding(Constants.errorMessagePadding)
                .accessibilityElement(children: .contain)
                .transition(.opacity)
            }
        }
        .animation(Constants.animation, value: workspace.creationFailure)
    }
}

extension View {
    /// Shows the workspace's `creationFailure` over this view when it belongs to `site`.
    func creationFailureBanner(_ workspace: SplitKitWorkspace, at site: CreationFailure.Site) -> some View {
        modifier(CreationFailureBanner(workspace: workspace, site: site))
    }
}
