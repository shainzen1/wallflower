import Foundation
import Testing
@testable import AgentOverview

/// Collects the window states a model asked for (a class so the closure can append).
@MainActor
private final class WindowStateRecorder {
    var states: [PanelWindowState] = []
}

@Suite("Panel model")
@MainActor
struct PanelModelTests {
    private let since = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeSession(pid: pid_t, status: RegistryStatus, waitingFor: String? = nil, since: Int) throws -> Session {
        var record = try TestSupport.fixtureRecord("idle-desktop")
        record.pid = pid
        record.status = status
        record.waitingFor = waitingFor
        record.statusUpdatedAt = since
        return Session(record: record)
    }

    // MARK: Status mapping

    @Test func needsInputMapsToNeedsInput() {
        let status = SessionRow.faceStatus(state: .needsInput(kind: .question), isJustFinished: false, ended: false, stateSince: since)
        #expect(status == .needsInput(kind: .question))
        let permission = SessionRow.faceStatus(state: .needsInput(kind: .permission), isJustFinished: false, ended: false, stateSince: since)
        #expect(permission == .needsInput(kind: .permission))
    }

    @Test func workingMapsToWorking() {
        #expect(SessionRow.faceStatus(state: .working, isJustFinished: false, ended: false, stateSince: since) == .working)
    }

    @Test func idleMapsToIdleSinceStateStart() {
        #expect(SessionRow.faceStatus(state: .idle, isJustFinished: false, ended: false, stateSince: since) == .idle(since: since))
    }

    @Test func idleWhileJustFinishedMapsToJustFinished() {
        #expect(SessionRow.faceStatus(state: .idle, isJustFinished: true, ended: false, stateSince: since) == .justFinished)
    }

    @Test func endedWinsOverEveryState() {
        #expect(SessionRow.faceStatus(state: .needsInput(kind: .question), isJustFinished: false, ended: true, stateSince: since) == .ended)
        #expect(SessionRow.faceStatus(state: .working, isJustFinished: false, ended: true, stateSince: since) == .ended)
        #expect(SessionRow.faceStatus(state: .idle, isJustFinished: true, ended: true, stateSince: since) == .ended)
    }

    @Test func rowFromSessionCarriesTheFields() throws {
        let session = try makeSession(pid: 4242, status: .waiting, waitingFor: "input needed", since: 1_700_000_000_000)
        let row = SessionRow(session: session)
        #expect(row.pid == 4242)
        #expect(row.id == 4242)
        #expect(row.name == "Fix onboarding layout")
        #expect(row.status == .needsInput(kind: .question))
        #expect(row.label == "Needs input")
        #expect(row.stateSince == since)
        #expect(row.hostSessionId == "local_93928bc1-635f-4580-9c90-29b1bc783406")
        #expect(row.seed == "local_93928bc1-635f-4580-9c90-29b1bc783406")
        #expect(!row.ended)

        session.markEnded()
        let endedRow = SessionRow(session: session)
        #expect(endedRow.ended)
        #expect(endedRow.status == .ended)
        #expect(endedRow.label == "Ended")
    }

    @Test func justFinishedSessionRowFollowsTheClock() throws {
        var record = try TestSupport.fixtureRecord("busy-desktop")
        record.pid = 1
        let session = Session(record: record)
        record.status = .idle
        record.statusUpdatedAt = (record.statusUpdatedAt ?? 0) + 1000
        let now = Date()
        session.apply(record: record, now: now)
        #expect(SessionRow(session: session, now: now).status == .justFinished)
        #expect(SessionRow(session: session, now: now).label == "Finished")
        let later = now.addingTimeInterval(DataTuning.justFinishedDuration + 1)
        #expect(SessionRow(session: session, now: later).status == .idle(since: session.stateSince))
        #expect(SessionRow(session: session, now: later).label == "Idle")
    }

    // MARK: Labels

    @Test func labelsForEveryStatus() {
        #expect(SessionRow.label(for: .needsInput(kind: .question)) == "Needs input")
        #expect(SessionRow.label(for: .working) == "Working")
        #expect(SessionRow.label(for: .idle(since: since)) == "Idle")
        #expect(SessionRow.label(for: .justFinished) == "Finished")
        #expect(SessionRow.label(for: .ended) == "Ended")
    }

    // MARK: Duration formatting

    @Test func durationBoundaries() {
        func text(_ seconds: TimeInterval) -> String {
            StateDurationText.duration(since: since, now: since.addingTimeInterval(seconds))
        }
        #expect(text(0) == "now")
        #expect(text(59) == "now")
        #expect(text(60) == "1m")
        #expect(text(119) == "1m")
        #expect(text(59 * 60 + 59) == "59m")
        #expect(text(60 * 60) == "1h 0m")
        #expect(text(60 * 60 + 5 * 60) == "1h 5m")
        #expect(text(23 * 3600 + 59 * 60) == "23h 59m")
        #expect(text(24 * 3600) == "1d")
        #expect(text(3 * 24 * 3600 + 7 * 3600) == "3d")
        #expect(text(-30) == "now", "a state start in the future (clock skew) reads as now")
    }

