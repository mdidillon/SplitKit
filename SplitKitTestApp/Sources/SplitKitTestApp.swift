import SwiftUI
import SplitKit
import ImageViewer
import ModelViewer3D

@main
struct SplitKitTestApp: App {
    var body: some Scene {
        WindowGroup {
            Text("SplitKitTestApp placeholder (SplitKit \(SplitKitInfo.version), ImageViewer \(ImageViewerInfo.version), ModelViewer3D \(ModelViewer3DInfo.version))")
                .padding()
                .frame(minWidth: 400, minHeight: 200)
        }
        Window("Glass & Accessibility Check", id: GlassVerificationCommands.windowID) {
            GlassVerificationView()
        }
        .commands { GlassVerificationCommands() }
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
