# SplitKit working rules

- `Docs/Phase0-Spec.md` is the source of truth. Read the relevant sections before changing code.
- Work in small, focused PRs on branches. Never commit to `main`. Never merge: Marc approves merges.
- Every PR body carries the §13 report: exact commands, exit codes, test counts (pass/fail/skip), coverage when applicable, known gaps, and manual checks for Marc. Claim nothing as working without evidence.
- Any deviation from the spec needs a written deviation report and Marc's approval before merge.
- Update `Docs/Traceability.md` in every PR.
- Toolchain (spec §1): Xcode 27.1, Swift 6.4, Swift 6 language mode, macOS 26 minimum with no legacy shims or availability branches. Both manifests start with `// swift-tools-version: 6.2`. CI pins Xcode 27.1 and fails on any other.
- Package graph (spec §3): content products depend on `SplitKitContent`, never on the `SplitKit` UI target. No target in `SplitKit/` depends on `SplitKitViews/`.
- Never delete files you did not create in the task.
- If the spec is ambiguous, stop and report instead of guessing.
