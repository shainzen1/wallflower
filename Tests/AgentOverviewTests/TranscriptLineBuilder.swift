import Foundation

/// Builds synthetic transcript lines with the real key structure for the end-to-end tests.
/// Content is always "hello"; paths are under `/Users/demo`.
enum TranscriptLineBuilder {
    static let sessionId = "11111111-1111-4111-8111-111111111111"

    static func assistantToolUse(id: String, name: String, messageId: String, gitBranch: String? = "main") -> String {
        assistant(
            messageId: messageId, gitBranch: gitBranch,
            block: ["type": "tool_use", "id": id, "name": name, "input": ["command": "echo hello"], "caller": ["type": "direct"]],
            stopReason: "tool_use"
        )
    }

    static func assistantText(messageId: String, gitBranch: String? = "main") -> String {
        assistant(messageId: messageId, gitBranch: gitBranch, block: ["type": "text", "text": "hello"], stopReason: "end_turn")
    }

    static func toolResult(id: String, isError: Bool? = nil, gitBranch: String? = "main") -> String {
        var block: [String: Any] = ["tool_use_id": id, "type": "tool_result", "content": "hello"]
        if let isError { block["is_error"] = isError }
        var object = envelope(type: "user", gitBranch: gitBranch)
        object["message"] = ["role": "user", "content": [block]]
        object["toolUseResult"] = ["stdout": "hello"]
        return encode(object)
    }

    static func attachment(gitBranch: String? = "main") -> String {
        var object = envelope(type: "attachment", gitBranch: gitBranch)
        object["attachment"] = ["type": "hook_success", "hookName": "demo", "content": "hello"]
        return encode(object)
    }

    /// Appends lines (each terminated by a newline) to a transcript file, like Claude Code's appender.
    static func append(_ lines: [String], to url: URL) throws {
        let data = Data((lines.joined(separator: "\n") + "\n").utf8)
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } else {
            try data.write(to: url)
        }
    }

    // MARK: Private

    private static func assistant(messageId: String, gitBranch: String?, block: [String: Any], stopReason: String) -> String {
        var object = envelope(type: "assistant", gitBranch: gitBranch)
        object["message"] = [
            "id": messageId, "type": "message", "role": "assistant", "model": "claude-demo",
            "content": [block], "stop_reason": stopReason, "stop_sequence": NSNull(),
            "usage": ["input_tokens": 1, "output_tokens": 1],
        ]
        object["requestId"] = "req_\(messageId)"
        return encode(object)
    }

    private static func envelope(type: String, gitBranch: String?) -> [String: Any] {
        var object: [String: Any] = [
            "parentUuid": "u-0000", "isSidechain": false, "userType": "external", "cwd": "/Users/demo/project",
            "sessionId": sessionId, "version": "2.1.295", "type": type, "uuid": UUID().uuidString.lowercased(),
            "timestamp": "2026-10-13T10:00:00.000Z",
        ]
        if let gitBranch { object["gitBranch"] = gitBranch }
        return object
    }

    private static func encode(_ object: [String: Any]) -> String {
        let data = try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return String(decoding: data, as: UTF8.self)
    }
}
