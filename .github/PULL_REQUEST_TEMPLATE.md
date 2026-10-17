## What and why

<!-- What does this change, and what problem does it solve? Link the issue if there is one. -->

## How you tested it

<!-- Tests added or run, and what you tried by hand (a fake registry with --sessions-folder works well). Screenshots or a short recording help for visual changes. -->

## Checklist

- [ ] `swift build` and `swift test` pass.
- [ ] Nothing new runs at rest: no timers, no polling, no per-frame work. Loops stay in Core Animation.
- [ ] New tunable values live in `Theme.swift` (or `DataTuning.swift`) with a comment.
- [ ] Reduce Motion still works.
- [ ] New fixtures are anonymised (made-up names, paths under `/Users/demo/`).
- [ ] `CHANGELOG.md` updated under Unreleased for user-facing changes.
