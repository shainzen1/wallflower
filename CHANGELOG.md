# Changelog

All notable changes to Wallflower are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.2] - 2026-10-22

### Added

- A disk image to install from: open `Wallflower.dmg` and drag Wallflower onto Applications in its window, no zip to unpack. Every release carries it under that same name, so [the latest download link](https://github.com/shainzen1/wallflower/releases/latest/download/Wallflower.dmg) always gets the newest version.
- A **Download for macOS** button at the top of the README, straight to that disk image.

### Changed

- Install instructions in the README and the release notes start from the disk image. The versioned zip stays on every release as the payload of in-app updates; you never need to download it.
- License: from this version on, Wallflower is under the MIT License with the Commons Clause: free to use, change and share, but not to sell. Versions up to 0.1.1 stay under the plain MIT License. Settings > About and the app's Info say so.
- The app carries the license texts in `Contents/Resources`: its own and that of [Sparkle](https://sparkle-project.org), which it bundles for updates. `THIRD_PARTY_NOTICES.md` lists Sparkle's notices.

### Removed

- The Buy me a coffee button in Settings > About and the donation links in the README and on GitHub: the donation page does not exist yet. They come back once it does.

## [0.1.1] - 2026-10-22

### Changed

- Privacy: Wallflower now makes one kind of network request, the weekly update check (see Added), and Settings turns it off. Still no system profile, no analytics and no telemetry.
- Your turn is louder and has its own colour: a vivid lime in every Colour setting (it used to keep the project or session colour, so in a repo with several sessions it looked like the working ones). Its glow and edge line are stronger, and the amber of needs input got a stronger glow and edge line too, so it stays the loudest. The project colour green became emerald and the per-session sage became seafoam, so nothing else looks like the lime.

### Added

- In-app updates with [Sparkle](https://sparkle-project.org): once a week Wallflower asks GitHub whether there is a newer version and, if so, shows what changed and installs it in place when you click Install Update. **Check for Updates…** in the menu bar menu checks right away; Settings > General has **Check for updates automatically** (weekly) and **Check Now** with the time of the last check. Updates are verified with an EdDSA signature before they are unpacked. The check sends no system profile, and nothing downloads until you say so. Coming from 0.1.0, install this version by hand once.
- Model and effort per action: an action can start Claude Code with its own model (`claude --model`, an alias such as `sonnet` or a full model id) and effort (`claude --effort`, `low` to `max`), so a routine prompt can run on a cheaper model. Set them in the action editor's Model and Effort pickers (Custom… takes a full model id) or as `model` and `effort` in `actions.json`; Default leaves them out. They apply when actions run in Terminal; the Claude app ignores them. The actions list shows them after the days.

## [0.1.0] - 2026-10-17

The first public release.

### Added

- A black capsule on the right screen edge with one animated face per running Claude Code session.
- Faces whose shape shows the status: a drop for needs input, a cloud for working, a capsule for idle, a mint burst for just finished.
- Your turn: a session whose turn just ended stays a soft mint, looks at you and shows a quiet mint line on the capsule's edge for 15 minutes or until you click it, then settles to a more muted idle. The panel sorts needs input, working, your turn, idle. Working substates, subagent satellites, and an attention halo and hop that tell questions from permission prompts.
- Faces get excited when your message arrives: a resting or waiting session that starts working opens its eyes wide, hops twice and brightens for a moment.
- The glow behind a face lifts with it when it hops.
- Dock-style magnification on hover, with the session's name, status, time in that state and git branch in a goo bulge.
- Click a face to open that chat in the Claude desktop app; terminal sessions bring their terminal app forward.
- Drag the capsule along the edge; the position is remembered.
- Panel side: Settings > General docks the capsule to the left or the right screen edge, live. On the left everything is mirrored: the bulge opens rightward with right-aligned text, the edge cue sits on the capsule's right edge, the faces look and stretch toward the screen and a face is thrown out to the right.
- Throw a face out of the capsule to stop watching that session; Show hidden sessions in the menu brings them back.
- Action faces from `actions.json` that run a saved prompt with `claude` in a background Terminal window, or optionally as a new chat in the Claude app (sent for you with Accessibility permission).
- An actions editor in Settings > General: add, edit, reorder and remove action faces (name, folder with a folder picker, prompt, weekdays) without touching JSON. Changes save to `actions.json` as you type and the panel follows live; the app ships with no actions. Edit JSON… still opens the file.
- Sessions from other tools: any tool (Codex CLI, Gemini CLI, Cursor, Copilot CLI, OpenCode, your own scripts) can show a face by writing one JSON file per session into `~/Library/Application Support/Wallflower/sessions/`. Same states, colours and sorting as Claude sessions; the hover names the tool (`codex · Working · 2m`); a click opens the file's URL, app or command. `scripts/wallflower-session` writes the files from a shell, a wrapper or a hook. Documented in `docs/external-sessions.md`; Settings > General > Sessions from other tools turns them off.
- Menu bar menu, Settings (General, Appearance, About) and a first-launch welcome.
- About tab as a small credits card: made by Shain Gerstner (linked to GitHub) at osoro.studio, View on GitHub and a Buy me a coffee button.
- Launch at login.

### Fixed

- The welcome's Set up page keeps the "Where do you run Claude Code?" choice and the Launch at login switch inside their card.

[0.1.2]: https://github.com/shainzen1/wallflower/compare/v0.1.1...v0.1.2
[0.1.1]: https://github.com/shainzen1/wallflower/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/shainzen1/wallflower/releases/tag/v0.1.0
