import Darwin
import Foundation

/// The process a hook's session belongs to, found by walking up from the hook's parent: its pid ends
/// the face when it exits, and an app owner (Cursor, VS Code, Windsurf, Codex in the ChatGPT app)
/// also decides what a click opens.
public struct SessionOwner: Equatable, Sendable {
    public var pid: pid_t?
    /// The bundle id of the app the session runs in, when a click should bring that app forward.
    public var appBundleID: String?
    /// Codex running inside the ChatGPT (or old Codex) app: a click opens `codex://threads/<id>`.
    public var isCodexDesktop = false

    public init(pid: pid_t? = nil, appBundleID: String? = nil, isCodexDesktop: Bool = false) {
        self.pid = pid
        self.appBundleID = appBundleID
        self.isCodexDesktop = isCodexDesktop
    }
}

/// Reads the process table. The real one asks the kernel; tests hand in a fixed tree.
public protocol ProcessInspector: Sendable {
    func parent(of pid: pid_t) -> pid_t?
    /// The full path of the executable, nil when unknown.
    func executablePath(of pid: pid_t) -> String?
    /// The short process name (`p_comm`), for when the path is unknown.
    func name(of pid: pid_t) -> String?
    /// The process's arguments (`argv`), for interpreters such as `node` running a CLI.
    func arguments(of pid: pid_t) -> [String]
}

public enum OwnerResolver {
    /// Steps up at most this many parents: hook, shell, tool, and an editor's helper chain fit easily.
    public static let maxDepth = 12

    /// Walks up from `start` (the helper's parent, usually the shell the tool ran the hook in) and
    /// picks the tool's own process. `bundleID` reads an app bundle's id from its path.
    public static func resolve(
        tool: AgentTool, start: pid_t, inspector: some ProcessInspector, bundleID: (String) -> String? = Self.bundleIdentifier(appPath:)
    ) -> SessionOwner {
        var pid = start
        var appOwner: (pid: pid_t, appPath: String)?
        for _ in 0..<maxDepth {
            guard pid > 1 else { break }
            let path = inspector.executablePath(of: pid)
            let executable = path.map { ($0 as NSString).lastPathComponent } ?? inspector.name(of: pid) ?? ""
            if let match = matches(tool: tool, executable: executable, path: path, arguments: { inspector.arguments(of: pid) }) {
                return match(pid)
            }
            if appOwner == nil, let path, let app = mainExecutableApp(path), tool.hostsApp(named: (app as NSString).lastPathComponent) {
                appOwner = (pid, app)
            }
            guard let next = inspector.parent(of: pid), next != pid else { break }
            pid = next
        }
        // No tool process on the way up: an editor or app hosts the agent (Cursor, VS Code, Windsurf, Goose).
        if tool.usesAppOwner, let appOwner {
            return SessionOwner(pid: appOwner.pid, appBundleID: bundleID(appOwner.appPath))
        }
        return SessionOwner()
    }

    /// The `.app` a path is the main executable of (`X.app/Contents/MacOS/X`), nil for anything else,
    /// including an app's nested helper apps.
    public static func mainExecutableApp(_ path: String) -> String? {
        guard let range = path.range(of: ".app/") else { return nil }
        let rest = path[range.upperBound...]
        guard rest.hasPrefix("Contents/MacOS/"), !rest.dropFirst("Contents/MacOS/".count).contains("/") else { return nil }
        return String(path[..<range.upperBound].dropLast())
    }

    /// `CFBundleIdentifier` from an app's `Contents/Info.plist`.
    public static func bundleIdentifier(appPath: String) -> String? {
        let url = URL(filePath: appPath).appending(path: "Contents/Info.plist")
        guard let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { return nil }
        return plist["CFBundleIdentifier"] as? String
    }

    // MARK: Private

