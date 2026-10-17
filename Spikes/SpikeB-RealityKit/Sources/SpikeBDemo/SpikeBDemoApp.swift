import AppKit
import RealityKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Needed when launched with `swift run` (no app bundle) to get a Dock icon and key window.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
    }
}

@main
struct SpikeBDemoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = ViewerModel()

    var body: some SwiftUI.Scene {
        WindowGroup("Spike B — GLTFKit2 → RealityKit") {
            ViewerView(model: model)
                .frame(minWidth: 640, minHeight: 480)
                .task {
                    // `swift run SpikeBDemo <file>` opens a file directly.
                    if let path = CommandLine.arguments.dropFirst().first {
                        model.open(url: URL(fileURLWithPath: path))
                    }
                }
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open…") { model.presentOpenPanel() }
                    .keyboardShortcut("o")
            }
            CommandMenu("Camera") {
                Button("Reset Camera") { model.resetCamera() }
                    .keyboardShortcut("0")
            }
        }
    }
}

struct ViewerView: View {
    @Bindable var model: ViewerModel

    var body: some View {
        ZStack {
            RealityView { content in
                content.add(model.sceneRoot)
            } update: { content in
                content.cameraTarget = model.modelContainer
            }
            .realityViewCameraControls(model.mode.nativeControls)
            .id(model.nativeResetToken)

            if model.mode == .custom {
                CameraInputView(model: model)
            }

            if let error = model.errorMessage {
                ContentUnavailableView("Can’t open \(model.fileName ?? "file")",
                                       systemImage: "exclamationmark.triangle",
                                       description: Text(error))
                    .background(.regularMaterial)
            }
        }
        .safeAreaInset(edge: .bottom) {
            Text(model.status)
                .font(.caption.monospaced())
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(6)
                .background(.bar)
        }
        .toolbar {
            ToolbarItem {
                Button("Open…", systemImage: "folder") { model.presentOpenPanel() }
            }
            ToolbarItem {
                Picker("Camera", selection: $model.mode) {
                    ForEach(CameraMode.allCases) { Text($0.rawValue).tag($0) }
                }
            }
            ToolbarItem {
                Button("Reset Camera", systemImage: "camera.metering.center.weighted") { model.resetCamera() }
                    .help("Reset Camera (⌘0)")
            }
            ToolbarItem {
                Button("Play Animations", systemImage: "play") { model.playAnimations() }
                    .disabled(model.animationCount == 0)
            }
        }
    }
}
