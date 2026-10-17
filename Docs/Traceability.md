# Traceability matrix

Seeded from Phase0-Spec.md §13.1 (Revision 4). Updated by every PR.

| Requirement ID | Requirement | Spec section | Code location | Verification | Status |
|---|---|---|---|---|---|
| R-TREE | Tree invariants, flattening, fractions, tree arithmetic, window-level invariants | §6.1 | - | unit + property | not started |
| R-TXN | Transactions incl. self-drop no-op, swap, cross-window dock atomicity, insert/move into empty window, open main window | §6.2 | - | unit + property | not started |
| R-IDS | Injected ID generator, fixed-seed reproducibility, byte-identical encoding | §5, §6.1.9, §8 | - | property (same seed → same bytes) | not started |
| R-RECORD | Content record lifecycle, `.unavailable` in transactions | §6.5 | - | unit + integration | not started |
| R-FAIL | Failed op leaves all observable state unchanged | §6.2 | `Spikes/SpikeA-LiveTransfer` (`HostRegistry`, `TransferCoordinator`) | integration (failed detach/dock/close/insert); spike: `HostRegistryTests.failedDropLeavesRegistryUnchanged`, `WindowTransferTests.failedDropOnInvalidTargetLeavesNoResidue`, `cancelledDragLeavesNoResidue` | spike evidence, PR Spike A (failed/cancelled drop only; product transactions not started) |
| R-CLOSE | Two-stage close incl. window close; runtime-only pending | §6.3 | - | unit + integration | not started |
| R-STATE | State ownership / single host | §6.4 | `Spikes/SpikeA-LiveTransfer` (`HostingLedger`, `HostRegistry`, `CounterContent`, `SpinnerContent`) | counter test, debug assertion; spike: `WindowTransferTests.*`, `DoubleHostAssertionTests.*` (exit tests), manual `Docs/Manual/SpikeA-checklist.md`; ADR `Docs/ADR/0001-spike-a-live-transfer.md` | spike evidence, PR Spike A (Gate A: GO recommended, manual checks pending) |
| R-HDR | Header contents, focus toggle, overflow | §7.1, §7.4 | - | snapshot + manual | not started |
| R-THEME | `.glass`/`.plain`, tokens, accessibility | §7.2 | - | snapshot + P2 example | not started |
| R-FOCUS | activePane / focusModePane rules | §7.3 | - | unit + manual | not started |
| R-KEYS | Shortcut table, collisions, close-semantics usability | §7.5 | - | unit + manual usability check | not started |
| R-PERSIST | Fatal vs recoverable validation, registry marking, unavailable placeholders, orphan drop, v0 → v1 chain, encoder setup, atomic first and later save | §8 | - | unit + fault-injection | not started |
| R-WIN | Placement coordinate space and `resolve` rules, no drift, ownership modes | §9 | - | simulated displays + manual | not started |
| R-3D | Camera contract, corpus | §10 | `Spikes/SpikeB-RealityKit` (`SpikeBCore`, `SpikeBDemo`, `SpikeBRender`); ADR `Docs/ADR/0002-spike-b-realitykit.md` | Spike B gate + manual: `swift test` in `Spikes/SpikeB-RealityKit` (CameraControllerTests, CorpusTests); `Docs/Manual/SpikeB-checklist.md` | spike evidence, PR Spike B (automated rows pass; camera + PBR manual pending) |
| R-PROD | One product per view, clean consumer build | §2, §11 | `SplitKit/Package.swift`, `SplitKitViews/Package.swift` | per-product CI job | products declared, consumer build pending |
| R-TOOL | tools-version 6.2; local Xcode 27.1; CI on `xcode-27` asserting Xcode 27.x (27.1 once available) | §1 | `SplitKit/Package.swift`, `SplitKitViews/Package.swift`, `.github/workflows/ci.yml` | CI check | done in PR 1 (CI green on `xcode-27`, Xcode 27.1 RC 27A9275) |
