import Foundation

/// The text behind "Copy Setup Prompt" (Settings > General > Actions and the welcome's "Action faces"):
/// a prompt a person pastes into Claude Code, Codex or any coding agent, which then helps them write
/// actions into `actions.json` by hand. Pure: it takes the file's path and returns the text. The
/// allowed values come from the decoding code (`ActionSchedule`, `BlobShape`, `ClaudeEffort`, the
/// editor's model aliases), and a test checks it names every key `ActionItem` encodes, so the
/// prompt and the file format cannot drift apart.
enum ActionSetupPrompt {
    /// How long the button reads "Copied" after a click.
    static let copiedDuration: Duration = .seconds(1.5)

    /// The prompt for the file at `fileURL`, the home folder written as `~`.
    static func text(fileURL: URL, home: String = NSHomeDirectory()) -> String {
        text(filePath: ActionEditorModel.displayPath(fileURL.path, home: home))
    }

    /// The prompt for the actions file at `filePath`, as it should be shown (`~/...`).
    static func text(filePath: String) -> String {
        let days = list(ActionSchedule.weekdayKeys)
        let aliases = list(ActionEditorModel.ModelChoice.aliases.map(\.rawValue))
        let efforts = list(ClaudeEffort.allCases.map(\.rawValue))
        let shapes = list(BlobShape.allCases.map(\.rawValue))
        return """
        Help me set up actions in \(AppInfo.name) by editing its actions file.

        \(AppInfo.name) is a macOS app that shows each of my coding agent sessions as a small face at the edge \
        of my screen. An action is a saved prompt with a face of its own: a lavender star below a thin divider, \
        under the session faces. Clicking it starts a new Claude Code session that runs the prompt in the \
        action's folder. An action can show on some weekdays only, and can pick the session's model and effort.

        ## The file

        `\(filePath)`

        \(AppInfo.name) watches this file and reloads it as soon as it is saved, so there is no need to restart \
        the app. If the file does not load, \(AppInfo.name) quietly keeps the last list that worked.

        ## Format

        A JSON array with one object per action, in the order the faces show. A missing required key or a \
        wrong type in any action makes the whole file fail to load.

        Required, all strings:
        - `id`: unique and stable, lowercase letters, digits and dashes (`review-prs`). Don't change it \
        later: it names the face and its launch script.
        - `name`: shown when I hover the face, and in Settings.
        - `cwd`: the folder the session starts in, absolute or starting with `~/`. It has to exist.
        - `prompt`: the first message of the session. Slash commands work (`/review`).

        Optional. Leave a key out for its default; don't write `null`:
        - `days`: an array of the weekdays the face shows on: \(days). Default: every day. Unknown values \
        are ignored.
        - `model`: passed to `claude --model`: an alias (\(aliases)) or a full model id. Default: Claude \
        Code's own.
        - `effort`: passed to `claude --effort`: \(efforts). Default: Claude Code's own.
        - `shape`: the face's silhouette: \(shapes). Default: the action star.
        - `color`: the face's body colour as `#RRGGBB`. Default: lavender.
        - `seed`: any string; it changes the face's small quirks. Default: the id.
        - `symbol`: an SF Symbol name, reserved for later; it has no effect yet.

        `model` and `effort` apply when actions run in Terminal, the default. When Settings > General > \
        Run actions in is set to the Claude app, they are ignored.

        ## Examples

        ```json
        \(examples)
        ```

        ## How to work

        1. Read the file first. Keep every action already in it, unchanged, unless I ask otherwise. If the \
        file is missing, start from `[]`.
        2. Ask me which actions I want: what each one should do, which folder it runs in, and on which days. \
        Wait for my answers before you write anything.
        3. Check that every folder exists, for example with `ls`. Never invent a folder; if one is missing, ask me.
        4. Back up the file before you change it: copy it into the same folder with the date and time in the \
        name, such as `actions-backup-YYYYMMDD-HHMM.json`.
        5. Write valid JSON only: no comments, no trailing commas. Check it afterwards with `plutil -lint` on \
        the file.
        6. Show me the final list.

        ## Check that it worked

        The new faces appear in \(AppInfo.name)'s capsule right away, below the divider (on their days only), \
        and Settings > General > Actions lists them. If nothing changed, the file probably does not load: \
        check it with `plutil -lint` and fix it.
        """
    }

    /// Three realistic actions, valid as a whole file (a test decodes them).
    static let examples = """
    [
      {
        "id": "review-prs",
        "name": "Review open PRs",
        "cwd": "~/Projects/my-app",
        "prompt": "Review the open pull requests in this repo and tell me which need my attention first.",
        "days": ["mon", "tue", "wed", "thu", "fri"],
        "model": "sonnet"
      },
      {
        "id": "yesterday",
        "name": "Summarize yesterday",
        "cwd": "~/Projects/my-app",
        "prompt": "Summarize yesterday's commits and changes in this repo in five short bullet points.",
        "effort": "low"
      },
      {
        "id": "friday-tidy",
        "name": "Friday tidy-up",
        "cwd": "~/Projects/notes",
        "prompt": "Go through TODO.md, tick off what is done and list what is left for next week.",
        "days": ["fri"],
        "color": "#7FD1B9"
      }
    ]
    """

    /// `values` in backticks: "`a`, `b` or `c`".
    private static func list(_ values: [String]) -> String {
        let quoted = values.map { "`\($0)`" }
        guard let last = quoted.last, quoted.count > 1 else { return quoted.first ?? "" }
        return quoted.dropLast().joined(separator: ", ") + " or " + last
    }
}
