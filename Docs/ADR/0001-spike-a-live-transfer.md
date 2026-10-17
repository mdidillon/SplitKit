# ADR 0001: Spike A — cross-window live-content transfer

- **Status:** Proposed (awaiting Marc's Gate A decision and the manual checklist)
- **Date:** 17 Oct 2026
- **Phase:** P1, Spike A (spec §11, Gate A; §14 risk 1)
- **Code:** `Spikes/SpikeA/` (standalone Swift package; no dependency on `SplitKit/` or `SplitKitViews/`)
- **Manual checklist:** `Docs/Manual/SpikeA-checklist.md`

## Context

Spec §14 risk 1: SwiftUI drag and drop is limited, so moving a *live* content object (spec §4, §5, §6.4) between two windows probably needs AppKit drag sessions. Gate A (§11): *"a counter and a live 3D view move between two windows with state and responder intact, cancelled drops leave no residue, and there's never a double host (asserted)"*. Go only if every criterion passes; otherwise no-go with (a) commands-only detach/dock in v1 or (b) a redesign.

## What was built

| Piece | File | Role |
|---|---|---|
| `HostRegistry` | `Sources/SpikeACore/HostRegistry.swift` | Pure value type: `ContentID → HostID`, hosts per window, the single active transfer. Validates before mutating; throws `TransferError`; checks invariants after every mutation (`preconditionFailure` in debug). Deterministic `encodedSnapshot()` for byte-for-byte comparisons. |
| `HostingLedger` | `Sources/SpikeACore/SpikeContent.swift` | View-level single-host guard shared by every pane in the app. A second claim for a content from another pane is the §12 programmer error: traps in debug, refuses (returns false) in release. |
| `SpikeContent` | `Sources/SpikeACore/SpikeContent.swift` | Cut-down `PaneContent`: `id`, `title`, `makeView()`, `didAttach`/`willDetach`, `responderKind`. |
| `CounterContent` | `Sources/SpikeACore/CounterContent.swift` | Count + text-field note in the object; "view-local taps" in `@State` (§6.4 proof content). |
| `SpinnerContent` | `Sources/SpikeACore/SpinnerContent.swift` | RealityKit `RealityView` showing a procedurally generated (MeshDescriptor) asymmetric octahedron. Rotation angle lives in the object; a main-actor rotation driver runs only while attached. |
| `PaneHostView` | `Sources/SpikeACore/PaneHostView.swift` | One pane: header + body hosting at most one `ContentHostContainer` (which wraps the only `NSHostingView` for that content). `NSDraggingDestination`, drop highlight, drag placeholder, first-responder detection (incl. field editor) and handover. |
| `PaneHeaderView` | `Sources/SpikeACore/PaneHeaderView.swift` | `NSDraggingSource` (4 pt threshold, in-app-only `.move`, private pasteboard type), "Move ⇥" button, click-to-focus. |
| `TransferCoordinator` | `Sources/SpikeACore/TransferCoordinator.swift` | Content store, registry and panes. `beginTransfer` / `validateDrop` / `completeTransfer` / `cancelTransfer` / `endDrag` / `move` / `moveToOtherWindow`, and a `residue(windows:)` census. |
| Demo | `Sources/SpikeADemo/SpikeADemoApp.swift` | Window A: Counter + 3D. Window B: two empty panes + a **Locked** pane (invalid drop target). *Pane ▸ Move to Other Window* (⌥⌘M), *Pane ▸ Residue Report…* (⌥⌘R). Logs every transfer to stdout. |

**Transfer order** (mirrors spec §6.2 "compute purely, then side effects"): validate against a copy of the registry → commit registry → uninstall source view (resigning first responder if it was inside) → install a fresh `NSHostingView` from `makeView()` for the **same object** in the destination → if the source held first responder, make the destination window key and give the responder to the content (first editable text field, or the pane itself for 3D) → verify single host. Every error is thrown before the first side effect.

**Drag lifecycle:** header drag past 4 pt → `beginTransfer` (placeholder over source) → AppKit session with a private pasteboard payload `{session, content}` → destinations validate on enter/update (accept highlight + `.move`, or reject highlight + `[]`) → `performDragOperation` completes the transfer → the source's `draggingSession(_:endedAt:operation:)` calls `endDrag`; any transfer still active (Esc, outside the app, invalid target, refused drop) is cancelled, which removes the placeholder and every highlight. A self-drop is a no-op.

## Evidence per Gate A criterion

Automated: `cd Spikes/SpikeA && swift test` → 21 tests (24 cases), 0 failures, run on Xcode 27.1 / Swift 6.4. The window tests build two real `NSWindow`s (not ordered on screen) with real `NSHostingView`s and drive the real `NSDraggingDestination` methods through a fake `NSDraggingInfo`; only the mouse-driven `NSDraggingSession` itself cannot be created in a test.

| # | Criterion | How verified | Automated test / manual check | Result |
|---|---|---|---|---|
| 1 | Counter moves between two windows with **state** intact (same object, same `ContentID`) | Move via coordinator; assert `===` identity in store and destination pane, count/note unchanged, `attachmentCount == 1`, registry host updated | `WindowTransferTests.counterMovesWithIdentityStateAndResponder`, `rapidRepeatedTransfersKeepOneHost`, `HostRegistryTests.moveKeepsContentIDAndSingleHost` | **PASS** |
| 2 | Live 3D view moves with **state** intact (angle survives, keeps animating, one driver) | Angle set, moved, compared exactly; with auto-rotation the angle carries over and keeps increasing in the destination with exactly one driver | `spinnerMovesWithIdentityAngleAndResponder`, `liveRotationContinuesAcrossMoveWithOneDriver` | **PASS** (state). Visual rendering of the re-hosted `RealityView`: **MANUAL-PENDING** (checklist 2) |
| 3 | **First responder** follows the content | Counter: field editor of the moved text field is `windowB.firstResponder`, source no longer holds it, typed text reaches the same object. 3D: pane container becomes `windowB.firstResponder` | `counterMovesWithIdentityStateAndResponder`, `spinnerMovesWithIdentityAngleAndResponder` | **PASS** (programmatic). With a real mouse drag, key-window activation + focus ring: **MANUAL-PENDING** (checklist 1, 2, 6) |
| 4 | **Cancelled** drop (Esc / outside) leaves no residue | Begin (placeholder present), hover a valid target (highlight present), exit, end with no operation; compare full residue report (view census of both windows, registry bytes, ledger, attachment counts), first responder, content state, `makeView` count | `cancelledDragLeavesNoResidue`, `HostRegistryTests.cancelledTransferLeavesRegistryByteIdentical` | **PASS**. Real Esc and drop-outside-app: **MANUAL-PENDING** (checklist 3, 4) |
| 5 | **Failed** drop (invalid target) leaves no residue | Drop on the Locked pane and on an occupied pane through the real destination methods: `draggingEntered == []`, reject highlight shown then removed, `performDragOperation == false`, registry bytes unchanged during the drag; after end, residue identical to before | `failedDropOnInvalidTargetLeavesNoResidue`, `HostRegistryTests.failedDropLeavesRegistryUnchanged` (locked, occupied, unknown host, stale session) | **PASS**. Real drop on Locked pane: **MANUAL-PENDING** (checklist 5) |
| 6 | **Never a double host (asserted)** | Throwing API: registry `place` and coordinator `add` throw `contentAlreadyHosted` and change nothing. Debug assertion: exit tests prove the process traps when one content is claimed/installed by two panes; a control exit test proves the same setup exits cleanly with one install. Random sequences check one container per content across both windows after every step | `HostRegistryTests.doubleHostThrows`, `WindowTransferTests.doubleHostThroughCoordinatorThrows`, `DoubleHostAssertionTests.ledgerDoubleClaimTraps`, `installingOneContentInTwoPanesTraps`, `installingOneContentOnceExitsCleanly`, `rapidRepeatedTransfersKeepOneHost` (300 window moves), `HostRegistryTests.rapidRandomTransfersKeepOneHost` (5,000 ops, seed `0x5A117A`) | **PASS** |
| 7 | No leaked hosting views / observers after moves | Weak refs to the old container and `NSHostingView` are nil after a move; after 300 random moves at most the 2 live hosting views remain; rotation driver count stays 1 | `counterMovesWithIdentityStateAndResponder`, `rapidRepeatedTransfersKeepOneHost`, `liveRotationContinuesAcrossMoveWithOneDriver` | **PASS** |
| 8 | Self-drop is a no-op (spec §6.2) | Drop on own pane: `[]`, no re-host, residue identical | `WindowTransferTests.selfDropIsNoOp`, `HostRegistryTests.selfDropIsNoOp` | **PASS** |
| 9 | Drag feel, threshold, drag image, highlight, cancel animation | Human | Checklist 7 | **MANUAL-PENDING** |

## Findings

**AppKit vs SwiftUI drag.**
- AppKit gives exactly the hooks Gate A needs: `draggingSession(_:sourceOperationMaskFor:)` (refuse drops outside the app, so Finder/Desktop drops fail cleanly), `draggingSession(_:endedAt:operation:)` with an empty operation for Esc / outside / refused drops (the single place to cancel and clean up), and per-view `draggingEntered/Updated/Exited/Ended` for highlights. The coordinator is the only place that mutates ownership, so both the drag and the menu command paths share one transaction.
- A SwiftUI-only path (`.draggable` / `.dropDestination` / `Transferable`) was **not built** in this spike. Without a session-end callback carrying the operation, it is unclear how the source would learn about a cancel or a failed drop to remove its placeholder. Whether the macOS 26 SwiftUI drag-session APIs close that gap was **not evaluated**. It isn't needed: AppKit hosts SwiftUI content without problems.
- The payload is a private in-app pasteboard type that carries only IDs. The live object never goes through the pasteboard; the coordinator looks it up by `ContentID`.

**Re-hosting.**
- Each move builds a fresh `NSHostingView` from `makeView()` for the same object (allowed by spec §5). View-local `@State` (the counter's "view-local taps") resets, as §6.4 documents. Re-parenting the existing `NSHostingView` across windows was not tried; the fresh-view approach keeps exactly one hosting view per content and the old one deallocates (tested).
- `RealityView` constructs and re-hosts in off-screen windows inside the test process without errors. Whether it renders correctly after a cross-window move (Metal layer, new window) can only be seen by hand.

**First responder.**
- When a SwiftUI `TextField` is being edited, the window's first responder is the shared **field editor** (`NSTextView`, `isFieldEditor`), whose `delegate` is the text field. Detecting "the content holds focus" has to check the delegate as well as the view ancestry.
- AppKit doesn't move focus between windows on its own. The coordinator resigns it in the source before removing the view, makes the destination window key, and calls `makeFirstResponder` on the content's preferred key view after `layoutSubtreeIfNeeded()`. This worked synchronously; no deferred retry was needed.

**Residue measurement.**
- The residue census counts our view classes (hosting views, containers, placeholders, highlights), the total view count, registry bytes, ledger claims and attachment counts. It **excludes the field editor's subtree**: AppKit's insertion-point indicator appeared and disappeared on its own (38 → 37 views) while a text field was being edited. That is AppKit state, not ours.
- Synchronous main-actor tests never drained the autorelease pool, so deallocation checks only passed after an `await` (the fixture's `settle()` suspends). A unit test written the other way would report false leaks.

**Spike simplifications** (see Deviations below): drops only go into empty panes; occupied panes and the Locked pane are invalid targets. Swap and edge-split semantics belong to SplitKitModel (P1 model, P3).

## Risks and gaps

1. The `NSDraggingSession` itself (mouse-driven) can't be created in a test, so the header's `draggingSession(_:endedAt:operation:)` → `endDrag` link is only covered by reading the code and by the manual checklist. Everything after it is automated.
2. A real drag across windows, key-window activation at drop time, the visual focus ring and 3D rendering after a move are **manual-pending**.
3. Not covered: closing a window or quitting during a drag, app deactivation mid-drag, drags between Spaces or full-screen windows (single-screen setup, §13 remaining risk).
4. The spike package is **not in CI** (changing `.github/workflows/ci.yml` was outside this task's scope). Proposed follow-up: add a `swift test` step for `Spikes/SpikeA`, or delete the spike after Gate A.
5. The release-mode fallback of the double-host guard (refuse instead of trap) is implemented but not tested (tests run in debug).

## Deviations from the spec (spike-only)

| Item | Spec | Spike | Why | Needs approval? |
|---|---|---|---|---|
| Drop into an **occupied** pane | §6.2: centre = swap, edge = move + split | Rejected as an invalid target | Spike scope is the live-transfer mechanism; tree semantics are SplitKitModel's job | Marc to acknowledge; not carried into product code |
| Identifiers / registry | §5 `PaneID`, `SessionEngine`, `WorkspaceRuntime.activeDrag` | Spike-local `HostID`, `HostRegistry.activeTransfer` | Spike must not depend on the SplitKit package | Marc to acknowledge; P3 maps them onto §5 types |

## Decision

**Recommendation: GO** for live cross-window transfer via AppKit drag sessions. Every automatically verifiable Gate A criterion passes, and nothing found blocks the manual ones. **This is conditional on `Docs/Manual/SpikeA-checklist.md` passing on Marc's MacBook**: criteria 2 (3D rendering), 3 (real-drag focus), 4–5 (real Esc / outside / Locked drops) and 9 (drag feel) are MANUAL-PENDING. If any manual check fails and can't be fixed within the spike, the result becomes **NO-GO**, with options (a) commands-only detach/dock in v1 (the menu path, `moveToOtherWindow`, already passes every automated check) or (b) a redesign.