    @Test func durationTextJoinsLabelAndDuration() {
        let text = StateDurationText.text(label: "Needs input", since: since, now: since.addingTimeInterval(2 * 60))
        #expect(text == "Needs input · 2m")
    }

    // MARK: Rows follow the store

    @Test func rowsFollowTheStoreOrder() throws {
        let store = SessionStore(folder: URL(filePath: "/nonexistent"), entrypoints: nil)
        defer { store.stop() }
        let model = PanelModel(store: store)
        #expect(model.rows.isEmpty)
        #expect(model.capsuleRows == Theme.emptyCapsuleRows)
        #expect(model.capsuleHeight == Theme.capsuleHeight(rows: Theme.emptyCapsuleRows))

        var idle = try TestSupport.fixtureRecord("idle-desktop")
        var busy = try TestSupport.fixtureRecord("busy-desktop")
        var waiting = try TestSupport.fixtureRecord("waiting-desktop")
        idle.pid = TestSupport.livePid
        busy.pid = TestSupport.otherLivePid
        waiting.pid = TestSupport.keeperPid
        let pids: Set<pid_t> = [idle.pid, busy.pid, waiting.pid]
        store.reconcile(RegistryScanResult(records: [idle, busy], presentPids: pids))
        #expect(model.rows.map(\.pid) == [busy.pid, idle.pid])
        #expect(model.rows.map(\.status) == [.working, .idle(since: idle.statusUpdatedDate)])
        #expect(model.capsuleRows == 2)

        store.reconcile(RegistryScanResult(records: [idle, busy, waiting], presentPids: pids))
        #expect(model.rows.map(\.pid) == [waiting.pid, busy.pid, idle.pid], "a waiting session sorts to the top")
        #expect(model.rows.first?.label == "Needs input")

        busy.status = .idle
        busy.statusUpdatedAt = (idle.statusUpdatedAt ?? 0) + 60_000
        store.reconcile(RegistryScanResult(records: [idle, busy, waiting], presentPids: pids))
        #expect(model.rows.map(\.pid) == [waiting.pid, busy.pid, idle.pid], "the newest idle sits above the older idle")
        #expect(model.rows[1].status == .justFinished)

        store.reconcile(RegistryScanResult(records: [idle, busy], presentPids: [idle.pid, busy.pid]))
        #expect(model.rows.first?.pid == waiting.pid, "an ended session lingers in place")
        #expect(model.rows.first?.ended == true)
        #expect(model.rows.first?.status == .ended)
    }

    // MARK: Window height timing

    @Test func windowGrowsAtOnceAndShrinksAfterTheSpringSettled() async throws {
        let store = SessionStore(folder: URL(filePath: "/nonexistent"), entrypoints: nil)
        defer { store.stop() }
        let model = PanelModel(store: store)
        var heights: [CGFloat] = []
        model.setWindowHeight = { heights.append($0) }

        model.rowCountDidChange(0)
        #expect(heights == [Theme.capsuleHeight(rows: 1)], "initial call sets the stub height right away")
        #expect(model.layoutAnimation(rowCount: 3) == Theme.openSpring)

        model.rowCountDidChange(3)
        #expect(heights.last == Theme.capsuleHeight(rows: 3), "growing sets the final height immediately")
        #expect(model.layoutAnimation(rowCount: 2) == RowEntrance.departureAnimation(reduceMotion: false), "a shrink runs on the departure progress")
        #expect(model.layoutAnimation(rowCount: 3) == Theme.openSpring, "reorder (same count) uses the open spring")

        model.rowCountDidChange(2)
        #expect(heights.count == 2, "shrinking waits for the spring")
        #expect(await TestSupport.waitUntil(timeout: Theme.closeSpringSettleTime + 1) { heights.count == 3 })
        #expect(heights.last == Theme.capsuleHeight(rows: 2))

        // A grow during a pending shrink cancels the shrink.
        model.rowCountDidChange(1)
        model.rowCountDidChange(4)
        #expect(heights.last == Theme.capsuleHeight(rows: 4))
        try await Task.sleep(for: .seconds(Theme.closeSpringSettleTime + 0.2))
        #expect(heights.last == Theme.capsuleHeight(rows: 4), "the cancelled shrink never lands")
    }

    // MARK: Hover and window state (animation rule 4)

