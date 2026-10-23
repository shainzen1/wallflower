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
    /// A third live pid: a helper process that lives exactly as long as the test run (`Keeper`).
    static let keeperPid = Keeper.shared.pid
    /// Pids for tests that show several sessions at once, each alive for the whole run. Never
    /// `livePid + n`: that is often no process at all, or a short-lived one another test started, and
    /// the store ends a session whose process is gone (its exit source fires at once for a missing
    /// pid) and drops the row after `DataTuning.endedLinger`. A test that ran past that lost rows.
    static let livePids: [pid_t] = [livePid, otherLivePid, keeperPid]
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

    /// Runs blocking work (a subprocess and its pipes) on a dispatch queue and awaits its result, so
    /// the test holds no thread of the cooperative pool while it waits. swift-testing runs the tests
    /// on that pool (as many threads as cores), and every `Task.sleep` resumes through it: the script
    /// suites (publish.sh with its git repos, release scripts, `swift` running a script) used to block
    /// pool threads for seconds, so the sleeps and polls of the timing tests woke late.
    static func offThePool<T: Sendable>(_ work: @escaping @Sendable () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global().async { continuation.resume(with: Result { try work() }) }
        }
    }

    /// How much longer than its `timeout` a wait may run before it gives up. The timeout says how long
    /// the awaited thing should take; this covers a busy machine. In a full parallel `swift test` the
    /// main actor runs the synchronous `@MainActor` tests (goo geometry, containment, path rendering)
    /// one after the other, so a poll's wake-up and the model's own `Task.sleep` both queue behind
    /// them: under load a single 20 ms poll was measured resuming 1.5 to 3.2 s late, past the old
    /// "duration + 1 s" deadline, before the model's sleep had even run. A wait that holds returns as
    /// soon as it holds, so the allowance costs a passing test nothing.
    static let busyRunAllowance: TimeInterval = 15

    /// Polls `condition` until it holds or `timeout` (plus `busyRunAllowance`) passes. Only tests
    /// poll; the app never does.
    @MainActor
    static func waitUntil(
        timeout: TimeInterval = 2,
        pollEvery interval: Duration = .milliseconds(20),
        _ condition: @MainActor () -> Bool
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout + busyRunAllowance)
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

/// The process behind `TestSupport.keeperPid`: `/bin/cat` reading a pipe that only the test process
/// writes to. However the run ends, the pipe closes with it and cat exits, so nothing outlives it.
/// Started on first use, never changed afterwards.
private final class Keeper: @unchecked Sendable {
    static let shared = Keeper()
    private let process = Process()
    private let input = Pipe()

    var pid: pid_t { process.processIdentifier }

    private init() {
        process.executableURL = URL(filePath: "/bin/cat")
        process.standardInput = input
        process.standardOutput = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            fatalError("Could not start the keeper process: \(error)")
        }
    }
}
