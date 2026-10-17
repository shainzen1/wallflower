import AppKit
import ApplicationServices
import Carbon.HIToolbox

/// Starts the Claude Code session of an action (`Theme.actionLauncher` picks how).
///
/// Verified in the Claude app bundle (13-10-26, `claudeURLHandler` in the main process):
/// `claude://code/new` reads `q` (alias `prompt`, capped in length), `folder` (repeatable), `file` and
/// the `ssh_host` / `ssh_port` / `ssh_folder` trio, then navigates the renderer to
/// `/epitaxy?q=<prompt>&folder=<path>&src=external`. Every other parameter is dropped there, so no
/// URL can make the page submit: the prompt is only prefilled. The page also defuses it: a leading
/// `/` arrives as U+FF0F, a leading `!` as U+FF01 and `@` mentions as U+FF20 (the bundle's own
/// defuser does the same for scheduled tasks), so a prefilled `/standup` is plain text, no command.
/// `.deepLinkAndSend` therefore finishes the job with key presses once Claude is frontmost: it
/// retypes a defused prompt and presses Return (needs Accessibility).
///
/// Measured (13-10-26) why the prefill cannot simply be waited for once: it lands 0.1 to 2.4 s after
/// the link; when a new-session page is already showing, the old page (with an older prefill) stays
/// for up to about half a second before the route reloads, and a Return on it is lost; when the very
/// same link is opened again while Claude is frontmost, nothing reloads at all. So the send loop acts
/// on what the composer holds every time it holds the prompt, and only calls it sent once the
/// composer stayed empty after a Return.
enum ActionLaunch {
    /// What became of a click, reported to the panel model.
    enum Report: Equatable, Sendable {
        /// The prompt was sent (or the launcher runs it without a keystroke).
        case sent
        /// The session is open with the prompt prefilled; the person has to press Return.
        case needsManualSend
    }

    /// What Claude's focused composer holds, compared with an action's prompt.
    enum ComposerState: Equatable, Sendable {
        /// Nothing (only whitespace).
        case blank
        /// Exactly the prompt.
        case prompt
        /// The prompt as the deep link page defused it (fullwidth `/`, `!` or `@`).
        case defusedPrompt
        /// A slash prompt after the first Return picked it from the command menu: the command name,
        /// without the slash (the slash became a chip).
        case pickedCommand
        /// Anything else: someone's draft, never touched.
        case other
    }

    /// The next move of the send loop for what the composer holds.
    enum SendStep: Equatable, Sendable {
        /// Nothing to do yet (no composer, not prefilled yet, someone else's text).
        case wait
        /// Select all and type the prompt (the prefill is defused).
        case retype
        case pressReturn
        /// Empty after our Return: sent, once it stays empty for `Theme.actionSentConfirm`.
        case confirmSent
    }

    /// Where the terminal fallback writes its `.command` files: the app's Application Support folder.
    nonisolated static var commandFolder: URL {
        AppInfo.supportFolder
    }

    /// `claude://code/new?folder=<cwd>&q=<prompt>`.
    static func deepLink(for item: ActionItem) -> URL? {
        var components = URLComponents()
        components.scheme = "claude"
        components.host = "code"
        components.path = "/new"
        components.queryItems = [
            URLQueryItem(name: "folder", value: item.resolvedCwd),
            URLQueryItem(name: "q", value: item.prompt),
        ]
        return components.url
    }

    /// The shell script of the terminal fallback: a `.command` file the default terminal app runs.
    static func commandScript(for item: ActionItem) -> String {
        commandScript(cwd: item.resolvedCwd, prompt: item.prompt)
    }

    /// A `.command` script that runs `claude` in `cwd` (symlinks resolved, so the CLI sees the path it
    /// already trusts) with `prompt` as its first message; an empty prompt runs plain `claude`.
    static func commandScript(cwd: String, prompt: String) -> String {
        let folder = shellQuoted(NSString(string: cwd).resolvingSymlinksInPath)
        let command = prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "claude" : "claude \(shellQuoted(prompt))"
        return """
        #!/bin/zsh
        cd \(folder) && exec \(command)

        """
    }

