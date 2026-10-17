# SplitKit working rules

- `Docs/Phase0-Spec.md` is the source of truth. Read the relevant sections before changing code.
- Work in small, focused PRs on branches. Never commit to `main`. Never merge: Marc approves merges.
- Every PR body carries the §13 report: exact commands, exit codes, test counts (pass/fail/skip), coverage when applicable, known gaps, and manual checks for Marc. Claim nothing as working without evidence.
- Any deviation from the spec needs a written deviation report and Marc's approval before merge.
- Update `Docs/Traceability.md` in every PR.
- Toolchain (spec §1): local development on Xcode 27.1, Swift 6.4, Swift 6 language mode; deployment target macOS 26 (the dev Mac runs macOS 27.0.1; record both OS versions in reports, never add availability branches). Both manifests start with `// swift-tools-version: 6.2`; no 6.4 tools-version path in P1.
- CI (spec §1): GitHub-hosted `runs-on: xcode-27` preview image; accepts any Xcode 27.x until a final 27.1 is on the image (actions/runner-images#14850), asserting `xcodebuild -version` matches `^Xcode 27(\.|$)` and printing `xcodebuild -version` and `swift --version` into the job summary. Our selector prefers 27.1 (incl. RC) over newer 27.x betas (deviation noted in PR 1). If no 27.x is found CI goes red and Marc decides; never change the toolchain silently.
- Package graph (spec §3): content products depend on `SplitKitContent`, never on the `SplitKit` UI target. No target in `SplitKit/` depends on `SplitKitViews/`.
- Repository layout per spec §2: spikes live in `Spikes/SpikeA-LiveTransfer/` and `Spikes/SpikeB-RealityKit/` and are never a dependency of any package; ADRs are `Docs/ADR/NNNN-title.md`.
- Never delete files you did not create in the task.
- If the spec is ambiguous, stop and report instead of guessing.
