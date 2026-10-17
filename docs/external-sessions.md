# Sessions from other tools

Wallflower reads Claude Code's own session registry (see [registry-format.md](registry-format.md)). Any other tool can show up in the same capsule by writing one small JSON file per session into a folder Wallflower watches. Codex CLI, Gemini CLI, Cursor, Copilot CLI, OpenCode, your own scripts: if it can run a shell command when a session starts, changes and ends, it can have a face.

This page is the contract: where the files go, what is in them, how Wallflower decides a session is alive, and a helper script so a hook or a wrapper needs no JSON of its own.

> Wallflower ships no reader for any particular tool, and none of the examples below were tested against a real Codex, Gemini, Cursor or Copilot install. Where a section mentions a tool's hooks, check that tool's own documentation for what it actually offers.

## The folder

```
~/Library/Application Support/Wallflower/sessions/<id>.json
```

One file per session. Wallflower watches the folder and every file in it with kernel file events, so a new file, a rewrite and a deletion all show within a fraction of a second, and nothing is polled. The folder does not have to exist when Wallflower starts; it is picked up when it appears.

Wallflower only reads this folder. It never writes, rewrites or deletes a session file. Creating, updating and removing them is the writer's job.

For testing, `--external-sessions-folder <path>` points the app at another folder, and the helper script follows `WALLFLOWER_SESSIONS_DIR`.

## The file

A full example of a session that waits for a permission:

```json
{
  "id": "codex-48213",
  "tool": "codex",
  "name": "Port the parser",
  "cwd": "/Users/demo/Developer/parser",
  "status": "waiting",
  "waitingFor": "permission",
  "pid": 48213,
  "startedAt": 1791884000000,
  "updatedAt": 1791884300000,
  "statusUpdatedAt": 1791884290000,
  "open": { "command": "tmux attach -t codex-48213" }
}
```

The smallest file Wallflower accepts:

```json
{ "id": "my-session", "status": "busy" }
```

| Key | Type | Required | Meaning |
|---|---|---|---|
| `id` | string | yes | The session's identity, stable for its whole life. It must also be the file name (`<id>.json`): letters, digits, `.`, `-` and `_`, not starting with a dot, at most 128 characters. |
| `status` | string | yes | `busy` (working), `idle` (done, your turn) or `waiting` (it needs you). Nothing else. |
| `tool` | string | no | A short display name, shown before the status on hover: `codex · Working · 2m`. |
| `name` | string | no | What the face says on hover. Without it: the last folder of `cwd`, then `<tool> session`, then the `id`. |
| `cwd` | string | no | The session's working directory. Its last component picks the project colour (shared with Claude sessions in the same folder), and an `open.command` runs there. |
| `waitingFor` | string | no | While `waiting`: `question` (shows "Needs input") or `permission` (shows "Needs permission", with a faster pulse). Anything else shows "Needs you". |
| `pid` | number | no | The process that owns the session. When present, the session ends the moment that process exits. Recommended. |
| `updatedAt` | number | no | Epoch milliseconds of the last write. Without a `pid` it decides liveness (see below). The file's modification time counts too, whichever is later. |
| `statusUpdatedAt` | number | no | Epoch milliseconds the current status began: the "2m" on hover and the 15 minute your-turn window. Defaults to `updatedAt`. |
| `startedAt` | number | no | Epoch milliseconds the session started. Defaults to the file's creation time. A thrown-out face stays hidden for this session only; a new session under the same id (a different `startedAt`) shows again. |
| `open` | object | no | What a click does. Exactly one of `{"url": "..."}`, `{"app": "<bundle id>"}` or `{"command": "..."}`; see below. |

Rules:

- The file is a UTF-8 JSON object. Unknown keys are ignored, so you can keep your own data in it.
- A file that is not valid JSON, has no `id` or `status`, or has an unknown `status` is skipped (and logged at debug level, see Debugging). An optional key with the wrong type is treated as absent.
- Times are numbers of milliseconds since 1970 (`$(date +%s)000` in a shell is fine).
- Hidden files (starting with `.`) and files not ending in `.json` are ignored, so a writer can use `.<id>.json.tmp` as its temp file.

## Lifecycle

1. **Start:** write `<id>.json` with the first status.
2. **Every status change:** rewrite the whole file. Best is atomically: write a temp file in the same folder, then rename it over the old one. Rewriting in place works too; a file caught half written is kept as it was until the next complete write.
3. **Exit:** delete the file.

How Wallflower decides a session is alive:

