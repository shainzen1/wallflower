import Foundation
import Observation
import QuartzCore
import Testing
@testable import AgentOverview

/// The three idle tiers: just finished (the 8 s done moment), your turn (a fresh idle period the
/// person has not acknowledged, for `Theme.yourTurnFor`) and idle (parked).
@Suite("Your turn: the tier rule, rows, order, acknowledgement, expiry and looks")
@MainActor
struct YourTurnTests {
    private let since = Date(timeIntervalSince1970: 1_800_000_000)

    /// A session from the idle fixture with the given status, its state starting at `since`.
    private func makeSession(
        pid: pid_t, status: RegistryStatus, waitingFor: String? = nil, since: Date, yourTurnFor: TimeInterval = Theme.yourTurnFor, now: Date = Date()
    ) throws -> Session {
        var record = try TestSupport.fixtureRecord("idle-desktop")
        record.pid = pid
        record.status = status
        record.waitingFor = waitingFor
        record.statusUpdatedAt = Self.millis(since)
        return Session(record: record, yourTurnFor: yourTurnFor, now: now)
    }

    private static func millis(_ date: Date) -> Int {
        Int((date.timeIntervalSince1970 * 1000).rounded())
    }

    // MARK: The rule

    @Test("Fresh idle is your turn, until yourTurnFor has passed")
    func freshIdleIsYourTurn() {
        #expect(IdleTier.tier(idleSince: since, acknowledgedAt: nil, now: since) == .yourTurn)
        #expect(IdleTier.tier(idleSince: since, acknowledgedAt: nil, now: since.addingTimeInterval(Theme.yourTurnFor - 1)) == .yourTurn)
        #expect(IdleTier.tier(idleSince: since, acknowledgedAt: nil, now: since.addingTimeInterval(Theme.yourTurnFor)) == .idle)
        #expect(IdleTier.tier(idleSince: since, acknowledgedAt: nil, now: since.addingTimeInterval(Theme.yourTurnFor + 3600)) == .idle)
        #expect(IdleTier.tier(idleSince: since, acknowledgedAt: nil, now: since.addingTimeInterval(-30)) == .yourTurn, "clock skew reads as fresh")
    }

    @Test("Acknowledged at or after the idle start is idle; a newer idle period is eligible again")
    func acknowledgementParksTheIdlePeriod() {
        let now = since.addingTimeInterval(60)
        #expect(IdleTier.tier(idleSince: since, acknowledgedAt: since, now: now) == .idle)
        #expect(IdleTier.tier(idleSince: since, acknowledgedAt: since.addingTimeInterval(10), now: now) == .idle)
        #expect(IdleTier.tier(idleSince: since, acknowledgedAt: since.addingTimeInterval(-10), now: now) == .yourTurn, "acknowledged before this idle began")
        let nextIdle = since.addingTimeInterval(300)
        #expect(IdleTier.tier(idleSince: nextIdle, acknowledgedAt: since.addingTimeInterval(10), now: nextIdle.addingTimeInterval(5)) == .yourTurn)
    }

    @Test("Sleepy never comes while it is still your turn")
    func sleepyAfterYourTurn() {
        #expect(Theme.sleepyAfter >= Theme.yourTurnFor)
        #expect(Theme.yourTurnFor == 15 * 60)
    }

    // MARK: Rows

    @Test("faceStatus: an idle session is your turn or idle by its tier; just finished and ended win")
    func faceStatusMapping() {
        #expect(SessionRow.faceStatus(state: .idle, isJustFinished: false, ended: false, stateSince: since, idleTier: .yourTurn) == .yourTurn(since: since))
        #expect(SessionRow.faceStatus(state: .idle, isJustFinished: false, ended: false, stateSince: since, idleTier: .idle) == .idle(since: since))
        #expect(SessionRow.faceStatus(state: .idle, isJustFinished: true, ended: false, stateSince: since, idleTier: .yourTurn) == .justFinished)
        #expect(SessionRow.faceStatus(state: .idle, isJustFinished: false, ended: true, stateSince: since, idleTier: .yourTurn) == .ended)
        #expect(SessionRow.faceStatus(state: .working, isJustFinished: false, ended: false, stateSince: since, idleTier: .yourTurn) == .working)
        #expect(SessionRow.faceStatus(state: .needsInput(kind: .question), isJustFinished: false, ended: false, stateSince: since, idleTier: .yourTurn) == .needsInput(kind: .question))
    }

