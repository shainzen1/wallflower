import Foundation
import Testing
@testable import AgentOverview

@Suite("Session sorting")
@MainActor
struct SessionSortingTests {
    private func makeSession(pid: pid_t, status: RegistryStatus, waitingFor: String? = nil, since: Int) throws -> Session {
        var record = try TestSupport.fixtureRecord("idle-desktop")
        record.pid = pid
        record.status = status
        record.waitingFor = waitingFor
        record.statusUpdatedAt = since
        return Session(record: record)
    }

    @Test func needsInputThenWorkingThenIdleMostRecentFirst() throws {
        let sessions = try [
            makeSession(pid: 10, status: .idle, since: 5000),
            makeSession(pid: 11, status: .busy, since: 1000),
            makeSession(pid: 12, status: .waiting, waitingFor: "permission prompt", since: 100),
            makeSession(pid: 13, status: .idle, since: 9000),
            makeSession(pid: 14, status: .waiting, waitingFor: "input needed", since: 200),
            makeSession(pid: 15, status: .busy, since: 3000),
        ]
        let ordered = SessionStore.sorted(sessions).map(\.pid)
        #expect(ordered == [14, 12, 15, 11, 13, 10])
    }

    @Test func pidBreaksTiesDeterministically() throws {
        let sessions = try [
            makeSession(pid: 30, status: .busy, since: 1000),
            makeSession(pid: 20, status: .busy, since: 1000),
            makeSession(pid: 10, status: .busy, since: 1000),
        ]
        #expect(SessionStore.sorted(sessions).map(\.pid) == [10, 20, 30])
        #expect(SessionStore.sorted(sessions.reversed()).map(\.pid) == [10, 20, 30])
    }

    @Test func storeKeepsOrderAfterReconcile() throws {
        let store = SessionStore(folder: URL(filePath: "/nonexistent"), entrypoints: nil)
        var a = try TestSupport.fixtureRecord("busy-desktop")
        var b = try TestSupport.fixtureRecord("idle-desktop")
        a.pid = TestSupport.livePid
        b.pid = TestSupport.otherLivePid
        b.statusUpdatedAt = (a.statusUpdatedAt ?? 0) + 10_000
        store.reconcile(RegistryScanResult(records: [b, a], presentPids: [a.pid, b.pid]))
        #expect(store.sessions.map(\.pid) == [a.pid, b.pid])
        #expect(store.hasScanned)

        b.status = .waiting
        b.waitingFor = "input needed"
        store.reconcile(RegistryScanResult(records: [a, b], presentPids: [a.pid, b.pid]))
        #expect(store.sessions.map(\.pid) == [b.pid, a.pid])
        #expect(store.sessions.first?.state == .needsInput(kind: .question))
        store.stop()
    }
}
