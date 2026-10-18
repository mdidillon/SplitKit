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

**Contents:** *Colour* (a pane filled with one system colour, picked at random; the header title is its name; toolbar: *Next Colour* and the *Choose Colour* ▸ menu) and *Counter* (a number; toolbar **−** and **+**, also ⌘- and ⌘= while the pane is active; closing it with a count other than 0 asks "Close the counter at N?"). The Add Content type list shows them in this order: Colour, Counter.

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
| 21 | **`.host` mode and Detach options.** Launch the host-mode variant of the test app if available; set `SplitKitConfiguration.detach` to `.disabled` and `.commandOnly`. | `.disabled`: no *Detach* and no *Move to Window* in the menus. `.commandOnly`: both present. In `.host` mode detached windows are created by SplitKit (or `makeDetachedWindow`), the host's main window is never moved. | |

## Design.md §11 [check] values (check 13)

| # | Value | OK / change to |
|---|---|---|
| 1 | Card corner radius 10 pt (`.glass`) | |
| 2 | Card inset 4 pt (gap between cards 8 pt) | |
| 3 | Header padding 6 pt, item spacing 4 pt | |
| 4 | Active indicator: 2 pt accent line on top of the header | |
| 5 | Drop overlay (P3: not visible yet) | n/a in P2 |
| 6 | Dragged-source opacity (P3: not visible yet) | n/a in P2 |
| 7 | Divider line only on hover and drag | |
| 8 | Window background: standard, no custom material | |
| 9 | Empty state: 28 pt symbol, `.title3` title, 8 pt spacing, `.glassProminent` Add button | |
| 10 | Drag handle symbol `line.3.horizontal` | |
| 11 | Header control labels "Focus Pane", "Close Pane" (tooltips; VoiceOver) | |
| 12 | Header controls: borderless buttons with interactive glass capsules | |
| 13 | Empty window title "No Content" | |
| 14 | Header title minimum width 64 pt (narrow a pane until toolbar items go to ⋯) | |

## Gaps known before the run

- Drag between panes, the drag-out ghost window and drop overlays are the next P3 task. Detach, Move to Window, Dock Back and Dock Back Instead are checks 17–20 (menu and shortcut only).
- Display hot-plug and Spaces can't be tested on one screen (spec §13).

## Sign-off

- Tester / date:
- Mac, macOS version (deployment target macOS 26):
- Trackpad / mouse:
- Overall: PASS / FAIL
- Notes:
