# Traceability matrix

Seeded from Phase0-Spec.md §13.1. Updated by every PR.

| Requirement ID | Requirement | Spec section | Code location | Verification | Status |
|---|---|---|---|---|---|
| R-TREE | Tree invariants, flattening, fractions | §6.1 | - | unit + property | not started |
| R-TXN | Transactions incl. self-drop no-op, swap, cross-window dock atomicity | §6.2 | - | unit + property | not started |
| R-FAIL | Failed op leaves all observable state unchanged | §6.2 | - | integration (failed detach/dock/close/insert) | not started |
| R-CLOSE | Two-stage close; runtime-only pending | §6.3 | - | unit + integration | not started |
| R-STATE | State ownership / single host | §6.4 | - | counter test, debug assertion | not started |
| R-HDR | Header contents, focus toggle, overflow | §7.1, §7.4 | - | snapshot + manual | not started |
| R-THEME | `.glass`/`.plain`, tokens, accessibility | §7.2 | - | snapshot + P2 example | not started |
| R-FOCUS | activePane / focusModePane rules | §7.3 | - | unit + manual | not started |
| R-KEYS | Shortcut table, collisions, close-semantics usability | §7.5 | - | unit + manual usability check | not started |
| R-PERSIST | Validation, unavailable placeholders, orphan drop, atomic first and later save | §8 | - | unit + fault-injection | not started |
| R-WIN | Placement fallback, no drift, ownership modes | §9 | - | simulated displays + manual | not started |
| R-3D | Camera contract, corpus | §10 | `Spikes/SpikeB` (`SpikeBCore`, `SpikeBDemo`, `SpikeBRender`); ADR `Docs/ADR/0002-spike-b-gltfkit2-realitykit.md` | Spike B gate + manual: `swift test` in `Spikes/SpikeB` (CameraControllerTests, CorpusTests); `Docs/Manual/SpikeB-checklist.md` | spike evidence, PR Spike B (automated rows pass; camera + PBR manual pending) |
| R-PROD | One product per view, clean consumer build | §2, §11 | `SplitKit/Package.swift`, `SplitKitViews/Package.swift` | per-product CI job | products declared, consumer build pending |
| R-TOOL | tools-version 6.2, Xcode 27.1 pinned in CI | §1 | `SplitKit/Package.swift`, `SplitKitViews/Package.swift`, `.github/workflows/ci.yml` | CI check | in progress, PR 1 |