    @Test("Your turn reads `Your turn · 5m`")
    func labels() {
        let status = FaceStatus.yourTurn(since: since)
        #expect(SessionRow.label(for: status) == "Your turn")
        #expect(SessionRow.label(for: status, activity: .coding) == "Your turn", "no activity outside working")
        #expect(StateDurationText.text(label: SessionRow.label(for: status), since: since, now: since.addingTimeInterval(5 * 60)) == "Your turn · 5m")
        #expect(status.isYourTurn && !status.isNeedsInput && status.waitingKind == nil)
        #expect(!FaceStatus.idle(since: since).isYourTurn && !FaceStatus.justFinished.isYourTurn)
    }

    @Test("A row from a session: fresh idle is your turn, old idle is idle, acknowledged is idle")
    func rowFromSession() throws {
        let now = Date()
        let fresh = try makeSession(pid: 1, status: .idle, since: now.addingTimeInterval(-120), now: now)
        let row = SessionRow(session: fresh, now: now)
        #expect(row.status == .yourTurn(since: fresh.stateSince))
        #expect(row.label == "Your turn")
        #expect(SessionRow(session: fresh, now: now, acknowledgedAt: now).status == .idle(since: fresh.stateSince))

        let old = try makeSession(pid: 2, status: .idle, since: now.addingTimeInterval(-Theme.yourTurnFor - 60), now: now)
        #expect(SessionRow(session: old, now: now).status == .idle(since: old.stateSince), "a relaunch keeps the tier: old idle stays idle")
    }

    @Test("The done moment hands over to your turn, not to idle")
    func justFinishedEasesIntoYourTurn() throws {
        var record = try TestSupport.fixtureRecord("busy-desktop")
        record.pid = 3
        let session = Session(record: record)
        let now = Date()
        record.status = .idle
        record.statusUpdatedAt = Self.millis(now)
        session.apply(record: record, now: now)
        #expect(SessionRow(session: session, now: now).status == .justFinished)
        let later = now.addingTimeInterval(DataTuning.justFinishedDuration + 1)
        #expect(SessionRow(session: session, now: later).status == .yourTurn(since: session.stateSince))
        let parked = now.addingTimeInterval(Theme.yourTurnFor + 1)
        #expect(SessionRow(session: session, now: parked).status == .idle(since: session.stateSince))
    }

    // MARK: Order

    @Test("Order: needs input, working, your turn, idle; an acknowledged idle drops below your turn")
    func fourTiers() throws {
        let now = Date()
        let sessions = try [
            makeSession(pid: 10, status: .idle, since: now.addingTimeInterval(-3600), now: now),
            makeSession(pid: 11, status: .idle, since: now.addingTimeInterval(-60), now: now),
            makeSession(pid: 12, status: .busy, since: now.addingTimeInterval(-30), now: now),
            makeSession(pid: 13, status: .waiting, waitingFor: "input needed", since: now.addingTimeInterval(-7200), now: now),
            makeSession(pid: 14, status: .idle, since: now.addingTimeInterval(-300), now: now),
            makeSession(pid: 15, status: .idle, since: now.addingTimeInterval(-1800), now: now),
        ]
        #expect(SessionStore.sorted(sessions, now: now).map(\.pid) == [13, 12, 11, 14, 15, 10])
        // The person opened the newest idle one: it is parked, below the older your-turn session,
        // and still above the older idle ones (newest state change first within a group).
        let acknowledged = SessionStore.sorted(sessions, acknowledgements: [11: now], now: now).map(\.pid)
        #expect(acknowledged == [13, 12, 14, 11, 15, 10])
        #expect(SessionState.idle.sortRank(idleTier: .yourTurn) < SessionState.idle.sortRank(idleTier: .idle))
        #expect(SessionState.working.sortRank(idleTier: .yourTurn) < SessionState.idle.sortRank(idleTier: .yourTurn))
    }

    // MARK: Acknowledgement

