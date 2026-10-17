import AppKit
import Darwin

/// Opens a session's chat. A desktop session with a session id: the (undocumented) continue deep
/// link. A session started in a terminal or an editor: that app comes to the front (found by walking
/// up the session's parent processes, `ProcessAncestry`). Anything else: Claude.app comes forward.
/// An external session (`docs/external-sessions.md`) follows its file's `open`: a URL, an app by
/// bundle id, or a command run in the terminal; without one, the app hosting its pid, if it has one.
/// `route(for:)` decides, `open` performs, so the decision is testable without opening anything.
enum SessionOpener {
    static let claudeBundleIdentifier = "com.anthropic.claudefordesktop"

    /// What a click on a row does.
    enum Route: Equatable, Sendable {
        /// `claude://code/continue?session=<hostSessionId>`.
        case claudeDeepLink(URL)
        /// The app hosting this process comes forward; `fallsBackToClaude`: Claude.app when none is found.
        case hostApp(pid: pid_t, fallsBackToClaude: Bool)
        /// Claude.app comes forward.
        case claudeApp
        /// An external session's `open.url`.
        case url(URL)
        /// An external session's `open.app`.
        case app(bundleID: String)
        /// An external session's `open.command`, as the `.command` script the terminal runs.
        case command(script: String, fileName: String)
        /// Nothing to open (an external session with neither `open` nor a pid).
        case nothing
    }

    /// `claude://code/continue?session=<hostSessionId>`, or nil without a desktop session id.
    static func deepLink(for row: SessionRow) -> URL? {
        guard let id = row.hostSessionId, !id.isEmpty else { return nil }
        var components = URLComponents()
        components.scheme = "claude"
        components.host = "code"
        components.path = "/continue"
        components.queryItems = [URLQueryItem(name: "session", value: id)]
        return components.url
    }

    /// Whether a click should look for the session's own app: no desktop session id and not a desktop session.
    static func opensHostApp(_ row: SessionRow) -> Bool {
        (row.hostSessionId ?? "").isEmpty && !DataTuning.desktopEntrypoints.contains(row.entrypoint)
    }

    /// The route of a click on `row`.
    static func route(for row: SessionRow) -> Route {
        guard row.source.isClaude else { return externalRoute(for: row) }
        if let url = deepLink(for: row) { return .claudeDeepLink(url) }
        if opensHostApp(row), let pid = row.pid { return .hostApp(pid: pid, fallsBackToClaude: true) }
        return .claudeApp
    }

    /// An external session: its `open`, else the app hosting its pid, else nothing.
    private static func externalRoute(for row: SessionRow) -> Route {
        switch row.opener {
        case .url(let url)?: return .url(url)
        case .app(let bundleID)?: return .app(bundleID: bundleID)
        case .command(let command)?:
            let name = ActionItem.slug(for: row.key.description)
            return .command(script: commandScript(command: command, cwd: row.cwd), fileName: "open-\(name).command")
        case nil:
            if let pid = row.pid { return .hostApp(pid: pid, fallsBackToClaude: false) }
            return .nothing
        }
    }

    /// The `.command` script of an external session's `open.command`: `cd` into its folder when it has
    /// one, then the command exactly as written (it may be a pipeline or several commands).
    static func commandScript(command: String, cwd: String) -> String {
        let folder = cwd.isEmpty ? "" : "cd \(ActionLaunch.shellQuoted(NSString(string: cwd).expandingTildeInPath)) || exit 1\n"
        return """
        #!/bin/zsh
        \(folder)\(command)

        """
    }

    @MainActor
    static func open(_ row: SessionRow) {
        perform(route(for: row))
    }

    @MainActor
    static func perform(_ route: Route) {
        switch route {
        case .claudeDeepLink(let url):
            NSWorkspace.shared.open(url)
        case .hostApp(let pid, let fallsBackToClaude):
            if let app = ProcessAncestry.hostApplication(of: pid) {
                activate(app)
            } else if fallsBackToClaude {
                activateClaude()
            } else {
                NSLog("\(AppInfo.name): no app found for an external session")
            }
        case .claudeApp:
            activateClaude()
        case .url(let url):
            ActionSender.openActivating(url)
        case .app(let bundleID):
            activateApp(bundleID: bundleID)
        case .command(let script, let fileName):
            ActionLaunch.runInTerminal(script: script, named: fileName, effects: .live, inBackground: false)
        case .nothing:
            NSLog("\(AppInfo.name): an external session without open or pid has nothing to bring forward")
        }
    }

    @MainActor
    static func activateClaude() {
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: claudeBundleIdentifier) else {
            NSLog("\(AppInfo.name): Claude.app not found (%@)", claudeBundleIdentifier)
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: appURL, configuration: configuration)
    }

    /// Brings the app with `bundleID` forward (launching it when it is not running).
    @MainActor
    static func activateApp(bundleID: String) {
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            NSLog("\(AppInfo.name): no app with bundle id %@", bundleID)
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: appURL, configuration: configuration)
    }

    /// Brings a running app forward. Through Launch Services by its bundle, like `activateClaude`
    /// (a plain `activate()` from a non-active accessory app may be refused), else directly.
    @MainActor
    static func activate(_ app: NSRunningApplication) {
        if let url = app.bundleURL {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            NSWorkspace.shared.openApplication(at: url, configuration: configuration)
        } else {
            app.activate()
        }
    }
}

/// Finds the app a process runs in: up the parent chain to the first ancestor that is a regular app
/// (Terminal, iTerm, Ghostty, VS Code, Cursor). Helper processes have a bundle id too but are not
/// regular apps, so an editor's extension host leads on to the editor itself.
enum ProcessAncestry {
    /// Steps up at most this many parents (a guard against a cycle in a racing process table).
    static let maxDepth = 32

    /// The first ancestor of `pid` (the process itself excluded) for which `isApp` holds, walking with
    /// `parent`. Stops at launchd (pid 1), at an unknown process, or after `maxDepth` steps.
    static func firstAncestor(of pid: pid_t, parent: (pid_t) -> pid_t?, isApp: (pid_t) -> Bool) -> pid_t? {
        var current = pid
        for _ in 0..<maxDepth {
            guard let next = parent(current), next > 1, next != current else { return nil }
            if isApp(next) { return next }
            current = next
        }
        return nil
    }

    /// The regular app hosting the session process `pid`, nil when there is none (a detached tmux
    /// server, a process that already exited).
    @MainActor
    static func hostApplication(of pid: pid_t) -> NSRunningApplication? {
        let ancestor = firstAncestor(of: pid, parent: parentPid(of:)) { candidate in
            guard let app = NSRunningApplication(processIdentifier: candidate) else { return false }
            return app.bundleIdentifier != nil && app.activationPolicy == .regular
        }
        return ancestor.flatMap(NSRunningApplication.init(processIdentifier:))
    }

    /// The parent of `pid` from the kernel (`sysctl` `KERN_PROC_PID`), nil when the process is gone.
    static func parentPid(of pid: pid_t) -> pid_t? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, u_int(mib.count), &info, &size, nil, 0) == 0, size > 0 else { return nil }
        return info.kp_eproc.e_ppid
    }
}
