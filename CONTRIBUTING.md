# Contributing to Wallflower

Thanks for helping. Wallflower is small on purpose, so the bar is: does it make the edge of the screen calmer and clearer, without costing CPU?

## Before you start

- For a bug, open an issue with the bug report form. Your macOS and Claude Code versions matter, because Wallflower reads an undocumented format.
- For a feature, open an issue first so we can talk about it before you spend time on code.
- Read [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) for the architecture, and [docs/registry-format.md](docs/registry-format.md) for the Claude Code files Wallflower reads.

## Build and test

You need macOS 26 and the Command Line Tools for macOS 26 (`xcode-select --install`). Xcode is not required.

```sh
swift build          # debug build
swift test           # all tests (swift-testing, no XCTest)
scripts/bundle.sh    # build/Wallflower.app, ad hoc signed
```

To try a change against made-up sessions instead of your own, run the debug binary with `--sessions-folder <folder>`. `docs/assets/make-hero.sh` shows how to fake a registry; DEVELOPMENT.md lists every debugging flag.

## Where things live

- **Visual tuning:** every size, colour, duration and spring is in `Sources/AgentOverview/UI/Theme.swift`, with a comment on what it does. Views read these values, never literals. Data-layer timings are in `Data/DataTuning.swift`.
- **The Swift target** is still called `AgentOverview`. The product name, bundle id and links are in `App/AppInfo.swift`.

## The performance contract

Wallflower runs all day, so these rules are not up for trade:

- **0 % CPU at rest.** No polling, no repeating timers, no `Timer`, no per-frame work on the main thread. React to file and process events (`DispatchSource`).
- **Loops live in Core Animation.** Blinks, breathing, pulses and orbits are `CAAnimation`s that run in the render server, not code that runs every frame.
- **One window resize per transition**, never per frame.
- **No network access** beyond the weekly update check (Sparkle, off in Settings), no analytics, no telemetry.

If a change needs to break one of these, say so in the pull request and explain why.

## Pull request checklist

- [ ] `swift build` and `swift test` pass.
- [ ] Nothing new runs at rest: no timers, no polling, no new per-frame work.
- [ ] New tunable values go into `Theme.swift` (or `DataTuning.swift`) with a comment.
- [ ] Reduce Motion still works (fades instead of motion).
- [ ] New test fixtures are anonymised: made-up names, paths under `/Users/demo/`, no real session ids.
- [ ] User-facing changes are in `CHANGELOG.md` under Unreleased, and in the README if they change how Wallflower is used.

## Style

Swift 6 language mode, strict concurrency. Match the code around you. Comments explain why, and measurements that led to a decision are worth writing down. In docs and UI text, keep it short and plain, use sentence-case headings, and skip em and en dashes.

By contributing, you agree that your contributions are licensed under the [MIT License](LICENSE).