    private static func matches(
        tool: AgentTool, executable: String, path: String?, arguments: () -> [String]
    ) -> ((pid_t) -> SessionOwner)? {
        let plain = { (pid: pid_t) in SessionOwner(pid: pid) }
        switch tool {
        case .codex:
            guard executable == "codex" else { return nil }
            let desktop = path?.contains(".app/") == true
            return { SessionOwner(pid: $0, isCodexDesktop: desktop) }
        case .gemini:
            return executable == "gemini" || runsScript("gemini", executable, arguments) ? plain : nil
        case .cursor:
            return executable == "cursor-agent" || runsScript("cursor-agent", executable, arguments) ? plain : nil
        case .copilot:
            return executable == "copilot" || runsScript("copilot", executable, arguments) ? plain : nil
        case .goose:
            return executable == "goose" ? plain : nil
        case .devin:
            return executable == "devin" || runsScript("devin", executable, arguments) ? plain : nil
        case .windsurf, .opencode:
            return nil
        }
    }

    /// An interpreter (`node`, `bun`) running a script whose name starts with `name`
    /// (`node /opt/homebrew/bin/gemini`, `node .../@github/copilot/index.js`).
    private static func runsScript(_ name: String, _ executable: String, _ arguments: () -> [String]) -> Bool {
        guard ["node", "bun"].contains(executable) else { return false }
        return arguments().dropFirst().prefix(4).contains { argument in
            argument.split(separator: "/").contains { $0.hasPrefix(name) || $0 == "@github" && name == "copilot" }
        }
    }
}

extension AgentTool {
    /// Whether an app hosting the agent (no CLI process of its own on the way up) is its owner.
    var usesAppOwner: Bool {
        !hostAppNames.isEmpty
    }

    /// The apps the agent runs inside (by bundle name): only these become the owner, never just any
    /// app further up (a terminal, another agent's app).
    var hostAppNames: [String] {
        switch self {
        case .cursor: ["Cursor"]
        case .copilot: ["Visual Studio Code", "Code", "GitHub Copilot"]
        case .windsurf: ["Windsurf", "Devin"]
        case .goose: ["Goose"]
        case .codex, .gemini, .devin, .opencode: []
        }
    }

    func hostsApp(named bundleName: String) -> Bool {
        let name = bundleName.hasSuffix(".app") ? String(bundleName.dropLast(4)) : bundleName
        return hostAppNames.contains { name == $0 || name.hasPrefix($0 + " ") }
    }
}

/// The kernel's process table.
public struct SystemProcessInspector: ProcessInspector {
    public init() {}

    public func parent(of pid: pid_t) -> pid_t? {
        kinfo(pid).map { $0.kp_eproc.e_ppid }
    }

    public func executablePath(of pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        return String(decoding: buffer.prefix(Int(length)).map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    public func name(of pid: pid_t) -> String? {
        guard var info = kinfo(pid) else { return nil }
        return withUnsafeBytes(of: &info.kp_proc.p_comm) { raw in
            String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
        }
    }

    /// `KERN_PROCARGS2`: argc, the executable path, padding, then the arguments, NUL separated.
    public func arguments(of pid: pid_t) -> [String] {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > MemoryLayout<Int32>.size, size < 1 << 20 else { return [] }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0 else { return [] }
        let argc = buffer.withUnsafeBytes { $0.loadUnaligned(as: Int32.self) }
        var index = MemoryLayout<Int32>.size
        // Skip the executable path and the NULs after it.
        while index < size, buffer[index] != 0 { index += 1 }
        while index < size, buffer[index] == 0 { index += 1 }
        var arguments: [String] = []
        while index < size, arguments.count < min(Int(argc), 16) {
            let start = index
            while index < size, buffer[index] != 0 { index += 1 }
            arguments.append(String(decoding: buffer[start..<index], as: UTF8.self))
            index += 1
        }
        return arguments
    }

    private func kinfo(_ pid: pid_t) -> kinfo_proc? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, u_int(mib.count), &info, &size, nil, 0) == 0, size > 0 else { return nil }
        return info
    }
}
