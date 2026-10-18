# Split UI manual checklist: usable split UI in the test app

For the P2 acceptance criteria (spec §11) and the Docs/Design.md §11 **[check]** values. Run on the MacBook (trackpad; a mouse where noted). Record both macOS versions (the Mac's and the deployment target, macOS 26) in the sign-off.

## Setup

Build from the repo root (Xcode 27.1, default derived data location):

```sh
cd ~/Github/SplitKit
xcodebuild -project SplitKitTestApp/SplitKitTestApp.xcodeproj -scheme SplitKitTestApp build
```

Launch from Terminal (`--stdout "$(tty)"` prints the restore report in this Terminal; launch arguments go after `--args`):

```sh
open --stdout "$(tty)" "$(xcodebuild -project SplitKitTestApp/SplitKitTestApp.xcodeproj -scheme SplitKitTestApp -showBuildSettings 2>/dev/null | awk -F' = ' '/ BUILT_PRODUCTS_DIR =/{print $2; exit}')/SplitKitTestApp.app" --args <launch args>
```

- **`.plain`:** add `-SplitKitPlainStyle YES` (all three styles `.plain` plus `SplitKitTokens.plain`, applied through `SplitKitConfiguration.windowContent`); without it the windows use `.glass`. Example: `--args -SplitKitPersistenceDisabled YES -SplitKitPlainStyle YES`.
- **Clean run without a session file:** append `-SplitKitPersistenceDisabled YES`. Nothing is read or written; every launch starts from the default layout. Use it for checks 1–9; checks 10–12 need persistence on (no argument).
- **Quit** with ⌘Q (the Terminal prompt returns). Do not stop it with ⌃C: that skips the quit save.
- The session file is `~/Library/Application Support/com.mdidillon.SplitKitTestApp/SplitKit/session.json`. At launch the Terminal prints `SplitKitTestApp restore: RestoreReport(source: …, keptInvalidFile: …, …)`.

At launch one window opens (the main window): **No Content** with an **Add Content** button, centred on the screen, about 1200 × 800 pt.

**Contents:** *Colour* (a pane filled with one system colour, picked at random; the header title is its name; toolbar: *Next Colour* and the *Choose Colour* ▸ menu) and *Counter* (a number; toolbar **−** and **+**, also ⌘- and ⌘= while the pane is active; closing it with a count other than 0 asks "Close the counter at N?"). *Image* (P4a, see the P4 section) is registered third. The Add Content type list shows them in this order: Colour, Counter, Image.

**Keyboard reference** (spec §7.5): ⇧⌘N Add Content… (the type list opens; ↑/↓ choose, Return adds, Esc cancels), ⌘D Split Right, ⇧⌘D Split Down, ⌥⌘← → ↑ ↓ move the active pane, ⌃⌥⌘← → ↑ ↓ move the pane to that edge, ⇧⌘↩ Focus Pane, ⇧⌥⌘D Detach Pane, ⌘W Close Pane, ⇧⌘W Close Window, ⌘N New Window. (⇧⌘↩ and ⇧⌥⌘D replace ⌃⌘F and ⌥⌘D, which collide with Enter Full Screen and the Dock-hiding toggle; spec §7.5.)

## Checks

| # | Step | Expected | Result (PASS/FAIL + notes) |
|---|---|---|---|
| 1 | **2×2 by mouse** (`-SplitKitPersistenceDisabled YES`). Click **Add Content** ▸ *Counter*. In its header, click the title ▾ ▸ *Split Right*. In the new empty pane click **Add Content** ▸ *Colour*. Title ▾ of the counter ▸ *Split Down*; fill the new pane (Add Content ▸ *Colour*). Title ▾ of the right colour ▸ *Split Down*; fill it (Add Content ▸ *Counter*). | Four cards in a 2 × 2 grid: left column Counter / Colour, right column Colour / Counter. Each new pane takes half of the pane it was split from. Clicking a card makes it active (accent line on top of its header). | |
| 2 | **Dividers.** Drag the vertical divider left and right, then a horizontal one up and down. Drag one as far as it goes. Shrink the window as far as it goes. | The line follows the pointer (in `.glass` it appears on hover and is accent-coloured while dragging). A pane never gets smaller than its minimum; the drag stops there. The window cannot be made smaller than the four minimums together. | |
| 3 | **2×2 by keyboard only** (relaunch, no mouse after launch). Press: ⇧⌘N, ↓, Return (Counter) · ⌘D · ⌥⌘→ · ⇧⌘N, Return (Colour) · ⌥⌘← · ⇧⌘D · ⌥⌘↓ · ⇧⌘N, Return (Colour) · ⌥⌘→ · ⇧⌘D · ⌥⌘↓ · ⇧⌘N, ↓, Return (Counter). | The same 2 × 2 grid as check 1. After each ⌥⌘-arrow the accent line moves to that pane. The type list opens on the active pane and closes after Return. | |
| 4 | **3-level mixed tree by keyboard only** (relaunch). Press: ⇧⌘N, Return (A) · ⌘D · ⌥⌘→ · ⇧⌘N, ↓, Return (B) · ⇧⌘D · ⌥⌘↓ · ⇧⌘N, Return (C) · ⌘D · ⌥⌘→ · ⇧⌘N, ↓, Return (D). | Left half A; right half split top/bottom: B on top, and the bottom split left/right into C and D (`H[A, V[B, H[C, D]]]`). Then ⌃⌥⌘← on D moves it to the left edge of C (C and D swap places). | |
| 5 | **3-level mixed tree by mouse** (relaunch). Repeat check 4 with the title ▾ menus (*Split Right*, *Split Down*) and the **Add Content** buttons. | The same tree as check 4. | |
| 6 | **Decline a close.** On a counter press **+** three times (or ⌘= with the pane active). Click its header **×** (or ⌘W). In the alert click **Cancel**. Then ⇧⌘W (Close Window) on a window with 2+ panes, **Close All**, then **Cancel** in the counter's alert. | While asking, the counter's close button is a spinner and its other header controls are disabled. After Cancel: the counter still shows **3**, the layout and active pane are unchanged, nothing is closed. For ⇧⌘W: first "Close window with N panes?", then the counter's alert; Cancel there closes nothing. | |
| 7 | **Accept a close.** ⌘W on the counter, **Close** in the alert. ⌘W on a colour pane (no question). | The pane is removed; its neighbour takes the space; the nearest pane becomes active. A count of 0 closes without asking. | |
| 8 | **Last pane → empty state.** Close panes with ⌘W until one is left, then ⌘W once more (*Pane ▸ Close Pane*). Then check the menu: *Pane ▸* its last item now reads *Close Window*; press ⌘W. Then ⌘N (*File ▸ New Window*). Finally click the Dock icon with no window open. | The last close leaves **No Content** with **Add Content**, the window stays. ⌘W in the empty window closes it; **the app keeps running** (menu bar still there, no Terminal prompt). ⌘N opens a new empty main window; with a window open ⌘N only brings it to the front. The Dock icon also reopens the window. | |
| 9 | **Focus mode, menus, shortcuts.** In the 2×2: click a header's focus toggle; press Esc; press ⇧⌘↩; press ⇧⌘↩ again. Open each menu bar menu (*File*, *Pane* incl. *Move Focus* ▸, *Move Pane to Edge* ▸ and the *Counter* / *Colour* submenu, *Window*). Right-click a header. | Focus mode: the pane fills the window, the toggle symbol flips, Esc and ⌃⌘F leave it. Every menu item shows the §7.5 shortcut; *Detach* and *Move to Window* are present and disabled (P3). *Pane ▸ Counter ▸ Increment / Decrement* work and show ⌘= / ⌘-, only for the active counter. Right-click shows the same menu as the title ▾. | |
| 10 | **Relaunch restores everything** (no launch argument). Build any layout with 2+ counters at different counts and 2+ colours; make one pane active; move and resize the window; quit with ⌘Q. Relaunch. | Terminal: `source: …restoredFile`. Same tree, divider positions, active pane, counter values and colours; the window at the same place and size. (Resize, then quit within 1 s: the quit save still has it.) | |
| 11 | **Invalid file → default layout + kept file.** Quit. Run: `printf 'not json' > ~/Library/Application\ Support/com.mdidillon.SplitKitTestApp/SplitKit/session.json` then relaunch, then `ls ~/Library/Application\ Support/com.mdidillon.SplitKitTestApp/SplitKit/`. | The default layout (No Content). Terminal: `source: …defaultAfterError(…unreadable…)` and `keptInvalidFile: …session.invalid-<timestamp>.json`. The folder lists `session.json` (the new default layout, written about 1 s after launch) and `session.invalid-<timestamp>.json` containing `not json`. | |
| 12 | **Window placement without drift.** Move the window to the right half of the screen and make it smaller; quit; change the display resolution (System Settings ▸ Displays, a larger text size); relaunch; set the resolution back; quit; relaunch. | Each launch shows the window fully on screen, never below its minimum; after the resolution is restored the window is back where you put it (the system's re-placement was not saved). | |
| 13 | **Look (`.glass`).** In a 2 × 2 with both contents, in light and dark mode, judge the Design.md §11 **[check]** values below. | Matches Design.md §4.1 / §7; note anything to change. Then repeat the 2 × 2 with `-SplitKitPlainStyle YES` (light and dark mode) and judge `.plain` against Design.md: no glass, tokens `SplitKitTokens.plain`; note anything to change. | |
| 14 | **Glass & Accessibility example.** *Window ▸ Glass & Accessibility Check* (⌥⌘G). | Run `Docs/GlassAccessibility-checklist.md`; record its result here. | |
| 15 | **Close semantics usability** (spec §13; detached-window rows wait for P3). With 3 panes: ⌘W on a pane, ⌘W on the last pane, ⌘W in the empty window, ⇧⌘W, and the red close button. | Each result matches its menu label; note whether you predicted it before pressing and whether the prompt text was clear. The red close button behaves like ⇧⌘W. | |
| 16 | **Replace Content…** (`-SplitKitPersistenceDisabled YES`). Add a Counter, press **+** twice. Title ▾ ▸ *Replace Content…* ▸ *Colour*. Then Counter again, title ▾ ▸ *Replace Content…* ▸ *Counter* and, in the counter's close alert, **Cancel**. Also try *Pane ▸ Replace Content…* from the menu bar. | The type list opens as for Add Content. First: the pane keeps its place and size, now a colour (the counter's close alert does not appear because the counter accepts; if it asks, **Close**). Cancel: nothing changes, the count stays. | |
| 17 | **Detach (⇧⌥⌘D).** With 2+ panes, press ⇧⌥⌘D on the active pane, then title ▾ ▸ *Detach* on another. | Each pane opens in a new window, 24 pt right and below its source window, fully on screen; the counter keeps its count; the main window keeps the other panes (the last pane leaves the empty state). | |
| 18 | **Move to Window ▸.** With a main window and 2 detached ones: title ▾ ▸ *Move to Window* ▸ lists the other windows (main first), each titled by its content. Choose one. Move the last pane out of a detached window. | The pane lands to the right of the target's active pane (or its last pane); the counter keeps its count. A detached window left without content closes. In an empty main window the pane fills it. | |
| 19 | **Dock Back.** In a detached window with 2 panes: *Window ▸ Dock Back*, then again with title ▾ ▸ *Dock Back* on a detached window. Close the main window first (⇧⌘W while empty) and Dock Back. | All its panes appear in the main window in the same order, state intact, and the detached window closes. With no main window, one opens at the default size first. The item is disabled in the main window. | |
| 20 | **Dock Back Instead.** Detached window with 2+ panes: click the red close button. | Prompt "Close window with N panes?" with **Close All**, **Dock Back Instead**, **Cancel**. Dock Back Instead docks the panes into the main window and asks no content. Cancel closes nothing. Close All asks each content. | |
| 21 | **`.host` mode and Detach options.** Launch the host sample (check 34); set `SplitKitConfiguration.detach` to `.disabled` and `.commandOnly` (edit `HostSampleApp.makeWorkspace`). | `.disabled`: no *Detach* and no *Move to Window* in the menus. `.commandOnly`: both present. In `.host` mode detached windows are created by SplitKit (or `makeDetachedWindow`), the host's main window is never moved. | |
| 22 | **Drag feel and threshold.** In a 2 × 2 press on a header's drag handle (the `≡` at the leading edge) and move the mouse 2 pt, then 6 pt. Click the handle without moving. Press on the title ▾ and a toolbar button and drag. | Under about 4 pt nothing starts; beyond it a drag image of the header follows the cursor and the dragged pane's header and content dim (Design.md §3). A click on the handle only makes the pane active. Dragging from the title ▾ or a button does not start a pane drag. Right-click on the handle still opens the pane menu. Note whether the handle is easy to hit. | |
| 23 | **Edge and centre drops** (`-SplitKitPersistenceDisabled YES`, 3 panes). Drag a header over another pane: left, right, top and bottom parts, the middle, then its own pane. Drop on a right half, then drop one on a centre. | The overlay covers the half of the card nearest the cursor, or the whole card in the middle (a swap); it moves smoothly between zones. Over its own pane there is no overlay. An edge drop splits the target on that side; a centre drop swaps the two panes. Counters keep their counts. Cursor in the gap between cards still picks the nearer card. | |
| 24 | **Cross-window dock.** Detach a counter (⇧⌥⌘D), then drag a pane from the main window into the detached window and back, with edge and centre drops. Detach another and drag the **only** pane of a detached window into the main window. Close the main window's last pane (empty window), then drag a pane from a detached window onto the empty main window. | Every SplitKit window shows the overlay and accepts the drop; the counter keeps its object and count. A detached window left without content closes. An empty main window highlights as a whole and takes the pane. | |
| 25 | **Drag-out ghost.** Drag a header out of its window more than 40 pt past its edge over the desktop (no other SplitKit window). Move back inside the 40 pt band, then out again. Release outside. Repeat on a second display if you have one. | A semi-transparent snapshot window follows the cursor (it replaces the drag image; no snap-back animation). Inside the band or over another SplitKit window it disappears. Releasing outside creates a detached window exactly at the ghost's position (pulled fully onto the display if needed), with the counter intact; the source window keeps its other panes. | |
| 26 | **Cancel paths.** Start a drag and press Esc over a valid pane; Esc while the ghost shows; release within 40 pt outside the window; release over an invalid target (own pane); drag over Finder or another app and release. | Every case leaves the layout, active pane and windows exactly as before; the dimmed look and overlay go; the ghost closes; no window appears (Esc with the ghost showing must **not** detach). Dropping on Finder or another app does nothing. | |
| 27 | **Detach options and pending close.** With `SplitKitConfiguration.detach` set to `.commandOnly`, then `.disabled` (test app edit), drag a header outside the window. Click × on a counter with count ≠ 0 (its alert is open, the pane is pending) and try to drag that header. | `.commandOnly` and `.disabled`: no ghost, release outside cancels; docking drags between windows still work. A pane in a pending close cannot be dragged. | |
| 28 | **Overlay look in `.glass` and `.plain`.** Judge the drop overlay over a busy content (e.g. a colour pane next to a counter) in light and dark mode, then with `-SplitKitPlainStyle YES`. | `.glass`: `.thinMaterial` in the zone shape with the accent fill (0.18) and 2 pt accent stroke, rounded on the card's outer corners. `.plain`: fill and stroke only, square corners. The zone follows `metrics.cornerRadius`. Note anything to change in Design.md §3 (fill 0.18, stroke 2 pt, centre fraction 0.5, ghost opacity 0.6). | |
| 29 | **First responder and focus after a drop.** Drag a counter (with the keyboard shortcut ⌘= working in the active pane) into another window and press ⌘=. Drop a pane that contains a text field if the content has one. | The dropped pane stays active in its window and the shortcut works; no stale first responder in the source window; no console assertion about a double host. | |

## P3 single-screen (spec §11 P3 acceptance)

One screen only; multi-display and hot-plug stay with the simulated matrix (`DisplayMatrixTests`, spec §13). Use the test app with `-SplitKitPersistenceDisabled YES` unless the row says otherwise. For every path: put a **Counter** at a count other than 0 (e.g. 7) in the pane you move, plus a second counter at another count, and compare both counts after the step.

| # | Step | Expected | Result (PASS/FAIL + notes) |
|---|---|---|---|
| 30 | **Counter survives every path.** Run each path with the 7-counter: (a) drag dock onto an edge of another pane, (b) drag dock onto a centre (swap), (c) drag out past the 40 pt band and release (new detached window), (d) ⇧⌥⌘D Detach, (e) title ▾ ▸ *Move to Window* ▸ main, (f) *Window ▸ Dock Back* from a detached window, (g) close a detached window with the red button ▸ *Dock Back Instead*, (h) quit with ⌘Q and relaunch **without** `-SplitKitPersistenceDisabled` (windows, placement and counts restored). | After each step the counter shows **7** (the same object, not a new one) and the other counter keeps its count; one host only, no console assertion. After (h) both counts, the tree and the detached windows are back. | |
| 31 | **Resolution change while running.** With a main window and 2 detached windows, open System Settings ▸ Displays and change the resolution (a larger text size, then back). | During the change every window stays fully on screen and at least its minimum size. After the original resolution is back, each window is where you put it. Quit with ⌘Q and relaunch: the placements are the ones you chose, not the temporary ones. | |
| 32 | **Hand-edited session with a missing display.** Quit. In `~/Library/Application Support/com.mdidillon.SplitKitTestApp/SplitKit/session.json` set a window's `displayID` to `"unplugged"` (keep its `relativeOrigin`) and, in another window, set `intendedFrame` to a position far off screen (for example x `-9000`). Relaunch. | Both windows open fully on screen on the main display (the one with the menu bar), at least minimum size, with no error. Move one window slightly and quit: only that window's placement is rewritten. | |
| 33 | **Full screen and focus mode.** Put the main window in full screen (green button), enter focus mode on a counter (⇧⌘↩), leave with Esc, then leave full screen. Repeat with a detached window. Detach (⇧⌥⌘D) a pane while the main window is in full screen. | The counter state is unchanged throughout. Leaving full screen returns the window to its earlier frame (not saved as a new placement). Detach from a full-screen window opens the new window on the same display, fully visible. | |
| 34 | **Host sample (`.host` mode, persistence disabled).** Build and launch the sample (commands below). Add a Counter and a Colour, press **+** a few times, then run: drag a header onto the other pane's edge and centre; ⇧⌥⌘D Detach; drag a pane from the detached window back onto the host window; *Dock Back*; drag a pane out past the 40 pt band. Move and resize the host window. Quit with ⌘Q and relaunch. | The host's window is a drop destination (overlay and docking work, clicks and scrolls in the host's content still work); detached windows are created by SplitKit; the host window's frame is never changed by SplitKit; counts survive every step. After the relaunch the sample starts from the default layout (persistence `.disabled`; no `session.json` is written for `com.mdidillon.SplitKitHostSample`). | |

Host sample commands (repo root):

```sh
cd ~/Github/SplitKit
xcodebuild -project SplitKitTestApp/SplitKitTestApp.xcodeproj -scheme SplitKitHostSample build
open --stdout "$(tty)" "$(xcodebuild -project SplitKitTestApp/SplitKitTestApp.xcodeproj -scheme SplitKitHostSample -showBuildSettings 2>/dev/null | awk -F' = ' '/ BUILT_PRODUCTS_DIR =/{print $2; exit}')/SplitKitHostSample.app"
```

The Terminal prints `SplitKitHostSample restore: RestoreReport(source: persistenceDisabled, …)` at launch.

## P4 ImageViewer and ModelViewer3D (spec §10, §11 P4; ImageViewer checks 35–39 from P4a, ModelViewer3D checks 40–47 from P4b)

The test app and the host sample register *Image* as a third type and *3D Model* as a fourth (after Counter). Use any PNG or JPEG, plus a corrupt one: `printf 'not a png' > ~/Desktop/broken.png` (delete it afterwards). Run in the test app with `-SplitKitPersistenceDisabled YES` unless the check says otherwise.

| # | Check | Expected | OK |
|---|---|---|---|
| 35 | **Standalone and picker file panel.** Empty window ▸ Add Content ▸ Image. Cancel the panel once. Choose a PNG. Resize the window. | The type list closes and an open panel shows only image files. Cancel adds nothing. The image fills the pane aspect-fit (no zoom, pan or rotate, no toolbar items) and the title is the file name. Resizing keeps the aspect ratio. | |
| 36 | **Docked and detached.** Add a Colour next to it (⌘D, ⇧⌘N). Drag the Image header onto the Colour's edge and centre; *Detach* it (⇧⌥⌘D); *Dock Back*. Add a second Image through the pane menu ▸ Replace Content… ▸ Image on the Colour. | The image is the same after every move (same file, same title); Replace Content… also shows the file panel and the Colour is replaced by the image. | |
| 37 | **Finder drop.** Drag a PNG from Finder onto: the empty window; an empty pane (⌘D first); the centre of an occupied pane; an edge of a pane; a `.txt` file onto a pane. Also drag over a pane and leave the window without dropping. | Empty window and empty pane: the image fills it. Centre of an occupied pane: it replaces that pane's content (after the usual close question). Edge: the pane splits and the image takes the new half. The accent drop overlay shows the same zones as a header drag; the `.txt` shows no overlay and nothing happens. Leaving the window clears the overlay. | |
| 38 | **Corrupt file.** Pick `broken.png` in the file panel, then drop it on an occupied pane's centre and on a pane's edge. | Each time the pane (or the empty window) shows a dismissible message “broken.png” couldn't be read. (warning symbol, ✕ to dismiss) at its bottom; the layout is exactly as before (no empty pane left after the edge drop); the next add or drop clears the message. | |
| 39 | **Relaunch (persistence on).** Open two images in two panes, quit with ⌘Q, relaunch. Quit again, move one image file elsewhere, relaunch. | Both images come back in their panes. With a moved file that pane shows the placeholder “Image couldn't be restored” with Restore and Close; the other pane is intact. | |

The models are in `SplitKitViews/Tests/Fixtures/Models/` (`DamagedHelmet/glTF-Binary/DamagedHelmet.glb`, `CesiumMilkTruck/glTF/CesiumMilkTruck.gltf`, `Duck/glTF-Binary/Duck.glb`, `BoxTextured/glTF/BoxTextured.gltf`, `CesiumMan/glTF-Binary/CesiumMan.glb`; error files in `Errors/`, Draco in `Box/glTF-Draco/Box.gltf`); the reference renders are `Models/<Model>/screenshot/`. Do checks 40–42 on the **MacBook trackpad** and then with a **mouse with a wheel and a middle button**, and write down which input did what.

| # | Check | Expected | OK |
|---|---|---|---|
| 40 | **Standalone.** Empty window ▸ Add Content ▸ 3D Model. Cancel the panel once, then choose `DamagedHelmet.glb`. Add a pane with the picker and look at the panel's file filter. | The open panel shows only `.gltf` and `.glb` files. The helmet appears upright, centred and framed (a progress indicator shows briefly), the title is the file name, the header has a *Reset Camera* item. Gestures move the view at all, i.e. the `RealityView` renders through the camera entity (spec §11.2 P4b decision 2: if nothing moves, report it). | |
| 41 | **Camera contract, trackpad and mouse.** Orbit: one-finger click-drag / left-drag. Pan: two-finger scroll / ⇧ + drag / middle-drag. Dolly: pinch / wheel. Zoom all the way in and all the way out. | Orbit turns the model about its centre (drag right turns the model right), stops before flipping over the poles and keeps the size. Pan slides the model with your fingers without turning it, and a later orbit pivots about the new centre. Pinch out / wheel up moves closer. The camera stops at a minimum distance and never passes through the model's centre; it stops at a maximum distance with the model still visible. Note the scroll direction (natural scrolling) and a Magic Mouse (pans rather than zooms, known). | |
| 42 | **Reset.** Orbit, pan and zoom, then click *Reset Camera*; repeat with ⌘0. Then resize the pane very wide and very tall and press ⌘0. With two 3D panes side by side, press ⌘0 in the inactive one. | The view returns exactly to the framed start view (same angle, same centre, same size). After a resize the model fits the new shape. ⌘0 resets only the active pane; the item is disabled while a model is loading. | |
| 43 | **Docked and detached.** Add a Colour next to the model (⌘D, ⇧⌘N). Orbit and zoom the model, drag its header onto the Colour's edge and centre, *Detach* it (⇧⌥⌘D), *Dock Back*. Replace Content… on the Colour with a second model. | The model, its camera pose and a running animation (`CesiumMan.glb` walks) are the same after every move; the view renders again after each move (no blank pane); the second model shows in the replaced pane. | |
| 44 | **PBR look against the reference.** Open `DamagedHelmet.glb`, `Duck.glb`, `BoxTextured.gltf`, `CesiumMilkTruck.gltf` (⌘0 each) and compare with `Models/<Model>/screenshot/`. | Lighting and angle differ; the materials read right: visor, metal and paint on the helmet, emissive lights glow, normal-map dents; Duck yellow with orange beak, texture not flipped; the Cesium logo on every box face, not mirrored; the truck upright with the logo on its sides. Say whether this counts as "visually matches" (spec §10). | |
| 45 | **Error files.** Pick `Errors/malformed.gltf`, `Errors/missing-buffer.gltf` and `Box/glTF-Draco/Box.gltf` in the file panel and drop each on an occupied pane's centre. Drag `Errors/fake.fbx` from Finder over a pane. | Each shows the dismissible message “…” can't be opened: it is not a valid glTF asset (invalid JSON) / it refers to “does-not-exist.bin”, which is missing / it requires unsupported glTF extensions: KHR_draco_mesh_compression. The layout is as before. The `.fbx` shows no drop overlay and nothing happens. The app never crashes. | |
| 46 | **Optional rows.** Open `CesiumMan.glb`, `AnimatedMorphCube.glb`, `TransmissionTest.glb`, `ClearCoatTest.glb`. | CesiumMan walks (looping). The morph cube loads and stays still (unsupported, no crash). Transmission parts are opaque (known gap). The clearcoat parts look coated. | |
| 47 | **Relaunch (persistence on).** Open a model, orbit and zoom, quit with ⌘Q, relaunch. Quit again, move the model file elsewhere, relaunch. | The model comes back in its pane with the same camera pose. With the file moved that pane shows the placeholder “3D Model couldn't be restored” with Restore and Close; the other panes are intact. | |

## Design.md §11 [check] values (check 13)

| # | Value | OK / change to |
|---|---|---|
| 1 | Card corner radius 10 pt (`.glass`) | |
| 2 | Card inset 4 pt (gap between cards 8 pt) | |
| 3 | Header padding 6 pt, item spacing 4 pt | |
| 4 | Active indicator: 2 pt accent line on top of the header | |
| 5 | Drop overlay: 0.18 fill, 2 pt stroke, `.thinMaterial` in `.glass` (checks 23, 28) | |
| 6 | Dragged-source opacity 0.5, drop zone centre fraction 0.5, ghost window opacity 0.6 (checks 22, 23, 25) | |
| 7 | Divider line only on hover and drag | |
| 8 | Window background: standard, no custom material | |
| 9 | Empty state: 28 pt symbol, `.title3` title, 8 pt spacing, `.glassProminent` Add button | |
| 10 | Drag handle symbol `line.3.horizontal` | |
| 11 | Header control labels "Focus Pane", "Close Pane" (tooltips; VoiceOver) | |
| 12 | Header controls: borderless buttons with interactive glass capsules | |
| 13 | Empty window title "No Content" | |
| 14 | Header title minimum width 64 pt (narrow a pane until toolbar items go to ⋯) | |
| 15 | Creation error message: `exclamationmark.triangle`, `.callout` text, `.thinMaterial` box (corner radius `metrics.cornerRadius`) at the pane's bottom with 8 pt padding (check 38) | |

## Gaps known before the run

- The mouse-driven `NSDraggingSession` (checks 22–29) can't run in a test: the destination, hit-testing, ghost and cleanup code is tested directly (`PaneDragTests`), the session itself, the Esc detection, hiding the drag image while the ghost shows and snapshots of SwiftUI content are manual only.
- A `.host` main window becomes a drop destination through a transparent overlay that `SplitKitView` lays over its content (`HostDropDestination`); it takes part in hit testing only while a pane drag is in flight, which is manual only (check 34). The ghost snapshot of a pane dragged out of a host window is blank (the overlay holds no content to snapshot).
- Display hot-plug and Spaces can't be tested on one screen (spec §13).

## Sign-off

- Tester / date:
- Mac, macOS version (deployment target macOS 26):
- Trackpad / mouse:
- Overall: PASS / FAIL
- Notes:
