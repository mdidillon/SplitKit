import AppKit
import SwiftUI
import SplitKit
import SplitKitContent
import ImageViewer
import ModelViewer3D

@main
struct SplitKitTestApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate

    var body: some Scene {
        // SplitKit owns the workspace windows (.splitKit mode); this is the only SwiftUI scene.
        Window("Glass & Accessibility Check", id: GlassVerificationCommands.windowID) {
            GlassVerificationView()
        }
        .defaultLaunchBehavior(.suppressed)
        .commands {
            SplitKitCommands(delegate.workspace)
            GlassVerificationCommands()
        }
    }
}

/// Creates the workspace (colour and counter contents, `.splitKit` windows, the session file at its
/// default location), restores it at launch, saves it at quit (at most 2 s, spec §8) and keeps the app
/// running without windows (spec §6.3.5).
///
/// Launch argument `-SplitKitPersistenceDisabled YES` runs with persistence `.disabled`: no session is
/// read or written, so every launch starts from the default layout. `-SplitKitPlainStyle YES` shows the
/// `.plain` styles and `SplitKitTokens.plain` in every window (through `SplitKitConfiguration.windowContent`);
/// the default is `.glass`.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static let persistenceDisabledKey = "SplitKitPersistenceDisabled"
    static let plainStyleKey = "SplitKitPlainStyle"

    let workspace: SplitKitWorkspace

    override init() {
        let registry = ContentRegistry()
        do {
            try registry.register(ColorContent.self)
            try registry.register(CounterContent.self)
        } catch {
            preconditionFailure("registering the dummy contents failed: \(error)")
        }
        let disabled = UserDefaults.standard.bool(forKey: Self.persistenceDisabledKey)
        var configuration = SplitKitConfiguration(persistence: disabled ? .disabled : .file(.applicationSupportDefault))
        if UserDefaults.standard.bool(forKey: Self.plainStyleKey) {
            configuration.windowContent = { content in
                AnyView(content
                    .paneHeaderStyle(.plain)
                    .paneDividerStyle(.plain)
                    .emptyPaneStyle(.plain)
                    .splitKitTokens(.plain))
            }
        }
        do {
            workspace = try SplitKitWorkspace(registry: registry, configuration: configuration)
        } catch {
            preconditionFailure("the default session location is not a file URL: \(error)")
        }
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let report = workspace.restoreOrOpenDefault()
        print("SplitKitTestApp restore: \(report)")
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        Task {
            await workspace.saveBeforeQuit()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    /// A click on the Dock icon with no window open does File ▸ New Window.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if !hasVisibleWindows { Task { try? await workspace.perform(.newWindow) } }
        return true
    }
}

struct GlassVerificationCommands: Commands {
    static let windowID = "glass-verification"
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(after: .windowArrangement) {
            Button("Glass & Accessibility Check") { openWindow(id: Self.windowID) }
                .keyboardShortcut("g", modifiers: [.command, .option])
        }
    }
}
