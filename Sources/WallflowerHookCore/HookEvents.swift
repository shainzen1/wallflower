import Foundation

/// Which hook events each tool's config registers, and what each one means for the session. The
/// installers write exactly `events(for:)`, each entry calling `wallflower-hook <tool> <event>`, so the
/// helper knows the event from its arguments even when the payload does not name it (Copilot's
/// camelCase events). Sources per tool: `docs/agents.md`.
///
/// Questions a tool cannot signal (Codex plan mode, Gemini's `ask_user`) stay "working": there is no
/// event for them.
public enum HookEvents {
    /// The events the installer registers for `tool`, in the order they are written. OpenCode has none:
    /// its plugin listens to the event bus itself.
    public static func events(for tool: AgentTool) -> [String] {
        switch tool {
        case .codex: ["SessionStart", "UserPromptSubmit", "PermissionRequest", "PostToolUse", "Stop", "Interrupt", "SessionEnd"]
        case .gemini: ["SessionStart", "BeforeAgent", "AfterTool", "Notification", "AfterAgent", "SessionEnd"]
        case .cursor: ["sessionStart", "beforeSubmitPrompt", "stop", "sessionEnd"]
        case .copilot: ["sessionStart", "userPromptSubmitted", "postToolUse", "notification", "agentStop", "sessionEnd"]
        case .windsurf: ["pre_user_prompt", "post_cascade_response"]
        case .goose: ["SessionStart", "UserPromptSubmit", "Stop", "SessionEnd"]
        case .devin: ["SessionStart", "UserPromptSubmit", "PermissionRequest", "PostToolUse", "Stop", "SessionEnd"]
        case .opencode: []
        }
    }

    /// What `event` of `tool` does. `notificationType` is the payload's `notification_type`, read only
    /// for notification events. Event names compare without case, so Copilot's PascalCase variant
    /// (VS Code) maps like its camelCase one.
    public static func action(tool: AgentTool, event: String, notificationType: String? = nil) -> HookAction {
        let name = event.lowercased()
        switch tool {
        case .codex, .devin:
            switch name {
            case "sessionstart": return .start
            case "userpromptsubmit", "posttooluse": return .status(.busy)
            case "permissionrequest": return .status(.waiting, waitingFor: .permission)
            case "stop", "interrupt": return .status(.idle)
            case "sessionend": return .end
            default: return .ignore
            }
        case .gemini:
            switch name {
            case "sessionstart": return .start
            case "beforeagent", "aftertool": return .status(.busy)
            case "notification":
                return notificationType?.lowercased() == "toolpermission" ? .status(.waiting, waitingFor: .permission) : .ignore
            case "afteragent": return .status(.idle)
            case "sessionend": return .end
            default: return .ignore
            }
        case .cursor:
            switch name {
            case "sessionstart": return .start
            case "beforesubmitprompt": return .status(.busy)
            case "stop": return .status(.idle)
            case "sessionend": return .end
            default: return .ignore
            }
        case .copilot:
            switch name {
            case "sessionstart": return .start
            case "userpromptsubmitted", "userpromptsubmit", "posttooluse": return .status(.busy)
            case "notification":
                switch notificationType?.lowercased() {
                case "permission_prompt": return .status(.waiting, waitingFor: .permission)
                case "elicitation_dialog": return .status(.waiting, waitingFor: .question)
                // `agent_idle` is a background agent's turn, `shell_completed` a detached shell: not this session's state.
                default: return .ignore
                }
            case "agentstop", "stop": return .status(.idle)
            case "sessionend": return .end
            default: return .ignore
            }
        case .windsurf:
            switch name {
            case "pre_user_prompt": return .status(.busy)
            case "post_cascade_response": return .status(.idle)
            default: return .ignore
            }
        case .goose:
            switch name {
            case "sessionstart": return .start
            case "userpromptsubmit": return .status(.busy)
            case "stop": return .status(.idle)
            case "sessionend": return .end
            default: return .ignore
            }
        case .opencode:
            return .ignore
        }
    }
}
