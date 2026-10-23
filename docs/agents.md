# Agents beyond Claude Code

Claude Code sessions show up on their own: Wallflower reads Claude Code's session registry (see [registry-format.md](registry-format.md)). Other coding agents get a face once you connect them in **Settings > Agents** (or tick them in the welcome tour). Connecting adds a small hook to that agent's own settings; the hook reports a session's status into the folder described in [external-sessions.md](external-sessions.md), and the capsule shows it like any other face.

This page lists every agent, what its faces can show, how Wallflower hooks into it, which file it touches, and the rules every connection follows.

## Supported agents

Statuses: **W** working, **Q** needs input (a question), **P** needs permission, **T** your turn (the turn ended), **E** ended.

| Agent | Shows | Mechanism | File Wallflower touches | Notes |
|---|---|---|---|---|
| Codex (CLI, Codex in the ChatGPT app, Codex in VS Code) | W, P, T, E | Lifecycle hooks | `~/.codex/hooks.json` (entries added) | Codex runs a new hook only after you trust it once (see below). |
| GitHub Copilot (CLI, Copilot's agent in VS Code) | W, Q, P, T, E | Hook drop-in | `~/.copilot/hooks/wallflower.json` (a file of Wallflower's own) | The most complete set of any agent. VS Code's hooks are a preview feature. |
| Gemini CLI | W, P, T, E | Hooks in settings | `~/.gemini/settings.json` (entries added) | Applies to new Gemini sessions. |
| Cursor (the editor's agent) | W, T, E | Hooks | `~/.cursor/hooks.json` (entries added, or the file created) | Cursor doesn't report approval prompts, so its faces show working and done only. |
| OpenCode 1.x | W, Q, P, T, E | Plugin | `~/.config/opencode/plugins/wallflower.js` (a file of Wallflower's own) | Runs inside OpenCode and writes the status files itself. Restart OpenCode after connecting. OpenCode 2 plugins are not supported yet. |
| Windsurf / Devin Desktop (Cascade) | W, T | Hooks | `~/.codeium/windsurf/hooks.json` (entries added) | No approval or session-end event: a face stays until Windsurf quits. |
| Devin CLI | W, P, T, E | Hooks | `~/.config/devin/config.json` (entries added) | Applies to new Devin sessions. |
| Goose (experimental) | W, T, E | Plugin with hooks | `~/.agents/plugins/wallflower/` (a folder of Wallflower's own) | Goose's hooks are new (May 2026). |

### Coming soon

| Agent | Why not yet |
|---|---|
| Amp | Its plugin API is new; Wallflower hasn't been tested against it yet. |
| Kiro CLI | Kiro doesn't document what its hooks receive yet. |
| Aider | Aider only reports when a reply is done (`notifications-command`), not when it starts working. |
| Antigravity CLI | Its hooks are new and not settled yet. |

### Not possible

| Agent | Why |
|---|---|
| ChatGPT chats (Chat, Work) | ChatGPT doesn't share chat status with other apps. Codex in the ChatGPT app works: connect Codex. |
| Claude app chats | Only Claude Code sessions report their status. Regular Claude chats don't. |
| Zed's agent | Zed has no way for other apps to see its agent's status yet. |
| Warp's agent | Warp keeps agent status inside Warp. Agents you run in Warp's terminal (Codex, Gemini, ...) work. |
| Roo Code | No hooks Wallflower could use. |
| Cline | Cline is changing its hook system; support comes once it settles. |
| Cloud agents (Cursor, Codex, Copilot) | They run on a server, so there's nothing on your Mac to watch. |

## Questions that can't be seen

Codex (plan mode, `request_user_input`), Gemini (`ask_user`) and Devin have no hook event for "the agent asked you a question". While one waits for your answer, its face keeps showing **working**. Permission prompts do have an event (except in Cursor and Windsurf) and show as **needs permission**. Copilot and OpenCode report questions too and show **needs input**.

## How it works

```
agent --hook event (JSON on stdin)--> wallflower-hook <tool> <event>      (a few milliseconds)
                                          |
                    atomic write / delete v
       ~/Library/Application Support/Wallflower/sessions/<tool>-<session id>.json
                                          |
                    Wallflower's watcher (kernel file events, nothing polls)
```

- **The helper.** `wallflower-hook` ships inside the app (`Contents/Helpers`). Connect copies it to `~/.local/share/wallflower/bin/wallflower-hook`, a path without spaces, so every agent's hook command names it without quoting, whether the agent runs commands through a shell (Codex: `$SHELL -lc`, Gemini and Windsurf: `bash -c`, Goose: `sh -c`) or not. At launch Wallflower replaces an installed copy that differs from its own (an update); it never installs one before you connect an agent. The last Disconnect removes it.
- **What it keeps.** From each event's JSON it reads only the session id, the folder (`cwd` or the first workspace root), the notification type and the event's time. Prompts, replies, tool input, transcript paths and (Cursor) your account email are never copied anywhere. It prints nothing, on stdout or stderr, and always exits 0, so it can't block, fail or steer an agent; a hard two-second stop ends it in any case.
- **Which process owns a session.** The helper walks up from the hook to the agent's own process (`codex`, `node` running `gemini` or `copilot`, `cursor-agent`, `devin`, `goose`), whose exit ends the face. Inside an editor it takes the editor itself (Cursor, VS Code, Windsurf), and only that one, never just any app further up. A click on a Codex thread in the ChatGPT app opens `codex://threads/<id>`; a click on an editor's session brings the editor forward; a CLI session brings its terminal forward.
- **Event order.** Each file keeps the time of the last event it applied (`eventAt`); an older event (two hooks racing) changes nothing.
- **OpenCode** needs no helper: the plugin runs inside OpenCode and writes the same files with OpenCode's own process id.

### Per agent

| Agent | Events registered | Status mapping |
|---|---|---|
| Codex | `SessionStart`, `UserPromptSubmit`, `PermissionRequest`, `PostToolUse`, `Stop`, `Interrupt`, `SessionEnd` | start: create as your turn; prompt or tool done: working; permission: needs permission; stop or interrupt: your turn; end: delete |
| Gemini CLI | `SessionStart`, `BeforeAgent`, `AfterTool`, `Notification` (`ToolPermission`), `AfterAgent`, `SessionEnd` | the same; timeout in milliseconds (5000) |
| Cursor | `sessionStart`, `beforeSubmitPrompt`, `stop`, `sessionEnd` | prompt: working; stop: your turn |
| Copilot | `sessionStart`, `userPromptSubmitted`, `postToolUse`, `notification` (`permission_prompt`, `elicitation_dialog`), `agentStop`, `sessionEnd` | `agent_idle` notifications are a background agent's, not this session's, and are ignored |
| Windsurf | `pre_user_prompt`, `post_cascade_response` | working, your turn |
| Devin CLI | as Codex, without `Interrupt` | |
| Goose | `SessionStart`, `UserPromptSubmit`, `Stop`, `SessionEnd` | |
| OpenCode | `session.created`, `session.status`, `session.idle`, `permission.asked` / `.replied`, `question.asked` / `.replied` / `.rejected`, `session.error`, `session.deleted` | subagent sessions (with a `parentID`) get no face |

Every hook command is `<helper> <tool> <event>`: the event comes from the command line, since Copilot's payloads don't name it.

## Codex: the one-time trust step

Codex runs a user hook only after you reviewed and trusted it. After Connect, type `/hooks` in a Codex chat and trust the Wallflower entries, or in the ChatGPT app open **Settings > Hooks**. You do this once (and again only if the hook changes).

Settings > Agents shows whether that happened. When you open the tab, and right after Connect, Wallflower starts Codex's own app server (`codex app-server --stdio`, the `codex` inside the ChatGPT app first, then `~/.local/bin`, `/opt/homebrew/bin`, `/usr/local/bin`) for one exchange: `initialize`, then `hooks/list` for your home folder, and reads each Wallflower hook's `trustStatus` and `enabled`. It never asks on a timer, and the process ends after the reply (or after five seconds). The row then reads "Waiting for you to trust the hooks in Codex" with a **How** button, "Connected", or that the hooks are turned off in Codex.

If `[features] hooks = false` is set in `~/.codex/config.toml`, Wallflower says so and never turns hooks back on. If `config.toml` already defines hooks inline, Wallflower doesn't add a second source (Codex warns about that); it shows the lines to add yourself instead.

## The rules every connection follows

- **Detection is existence only.** An agent counts as installed when its folder (`~/.codex`, `~/.gemini`, `~/.cursor`, `~/.copilot`, `~/.config/opencode`, ...) or its app exists. No file of an agent is read before you open Settings > Agents or tick it in the welcome.
- **Strict JSON or nothing.** A config file is edited only when it is strict JSON (no comments, no trailing commas, no duplicate keys, no byte order mark) and not a link to another file. Otherwise Wallflower shows the exact lines with a **Copy** button and you add them yourself. Gemini allows comments in `settings.json`; such a file gets the Copy sheet.
- **Only Wallflower's lines change.** The edit inserts Wallflower's entries and leaves every other byte alone: key order, spacing and indentation stay. The consent sheet lists every line before anything is written.
- **Backup first.** Before changing a file, Wallflower copies it to `~/Library/Application Support/Wallflower/backups/<tool>/` (the last five per file). Nothing is ever left beside the agent's own file.
- **Atomic, and never over a change.** The new file goes to a temporary file next to it and is renamed into place, with the original's permissions. If the file changed between reading and writing (the agent or you saved it), nothing is written and you are asked to try again.
- **A record of every write.** `~/Library/Application Support/Wallflower/integrations.json` lists each file written, whether Wallflower created it, the keys it added, and the backup.
- **Disconnect removes only Wallflower's part.** Entries whose command names `wallflower-hook` go; a group you share with your own hooks keeps yours. A file Wallflower created is deleted, folders it created are removed when empty. A file untouched since Wallflower wrote it gets its backup back, byte for byte.
- **Prefer drop-ins.** Where an agent reads a folder of hook files (Copilot, OpenCode, Goose), Wallflower writes a file of its own there and never opens yours.
- **Never Claude Code hooks.** Claude Code is read from its registry; Wallflower writes nothing into `~/.claude`.
- **Nothing on quit.** Quitting Wallflower leaves the hooks in place (they just write files nobody reads). **Settings > Agents > Disconnect all** removes every one; do that before deleting the app. A hook left behind after the app is gone fails harmlessly.

The **Show** switch next to a connected agent only hides or shows its faces. It never edits a config file; **Disconnect** (in the row's menu) and **Disconnect all** do.

## Troubleshooting

- **No face appears.** Codex: trust the hooks (`/hooks`). Gemini, Devin, Codex: start a new session; running sessions read their hooks at start. OpenCode, Goose: restart them. Copilot with the session sandbox on: user hooks run inside the sandbox and may not be allowed to write to Wallflower's folder.
- **A face stays.** Sessions without an owner process expire 10 minutes after their last event. Windsurf has no session-end event, so its faces stay until Windsurf quits.
- **Check the helper by hand:**

  ```sh
  echo '{"session_id":"test-1","cwd":"/tmp"}' | ~/.local/share/wallflower/bin/wallflower-hook codex UserPromptSubmit
  ls ~/Library/Application\ Support/Wallflower/sessions/   # codex-test-1.json
  echo '{"session_id":"test-1"}' | ~/.local/share/wallflower/bin/wallflower-hook codex SessionEnd
  ```

## For developers

- Code: `Sources/WallflowerHookCore/` (the helper's logic: events, payload allow-list, owner walk, file writer), `Sources/WallflowerHook/main.swift` (the executable), `Sources/AgentOverview/Agents/` (the catalog, the installers, the strict JSON editor, the manifest and safe writes, the Codex trust check, the Settings model), `Settings/AgentsSettingsView.swift`, `Onboarding/WelcomeAgents.swift`.
- Every installer works through an `AgentEnvironment`, which names the home folder. Tests and `--tools-home <dir>` use a fixture home; nothing can reach the real one there. `--connect-agents <list>`, `--disconnect-agents <list|all>`, `--agent-sheet <tool>` and `--welcome-agents <list>` drive it from the command line (see [DEVELOPMENT.md](DEVELOPMENT.md)).
- Tests use synthetic payloads in `Tests/Fixtures/agents/<tool>/`, built from each agent's documentation, with a canary string in every field Wallflower must drop; the tests check it never reaches the sessions folder.
- Sources: Codex hooks (learn.chatgpt.com/docs/hooks.md, the app server's `hooks/list` in openai/codex), Gemini CLI hooks (geminicli.com/docs/hooks), Cursor hooks (cursor.com/docs/hooks), Copilot CLI hooks (docs.github.com, Copilot CLI hooks reference) and VS Code agent hooks, OpenCode plugins (opencode.ai/docs/plugins), Cascade hooks (docs.devin.ai/desktop/cascade/hooks), Devin CLI hooks (docs.devin.ai/cli), Goose hooks (goose-docs.ai). Checked October 2026; agents change their hook formats, so a format may move after that.
