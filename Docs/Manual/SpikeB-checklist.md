# Spike B manual checklist (Gate B)

Spec §10 camera contract and corpus, §11 Gate B. Decision record: `Docs/ADR/0002-spike-b-realitykit.md`.

**Tester:** Marc · **Machine:** MacBook (built-in trackpad) + an external mouse with a wheel and a middle button · **Date:** ____

## 0. Setup

```sh
cd Spikes/SpikeB-RealityKit
./scripts/fetch-corpus.sh
swift run SpikeBDemo (or open `Spikes/SpikeB-RealityKit/SpikeBRealityKit.xcodeproj` in Xcode 27.1 and run the `SpikeBRealityKit` scheme for a real app bundle; GLTFKit2.framework is embedded)                                              # empty window, File ▸ Open… (⌘O)
swift run SpikeBDemo Fixtures/DamagedHelmet/glTF-Binary/DamagedHelmet.glb   # opens a file directly
```

The window shows these toolbar controls: **Open…**, a **Camera** picker (Custom / Native .orbit / .pan / .tilt / .dolly), **Reset Camera**, and **Play Animations**. Menu **Camera ▸ Reset Camera** is ⌘0. The status bar shows load time, texture slots, warnings and bounds.

Result column: ✅ pass, ❌ fail (add a note), ➖ n/a.

## 1. Launch

| # | Step | Expected | Result | Notes |
|---|---|---|---|---|
| 1.1 | `swift run SpikeBDemo` | The window appears in front and has a Dock icon. ⌘O opens a file panel. | | |
| 1.2 | Open DamagedHelmet.glb | The helmet is upright and centred, filling most of the view. The status bar shows the load time in ms and `6/6 texture slots, 0 warnings`. | | |

## 2. Camera contract, Custom mode (picker = Custom)

Do every row on the **trackpad** and then on the **mouse**. Use DamagedHelmet, then CesiumMilkTruck.

| # | Action | Trackpad gesture | Mouse gesture | Expected | Trackpad | Mouse | Notes |
|---|---|---|---|---|---|---|---|
| 2.1 | View uses the custom camera | — | — | Opening a file frames the model. Gestures move the view. (If nothing moves, see ADR risk 3.) | | | |
| 2.2 | Orbit | One-finger click-drag | Left-drag | The model turns around its centre and keeps its apparent size. Drag right turns the model right. Vertical orbit stops before flipping over the top or bottom. | | | |
| 2.3 | Pan (two-finger) | Two-finger scroll | — | The model slides with your fingers and doesn't rotate or change size. A later orbit pivots around the **new** centre. | | ➖ | |
| 2.4 | Pan (⇧ drag) | ⇧ + click-drag | ⇧ + left-drag | Same as 2.3. | | | |
| 2.5 | Pan (middle) | — | Middle-button drag | Same as 2.3. | ➖ | | |
| 2.6 | Zoom | Pinch | Scroll wheel | Fingers apart or wheel up moves closer; the reverse moves away. Speed feels controllable. | | | |
| 2.7 | Zoom near clamp | Keep pinching in | Keep scrolling up | Zooming stops at a minimum distance. The camera **never passes through** the centre or flips to the other side. | | | |
| 2.8 | Zoom far clamp | Keep pinching out | Keep scrolling down | Zooming stops at a maximum distance; the model stays visible. | | | |
| 2.9 | Reset (toolbar) | Orbit + pan + zoom, then click **Reset Camera** | same | The view returns exactly to the framed start view: same angle, same centre (the pan is undone) and same size. | | | |
| 2.10 | Reset (⌘0) | Orbit + pan + zoom, then press ⌘0 | same | Same as 2.9. | | | |
| 2.11 | Window resize then ⌘0 | Make the window very wide or tall, then ⌘0 | same | The model fits the new shape and nothing is clipped. | | | |
| 2.12 | Magic Mouse (if available) | — | Surface scroll | Note what happens: by design this pans rather than zooms (ADR risk 4). Say whether that's acceptable. | ➖ | | |

## 3. Native mode comparison (picker = Native …)

For each native mode, try every contract action. Record which ones work and how.

| # | Mode | Orbit? | Pan, target moves? | Zoom (pinch/wheel)? Clamped? | Reset (toolbar/⌘0)? | Notes |
|---|---|---|---|---|---|---|
| 3.1 | Native .orbit | | | | | |
| 3.2 | Native .pan | | | | | |
| 3.3 | Native .tilt | | | | | |
| 3.4 | Native .dolly | | | | | |
| 3.5 | **Verdict:** can any single native mode satisfy all four actions? (ADR expects no.) | | | | | |

## 4. PBR visual check vs reference

Compare the live view (Custom mode, after ⌘0) and the offscreen renders in `Docs/ADR/assets/spikeB/renders/` with `Docs/ADR/assets/spikeB/reference/`. Lighting and angle will differ. Judge the materials: correct texture placement, metal vs non-metal areas, roughness, normal-map detail, emissive glow, colours not washed out or too dark.

| # | Model | Expected | Result | Notes |
|---|---|---|---|---|
| 4.1 | DamagedHelmet | Visor glass, metal and paint read correctly. Emissive HUD and lights glow. Normal-map dents visible. | | |
| 4.2 | Duck | Yellow body, orange beak, eyes correct. Texture not flipped. | | |
| 4.3 | BoxTextured | Cesium logo on each face, not mirrored. | | |
| 4.4 | CesiumMilkTruck | Logo on the truck sides, wheels in place, truck upright. | | |
| 4.5 | **Accept PBR as "visually matches"?** | | | |

## 5. Error display

| # | Step | Expected | Result | Notes |
|---|---|---|---|---|
| 5.1 | Open `Fixtures/Errors/malformed.gltf` | An in-window message reads “Can’t open malformed.gltf” and says the file is not a valid glTF asset (1003, invalid JSON). The app keeps running. | | |
| 5.2 | Open `Fixtures/Errors/fake.fbx` | The message reads “Unsupported file type “.fbx”. Only glTF (.gltf) and GLB (.glb) can be opened.” No crash. | | |
| 5.3 | Open `Fixtures/Errors/missing-buffer.gltf` | The message reports I/O error 1007. No crash. | | |
| 5.4 | Open a valid model after an error | The error disappears and the model shows. | | |

## 6. Optional rows

| # | Step | Expected | Result | Notes |
|---|---|---|---|---|
| 6.1 | Open CesiumMan.glb, click **Play Animations** | The figure walks and the skin deforms with the bones. | | |
| 6.2 | Open RiggedSimple.glb, Play | The cylinder bends. | | |
| 6.3 | Open AnimatedMorphCube.glb, Play | Expected: no morph motion (unsupported, ADR §4). Note what you see. | | |
| 6.4 | Open TransmissionTest.glb | Expected: transmissive parts are opaque (gap). Note it. | | |

## Sign-off

| Gate B input | Result |
|---|---|
| Camera contract on trackpad (§2) | |
| Camera contract on mouse (§2) | |
| PBR visual match (§4.5) | |
| Error display (§5) | |
| **Gate B: GO / NO-GO** | |
