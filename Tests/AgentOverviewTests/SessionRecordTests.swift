import Foundation
import Testing
@testable import AgentOverview

@Suite("SessionRecord decoding")
struct SessionRecordTests {
    @Test("Every fixture decodes", arguments: TestSupport.fixtureNames)
    func fixtureDecodes(name: String) throws {
        let record = try TestSupport.fixtureRecord(name)
        #expect(record.pid > 0)
        #expect(!record.sessionId.isEmpty)
        #expect(!record.cwd.isEmpty)
        #expect(record.name != nil)
    }

    @Test func busyDesktop() throws {
        let record = try TestSupport.fixtureRecord("busy-desktop")
        #expect(record.status == .busy)
        #expect(record.waitingFor == nil)
        #expect(record.waitingKind == .other)
        #expect(record.entrypoint == "claude-desktop")
        #expect(record.hostSessionId?.hasPrefix("local_") == true)
        #expect(record.formerNames == nil)
        #expect(record.nameSource == "user")
        #expect(SessionState(record: record) == .working)
    }

    @Test func idleDesktop() throws {
        let record = try TestSupport.fixtureRecord("idle-desktop")
        #expect(record.status == .idle)
        #expect(record.entrypoint == "claude-desktop")
        #expect(record.hostSessionId != nil)
        #expect(SessionState(record: record) == .idle)
    }

    @Test func waitingQuestion() throws {
        let record = try TestSupport.fixtureRecord("waiting-desktop")
        #expect(record.status == .waiting)
        #expect(record.waitingFor == "input needed")
        #expect(record.waitingKind == .question)
        #expect(record.formerNames?.count == 2)
        #expect(record.formerNames?.first?.sessionId != record.sessionId)
        #expect(SessionState(record: record) == .needsInput(kind: .question))
    }

    @Test func waitingPermission() throws {
        let record = try TestSupport.fixtureRecord("waiting-permission-desktop.synthetic")
        #expect(record.status == .waiting)
        #expect(record.waitingKind == .permission)
        #expect(SessionState(record: record) == .needsInput(kind: .permission))
    }

    @Test func cliFixtures() throws {
        let busy = try TestSupport.fixtureRecord("busy-cli")
        let idle = try TestSupport.fixtureRecord("idle-cli")
        #expect(busy.entrypoint == "sdk-cli")
        #expect(busy.hostSessionId == nil)
        #expect(busy.nameSource == "derived")
        #expect(busy.status == .busy)
        #expect(idle.status == .idle)
        #expect(idle.pid == busy.pid)
    }

    @Test func timestampsAreEpochMilliseconds() throws {
        let record = try TestSupport.fixtureRecord("busy-desktop")
        #expect(record.startedDate == Date(timeIntervalSince1970: 1_791_883_748.274))
        #expect(record.statusUpdatedDate == Date(timeIntervalSince1970: 1_791_883_748.275))
    }

    @Test func unknownWaitingForIsOther() {
        #expect(WaitingKind(waitingFor: "dialog open") == .other)
        #expect(WaitingKind(waitingFor: nil) == .other)
        #expect(WaitingKind(waitingFor: "input needed") == .question)
        #expect(WaitingKind(waitingFor: "permission prompt") == .permission)
    }

    @Test func minimalRecordAndUnknownKeys() throws {
        let json = """
        {"pid": 42, "sessionId": "s", "cwd": "/Users/demo/Developer/widgets", "startedAt": 1000,
         "entrypoint": "claude-desktop", "status": "idle", "somethingNew": {"nested": true}}
        """
        let record = try JSONDecoder().decode(SessionRecord.self, from: Data(json.utf8))
        #expect(record.name == nil)
        #expect(record.hostSessionId == nil)
        #expect(record.waitingFor == nil)
        #expect(record.formerNames == nil)
        #expect(record.statusUpdatedDate == record.startedDate)
    }

    @Test func undecodableFileIsDropped() {
        #expect(SessionRegistryScanner.decode(Data("{not json".utf8), fileName: "1.json") == nil)
        #expect(SessionRegistryScanner.decode(Data("{\"pid\": 1}".utf8), fileName: "1.json") == nil)
    }
}
