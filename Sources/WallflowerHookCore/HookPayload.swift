import Foundation

/// The few fields of a hook's stdin JSON the helper uses, and nothing else. Payloads also carry the
/// prompt, the reply, tool input, transcript paths and (Cursor) the account's email; none of that is
/// ever copied out of the decoded dictionary, so it cannot reach a session file.
public struct HookPayload: Equatable, Sendable {
    /// The tool's session (or conversation, or trajectory) id, as given.
    public var sessionID: String?
    /// The session's folder: `cwd`, else the first workspace root.
    public var cwd: String?
    /// `notification_type` of a notification event.
    public var notificationType: String?
    /// The event's own time, when the payload has one (Gemini, Copilot, Windsurf).
    public var timestamp: Date?

    /// Stdin is read up to this many bytes; a larger payload is cut and then fails to decode, which
    /// only loses the optional fields.
    public static let maxBytes = 256 * 1024

    public init(sessionID: String? = nil, cwd: String? = nil, notificationType: String? = nil, timestamp: Date? = nil) {
        self.sessionID = sessionID
        self.cwd = cwd
        self.notificationType = notificationType
        self.timestamp = timestamp
    }

    /// Reads the allow-listed fields. Anything that is not a JSON object yields an empty payload.
    public init(data: Data) {
        self.init()
        guard !data.isEmpty, data.count <= Self.maxBytes,
              let object = try? JSONSerialization.jsonObject(with: data), let fields = object as? [String: Any] else { return }
        sessionID = Self.firstString(fields, ["session_id", "sessionId", "conversation_id", "conversationId", "trajectory_id", "thread_id"])
        cwd = Self.firstPath(fields)
        notificationType = Self.firstString(fields, ["notification_type", "notificationType"])
        timestamp = Self.date(fields["timestamp"])
    }

    // MARK: Private

    private static func firstString(_ fields: [String: Any], _ keys: [String]) -> String? {
        for key in keys {
            if let value = fields[key] as? String {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty, trimmed.utf8.count <= 512 { return trimmed }
            }
        }
        return nil
    }

    /// An absolute folder path: `cwd`, `working_dir`, or the first of `workspace_roots` / `workspaceRoots`.
    private static func firstPath(_ fields: [String: Any]) -> String? {
        var candidates: [Any?] = [fields["cwd"], fields["working_dir"]]
        for key in ["workspace_roots", "workspaceRoots", "workspacePaths"] {
            candidates.append((fields[key] as? [Any])?.first)
        }
        for case let path as String in candidates.compactMap({ $0 }) where path.hasPrefix("/") && path.utf8.count <= 1024 {
            return path
        }
        return nil
    }

    /// Epoch milliseconds (a number; seconds when it is too small to be milliseconds) or ISO 8601.
    private static func date(_ value: Any?) -> Date? {
        if let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() {
            let raw = number.doubleValue
            guard raw.isFinite, raw > 0 else { return nil }
            return Date(timeIntervalSince1970: raw < 100_000_000_000 ? raw : raw / 1000)
        }
        if let text = value as? String {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: text) { return date }
            formatter.formatOptions = [.withInternetDateTime]
            return formatter.date(from: text)
        }
        return nil
    }
}
