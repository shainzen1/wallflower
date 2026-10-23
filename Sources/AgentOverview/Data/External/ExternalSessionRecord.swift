import Foundation

/// How a click brings an external session to the front (`open` in its file).
enum ExternalOpener: Hashable, Sendable {
    /// Opened with `NSWorkspace` (any scheme the system can open: a deep link, `https`, `vscode://`).
    case url(URL)
    /// The app with this bundle id comes to the front.
    case app(bundleID: String)
    /// A shell command run in the default terminal app (through `ActionLaunch.runInTerminal`).
    case command(String)
}

/// One file in the external sessions folder, `<id>.json`, written by any tool
/// (`docs/external-sessions.md`). Only `id` and `status` are required; every other key is optional
/// and a key of the wrong type is treated as absent. Unknown keys are ignored.
struct ExternalSessionRecord: Decodable, Sendable, Equatable {
    var id: String
    /// Short display name of the tool ("codex"), shown after the name on hover.
    var tool: String?
    var name: String?
    var cwd: String?
    var status: RegistryStatus
    /// `question` or `permission` while `status` is `waiting`; anything else is generic.
    var waitingFor: String?
    /// When present, the session ends when this process exits (like a Claude session).
    var pid: pid_t?
    /// Epoch milliseconds of the last write. Without a pid, a file not refreshed for
    /// `DataTuning.externalSessionTTL` counts as ended.
    var updatedAt: Int?
    /// Epoch milliseconds the current status began; defaults to `updatedAt`.
    var statusUpdatedAt: Int?
    var startedAt: Int?
    var open: ExternalOpener?

    /// The file's modification date, filled in by the scanner (not decoded): a plain `touch` refreshes
    /// a session, and it stands in for a missing `updatedAt`.
    var fileModified: Date?
    /// The file's creation date, filled in by the scanner: stands in for a missing `startedAt`.
    var fileCreated: Date?

    var waitingKind: WaitingKind { WaitingKind(externalWaitingFor: waitingFor) }

    /// The later of `updatedAt` and the file's modification date: what the TTL is measured from.
    var freshness: Date? {
        let written = updatedAt.map(Self.date(fromMilliseconds:))
        switch (written, fileModified) {
        case (let a?, let b?): return max(a, b)
        case (let a?, nil): return a
        case (nil, let b?): return b
        case (nil, nil): return nil
        }
    }

    var startedDate: Date {
        startedAt.map(Self.date(fromMilliseconds:)) ?? fileCreated ?? freshness ?? Date(timeIntervalSince1970: 0)
    }

    /// When the current status began: `statusUpdatedAt`, else `updatedAt`, else the file's dates.
    var statusUpdatedDate: Date {
        if let ms = statusUpdatedAt ?? updatedAt { return Self.date(fromMilliseconds: ms) }
        return fileModified ?? startedDate
    }

    init(
        id: String, tool: String? = nil, name: String? = nil, cwd: String? = nil, status: RegistryStatus,
        waitingFor: String? = nil, pid: pid_t? = nil, updatedAt: Int? = nil, statusUpdatedAt: Int? = nil,
        startedAt: Int? = nil, open: ExternalOpener? = nil
    ) {
        self.id = id
        self.tool = tool
        self.name = name
        self.cwd = cwd
        self.status = status
        self.waitingFor = waitingFor
        self.pid = pid
        self.updatedAt = updatedAt
        self.statusUpdatedAt = statusUpdatedAt
        self.startedAt = startedAt
        self.open = open
    }

    // MARK: Decoding

    private enum CodingKeys: String, CodingKey {
        case id, tool, name, cwd, status, waitingFor, pid, updatedAt, statusUpdatedAt, startedAt, open
    }

    private enum OpenKeys: String, CodingKey {
        case url, app, command
    }

    struct InvalidID: Error {}

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decode(String.self, forKey: .id).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else { throw InvalidID() }
        self.id = id
        status = try container.decode(RegistryStatus.self, forKey: .status)
        tool = Self.text(container, .tool)
        name = Self.text(container, .name)
        cwd = Self.text(container, .cwd)
        waitingFor = Self.text(container, .waitingFor)
        pid = Self.number(container, .pid).flatMap { $0 > 0 && $0 <= Int(Int32.max) ? pid_t($0) : nil }
        updatedAt = Self.number(container, .updatedAt)
        statusUpdatedAt = Self.number(container, .statusUpdatedAt)
        startedAt = Self.number(container, .startedAt)
        open = Self.opener(container)
    }

    /// A non-empty trimmed string, nil when absent, empty or not a string.
    private static func text(_ container: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> String? {
        guard let value = try? container.decodeIfPresent(String.self, forKey: key) else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// An integer, also from a whole floating point number (`1.7e12`); nil otherwise.
    private static func number(_ container: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> Int? {
        if let value = try? container.decodeIfPresent(Int.self, forKey: key) { return value }
        if let value = try? container.decodeIfPresent(Double.self, forKey: key), value.isFinite, value.rounded() == value,
           abs(value) < 9e15 {
            return Int(value)
        }
        return nil
    }

    /// `{"url": ...}`, `{"app": ...}` or `{"command": ...}`. With more than one key, `url` wins over
    /// `app` over `command`; anything unusable is no opener.
    private static func opener(_ container: KeyedDecodingContainer<CodingKeys>) -> ExternalOpener? {
        guard let open = try? container.nestedContainer(keyedBy: OpenKeys.self, forKey: .open) else { return nil }
        func value(_ key: OpenKeys) -> String? {
            guard let text = try? open.decodeIfPresent(String.self, forKey: key) else { return nil }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        if let text = value(.url), let url = URL(string: text), url.scheme?.isEmpty == false { return .url(url) }
        if let bundleID = value(.app) { return .app(bundleID: bundleID) }
        if let command = value(.command) { return .command(command) }
        return nil
    }

    static func date(fromMilliseconds ms: Int) -> Date {
        Date(timeIntervalSince1970: TimeInterval(ms) / 1000)
    }
}

extension WaitingKind {
    /// The external format's `waitingFor`: `question` or `permission`; anything else is generic.
    init(externalWaitingFor value: String?) {
        switch value?.lowercased() {
        case "question": self = .question
        case "permission": self = .permission
        default: self = .other
        }
    }
}