- **With a `pid`:** while that process runs. The kernel reports its exit, so a crash or a `kill -9` ends the face at once, even though the file stays behind. A file whose pid is gone is ignored.
- **Without a `pid`:** for **10 minutes** after its last write (`updatedAt` or the file's modification time, whichever is later). A pid-less session has to refresh at least that often: rewrite the file, run `wallflower-session touch`, or just `touch` the file. Wallflower arms one timer for the next expiry, never a repeating one.

A deleted file ends the session either way. An ended face closes its eyes and fades out like a Claude session's.

Stale files (from a crash) are harmless: Wallflower ignores them, and the next `start` with the same id replaces them.

## Clicking a face

`open` decides:

| `open` | A click |
|---|---|
| `{"url": "https://..."}` | Opens the URL with the system (any scheme a Mac can open: `https`, `vscode://`, a tool's own deep link). |
| `{"app": "com.example.Editor"}` | Brings the app with that bundle id to the front (launching it if needed). |
| `{"command": "tmux attach -t work"}` | Runs the command in a new window of your default terminal app, in `cwd` when there is one. |
| none, with a `pid` | Brings forward the app the process runs in (Terminal, iTerm, an editor), found by walking up its parent processes. |
| none, no `pid` | Nothing. |

The command runs exactly as written, as you, through a `.command` file in Wallflower's Application Support folder, like an action face. Anything that can write the sessions folder can already run commands as you, but do not put text you did not write yourself into it.

## In the capsule

External sessions are faces like any other:

- The same states and motion: working (the cloud), just finished (the mint burst), your turn for 15 minutes or until you click it, idle, sleepy after half an hour, needs input (amber, the hop and the halo), and the excited hop when a resting session starts working again.
- The same sort: needs input, working, your turn, idle, newest change first.
- The same colours: in Project mode the hue comes from the last folder of `cwd`.
- Hover shows the name and `tool · status · time`. A long tool name is shortened before the status or the time is.
- What they do not have: a working substate (coding, reading, running), subagent satellites or a branch line. Wallflower reads those from Claude's transcripts and knows nothing about other tools' files.
- "Show sessions from" (Claude app, terminals, everywhere) only filters Claude sessions. External sessions always show, unless **Settings > General > Sessions from other tools** is off.
- Throwing a face out hides that session until it ends, and the menu bar's Show hidden sessions brings it back.

## The helper script

[`scripts/wallflower-session`](../scripts/wallflower-session) writes these files for you: plain bash, `sed` and `date`, nothing to install. Copy it to a folder on your `PATH`:

```sh
cp scripts/wallflower-session /usr/local/bin/    # or ~/bin, ~/.local/bin, wherever your PATH looks
chmod +x /usr/local/bin/wallflower-session
```

```sh
wallflower-session start  --id ID [--tool NAME] [--name TEXT] [--cwd DIR] [--pid PID]
                          [--status busy|idle|waiting] [--waiting-for question|permission]
                          [--open-url URL | --open-app BUNDLE_ID | --open-command COMMAND]
wallflower-session status --id ID busy|idle|waiting [--waiting-for question|permission]
wallflower-session touch  --id ID     # refresh updatedAt (pid-less sessions)
wallflower-session end    --id ID     # delete the file; fine to call twice
wallflower-session path   [--id ID]   # print the folder or the file
```

- `start` defaults to `idle` and writes `startedAt`, `updatedAt` and `statusUpdatedAt`.
- `status` keeps every other field and only restarts the status clock when the status (or `waitingFor`) actually changes.
- `--id` can be left out when `WALLFLOWER_SESSION_ID` is set: a wrapper exports it once, and hooks the tool runs inherit it.
- Every write goes to a hidden temp file and is renamed into place.
- `status`, `touch` and `end` work on files the script wrote; it reads its own one-key-per-line layout back and does not parse arbitrary JSON. A tool that writes its own JSON does not need the script at all.
- `WALLFLOWER_SESSIONS_DIR` overrides the folder.

## Hooking it up

### Any CLI: a wrapper

A wrapper script gives any command-line tool a face for as long as it runs. Save it as, say, `codex-wf` next to the helper and run `codex-wf` instead of `codex`:

```sh
#!/bin/bash
# Runs a CLI with a face in Wallflower: started now, gone when the CLI exits.
export WALLFLOWER_SESSION_ID="codex-$$"
wallflower-session start --tool codex --name "${PWD##*/}" --cwd "$PWD" --pid $$ --status busy
trap 'wallflower-session end' EXIT
codex "$@"
```

- `--pid $$` is the wrapper itself, which lives exactly as long as the tool. If the terminal window is closed or the wrapper is killed, the face ends anyway.
- With no `open`, a click brings forward the terminal app the wrapper runs in.
- The wrapper alone only knows that the session exists. Pick the status that fits: `busy` for a one-shot run (`codex-wf exec "fix the tests"`), `idle` for an interactive session that starts by waiting for you. For live status, add hooks.

### Tools with lifecycle hooks

Many tools can run a command on events such as "a turn finished", "a prompt was submitted" or "permission needed". Point those at the helper:

| Event | Command |
|---|---|
| You sent a prompt, the tool starts working | `wallflower-session status busy` |
| The tool finished its turn | `wallflower-session status idle` |
| It asks you a question | `wallflower-session status waiting --waiting-for question` |
| It waits for a permission | `wallflower-session status waiting --waiting-for permission` |

Run the tool through the wrapper above, so `WALLFLOWER_SESSION_ID` is set for the hooks, or pass `--id` yourself. Examples of hook mechanisms that exist at the time of writing, none of them verified here: Codex CLI's `notify` setting (a program run when a turn completes), Gemini CLI's hooks, and Claude Code style hooks (`UserPromptSubmit`, `Stop`, `Notification`) in tools that copied that design. What events a tool offers, what it passes to the command and how it is configured is up to that tool; read its documentation.

### Writing the file yourself

A tool or plugin that writes the JSON itself needs nothing else. Write it atomically (temp file in the same folder, then rename), include a `pid` if there is a process that lives as long as the session, delete it on exit, and refresh it at least every 10 minutes if there is no pid.

## Debugging

- Run a second copy of the app on a test folder: `Wallflower --external-sessions-folder /tmp/test-sessions --sessions-folder /tmp/empty --defaults-suite test`, and point the script at it with `WALLFLOWER_SESSIONS_DIR=/tmp/test-sessions`.
- Skipped files are logged once per file name at debug level:

  ```sh
  log stream --level debug --predicate 'subsystem == "dev.wallflower.Wallflower" AND category == "registry"'
  ```

- `wallflower-session path --id ID` prints the file a session lives in.
