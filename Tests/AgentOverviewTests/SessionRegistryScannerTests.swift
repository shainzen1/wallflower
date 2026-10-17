import Foundation
import Testing
@testable import AgentOverview

@Suite("SessionRegistryScanner")
struct SessionRegistryScannerTests {
    @Test func filtersByEntrypointAndSkipsStaleAndJunk() throws {
        let folder = try TestSupport.makeTempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let live = TestSupport.livePid
        let other = live + 100_000  // pid_t is Int32; keep a distinct, still dead, value
        try TestSupport.writeFixture("busy-desktop", to: folder, pid: live)
        try TestSupport.writeFixture("busy-cli", to: folder, pid: live - 1 > 0 ? live - 1 : live + 1)
        try TestSupport.writeFixture("idle-desktop", to: folder, pid: TestSupport.deadPid)
        try TestSupport.writeFixture("waiting-desktop", to: folder, pid: other)
        try Data("not json".utf8).write(to: folder.appending(path: "\(live).\(UUID().uuidString).key"))
        try Data("not json".utf8).write(to: folder.appending(path: "notes.txt"))
        try Data("{broken".utf8).write(to: folder.appending(path: "\(live + 1).json"))

        let filtered = SessionRegistryScanner.scan(folder: folder)
        #expect(filtered.records.map(\.pid) == [live])
        #expect(filtered.records.first?.entrypoint == "claude-desktop")
        #expect(filtered.fileURLs.count == 5)
        #expect(filtered.fileURLs.allSatisfy { $0.pathExtension == "json" })
        #expect(!filtered.presentPids.contains(TestSupport.deadPid))
        #expect(!filtered.presentPids.contains(other))
        #expect(filtered.presentPids.contains(live))

        let unfiltered = SessionRegistryScanner.scan(folder: folder, entrypoints: nil)
        let entrypoints = Set(unfiltered.records.map(\.entrypoint))
        #expect(unfiltered.records.contains { $0.pid == live })
        #expect(!unfiltered.records.contains { $0.pid == TestSupport.deadPid })
        #expect(!unfiltered.records.contains { $0.pid == other })
        // The CLI fixture is only included if its pid happens to be alive (a neighbouring pid usually is not).
        #expect(entrypoints.isSubset(of: ["claude-desktop", "sdk-cli"]))
    }

    @Test func missingFolderIsEmpty() {
        let result = SessionRegistryScanner.scan(folder: URL(filePath: "/nonexistent/agent-overview-\(UUID().uuidString)"))
        #expect(result == RegistryScanResult())
    }

    @Test func undecodableLiveFileCountsAsPresent() throws {
        let folder = try TestSupport.makeTempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        try Data("{".utf8).write(to: folder.appending(path: "\(TestSupport.livePid).json"))
        try Data("{".utf8).write(to: folder.appending(path: "\(TestSupport.deadPid).json"))
        let result = SessionRegistryScanner.scan(folder: folder)
        #expect(result.records.isEmpty)
        #expect(result.presentPids == [TestSupport.livePid])
        #expect(result.fileURLs.count == 2)
    }

    @Test func liveness() {
        #expect(SessionRegistryScanner.isAlive(TestSupport.livePid))
        #expect(SessionRegistryScanner.isAlive(1))  // launchd: exists, EPERM for us
        #expect(!SessionRegistryScanner.isAlive(TestSupport.deadPid))
        #expect(!SessionRegistryScanner.isAlive(0))
        #expect(!SessionRegistryScanner.isAlive(-1))
    }
}
