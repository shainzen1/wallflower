# The Claude Code session registry

A contributor reference for the files Wallflower reads: the per-session registry files, the transcripts next to them, and the Claude desktop app's deep links. Sessions from other tools use a format of Wallflower's own, documented in [external-sessions.md](external-sessions.md).

> **This is observed behaviour of an undocumented format.** Nothing here is a public API. It was worked out by watching the files of Claude Code 2.1.29x and the Claude desktop app in October 2026, and from reading what their bundles write. Any update can rename a field, add a status or move a file. Wallflower decodes leniently (unknown keys are ignored, most keys are optional) so small changes degrade gracefully, but a big one will need a code change. If you notice a difference, please open an issue with your Claude Code version.

## Where the files are

Every running Claude Code process writes one file:

```
~/.claude/sessions/<pid>.json
~/.claude/sessions/<pid>.<hash>.key
```

The `.json` file describes the session. The `.key` file belongs to Claude Code's own messaging and is of no interest here; Wallflower ignores it.

## Fields

An anonymised example of a desktop session that is waiting for an answer:

```json
{
  "pid": 12345,
  "sessionId": "8d7fd052-5936-4c1a-9b92-0427cef1ad2c",
  "cwd": "/Users/demo/Developer/project-c",
  "startedAt": 1791875323297,
  "procStart": "Tue Oct 13 07:08:42 2026",
  "version": "2.1.295",
  "peerProtocol": 1,
  "peerFeatures": ["notify_idle", "reply_across_default_dirs", "artifact_yield"],
  "kind": "interactive",
  "entrypoint": "claude-desktop",
  "hostSessionId": "local_54ebfa84-ef42-43b8-9bb8-1e5392b286bf",
  "pidDomain": "darwin",
  "messagingSocketPath": "/tmp/cc-demo3/ccccc.sock",
  "name": "Migrate search index",
  "nameSource": "user",
  "nameSince": 1791883299742,
  "status": "waiting",
  "waitingFor": "input needed",
  "updatedAt": 1791884247734,
  "statusUpdatedAt": 1791884247734,
  "formerNames": [
    { "name": "Earlier title", "until": 1791883299742, "sessionId": "d271379f-3377-4a45-9cce-a64be194744d" }
  ]
}
```

| Key | Type | Notes |
|---|---|---|
| `pid` | number | The Claude Code process. Use it as the session's identity. |
| `sessionId` | uuid string | The current conversation id. It rotates across resumes and compactions, so never cache it. |
| `cwd` | string | Working directory of the session. |
| `startedAt` | number | Epoch milliseconds. |
| `procStart` | string | Process start time as text. Claude Code's own reader checks it together with `pid` before trusting a file. |
| `version` | string | Claude Code version that wrote the file. |
| `peerProtocol`, `peerFeatures` | number, string array | Messaging capabilities. Not used by Wallflower. |
| `kind` | string | `interactive`, even for `claude -p` print-mode runs. |
| `entrypoint` | string | Which client started the session. See below. |
| `hostSessionId` | string | `local_<uuid v4>` (42 characters). Only desktop app sessions have it. It is what the deep link needs. |
| `pidDomain` | string | `darwin` on a Mac. |
| `messagingSocketPath` | string | Present for desktop and terminal sessions alike. |
| `name` | string | The session title. |
| `nameSource` | string | `user`, `derived` (print-mode sessions are named after the first words of the prompt) or absent. |
| `nameSince` | number | Epoch milliseconds of the last rename. |
| `status` | string | `busy`, `idle` or `waiting`. See below. |
| `waitingFor` | string | Only while `status` is `waiting`; the key is absent otherwise. |
| `updatedAt` | number | Epoch milliseconds of the last write. |
| `statusUpdatedAt` | number | Epoch milliseconds of the last status change. Wallflower uses it for the "2m" in `Needs input · 2m`. |
| `formerNames` | array | `{name, until, sessionId}` per earlier title, present after a rename. The `sessionId` in an entry can differ from the current one. |

The writer also knows a few optional keys that were never observed in practice: `tmux`, `logPath`, `agent`, `jobId`, `spare`, `bridgeSessionId`, `procStartFt`.

Wallflower's decoder (`Data/SessionRecord.swift`) requires `pid`, `sessionId`, `cwd`, `startedAt`, `entrypoint` and `status`. Everything else is optional, and files that fail to decode are skipped.

## Status

The registry only ever writes three values. The writer's rule is, in effect:

```
status = a dialog is open ? "waiting" : (loading or delegated work active ? "busy" : "idle")
```

There is no "finished" or "ended" status. Wallflower derives "just finished" from a `busy` to `idle` transition, and "ended" from the process exiting.

## `waitingFor`

While `status` is `waiting`, `waitingFor` says why. It resolves in this order:

1. `input needed`: a queued elicitation. That covers AskUserQuestion, MCP elicitations and teammate setup.
2. The open dialog's kind: `dialog open` (most settings and notice dialogs, model fallback, usage credits), `sandbox request`, `goal proposal`. Any dialog kind without its own entry, which includes the normal tool permission dialog, becomes `permission prompt`.
3. Pending requests without a dialog: `worker request`, `sandbox request`, and `dialog open` for a slash-command UI that is open while nothing streams.

Wallflower maps these to three kinds (`Data/WaitingKind.swift`): `input needed` is a question (`Needs input`), `permission prompt` is a permission (`Needs permission`), anything else, including an absent value, is generic (`Needs you`).

## Entrypoints

String literals found in the Claude Code bundle: `cli`, `sdk-cli`, `sdk-ts`, `sdk-py`, `claude-desktop`, `claude-vscode`, `claude-in-teams`, `local-agent`, `ssh-remote`, `remote`, `bench`.

- The desktop app writes `claude-desktop`, and only those sessions carry a `hostSessionId`.
- `claude -p` with a clean environment writes `sdk-cli`. A terminal `claude` is expected to write `cli`.
- A process started from inside a desktop session (a shell the desktop session opened, for example) inherits `CLAUDE_CODE_ENTRYPOINT=claude-desktop` and `CLAUDE_CODE_MESSAGING_SOCKET`, so its file looks like a desktop session but has no `hostSessionId`.

## Lifecycle

- A new process writes its `.json` and `.key` files within about half a second of starting.
- Status changes are whole-file rewrites in place. A watcher on the folder alone does not see them; watch each file too (Wallflower uses a `DispatchSource` per file plus one on the folder).
- On a normal exit both files are deleted. No "ended" marker is written.
- A crash or `SIGKILL` leaves a stale file behind. Check that the pid is alive before trusting a file (`kill(pid, 0)`; `EPERM` also means alive), and watch the process for exit (`DispatchSource.makeProcessSource` with `.exit`).
- Because `sessionId` rotates, use `pid` as the identity of a row and `hostSessionId` for the deep link, and always resolve transcript paths from the current file.

## Transcripts

```
~/.claude/projects/<slug>/<sessionId>.jsonl
~/.claude/projects/<slug>/<sessionId>/subagents/agent-<id>.jsonl
~/.claude/projects/<slug>/<sessionId>/subagents/agent-<id>.meta.json
~/.claude/projects/<slug>/<sessionId>/subagents/agent-<id>.prefix.json
```

`<slug>` is the `cwd` with every character that is not an ASCII letter or digit replaced by `-` (so `/`, `.` and `_` all become `-`). See `Data/Transcript/TranscriptLocator.swift`.

Each line is one JSON object with a `type`. The last line is not always a message. Types seen at the end of a file include `user`, `assistant`, `system`, `attachment`, `last-prompt`, `custom-title`, `agent-name`, `queue-operation` and `file-history-snapshot`. Assistant lines carry `message`, `uuid`, `parentUuid`, `timestamp`, `sessionId`, `cwd`, `requestId` and `isSidechain`; many lines also carry `gitBranch`.

Useful patterns, all read from a bounded tail of the file:

- **What a working session does:** the last assistant line's last `tool_use` block names the tool (`Edit`, `Bash`, `Read`, `Agent` and so on).
- **A pending question:** the last assistant line ends with a `tool_use` named `AskUserQuestion`, whose `input.questions[]` has `question`, `header`, `multiSelect` and `options[]` (`label`, `description`).
- **A pending permission:** the last assistant line's `tool_use` (for example `Bash` with `input.command`) has no `user` line with its `tool_result` after it.
- **A finished subagent:** its transcript ends with an assistant `tool_use` named `SubagentHandback`, followed by the `user` line holding its `tool_result`. Claude Code also writes `agent-<id>.prefix.json` when a subagent completes, which makes a cheap first check. The `.meta.json` file only holds launch data (`agentType`, `description`, `toolUseId` and similar), no status. `stop_reason` is unreliable in these files.

## Deep links

The Claude desktop app registers the `claude://` scheme. Two links matter:

- `claude://code/continue?session=<hostSessionId>` switches the app to that chat, for busy and idle sessions alike, and brings the app to the front. An unknown id shows the app's home screen without an error. Nothing is reported back to the caller, and the link never starts or resumes a process by itself.
- `claude://code/new?folder=<path>&q=<prompt>` opens a new session in that folder with the prompt filled in, but not sent. The handler reads only `q` (alias `prompt`), `folder`, `file` and `ssh_host` / `ssh_port` / `ssh_folder`; every other parameter is dropped, so no URL can submit the prompt. The page also defuses prefilled text: a leading `/` arrives as U+FF0F, a leading `!` as U+FF01 and `@` mentions as U+FF20. A folder the app does not trust yet shows a "Trust this workspace?" prompt first.