    /// A model over a store holding a fresh idle session (your turn) and an older your-turn one.
    private func makeModel() throws -> (SessionStore, PanelModel, fresh: pid_t, older: pid_t, record: SessionRecord) {
        let store = SessionStore(folder: URL(filePath: "/nonexistent"), entrypoints: nil)
        let now = Date()
        var fresh = try TestSupport.fixtureRecord("idle-desktop")
        var older = try TestSupport.fixtureRecord("idle-desktop")
        fresh.pid = TestSupport.livePid
        older.pid = TestSupport.otherLivePid
        fresh.statusUpdatedAt = Self.millis(now.addingTimeInterval(-60))
        older.statusUpdatedAt = Self.millis(now.addingTimeInterval(-300))
        store.reconcile(RegistryScanResult(records: [fresh, older], presentPids: [fresh.pid, older.pid]))
        let model = PanelModel(store: store)
        model.open = { _ in }
        return (store, model, fresh.pid, older.pid, fresh)
    }

    @Test("A click acknowledges the row: it drops to idle and below the other your-turn row")
    func clickAcknowledges() throws {
        let (store, model, fresh, older, _) = try makeModel()
        defer { store.stop() }
        #expect(model.rows.map(\.pid) == [fresh, older])
        #expect(model.rows.allSatisfy { $0.status.isYourTurn })

        model.tapped(model.rows[0])
        #expect(model.acknowledgements.time(for: .claude(fresh)) != nil)
        #expect(model.rows.map(\.pid) == [older, fresh], "the acknowledged row sorts below your turn")
        #expect(model.rows[0].status.isYourTurn)
        #expect(model.rows[1].status == .idle(since: model.rows[1].stateSince))
        #expect(model.rows[1].label == "Idle")
    }

    @Test("A click that ended a drag acknowledges nothing")
    func swallowedTapDoesNotAcknowledge() throws {
        let (store, model, fresh, _, _) = try makeModel()
        defer { store.stop() }
        model.pressBegan()
        model.dragBegan()
        model.dragEnded()
        model.tapped(model.rows[0])
        #expect(model.acknowledgements.time(for: .claude(fresh)) == nil)
        #expect(model.rows[0].status.isYourTurn)
    }

    @Test("A new idle period after an acknowledgement is your turn again")
    func newIdlePeriodIsEligibleAgain() throws {
        let (store, model, fresh, _, record) = try makeModel()
        defer { store.stop() }
        model.tapped(model.rows[0])
        #expect(model.rows.first { $0.pid == fresh }?.status.isYourTurn == false)

        var busy = record
        busy.status = .busy
        busy.statusUpdatedAt = Self.millis(Date().addingTimeInterval(1))
        store.reconcile(RegistryScanResult(records: [busy], presentPids: [fresh, TestSupport.otherLivePid]))
        var idle = record
        idle.statusUpdatedAt = Self.millis(Date().addingTimeInterval(2))
        store.reconcile(RegistryScanResult(records: [idle], presentPids: [fresh, TestSupport.otherLivePid]))
        let row = try #require(model.rows.first { $0.pid == fresh })
        #expect(row.status == .justFinished, "the done moment first")
        let after = SessionRow(
            session: try #require(store.sessions.first { $0.pid == fresh }),
            now: Date().addingTimeInterval(DataTuning.justFinishedDuration + 3),
            acknowledgedAt: model.acknowledgements.time(for: .claude(fresh))
        )
        #expect(after.status.isYourTurn, "the old acknowledgement predates this idle period")
    }

    @Test("Acknowledgements are pruned with the other per-pid state when sessions leave")
    func acknowledgementsArePruned() async throws {
        let (store, model, fresh, older, _) = try makeModel()
        defer { store.stop() }
        model.tapped(model.rows[0])
        model.tapped(model.rows[0])
        #expect(model.acknowledgements.times.keys.sorted() == [SessionKey.claude(fresh), .claude(older)].sorted())
        model.layoutDidChange(rows: 2, actions: 0)
        #expect(model.acknowledgements.times.count == 2, "both still shown")

        var acknowledgements = Acknowledgements()
        acknowledgements.acknowledge(key: 1, at: since)
        acknowledgements.acknowledge(key: 2, at: since)
        #expect(acknowledgements.keeping(keys: [2]).times.keys.sorted() == [2])
        #expect(acknowledgements.keeping(keys: [1, 2]) == acknowledgements)

        // The session with `fresh` leaves: it ends, lingers, then goes; the next layout prunes it.
        store.reconcile(RegistryScanResult(records: [], presentPids: [older]))
        #expect(await TestSupport.waitUntil(timeout: DataTuning.endedLinger + 2) { !store.sessions.contains { $0.pid == fresh } })
        model.layoutDidChange(rows: model.rows.count, actions: 0)
        #expect(model.acknowledgements.time(for: .claude(fresh)) == nil)
        #expect(model.acknowledgements.time(for: .claude(older)) != nil)
    }