    /// Writes the `.command` file under the app's Application Support folder and returns it, executable.
    static func writeCommandFile(for item: ActionItem, in folder: URL = ActionLaunch.commandFolder) throws -> URL {
        try writeCommandFile(named: "launch-\(item.id).command", script: commandScript(for: item), in: folder)
    }

    /// Writes `script` as an executable `.command` file named `name` into `folder` and returns it.
    static func writeCommandFile(named name: String, script: String, in folder: URL) throws -> URL {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: name, directoryHint: .notDirectory)
        try Data(script.utf8).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }

    /// The terminal launcher: writes `script` as `name` into the effects' command folder and opens it in
    /// the default terminal app (behind the current app when `inBackground`, by default
    /// `Theme.terminalOpensInBackground`; an external session's open command comes to the front).
    /// Returns false when the file could not be written.
    @MainActor
    @discardableResult
    static func runInTerminal(
        script: String, named name: String, effects: Effects, inBackground: Bool = Theme.terminalOpensInBackground
    ) -> Bool {
        do {
            let file = try writeCommandFile(named: name, script: script, in: effects.commandFolder)
            if inBackground { effects.openInBackground(file) } else { effects.open(file) }
            return true
        } catch {
            NSLog("\(AppInfo.name): could not write the launch command: %@", error.localizedDescription)
            return false
        }
    }

    /// The side effects of `run`, replaceable so tests can check the launcher switch without opening anything.
    struct Effects {
        /// Opens a URL (the deep link, or the terminal fallback's `.command` file).
        var open: @MainActor (URL) -> Void
        /// Opens the deep link and sends the prompt in Claude (`ActionSender.openAndSend`).
        var openAndSend: @MainActor (URL, String, @escaping @MainActor (Report) -> Void) -> Void
        /// Folder of the terminal fallback's `.command` files.
        var commandFolder: URL
        /// Opens a URL without bringing its handler app forward (the `.command` file when
        /// `Theme.terminalOpensInBackground`).
        var openInBackground: @MainActor (URL) -> Void = { ActionSender.openQuietly($0) }

        @MainActor static var live: Effects {
            Effects(
                open: { ActionSender.openActivating($0) },
                openAndSend: { ActionSender.openAndSend($0, prompt: $1, report: $2) },
                commandFolder: ActionLaunch.commandFolder
            )
        }
    }

    /// Starts the action. `report` is called once on the main actor: at once for `.deepLinkNew`
    /// (`.needsManualSend`) and `.terminalCommand` (`.sent`), after the key presses (or the reason
    /// there were none) for `.deepLinkAndSend`.
    @MainActor
    static func run(
        _ item: ActionItem,
        using launcher: Theme.ActionLauncher = Theme.actionLauncher,
        effects: Effects = .live,
        report: @escaping @MainActor (Report) -> Void = { _ in }
    ) {
        switch launcher {
        case .deepLinkNew:
            guard let url = deepLink(for: item) else { return }
            effects.open(url)
            report(.needsManualSend)
        case .deepLinkAndSend:
            guard let url = deepLink(for: item) else { return }
            effects.openAndSend(url, item.prompt, report)
        case .terminalCommand:
            if runInTerminal(script: commandScript(for: item), named: "launch-\(item.id).command", effects: effects) {
                report(.sent)
            }
        }
    }

    /// The send-window guard, checked before every key press: only while Claude is the frontmost
    /// app and the deep link was opened less than `window` seconds ago.
    static func shouldSend(
        frontmostBundleID: String?,
        elapsed: TimeInterval,
        claudeBundleID: String = SessionOpener.claudeBundleIdentifier,
        window: TimeInterval = Theme.actionSendWindow
    ) -> Bool {
        frontmostBundleID == claudeBundleID && elapsed >= 0 && elapsed < window
    }

    /// Compares the composer's text with the prompt, both trimmed; fullwidth `／ ！ ＠` count as the
    /// defused `/ ! @`.
    static func composerState(text: String, prompt: String) -> ComposerState {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let prompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return .blank }
        guard !prompt.isEmpty else { return .other }
        if text == prompt { return .prompt }
        let refused = text
            .replacingOccurrences(of: "\u{FF0F}", with: "/")
            .replacingOccurrences(of: "\u{FF01}", with: "!")
            .replacingOccurrences(of: "\u{FF20}", with: "@")
        if refused == prompt { return .defusedPrompt }
        if prompt.hasPrefix("/"), prompt.count > 1, text == String(prompt.dropFirst()) { return .pickedCommand }
        return .other
    }

    /// The send loop's decision. `returnInFocus`: a Return of this click went out and the composer kept the
    /// focus since (a dialog or a page change in between makes an empty composer meaningless). Only the
    /// prompt itself (exact, defused, or picked as a command after our Return) is ever acted on.
    static func sendStep(for state: ComposerState?, returnInFocus: Bool) -> SendStep {
        switch state {
        case nil, .other?: .wait
        case .defusedPrompt?: .retype
        case .prompt?: .pressReturn
        case .pickedCommand?: returnInFocus ? .pressReturn : .wait
        case .blank?: returnInFocus ? .confirmSent : .wait
        }
    }

    /// Single-quoted for zsh; embedded quotes are closed, escaped and reopened.
    static func shellQuoted(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

/// `.deepLinkAndSend`: opens the new-session link, waits for Claude to be frontmost (event driven,
/// at most `Theme.actionActivationTimeout`), then reads Claude's focused composer every
/// `Theme.actionPollInterval` until `Theme.actionSendWindow` after the link and acts on what it holds
/// (`ActionLaunch.sendStep`): the defused prompt is retyped (select all, the prompt as key events),
/// the prompt gets a Return, a slash command the first Return picked from the menu gets another, and
/// an empty composer after a Return counts as sent once it stayed empty for `Theme.actionSentConfirm`
/// and kept the focus since that Return (if the page reloads and shows the prompt again, the loop
/// simply acts again, at most `Theme.actionMaxKeyActions` times). Every key press goes to Claude's
/// process only and only while `ActionLaunch.shouldSend` holds; any other text in the composer is
/// never touched. When the composer never holds the prompt (the page sits behind "Trust this
/// workspace?" for a cwd Claude does not trust yet), nothing is pressed at all and the hint shows.
@MainActor
enum ActionSender {
    /// The system prompt for Accessibility is shown on the first click of a run only.
    private static var didPromptForAccessibility = false
    /// Claude processes asked to expose their accessibility tree (Electron's `AXManualAccessibility`).
    private static var exposedPids: Set<pid_t> = []

    /// Whether this process may post key events to other apps. `prompt` shows the system dialog
    /// that leads to System Settings when it may not.
    static func isTrusted(prompt: Bool) -> Bool {
        guard prompt else { return AXIsProcessTrusted() }
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    /// System Settings, Privacy & Security, Accessibility.
    static let accessibilitySettingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!

    static func openAccessibilitySettings() {
        NSWorkspace.shared.open(accessibilitySettingsURL)
    }

    /// Opens a URL without bringing its handler app forward (Terminal keeps working behind the current app).
    static func openQuietly(_ url: URL) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        NSWorkspace.shared.open(url, configuration: configuration)
    }

    /// Opens a URL and asks for its handler app to come forward.
    static func openActivating(_ url: URL) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.open(url, configuration: configuration)
    }

    static func openAndSend(_ url: URL, prompt: String, report: @escaping @MainActor (ActionLaunch.Report) -> Void) {
        let ask = !didPromptForAccessibility
        didPromptForAccessibility = true
        guard isTrusted(prompt: ask) else {
            NSLog("\(AppInfo.name): no Accessibility permission, the prompt is only prefilled")
            openActivating(url)
            report(.needsManualSend)
            return
        }
        let opened = ContinuousClock.now
        openActivating(url)
        Task { @MainActor in
            report(await send(prompt: prompt, opened: opened))
        }
    }

    /// The key presses after the link opened; see the type comment.
    private static func send(prompt: String, opened: ContinuousClock.Instant) async -> ActionLaunch.Report {
        func elapsed() -> TimeInterval { (ContinuousClock.now - opened) / .seconds(1) }
        let claudeID = SessionOpener.claudeBundleIdentifier
        await waitUntilFrontmost(claudeID, timeout: Theme.actionActivationTimeout)

        var actions = 0
        var returnInFocus = false
        var blankSince: ContinuousClock.Instant?
        var lastState: ActionLaunch.ComposerState?
        var loggedState = ""
        while elapsed() < Theme.actionSendWindow {
            let front = NSWorkspace.shared.frontmostApplication
            guard front?.bundleIdentifier == claudeID, let pid = front?.processIdentifier else {
                // Not frontmost: nothing is read or pressed; Claude may come forward again in time.
                blankSince = nil
                let described = "Claude not frontmost (\(front?.bundleIdentifier ?? "none"))"
                if described != loggedState {
                    NSLog("\(AppInfo.name): %@ at %.2f s", described, elapsed())
                    loggedState = described
                }
                try? await Task.sleep(for: .seconds(Theme.actionPollInterval))
                continue
            }
            exposeAccessibilityTree(of: pid)
            let text = focusedTextAreaValue(of: pid)
            let state = text.map { ActionLaunch.composerState(text: $0, prompt: prompt) }
            let described = state.map { "\($0)" } ?? "not in focus"
            if described != loggedState {
                NSLog("\(AppInfo.name): composer %@ at %.2f s", described, elapsed())
                loggedState = described
            }
            if state != nil { lastState = state }
            // Focus left the composer (a dialog such as "Trust this workspace?", a page change): an
            // empty composer seen later says nothing about our Return.
            if state == nil { returnInFocus = false }
            let step = ActionLaunch.sendStep(for: state, returnInFocus: returnInFocus)
            if step != .confirmSent { blankSince = nil }
            switch step {
            case .wait:
                break
            case .confirmSent:
                let since = blankSince ?? .now
                blankSince = since
                if (ContinuousClock.now - since) / .seconds(1) >= Theme.actionSentConfirm {
                    NSLog("\(AppInfo.name): prompt sent (%d key action(s)), confirmed %.1f s after the link", actions, elapsed())
                    return .sent
                }
            case .retype, .pressReturn:
                guard actions < Theme.actionMaxKeyActions else {
                    NSLog("\(AppInfo.name): gave up after %d key actions", actions)
                    return .needsManualSend
                }
                guard ActionLaunch.shouldSend(frontmostBundleID: front?.bundleIdentifier, elapsed: elapsed()) else { break }
                actions += 1
                NSLog("\(AppInfo.name): %@ at %.2f s", step == .retype ? "retype" : "Return", elapsed())
                if step == .retype {
                    postKey(kVK_ANSI_A, flags: .maskCommand, to: pid)
                    type(prompt, to: pid)
                    await waitForChange(of: pid, from: text)
                    // The slash command menu filters after the text changed; give it a moment.
                    if prompt.hasPrefix("/") { try? await Task.sleep(for: .seconds(Theme.actionSendDelay)) }
                } else {
                    postKey(kVK_Return, to: pid)
                    returnInFocus = true
                    await waitForChange(of: pid, from: text)
                }
                continue
            }
            try? await Task.sleep(for: .seconds(Theme.actionPollInterval))
        }
        if returnInFocus, lastState == .blank {
            NSLog("\(AppInfo.name): prompt sent (%d key action(s)); Claude left the front before the check ended", actions)
            return .sent
        }
        if actions == 0 {
            // Nothing pressed: the composer never held the prompt (for instance the page sits behind
            // "Trust this workspace?" because the action's cwd is not a trusted workspace yet).
            NSLog("\(AppInfo.name): the composer never held the prompt within %.0f s, nothing pressed", Theme.actionSendWindow)
        } else {
            NSLog("\(AppInfo.name): not sent within %.0f s (key actions: %d)", Theme.actionSendWindow, actions)
        }
        return .needsManualSend
    }

    /// Waits (checking every `Theme.actionPollInterval`, at most `Theme.actionReactTimeout`) until the
    /// focused composer's text is no longer `text`.
    private static func waitForChange(of pid: pid_t, from text: String?) async {
        let deadline = ContinuousClock.now + .seconds(Theme.actionReactTimeout)
        while ContinuousClock.now < deadline {
            try? await Task.sleep(for: .seconds(Theme.actionPollInterval))
            if focusedTextAreaValue(of: pid) != text { return }
        }
    }

    /// Returns once the app with `bundleID` is frontmost (at once if it already is) or `timeout` passed.
    static func waitUntilFrontmost(_ bundleID: String, timeout: TimeInterval) async {
        if NSWorkspace.shared.frontmostApplication?.bundleIdentifier == bundleID { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let gate = ResumeOnce(continuation)
            let center = NSWorkspace.shared.notificationCenter
            let token = center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { note in
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                guard app?.bundleIdentifier == bundleID else { return }
                MainActor.assumeIsolated { gate.resume() }
            }
            gate.onResume = { center.removeObserver(token) }
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(timeout))
                gate.resume()
            }
        }
    }

    /// Electron builds its accessibility tree only for assistive apps that ask for it.
    private static func exposeAccessibilityTree(of pid: pid_t) {
        guard !exposedPids.contains(pid) else { return }
        exposedPids.insert(pid)
        AXUIElementSetAttributeValue(AXUIElementCreateApplication(pid), "AXManualAccessibility" as CFString, kCFBooleanTrue)
    }

    /// The text of the app's focused element when it is a text area, else nil.
    private static func focusedTextAreaValue(of pid: pid_t) -> String? {
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(AXUIElementCreateApplication(pid), kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() else { return nil }
        let element = focused as! AXUIElement
        var role: CFTypeRef?
        var value: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role)
        guard role as? String == kAXTextAreaRole as String else { return nil }
        AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value)
        return value as? String ?? ""
    }

    /// One key down and up with exactly `flags`, delivered to `pid`.
    private static func postKey(_ code: Int, flags: CGEventFlags = [], to pid: pid_t) {
        let source = CGEventSource(stateID: .hidSystemState)
        for keyDown in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(code), keyDown: keyDown) else { continue }
            event.flags = flags
            event.postToPid(pid)
        }
    }

    /// Types `text` into `pid`, one character per key event pair.
    private static func type(_ text: String, to pid: pid_t) {
        let source = CGEventSource(stateID: .hidSystemState)
        for character in text {
            let units = Array(String(character).utf16)
            for keyDown in [true, false] {
                guard let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: keyDown) else { continue }
                event.flags = []
                event.keyboardSetUnicodeString(stringLength: units.count, unicodeString: units)
                event.postToPid(pid)
            }
        }
    }

    /// Resumes a continuation exactly once, whichever of the observer or the timeout comes first.
    @MainActor
    private final class ResumeOnce {
        private var continuation: CheckedContinuation<Void, Never>?
        var onResume: (() -> Void)?

        init(_ continuation: CheckedContinuation<Void, Never>) {
            self.continuation = continuation
        }

        func resume() {
            guard let continuation else { return }
            self.continuation = nil
            onResume?()
            onResume = nil
            continuation.resume()
        }
    }
}
