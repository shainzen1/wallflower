# Security

## Reporting a vulnerability

Please report security issues privately, not in a public issue. Use GitHub's private vulnerability reporting: open the repository's **Security** tab and click **Report a vulnerability**. You'll get a reply as soon as I can manage, usually within a week.

Please include the Wallflower version, your macOS version and the steps to reproduce.

## What Wallflower can access

Wallflower is a local app with no network access. It is useful to know what it touches when you judge an issue:

- **Reads** `~/.claude/sessions/*.json` (Claude Code's session registry), the end of each shown session's transcript and subagent files in `~/.claude/projects/`, and `.git/HEAD` in a session's working directory. It never writes to any of these.
- **Writes** its own preferences (including the list of hidden sessions) and `~/Library/Application Support/Wallflower/`: `actions.json`, and a `launch-<id>.command` script for each action face you click.
- **Runs** an action face's prompt by opening its `launch-<id>.command` script in your default terminal app, which starts `claude "<prompt>"` in the action's folder. Nothing runs unless you click an action face.
- **Opens** `claude://` links in the Claude desktop app, and brings a terminal or editor app to the front for terminal sessions.
- **Accessibility**, only if you set action faces to run in the Claude app and allow sending: it reads the Claude app's focused text field and posts key presses to the Claude app's process only, for a few seconds after you click an action face, and only while the Claude app is in front.
- **No network requests, no analytics, no telemetry.**

## Supported versions

Only the latest release gets fixes.