    // MARK: Expiry

    @Test("The your-turn window closing re-derives the row, with no polling")
    func expiryFlipsTheRow() async throws {
        let now = Date()
        let session = try makeSession(pid: TestSupport.livePid, status: .idle, since: now, yourTurnFor: 0.3, now: now)
        #expect(SessionRow(session: session).status.isYourTurn)
        let changed = ObservationFlag()
        withObservationTracking {
            _ = SessionRow(session: session)
        } onChange: {
            Task { @MainActor in changed.fired = true }
        }
        #expect(await TestSupport.waitUntil(timeout: 2) { changed.fired }, "the one-shot bumps an observed value")
        #expect(session.yourTurnExpiries == 1)
        #expect(SessionRow(session: session).status == .idle(since: session.stateSince))
    }

    @Test("An expiry for an idle period that already ended changes nothing")
    func staleExpiryIsIgnored() async throws {
        var record = try TestSupport.fixtureRecord("idle-desktop")
        record.pid = TestSupport.livePid
        record.statusUpdatedAt = Self.millis(Date())
        let session = Session(record: record, yourTurnFor: 0.2)
        record.status = .busy
        record.statusUpdatedAt = Self.millis(Date().addingTimeInterval(0.05))
        session.apply(record: record)
        try await Task.sleep(for: .milliseconds(450))
        #expect(session.yourTurnExpiries == 0)
        #expect(SessionRow(session: session).status == .working)
    }

    @Test("A session idle for longer than the window at launch arms nothing and shows idle")
    func oldIdleArmsNothing() async throws {
        let now = Date()
        let session = try makeSession(pid: TestSupport.livePid, status: .idle, since: now.addingTimeInterval(-1), yourTurnFor: 0.5, now: now)
        #expect(SessionRow(session: session).status == .idle(since: session.stateSince))
        try await Task.sleep(for: .milliseconds(200))
        #expect(session.yourTurnExpiries == 0)
    }

    // MARK: Looks