    /// A store with three live desktop sessions and a model whose window calls are recorded.
    private func makeHoverModel(expandMode: Theme.ExpandMode = .row) throws -> (SessionStore, PanelModel, () -> [PanelWindowState]) {
        let store = SessionStore(folder: URL(filePath: "/nonexistent"), entrypoints: nil)
        var idle = try TestSupport.fixtureRecord("idle-desktop")
        var busy = try TestSupport.fixtureRecord("busy-desktop")
        var waiting = try TestSupport.fixtureRecord("waiting-desktop")
        idle.pid = TestSupport.livePid
        busy.pid = TestSupport.otherLivePid
        waiting.pid = TestSupport.keeperPid
        store.reconcile(RegistryScanResult(records: [idle, busy, waiting], presentPids: [idle.pid, busy.pid, waiting.pid]))
        let model = PanelModel(store: store, expandMode: expandMode)
        let recorder = WindowStateRecorder()
        model.setWindowState = { recorder.states.append($0) }
        return (store, model, { recorder.states })
    }

    @Test func hoverExpandsTheWindowAtOnceAndCollapsesAfterTheSpringSettled() async throws {
        let (store, model, states) = try makeHoverModel()
        defer { store.stop() }
        #expect(!model.isExpanded)
        #expect(model.hoveredKey == nil)

        model.hover(rowIndex: 1)
        #expect(states() == [.expanded(width: Theme.capsuleWidth + Theme.bulgeMaxWidth)], "the window grows before anything animates")
        #expect(model.isExpanded)
        #expect(model.hoveredKey == model.rows[1].key)
        #expect(model.hoveredRowIndex == 1)
        #expect(model.bulgeRowIndex == 1)
        #expect(model.gooAnimation == Theme.openSpring)
        #expect(!model.bulgeTravelled)
        #expect(model.revealDelay == Theme.revealDelay)

        model.hover(rowIndex: 2)
        #expect(states().count == 1, "moving to another row never resizes the window")
        #expect(model.hoveredRowIndex == 2)
        #expect(model.bulgeTravelled, "the bulge travelled, so the reveal waits longer")
        #expect(model.revealDelay == Theme.revealTravelDelay)

        model.hover(rowIndex: nil)
        #expect(!model.isExpanded)
        #expect(model.hoveredKey == nil)
        #expect(model.bulgeRowIndex == 2, "the bulge melts where it was")
        #expect(model.gooAnimation == Theme.closeSpring)
        #expect(states().count == 1, "the window stays expanded while the bulge melts")
        #expect(await TestSupport.waitUntil(timeout: Theme.closeSpringSettleTime + 1) { states().count == 2 })
        #expect(states().last == .collapsed)
    }

    @Test func reEnteringCancelsThePendingCollapse() async throws {
        let (store, model, states) = try makeHoverModel()
        defer { store.stop() }
        model.hover(rowIndex: 0)
        model.hover(rowIndex: nil)
        model.hover(rowIndex: 0)
        #expect(model.isExpanded)
        #expect(states() == [.expanded(width: Theme.capsuleWidth + Theme.bulgeMaxWidth), .expanded(width: Theme.capsuleWidth + Theme.bulgeMaxWidth)])
        try await Task.sleep(for: .seconds(Theme.closeSpringSettleTime + 0.2))
        #expect(states().count == 2, "the cancelled collapse never lands")
        #expect(states().last != .collapsed)
    }

    @Test func hoveringAnUnknownRowEndsTheHover() throws {
        let (store, model, _) = try makeHoverModel()
        defer { store.stop() }
        model.hover(rowIndex: 0)
        model.hover(rowIndex: 7)
        #expect(!model.isExpanded)
        #expect(model.hoveredKey == nil)
    }

    @Test func rowIndexFromPointerY() throws {
        let (store, model, _) = try makeHoverModel()
        defer { store.stop() }
        let top = Theme.edgeFilletRadius + Theme.capsuleEndPadding
        #expect(model.rowIndex(atY: -1) == nil, "above the capsule")
        #expect(model.rowIndex(atY: 0) == 0, "the top fillet snaps to the first row")
        #expect(model.rowIndex(atY: top - 1) == 0, "the end padding snaps to the first row")
        #expect(model.rowIndex(atY: top) == 0)
        #expect(model.rowIndex(atY: top + Theme.rowPitch - 0.5) == 0)
        #expect(model.rowIndex(atY: top + Theme.rowPitch) == 1)
        #expect(model.rowIndex(atY: top + Theme.rowPitch + Theme.faceSize + 2) == 1, "the gap below a face still belongs to its row")
        #expect(model.rowIndex(atY: top + 2.5 * Theme.rowPitch) == 2)
        #expect(model.rowIndex(atY: model.capsuleHeight) == 2, "the bottom fillet snaps to the last row")
        #expect(model.rowIndex(atY: model.capsuleHeight + 1) == nil, "below the capsule")

        let empty = PanelModel(store: SessionStore(folder: URL(filePath: "/nonexistent"), entrypoints: nil))
        #expect(empty.rowIndex(atY: top + 1) == nil, "no rows, no hover")
    }

