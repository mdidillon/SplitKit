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
    }
}
