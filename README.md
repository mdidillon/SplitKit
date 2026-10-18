# SplitKit

SplitKit is a native macOS workspace layout engine for SwiftUI. It gives you nested horizontal and vertical splits, draggable dividers, drag-and-drop rearranging, panes you can drag out into their own windows and back, multi-window and multi-monitor layouts, focus mode, and versioned layout saving. **SplitKit Views** is a companion package of reusable pane contents, with one target per view.

> Status: Phase 0 specification approved (Revision 3, 16 Oct 2026, ready for Phase 1). Implementation starts with Phase 1: the model plus feasibility spikes. See [Docs/Specification.md](Docs/Specification.md).

## Repository layout

```
SplitKit/          Swift package: the layout engine. Renders no content. Products:
                   SplitKitModel   - pure model: tree, transactions, persistence, display placement
                   SplitKitContent - content contract (PaneContent, PaneToolbarItem, ContentRegistry)
                   SplitKit        - SwiftUI workspace, chrome, styles; includes the AppKit window coordinator
SplitKitViews/     Swift package: pane contents, one product per view (ImageViewer, ModelViewer3D, ...).
                   Each depends only on SplitKitContent, never on the SplitKit UI.
SplitKitTestApp/   Xcode project: test app and integration sample.
Docs/              Specification and design references.
```

## Requirements

- macOS 26 Tahoe or later (no legacy support)
- Xcode 27.1 or newer (Swift 6.4), Swift 6 language mode; package manifests use `swift-tools-version: 6.2`

## First content views

- **ImageViewer**: display only, aspect-fit. Opens from the content picker's file panel or a file dropped from Finder (`UTType.image`). Register it with `try ImageViewerContent.register(in: registry)`; depends only on `SplitKitContent`. A fresh package that depends on this one product builds and runs (CI step "Clean consumer test per product").
- **ModelViewer3D**: glTF and GLB via GLTFKit2 and RealityKit, with standard rotate, pan and zoom.

Deferred: terminal, code editor, browser, file browser, GitHub view.

## Getting started

1. Clone: `git clone https://github.com/mdidillon/SplitKit.git`
2. Open `SplitKitTestApp/SplitKitTestApp.xcodeproj` in Xcode 27.1+.
3. Run the `SplitKitTestApp` scheme on macOS 26.

The test app shows the split UI with two dummy contents (Colour and Counter) and saves its session to `~/Library/Application Support/com.mdidillon.SplitKitTestApp/SplitKit/session.json`. Pass the launch argument `-SplitKitPersistenceDisabled YES` to start from the default layout without reading or writing it, and `-SplitKitPlainStyle YES` to show `.plain` instead of `.glass`. Building and launching from Terminal, and the manual checks: `Docs/SplitUI-checklist.md`.

**Host sample.** The `SplitKitHostSample` scheme (same project) shows `.host` mode: the app owns its main window and embeds `SplitKitView(workspace:window:)`, persistence is `.disabled`, and SplitKit creates only the detached windows. Build and launch commands: `Docs/SplitUI-checklist.md`, check 34.

To use SplitKit in your own app, add the `SplitKit` package (and any `SplitKitViews` products you need) through Swift Package Manager. Create a `ContentRegistry`, register your contents, and create a `SplitKitWorkspace`. Then either let SplitKit manage windows, or embed `SplitKitView` in your own. See spec §5 (API) and §9 (window ownership).

## Licence

MIT. See [LICENSE](LICENSE).
