# SplitKit

SplitKit is a native macOS workspace layout engine for SwiftUI. It gives you nested horizontal and vertical splits, draggable dividers, drag-and-drop rearranging, panes you can drag out into their own windows and back, multi-window and multi-monitor layouts, focus mode, and versioned layout saving. **SplitKit Views** is a companion package of reusable pane contents, with one target per view.

> Status: Phase 0 (specification) is approved. Implementation starts with Phase 1. See [Docs/Phase0-Spec.md](Docs/Phase0-Spec.md).

## Repository layout

```
SplitKit/          Swift package: the layout engine (model, SwiftUI rendering, AppKit windows). Renders no content.
SplitKitViews/     Swift package: pane contents, one product per view (ImageViewer, ModelViewer3D, ...).
SplitKitTestApp/   Xcode project: test app and integration sample.
Docs/              Specification and design references.
```

## Requirements

- macOS 26 Tahoe or later (no legacy support)
- Xcode 27.1 or newer, Swift 6 language mode

## First content views

- **ImageViewer**: display only.
- **ModelViewer3D**: glTF and GLB via GLTFKit2 and RealityKit, with standard rotate, pan and zoom.

Deferred: terminal, code editor, browser, file browser, GitHub view.

## Getting started

*(The packages and app are created in Phase 1.)*

1. Clone: `git clone https://github.com/mdidillon/SplitKit.git`
2. Open `SplitKitTestApp/SplitKitTestApp.xcodeproj` in Xcode 27.1+.
3. Run the `SplitKitTestApp` scheme on macOS 26.

To use SplitKit in your own app, add the `SplitKit` package (and any `SplitKitViews` products you need) through Swift Package Manager. Then register your contents and host a workspace, as described in the spec's host-integration section.

## Licence

MIT. See [LICENSE](LICENSE).
