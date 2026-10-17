import Foundation
@testable import AgentOverview

/// Helpers shared by the data layer tests: fixture access, registry files in a temp folder, waiting.
enum TestSupport {
    static let fixtureNames = [
        "busy-desktop", "idle-desktop", "waiting-desktop",
        "waiting-permission-desktop.synthetic", "busy-cli", "idle-cli",
    ]

    /// Our own pid: certainly alive for the duration of a test.
    static let livePid = ProcessInfo.processInfo.processIdentifier
    /// A second live pid: the process that launched the tests, alive for the whole run. (`livePid + 1`
    /// is often no process at all, and the store ends a session whose process is gone.)
    static let otherLivePid = getppid()
    /// Far above the macOS pid range (99998), so no process can have it.
    static let deadPid: pid_t = 2_147_483_000

    static func fixtureURL(_ name: String) -> URL {
        guard let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures") else {
            fatalError("Missing fixture \(name).json")
        }
        return url
    }

    static func fixtureData(_ name: String) throws -> Data {
        try Data(contentsOf: fixtureURL(name))
    }

    static func fixtureRecord(_ name: String) throws -> SessionRecord {
        try JSONDecoder().decode(SessionRecord.self, from: fixtureData(name))
    }

    /// A synthetic transcript tail from `Tests/Fixtures/transcripts/<name>.jsonl`.
    static func transcriptFixtureURL(_ name: String) -> URL {
        guard let url = Bundle.module.url(forResource: name, withExtension: "jsonl", subdirectory: "Fixtures/transcripts") else {
            fatalError("Missing transcript fixture \(name).jsonl")
        }
        return url
    }

    static func transcriptFixtureData(_ name: String) throws -> Data {
        try Data(contentsOf: transcriptFixtureURL(name))
    }

    /// `Tests/Fixtures/transcripts/subagents/`: one finished and one live subagent.
    static var subagentsFixtureFolder: URL {
        guard let url = Bundle.module.url(forResource: "subagents", withExtension: nil, subdirectory: "Fixtures/transcripts") else {
            fatalError("Missing subagents fixture folder")
        }
        return url
    }

    /// A fresh empty folder under the temp directory.
    static func makeTempFolder() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "AgentOverviewTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Writes a fixture into `folder` as `<pid>.json`, with the pid and optionally status and waitingFor replaced.
    /// The write is in place (truncate and rewrite), like Claude Code's own writer.
    @discardableResult
    static func writeFixture(
        _ name: String,
        to folder: URL,
        pid: pid_t,
        status: RegistryStatus? = nil,
        waitingFor: String? = nil,
        statusUpdatedAt: Int? = nil,
        cwd: String? = nil,
        sessionId: String? = nil
    ) throws -> URL {
        var object = try JSONSerialization.jsonObject(with: fixtureData(name)) as? [String: Any] ?? [:]
        object["pid"] = Int(pid)
        if let cwd { object["cwd"] = cwd }
        if let sessionId { object["sessionId"] = sessionId }
        if let status { object["status"] = status.rawValue }
        if let waitingFor { object["waitingFor"] = waitingFor } else if status != nil { object["waitingFor"] = nil }
        if let statusUpdatedAt { object["statusUpdatedAt"] = statusUpdatedAt }
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        let url = folder.appending(path: "\(pid).json")
        try data.write(to: url)
        return url
    }

    /// An external session file from `Tests/Fixtures/external/<name>.json`.
    static func externalFixtureData(_ name: String) throws -> Data {
        guard let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures/external") else {
            fatalError("Missing external fixture \(name).json")
        }
        return try Data(contentsOf: url)
    }

    /// Epoch milliseconds of `date`.
    static func millis(_ date: Date) -> Int {
        Int((date.timeIntervalSince1970 * 1000).rounded())
    }

    /// Writes an external session file `<id>.json` into `folder` from a dictionary, in place (truncate
    /// and rewrite, like the Claude registry; the helper script renames instead).
    @discardableResult
    static func writeExternal(_ object: [String: Any], to folder: URL) throws -> URL {
        let id = object["id"] as? String ?? "session"
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        let url = folder.appending(path: "\(id).json")
        try data.write(to: url)
        return url
    }

    /// Polls `condition` until it holds or `timeout` passes. Only tests poll; the app never does.
    @MainActor
    static func waitUntil(
        timeout: TimeInterval = 2,
        pollEvery interval: Duration = .milliseconds(20),
        _ condition: @MainActor () -> Bool
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(for: interval)
        }
        return condition()
    }
}

/// Tests name Claude sessions by pid literal (`hide(key: 4242, ...)`, `[.claude(1): date]` as `[1: date]`).
extension SessionKey: ExpressibleByIntegerLiteral {
    public init(integerLiteral value: Int32) {
        self = .claude(value)
    }
}