    @Test("Blob style: every colour mode and shape mode builds a calm your-turn program")
    func blobPrograms() {
        let status = FaceStatus.yourTurn(since: Date())
        let key = "project-a"
        for colorMode in Theme.ColorMode.allCases {
            for shapeMode in [Theme.BlobShapeMode.status, .identity] {
                for projectKey in [nil, key] {
                    let identity = FaceIdentity(seed: "turn-\(colorMode.rawValue)")
                    let program = BlobProgramBuilder.program(
                        for: .status(status), identity: identity, shapeMode: shapeMode, colorMode: colorMode, projectKey: projectKey
                    )
                    #expect(program.halo == .yourTurn(color: program.color), "the halo takes the body colour in every mode")
                    #expect(program.grow == nil && program.restScale == 1 && !program.bounce && !program.burst && program.flashColor == nil)
                    #expect(program.bodyLoop == nil && program.scheduledBody == nil)
                    #expect(program.tracks.map(\.key) == ["loop.yourTurn"])
                    #expect(program.tracks[0].repeats)
                    #expect(program.tracks[0].samples.contains { $0.pose.lid < 1 }, "it blinks")
                    #expect(program.pose.yaw == Theme.blobNeedsInputYaw, "it looks at the person")
                    if shapeMode == .status { #expect(program.body == BlobBody(shape: Theme.blobIdleShape)) }
                    switch (colorMode, projectKey) {
                    case (.project, .some(let key)):
                        #expect(program.color == ProjectColor.color(for: key), "the project colour, undimmed")
                    case (.identity, _):
                        #expect(program.color == identity.blobColor)
                    default:
                        #expect(program.color == Theme.yourTurnColor)
                    }
                }
            }
        }
    }

    @Test("Dot-matrix style: the idle program in the your-turn colour at the normal glow")
    func dotMatrixPrograms() {
        let since = Date()
        let identity = FaceIdentity(seed: "dots")
        for colorMode in Theme.ColorMode.allCases {
            let program = FaceProgramBuilder.program(for: .status(.yourTurn(since: since)), identity: identity, colorMode: colorMode, projectKey: "project-a", now: since)
            let idle = FaceProgramBuilder.program(for: .status(.idle(since: since)), identity: identity, colorMode: colorMode, projectKey: "project-a", now: since)
            #expect(program.glow == Theme.glowOpacity)
            #expect(program.tracks == idle.tracks && program.wander)
        }
        #expect(FaceProgramBuilder.program(for: .status(.yourTurn(since: since)), identity: identity, colorMode: .status).color == Theme.yourTurnColor)
        #expect(FaceProgramBuilder.glow(for: .idle(since: since), colorMode: .status) < FaceProgramBuilder.glow(for: .yourTurn(since: since), colorMode: .status))
    }

    @Test("Both layer trees show your turn in every mode, from the done moment and on to idle")
    func layerTreesHandleYourTurn() {
        let since = Date()
        for style in FaceStyle.allCases {
            for colorMode in Theme.ColorMode.allCases {
                let root = CALayer()
                root.bounds = CGRect(x: 0, y: 0, width: Theme.faceSize, height: Theme.faceSize)
                var config = FaceConfiguration(identity: FaceIdentity(seed: "tree"), mode: .status(.justFinished), size: Theme.faceSize, filter: .none)
                config.colorMode = colorMode
                config.projectKey = "project-a"
                let apply: (FaceConfiguration) -> Void
                switch style {
                case .blob:
                    let tree = BlobLayerTree(root: root)
                    apply = { tree.apply($0) }
                case .dotMatrix:
                    let tree = EyeLayerTree(root: root)
                    apply = { tree.apply($0) }
                }
                apply(config)
                config.mode = .status(.yourTurn(since: since))
                apply(config)
                if style == .blob {
                    let haloHost = root.sublayers?.first?.sublayers?.first?.sublayers?.first
                    #expect(haloHost?.opacity == Float(Theme.yourTurnHaloOpacity), "the host carries the your-turn peak")
                }
                config.mode = .status(.idle(since: since))
                apply(config)
                if style == .blob {
                    let haloHost = root.sublayers?.first?.sublayers?.first?.sublayers?.first
                    #expect(haloHost?.opacity == 0, "idle has no halo")
                }
            }
        }
    }

    @Test("Only the done moment glides into your turn; the halo breath carries over")
    func glide() {
        var done = FaceConfiguration(identity: FaceIdentity(seed: "g"), mode: .status(.justFinished), size: Theme.faceSize, filter: .none)
        var turn = done
        turn.mode = .status(.yourTurn(since: Date()))
        #expect(BlobLayerTree.glides(from: done, to: turn))
        #expect(!BlobLayerTree.glides(from: turn, to: done))
        var idle = turn
        idle.mode = .status(.idle(since: Date()))
        #expect(!BlobLayerTree.glides(from: turn, to: idle), "your turn to idle blinks like any status change")
        done.colorMode = .identity
        #expect(!BlobLayerTree.glides(from: done, to: turn), "a look change at the same moment blinks")
        let yourTurn = BlobHalo.yourTurn(color: Theme.yourTurnColor)
        #expect(BlobLayerTree.sharesHaloLoop(.done, yourTurn) == (Theme.yourTurnHaloPulse == Theme.doneHaloPulse))
        #expect(BlobLayerTree.sharesHaloLoop(.done, .yourTurn(color: ProjectColor.color(for: "project-a"))) == (Theme.yourTurnHaloPulse == Theme.doneHaloPulse), "a project colour halo keeps the breath too")
        #expect(!BlobLayerTree.sharesHaloLoop(.attention(grow: Theme.attentionGrow), yourTurn))
        #expect(yourTurn.unit.opacity == 1 && yourTurn.unit.color == Theme.yourTurnColor)
    }

    @Test("Calmer than the done moment and than amber: halo, edge cue, colour")
    func belowAmber() {
        #expect(Theme.yourTurnHaloOpacity < Theme.doneHaloOpacity)
        #expect(Theme.yourTurnHaloOpacity < Theme.attentionHaloOpacity)
        #expect(Theme.yourTurnEdgeOpacity < Theme.attentionEdgeOpacity)
        #expect(BlobHalo.yourTurn(color: Theme.yourTurnColor).breath == Theme.yourTurnHaloPulse)
        #expect(Set([Theme.yourTurnColor, Theme.justFinishedColor, Theme.idleColor, Theme.needsInputColor]).count == 4)
        // Muted mint: between the flash and idle in green, never more saturated than the flash.
        #expect(Theme.yourTurnColor.green < Theme.justFinishedColor.green && Theme.yourTurnColor.green > Theme.idleColor.green)
        // Idle keeps the warm grey hue (red over green over blue) at a lower value.
        #expect(Theme.idleColor.red > Theme.idleColor.green && Theme.idleColor.green > Theme.idleColor.blue)
        #expect(Theme.idleColor.red < 0.7 && Theme.idleGlowOpacity < 0.45 && Theme.projectIdleDim > 0.45)
    }

    @Test("Edge cue: waiting rows amber, your-turn rows in their body colour, nothing else")
    func edgeCues() {
        let mint = Theme.yourTurnColor
        #expect(AttentionEdgeCue(status: .needsInput(kind: .permission), bodyColor: mint) == .waiting(.permission))
        #expect(AttentionEdgeCue(status: .yourTurn(since: since), bodyColor: mint) == .yourTurn(mint))
        for status: FaceStatus in [.working, .idle(since: since), .justFinished, .ended] {
            #expect(AttentionEdgeCue(status: status, bodyColor: mint) == nil)
        }
        #expect(AttentionEdgeCue.yourTurn(mint).halo.color == mint)
        #expect(AttentionEdgeCue.yourTurn(mint).halo.opacity == Theme.yourTurnEdgeOpacity)
        #expect(AttentionEdgeCue.waiting(.question).halo.color == Theme.needsInputColor)
        let loop = AttentionEdgeCue.yourTurn(mint).loop(phase: 0.25)
        #expect(loop.duration == Theme.yourTurnHaloPulse.period && loop.repeatCount == .infinity)
    }

    @Test("The edge cue and the halo of a your-turn row take its body colour in every mode and style; amber stays amber", arguments: Theme.ColorMode.allCases)
    func cueMatchesBody(colorMode: Theme.ColorMode) {
        let seed = "cue-seed"
        let key = "project-a"
        let turn = FaceStatus.yourTurn(since: since)
        for style in FaceStyle.allCases {
            let body = FaceLook.bodyColor(for: turn, seed: seed, projectKey: key, style: style, colorMode: colorMode)
            let expected: EyeColor = switch (style, colorMode) {
            case (_, .status): Theme.yourTurnColor
            case (_, .project): ProjectColor.color(for: key)
            case (.blob, .identity): FaceIdentity(seed: seed).blobColor
            case (.dotMatrix, .identity): FaceIdentity(seed: seed).color
            }
            #expect(body == expected, "\(style) \(colorMode)")
            #expect(AttentionEdgeCue(status: turn, bodyColor: body)?.halo.color == expected)
            let waiting = FaceStatus.needsInput(kind: .question)
            let amber = FaceLook.bodyColor(for: waiting, seed: seed, projectKey: key, style: style, colorMode: colorMode)
            #expect(AttentionEdgeCue(status: waiting, bodyColor: amber)?.halo.color == Theme.needsInputColor)
        }
        let program = BlobProgramBuilder.program(for: .status(turn), identity: FaceIdentity(seed: seed), colorMode: colorMode, projectKey: key)
        let body = FaceLook.bodyColor(for: turn, seed: seed, projectKey: key, style: .blob, colorMode: colorMode)
        #expect(program.color == body && program.halo?.color == body, "the halo is the body colour, the cue's colour")
    }

    @Test("Project colour mode: your turn keeps the project colour undimmed; it rests on the idle body")
    func projectAndReach() {
        let key = "project-a"
        let project = ProjectColor.color(for: key)
        #expect(ProjectColor.color(for: .yourTurn(since: since), projectKey: key) == project)
        #expect(BlobBody.forStatus(.yourTurn(since: since)) == BlobBody(shape: Theme.blobIdleShape))
        let reach = FaceReach.session(status: .yourTurn(since: since), seed: "r", hovered: false, style: .dotMatrix, shapeMode: .status)
        let idle = FaceReach.session(status: .idle(since: since), seed: "r", hovered: false, style: .dotMatrix, shapeMode: .status)
        #expect(reach == idle, "the dot-matrix disc does not swap or hop")
    }
}

/// A flag an observation callback can set from the main actor.
@MainActor
private final class ObservationFlag {
    var fired = false
}
