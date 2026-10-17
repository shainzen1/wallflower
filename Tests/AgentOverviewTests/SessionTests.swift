import Foundation
import Testing
@testable import AgentOverview

@Suite("Session")
@MainActor
struct SessionTests {
    @Test func nameFallsBackToFolderThenPid() throws {
        var record = try TestSupport.fixtureRecord("idle-desktop")
        #expect(Session.displayName(for: record) == "Fix onboarding layout")
        record.name = nil
        #expect(Session.displayName(for: record) == "project-b")
        record.name = "   "
        #expect(Session.displayName(for: record) == "project-b")
        record.cwd = "/"
        #expect(Session.displayName(for: record) == "Session \(record.pid)")
        record.cwd = ""
        #expect(Session.displayName(for: record) == "Session \(record.pid)")
    }

    @Test func busyToIdleMarksJustFinished() throws {
        var record = try TestSupport.fixtureRecord("busy-desktop")
        let session = Session(record: record)
        #expect(session.state == .working)
        #expect(session.justFinishedUntil == nil)

        let now = Date()
        record.status = .idle
        record.statusUpdatedAt = (record.statusUpdatedAt ?? 0) + 1000
        session.apply(record: record, now: now)
        #expect(session.state == .idle)
        #expect(session.justFinishedUntil == now.addingTimeInterval(DataTuning.justFinishedDuration))
        #expect(session.isJustFinished(at: now))
        #expect(!session.isJustFinished(at: now.addingTimeInterval(DataTuning.justFinishedDuration)))
        #expect(session.stateSince == record.statusUpdatedDate)

        // Going back to work clears the flag; idle without a preceding busy does not set it.
        record.status = .busy
        session.apply(record: record)
        #expect(session.justFinishedUntil == nil)
        record.status = .waiting
        record.waitingFor = "input needed"
        session.apply(record: record)
        record.status = .idle
        record.waitingFor = nil
        session.apply(record: record)
        #expect(session.state == .idle)
        #expect(session.justFinishedUntil == nil)
    }

    @Test func applyUpdatesFieldsInPlace() throws {
        var record = try TestSupport.fixtureRecord("waiting-desktop")
        let session = Session(record: record)
        #expect(session.state == .needsInput(kind: .question))
        #expect(session.hostSessionId == record.hostSessionId)
        record.name = "Renamed"
        record.waitingFor = "permission prompt"
        session.apply(record: record)
        #expect(session.name == "Renamed")
        #expect(session.state == .needsInput(kind: .permission))
        #expect(session.pid == record.pid)
        #expect(!session.ended)
        session.markEnded()
        #expect(session.ended)
    }
}
