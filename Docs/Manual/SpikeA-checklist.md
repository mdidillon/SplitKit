# Spike A manual checklist: cross-window live-content transfer

For Gate A (spec §11), together with `Docs/ADR/0001-spike-a-live-transfer.md`. Run on the MacBook (trackpad; repeat items 1 and 3 with a mouse if you have one).

## Setup

```sh
cd Spikes/SpikeA-LiveTransfer
swift run SpikeADemo (or open `Spikes/SpikeA-LiveTransfer/SpikeALiveTransfer.xcodeproj` in Xcode 27.1 and run the `SpikeALiveTransfer` scheme; the app bundle is preferred for real drag/activation behaviour)
```

Two windows open:
- **Window A:** *Counter* (left) and *3D Spinner* (right, an orange shape rotating with an `angle …°` readout).
- **Window B:** two empty panes ("Empty pane: drop here") and a red **Locked** pane (an invalid drop target).

Drag a pane by its **header** (the grey bar with `⠿ Title`). **Move ⇥** in the header, or *Pane ▸ Move to Other Window* (⌥⌘M), does the same move without dragging. *Pane ▸ Residue Report…* (⌥⌘R) shows a census of both windows. The Terminal prints a `[SpikeA]` line for every begin, move, cancel and residue report.

**Baseline:** press ⌥⌘R once at the start and keep the numbers (expected: Window A `hosting=2 containers=2 placeholders=0 highlights=0`, Window B `hosting=0 containers=0 placeholders=0 highlights=0`). "No residue" below means ⌥⌘R shows the same numbers as before that step (and the same `views=` count), with `attachmentCounts: [1, 1]`.

## Checks

| # | Step | Expected | Result (PASS/FAIL + notes) |
|---|---|---|---|
| 1 | Click **+1** on the counter until it shows 5. Click into the text field and type `abc` (focus ring on the field). Drag the Counter header into an empty pane of Window B and drop. | The counter lands in Window B showing **5** and `abc`; the `content-…` ID under it is unchanged. Window B becomes key, and the **text field has the focus ring**. Typing `d` goes into that field (`abcd`) without clicking. "view-local taps" may reset to 0 (documented). Window A's pane shows "Empty pane". Terminal: `moved … responder moved`. | |
| 2 | Note the 3D `angle` readout. Click the 3D Spinner header once (pane focus ring appears), then drag it into the other empty pane of Window B. | The shape is **drawn and keeps rotating** in Window B, continuing from about the same angle (no jump back to 0°). The pane has the focus ring and Window B is key. Terminal: `responder moved`. | |
| 3 | Start dragging the Counter header, move over an empty pane in the other window (blue highlight), then press **Esc** before releasing. | The drag image animates back. No highlight or "Moving…" overlay remains anywhere. The counter is still in its pane with the same count and text, and the focus is unchanged. ⌥⌘R shows **no residue**. Terminal: `cancelled …`. | |
| 4 | Drag the 3D header **outside both windows** (onto the Desktop or Finder) and release. | Drop refused: the image animates back, nothing changes, the shape keeps rotating, and there's no residue (⌥⌘R). Terminal: `cancelled …`. | |
| 5 | Drag a content onto the red **Locked** pane and release. Repeat, this time onto a pane that already holds content. | While hovering: a **red** highlight. On release: refused, animates back, the highlight disappears, nothing moves, and there's no residue (⌥⌘R). | |
| 6 | Drag a content and drop it back onto **its own** pane. | No-op: nothing is rebuilt (the counter's "view-local taps" does **not** reset), and there's no residue. | |
| 7 | **Drag feel:** a click on the header (without moving) only focuses the pane; a drag starts after a small move (~4 pt); the drag image is readable; the highlight follows the pointer between panes and windows; a drag works from the inactive window on the first click. Rate it: good / acceptable / poor. | Feels native; no flicker; no drag starts on a plain click. | |
| 8 | Move both contents back and forth between windows ~10 times quickly (drags and ⌥⌘M mixed), then press ⌥⌘R. | Exactly 2 `hosting` and 2 `containers` in total across both windows, `placeholders=0 highlights=0`, `attachmentCounts: [1, 1]`. Counter value, text and 3D rotation still intact. The app never crashes: a crash with "double host" in the Terminal would be the debug assertion firing, which is a FAIL. | |
| 9 | With the counter text field focused in Window B, press ⌥⌘M. | The counter moves to an empty pane in the other window with the focus ring on its text field. | |

## Sign-off

- Tester / date:
- Hardware (trackpad / mouse):
- Overall: PASS / FAIL
- Notes for the Gate A decision:
