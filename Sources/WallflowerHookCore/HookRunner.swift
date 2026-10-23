import Darwin
import Foundation

/// Where the helper lives and where it writes, relative to a home folder. The helper sits on a path
/// without spaces (`~/.local/share/wallflower/bin/wallflower-hook`), so every tool's hook command can
/// name it without quoting, whether the tool runs commands through a shell or splits them itself.
public enum HelperLayout {
    public static let helperName = "wallflower-hook"
    /// The helper's folder below the home folder.
    public static let binRelativePath = ".local/share/wallflower/bin"
    /// Wallflower's own folder below the home folder.
    public static let supportRelativePath = "Library/Application Support/Wallflower"

    public static func helperURL(home: URL) -> URL {
        home.appending(path: binRelativePath, directoryHint: .isDirectory).appending(path: helperName, directoryHint: .notDirectory)
    }

    public static func supportFolder(home: URL) -> URL {
        home.appending(path: supportRelativePath, directoryHint: .isDirectory)
    }

    public static func sessionsFolder(home: URL) -> URL {
        supportFolder(home: home).appending(path: "sessions", directoryHint: .isDirectory)
    }

    /// The home folder an installed helper belongs to, from its own path; nil for a helper anywhere else.
    public static func home(ofHelperAt path: String) -> URL? {
        let suffix = "/" + binRelativePath + "/" + helperName
        guard path.hasSuffix(suffix) else { return nil }
        return URL(filePath: String(path.dropLast(suffix.count)), directoryHint: .isDirectory)
    }
}

/// One run of `wallflower-hook <tool> <event>`: decode the allow-listed payload fields, map the event,
/// and create, rewrite or delete `<tool>-<session id>.json` in the sessions folder. Never throws,
/// never prints: every failure just leaves the folder as it was.
public enum HookRunner {
    /// Runs the helper. `start` is the helper's parent process, where the walk to the owner begins.
    public static func run(
        arguments: [String], stdin: Data, sessionsFolder: URL, start: pid_t, inspector: some ProcessInspector,
        now: Date = Date(), bundleID: (String) -> String? = OwnerResolver.bundleIdentifier(appPath:)
    ) {
        guard arguments.count >= 1, let tool = AgentTool(rawValue: arguments[0].lowercased()) else { return }
        let payload = HookPayload(data: stdin)
        // The event comes from the command line (the installers always pass it); a payload that names
        // its event is only a fallback for a hand-written hook.
        guard let event = arguments.count >= 2 ? arguments[1] : eventName(in: stdin) else { return }
        let action = HookEvents.action(tool: tool, event: event, notificationType: payload.notificationType)
        guard action != .ignore else { return }
        let owner = OwnerResolver.resolve(tool: tool, start: start, inspector: inspector, bundleID: bundleID)
        guard let id = fileID(tool: tool, sessionID: payload.sessionID, ownerPid: owner.pid) else { return }
        apply(action, id: id, tool: tool, payload: payload, owner: owner, folder: sessionsFolder, now: now)
    }

    /// The sessions folder: `WALLFLOWER_SESSIONS_DIR`, else the one next to the home the helper is
    /// installed in, else `$HOME`'s.
    public static func sessionsFolder(environment: [String: String], executablePath: String) -> URL {
        if let override = environment["WALLFLOWER_SESSIONS_DIR"], !override.isEmpty {
            return URL(filePath: override, directoryHint: .isDirectory)
        }
        if let home = HelperLayout.home(ofHelperAt: executablePath) {
            return HelperLayout.sessionsFolder(home: home)
        }
        let home = environment["HOME"].map { URL(filePath: $0, directoryHint: .isDirectory) }
            ?? URL(filePath: NSHomeDirectory(), directoryHint: .isDirectory)
        return HelperLayout.sessionsFolder(home: home)
    }

    /// `<tool>-<session id>` made safe as a file name (letters, digits, `.`, `-`, `_`, at most 128),
    /// else `<tool>-pid<owner>`; nil when there is neither.
    public static func fileID(tool: AgentTool, sessionID: String?, ownerPid: pid_t?) -> String? {
        let prefix = tool.rawValue + "-"
        if let sessionID {
            let safe = String(sessionID.unicodeScalars.map { scalar -> Character in
                let allowed = CharacterSet.alphanumerics.contains(scalar) && scalar.isASCII || "._-".unicodeScalars.contains(scalar)
                return allowed ? Character(scalar) : "-"
            })
            let trimmed = String(safe.prefix(128 - prefix.count))
            if !trimmed.isEmpty, !trimmed.allSatisfy({ $0 == "-" }) { return prefix + trimmed }
        }
        if let ownerPid { return prefix + "pid\(ownerPid)" }
        return nil
    }

    // MARK: Private

    private static func eventName(in data: Data) -> String? {
        guard data.count <= HookPayload.maxBytes, let object = try? JSONSerialization.jsonObject(with: data),
              let fields = object as? [String: Any] else { return nil }
        return (fields["hook_event_name"] ?? fields["event"]) as? String
    }

    private static func apply(
        _ action: HookAction, id: String, tool: AgentTool, payload: HookPayload, owner: SessionOwner, folder: URL, now: Date
    ) {
        let file = folder.appending(path: "\(id).json", directoryHint: .notDirectory)
        if action == .end {
            unlink(file.path)
            return
        }
        // Wallflower's folder gone (uninstalled): write nothing.
        guard FileManager.default.fileExists(atPath: folder.deletingLastPathComponent().path) else { return }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)

        let existing = SessionFileState(url: file)
        let eventTime = payload.timestamp ?? now
        // An event older than the last one applied (two hooks racing) changes nothing.
        if let last = existing?.eventAt, SessionFileState.milliseconds(last) > SessionFileState.milliseconds(eventTime) { return }

        var state = existing ?? SessionFileState(status: .idle, startedAt: now, statusSince: now)
        switch action {
        case .start:
            break
        case .status(let status, let waitingFor):
            let waiting = status == .waiting ? waitingFor : nil
            if existing == nil || state.status != status || state.waitingFor != waiting {
                state.statusSince = eventTime
            }
            state.status = status
            state.waitingFor = waiting
        case .end, .ignore:
            return
        }
        state.eventAt = eventTime
        state.cwd = payload.cwd ?? state.cwd
        state.pid = owner.pid ?? state.pid
        if owner.isCodexDesktop, let sessionID = payload.sessionID,
           let encoded = sessionID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "/"))) {
            state.open = .url("codex://threads/\(encoded)")
        } else if let bundleID = owner.appBundleID {
            state.open = .app(bundleID)
        }
        state.write(id: id, tool: tool, to: file, now: now)
    }
}

/// The fields of a session file the helper keeps across events. It reads back only files in its own
/// layout; anything else is replaced.
struct SessionFileState {
    enum Open: Equatable {
        case url(String)
        case app(String)
    }

    var status: HookStatus
    var waitingFor: HookWaitingFor?
    var cwd: String?
    var pid: pid_t?
    var startedAt: Date
    var statusSince: Date
    var eventAt: Date?
    var open: Open?

    init(status: HookStatus, startedAt: Date, statusSince: Date) {
        self.status = status
        self.startedAt = startedAt
        self.statusSince = statusSince
    }

    init?(url: URL) {
        guard let data = try? Data(contentsOf: url), data.count <= 64 * 1024,
              let fields = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let status = (fields["status"] as? String).flatMap(HookStatus.init(rawValue:)) else { return nil }
        func date(_ key: String) -> Date? {
            (fields[key] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue / 1000) }
        }
        self.status = status
        waitingFor = (fields["waitingFor"] as? String).flatMap(HookWaitingFor.init(rawValue:))
        cwd = fields["cwd"] as? String
        pid = (fields["pid"] as? NSNumber).map { pid_t(truncatingIfNeeded: $0.intValue) }
        startedAt = date("startedAt") ?? Date()
        statusSince = date("statusUpdatedAt") ?? startedAt
        eventAt = date("eventAt")
        if let open = fields["open"] as? [String: Any] {
            if let url = open["url"] as? String { self.open = .url(url) } else if let app = open["app"] as? String { self.open = .app(app) }
        }
    }

    /// Writes the file, one key per line in a fixed order, through a hidden temp file and a rename.
    func write(id: String, tool: AgentTool, to url: URL, now: Date) {
        var lines: [(String, String)] = [("id", Self.string(id)), ("tool", Self.string(tool.rawValue))]
        if let cwd { lines.append(("cwd", Self.string(cwd))) }
        lines.append(("status", Self.string(status.rawValue)))
        if let waitingFor { lines.append(("waitingFor", Self.string(waitingFor.rawValue))) }
        if let pid { lines.append(("pid", "\(pid)")) }
        lines.append(("startedAt", Self.ms(startedAt)))
        lines.append(("updatedAt", Self.ms(now)))
        lines.append(("statusUpdatedAt", Self.ms(statusSince)))
        if let eventAt { lines.append(("eventAt", Self.ms(eventAt))) }
        switch open {
        case .url(let link): lines.append(("open", "{\"url\": \(Self.string(link))}"))
        case .app(let bundleID): lines.append(("open", "{\"app\": \(Self.string(bundleID))}"))
        case nil: break
        }
        let text = "{\n" + lines.map { "  \"\($0.0)\": \($0.1)" }.joined(separator: ",\n") + "\n}\n"
        let temp = url.deletingLastPathComponent().appending(path: ".\(id).json.tmp.\(getpid())")
        guard (try? Data(text.utf8).write(to: temp)) != nil else { return }
        if rename(temp.path, url.path) != 0 { unlink(temp.path) }
    }

    private static func string(_ value: String) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: [value], options: [.withoutEscapingSlashes]),
              let text = String(data: data, encoding: .utf8) else { return "\"\"" }
        return String(text.dropFirst().dropLast())
    }

    private static func ms(_ date: Date) -> String {
        String(milliseconds(date))
    }

    /// Whole milliseconds, rounded down: what a file holds, so a time read back compares equal.
    static func milliseconds(_ date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 * 1000).rounded(.down))
    }
}
