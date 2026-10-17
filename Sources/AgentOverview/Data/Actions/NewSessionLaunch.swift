import Foundation

/// Starts a fresh Claude Code session with no prompt: what the new session button at the top of the
/// column does. The route follows "Show sessions from", so the new session shows up in the column:
/// the Claude app for `.desktop`, a background Terminal window running plain `claude` in the home
/// folder for `.terminal` and `.everywhere`. Both reuse `ActionLaunch`'s openers; the side effects are
/// injected (`ActionLaunch.Effects`), so the decision is testable without opening anything.
enum NewSessionLaunch {
    enum Route: Equatable, Sendable {
        /// `claude://code/new` with no query: the Claude app opens a new chat.
        case claudeApp
        /// `claude` in the home folder, through the terminal launcher's `.command` file.
        case terminal

        /// Second line of the button's bulge: where the new session opens.
        var title: String {
            switch self {
            case .claudeApp: "Claude app"
            case .terminal: "Terminal"
            }
        }
    }

    /// The route for the panel's session source.
    static func route(for source: SessionSource) -> Route {
        switch source {
        case .desktop: .claudeApp
        case .terminal, .everywhere: .terminal
        }
    }

    /// `claude://code/new`, no query: no folder, no prompt.
    static let deepLink: URL = {
        var components = URLComponents()
        components.scheme = "claude"
        components.host = "code"
        components.path = "/new"
        return components.url!
    }()

    /// The terminal route's script: plain `claude` in `home`.
    static func commandScript(home: String = NSHomeDirectory()) -> String {
        ActionLaunch.commandScript(cwd: home, prompt: "")
    }

    /// Starts the session on `route`.
    @MainActor
    static func run(_ route: Route, effects: ActionLaunch.Effects = .live, home: String = NSHomeDirectory()) {
        switch route {
        case .claudeApp:
            effects.open(deepLink)
        case .terminal:
            ActionLaunch.runInTerminal(script: commandScript(home: home), named: Theme.newSessionCommandFile, effects: effects)
        }
    }
}