    @Test func pointerRegionsCapsuleBulgeAndOutside() throws {
        let (store, model, _) = try makeHoverModel()
        defer { store.stop() }
        let width = Theme.capsuleWidth + Theme.bulgeMaxWidth + Theme.windowPadding
        let size = CGSize(width: width, height: model.capsuleHeight)
        let row1 = PanelModel.rowCenterY(index: 1)
        let onCapsule = CGPoint(x: width - Theme.capsuleWidth / 2, y: row1)
        let onBulge = CGPoint(x: width - Theme.capsuleWidth - 100, y: row1 + Theme.rowPitch / 2 + Theme.bulgePadding - 1)
        let leftOfBulge = CGPoint(x: width - Theme.capsuleWidth - Theme.bulgeWidth - 2, y: row1)
        let bulgeOfAnotherRow = CGPoint(x: width - Theme.capsuleWidth - 100, y: PanelModel.rowCenterY(index: 0) - 20)

        model.pointerMoved(to: onBulge, in: size)
        #expect(!model.isExpanded, "the bulge area only counts while expanded")

        model.pointerMoved(to: onCapsule, in: size)
        #expect(model.hoveredRowIndex == 1)
        model.pointerMoved(to: onBulge, in: size)
        #expect(model.hoveredRowIndex == 1, "the bulge keeps its row although its edge reaches into the next row's band")
        model.pointerMoved(to: bulgeOfAnotherRow, in: size)
        #expect(!model.isExpanded, "transparent window area outside the open bulge ends the hover")

        model.pointerMoved(to: onCapsule, in: size)
        model.pointerMoved(to: leftOfBulge, in: size)
        #expect(!model.isExpanded)

        model.pointerMoved(to: onCapsule, in: size)
        model.pointerMoved(to: nil, in: size)
        #expect(!model.isExpanded, "leaving the window ends the hover")
    }

    @Test func allModeExpandsEveryRow() throws {
        let (store, model, states) = try makeHoverModel(expandMode: .all)
        defer { store.stop() }
        #expect(model.bulgeReach == Theme.bulgeWidth)
        #expect(model.rows.allSatisfy { !model.isRowExpanded($0.key) })
        model.hover(rowIndex: 1)
        #expect(model.rows.allSatisfy { model.isRowExpanded($0.key) }, "every row shows its name and status")
        #expect(states() == [.expanded(width: Theme.capsuleWidth + Theme.bulgeMaxWidth)], "same window rules")
        let hit = model.hoverRegionContains(distanceFromEdge: Theme.capsuleWidth + Theme.bulgeWidth - 1, y: PanelModel.rowCenterY(index: 0))
        #expect(hit == .bulge, "the whole widened body is hoverable")
        model.hover(rowIndex: nil)
        #expect(model.rows.allSatisfy { !model.isRowExpanded($0.key) })

        let rowModel = try makeHoverModel(expandMode: .row).1
        rowModel.hover(rowIndex: 1)
        #expect(rowModel.rows.map { rowModel.isRowExpanded($0.key) } == [false, true, false], ".row mode expands the hovered row only")
        #expect(rowModel.bulgeReach == Theme.bulgeWidth - Theme.bulgeOverlap)
    }

    @Test func hoveredSessionLeavingEndsTheHover() async throws {
        let (store, model, _) = try makeHoverModel()
        defer { store.stop() }
        model.rowCountDidChange(3)
        model.hover(rowIndex: 0)
        let pid = model.hoveredKey!
        store.reconcile(RegistryScanResult(records: [], presentPids: []))
        #expect(model.rows.first?.key == pid, "the ended session lingers")
        model.rowCountDidChange(3)
        #expect(model.hoveredKey == pid, "still hovered while it lingers")
        #expect(await TestSupport.waitUntil(timeout: DataTuning.endedLinger + 1) { model.rows.isEmpty })
        model.rowCountDidChange(0)
        #expect(model.hoveredKey == nil, "the hovered session is gone, the hover ends")
        #expect(!model.isExpanded)
    }

    // MARK: Deep link

    @Test func deepLinkUsesHostSessionId() {
        let row = SessionRow(pid: 1, name: "A", status: .working, stateSince: since, hostSessionId: "local_abc", ended: false)
        #expect(SessionOpener.deepLink(for: row)?.absoluteString == "claude://code/continue?session=local_abc")
        let cli = SessionRow(pid: 2, name: "B", status: .working, stateSince: since, hostSessionId: nil, ended: false)
        #expect(SessionOpener.deepLink(for: cli) == nil)
    }
}
