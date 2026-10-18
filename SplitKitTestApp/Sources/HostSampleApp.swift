import AppKit
import SwiftUI
import SplitKit
import SplitKitContent

/// The host-mode sample (spec §9, §11 P3): the host owns its main window (a SwiftUI `Window`) and embeds
/// `SplitKitView`; SplitKit only creates the detached windows. Persistence is `.disabled`, so every launch
/// starts from the default layout. Colour and Counter are registered, `SplitKitCommands` is installed.
@main
struct SplitKitHostSample: App {
    @State private var workspace = HostSampleApp.makeWorkspace()

    var body: some Scene {
        Window("SplitKit Host Sample", id: "main") {
            HostMainView(workspace: workspace)
        }
        .commands { SplitKitCommands(workspace) }
    }
}

/// The host's main window content: `SplitKitView` for the workspace's main window, which exists once the
/// default layout is open.
private struct HostMainView: View {
    let workspace: SplitKitWorkspace

    var body: some View {
        Group {
            if let main = workspace.mainWindow {
                SplitKitView(workspace: workspace, window: main)
            } else {
                Color.clear
            }
        }
        .frame(minWidth: 480, minHeight: 320)
    }
}

enum HostSampleApp {
    /// `.host(makeDetachedWindow: nil)`: SplitKit creates and places the detached windows itself.
    @MainActor static func makeWorkspace() -> SplitKitWorkspace {
        let registry = ContentRegistry()
        do {
            try registry.register(ColorContent.self)
            try registry.register(CounterContent.self)
            let workspace = try SplitKitWorkspace(
                registry: registry,
                configuration: SplitKitConfiguration(windowManagement: .host(makeDetachedWindow: nil), persistence: .disabled))
            print("SplitKitHostSample restore: \(workspace.restoreOrOpenDefault())")
            return workspace
        } catch {
            preconditionFailure("creating the host sample workspace failed: \(error)")
        }
    }
}
