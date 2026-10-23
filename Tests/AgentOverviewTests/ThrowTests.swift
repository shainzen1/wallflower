import Foundation
import Testing
@testable import AgentOverview

/// Throwing a face out of the capsule: the axis of a press, the release rule, the hidden store and
/// the model's rows.
@Suite("Throw a face out")
@MainActor
struct ThrowTests {
    // MARK: Axis

    @Test func smallMovesStayAClick() {
        #expect(PressAxis.decide(dx: 0, dy: 0, canThrow: true) == .click)
        #expect(PressAxis.decide(dx: -10, dy: 4, canThrow: true) == .click, "both at their thresholds, neither passed")
        #expect(PressAxis.decide(dx: 30, dy: 2, canThrow: true) == .click, "rightward travel alone decides nothing")
    }

    @Test func verticalFirstIsAPanelDrag() {
        #expect(PressAxis.decide(dx: -3, dy: 5, canThrow: true) == .dragPanel)
        #expect(PressAxis.decide(dx: 0, dy: -4.5, canThrow: true) == .dragPanel)
        #expect(PressAxis.decide(dx: 25, dy: 6, canThrow: true) == .dragPanel)
    }

    @Test func leftwardFirstOnAFaceIsAThrow() {
        #expect(PressAxis.decide(dx: -10.5, dy: 0, canThrow: true) == .throwFace)
        #expect(PressAxis.decide(dx: -14, dy: 3, canThrow: true) == .throwFace)
    }

    @Test func leftwardWithoutAFaceStaysAClickUntilItTurnsVertical() {
        #expect(PressAxis.decide(dx: -40, dy: 0, canThrow: false) == .click)
        #expect(PressAxis.decide(dx: -40, dy: 5, canThrow: false) == .dragPanel)
    }

    @Test func bothPastInOneEventTheLargerTravelWins() {
        #expect(PressAxis.decide(dx: -20, dy: 8, canThrow: true) == .throwFace)
        #expect(PressAxis.decide(dx: -12, dy: 15, canThrow: true) == .dragPanel)
        #expect(PressAxis.decide(dx: -12, dy: -12, canThrow: true) == .throwFace, "a tie goes to the throw")
    }

    // MARK: Velocity and pose

    @Test func velocityIsMeasuredOverTheRecentWindowOnly() {
        var velocity = ThrowVelocity(window: 0.08)
        velocity.add(CGPoint(x: 0, y: 0), at: 1.0)
        velocity.add(CGPoint(x: -500, y: 0), at: 1.5)
        #expect(velocity.velocity == .zero, "the old sample left the window: the pointer rested")
        velocity.add(CGPoint(x: -530, y: 6), at: 1.55)
        #expect(abs(velocity.velocity.dx - -600) < 0.001)
        #expect(abs(velocity.velocity.dy - 120) < 0.001)
        velocity.add(CGPoint(x: -530, y: 6), at: 1.57)
        #expect(abs(velocity.velocity.dx - -600) < 0.001, "a release right after the move keeps its speed")
        velocity.add(CGPoint(x: -530, y: 6), at: 1.7)
        #expect(velocity.velocity == .zero, "a pointer that rested measures zero")
    }

    @Test func heldFaceFollowsOneToOneHorizontallyAndDampedVertically() {
        var faceThrow = FaceThrow(key: 1, start: CGPoint(x: 1000, y: 500), at: 0)
        faceThrow.moved(to: CGPoint(x: 960, y: 480), at: 0.05)
        let pose = faceThrow.heldPose(reduceMotion: false)
        #expect(pose.dx == -40)
        #expect(abs(pose.dy - 20 * Theme.throwVerticalFollow) < 0.0001, "20 pt down on screen, damped")
        #expect(pose.motion == .immediate)
        #expect(pose.angle > 0, "moving left tilts the top to the left")
        #expect(pose.angle <= Theme.throwTilt * .pi / 180 + 0.0001)
        #expect(faceThrow.heldPose(reduceMotion: true).angle == 0, "no tilt under Reduce Motion")
    }

    @Test func tiltIsCappedAtTheTheme() {
        let cap = Theme.throwTilt * .pi / 180
        #expect(abs(FaceThrow.tilt(velocityX: -5000) - cap) < 0.0001)
        #expect(abs(FaceThrow.tilt(velocityX: 5000) + cap) < 0.0001)
        #expect(FaceThrow.tilt(velocityX: 0) == 0)
    }

    // MARK: Release

    @Test func releaseDecisionByDistanceAndVelocity() {
        #expect(!FaceThrow.removes(faceCenterX: -70, velocityX: 0), "at the distance is not beyond it")
        #expect(FaceThrow.removes(faceCenterX: -71, velocityX: 0))
        #expect(!FaceThrow.removes(faceCenterX: 10, velocityX: -600))
        #expect(FaceThrow.removes(faceCenterX: 10, velocityX: -601))
        #expect(!FaceThrow.removes(faceCenterX: 10, velocityX: 2000), "fast to the right never throws")
    }

    @Test func slowReleaseShortOfTheDistanceSpringsBack() {
        var faceThrow = FaceThrow(key: 1, start: CGPoint(x: 1000, y: 500), at: 0)
        faceThrow.moved(to: CGPoint(x: 960, y: 500), at: 0.3)
        faceThrow.moved(to: CGPoint(x: 960, y: 500), at: 0.6)
        let release = faceThrow.release(reduceMotion: false)
        #expect(!release.removes)
        #expect(release.pose.isRest)
        #expect(release.pose.motion == .springBack)
        #expect(faceThrow.release(reduceMotion: true).pose.motion == .easeBack)
    }

    @Test func releaseBeyondTheDistanceFliesOnShrinkingAndFading() {
        var faceThrow = FaceThrow(key: 1, start: CGPoint(x: 1000, y: 500), at: 0)
        let travel = Theme.capsuleWidth / 2 + Theme.throwDistance + 10
        faceThrow.moved(to: CGPoint(x: 1000 - travel, y: 500), at: 0.5)
        faceThrow.moved(to: CGPoint(x: 1000 - travel, y: 500), at: 1.0)
        let release = faceThrow.release(reduceMotion: false)
        #expect(release.removes)
        #expect(release.pose.opacity == 0)
        #expect(release.pose.scale == Theme.throwFlyScale)
        #expect(abs(release.pose.dx - (-travel - Theme.throwFlyDistance)) < 0.001, "resting: it flies on to the left")
        #expect(release.pose.motion == .flyAway)

        let plain = faceThrow.release(reduceMotion: true)
        #expect(plain.removes)
        #expect(plain.pose.dx == -travel && plain.pose.scale == 1 && plain.pose.opacity == 0, "Reduce Motion: a plain fade in place")
    }

    @Test func fastFlickIsThrownOutAndFliesInItsDirection() {
        var faceThrow = FaceThrow(key: 1, start: CGPoint(x: 1000, y: 500), at: 0)
        faceThrow.moved(to: CGPoint(x: 985, y: 500), at: 0.02)
        faceThrow.moved(to: CGPoint(x: 970, y: 490), at: 0.04)
        let release = faceThrow.release(reduceMotion: false)
        #expect(release.removes, "750 pt/s to the left")
        #expect(release.pose.dx < -30 - Theme.throwFlyDistance * 0.9)
        #expect(release.pose.dy > 3, "moving down a little, it flies a little down")
    }

    // MARK: Hidden store

    private func makeDefaults() -> UserDefaults {
        let name = "ThrowTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func hiddenStoreRoundTrip() {
        let defaults = makeDefaults()
        let started = Date(timeIntervalSince1970: 1_791_879_441.228)
        let hidden = HiddenSessions(defaults: defaults)
        #expect(hidden.count == 0)
        hidden.hide(key: 4242, startedAt: started)
        hidden.hide(key: 77, startedAt: nil)
        hidden.hide(key: 4242, startedAt: started)
        #expect(hidden.count == 2, "hiding twice keeps one entry")

        let reloaded = HiddenSessions(defaults: defaults)
        #expect(reloaded.entries == [.init(key: 4242, startedAt: 1_791_879_441_228), .init(key: 77, startedAt: nil)])
        #expect(reloaded.contains(key: 4242, startedAt: started))
        #expect(!reloaded.contains(key: 4242, startedAt: started.addingTimeInterval(60)), "a reused pid is another session")
        #expect(reloaded.contains(key: 77, startedAt: .now), "no start: any session with the pid")

        let raw = defaults.array(forKey: HiddenSessions.key) as? [[String: Int]]
        #expect(raw == [["pid": 4242, "startedAt": 1_791_879_441_228], ["pid": 77]])

        reloaded.clear()
        #expect(HiddenSessions(defaults: defaults).count == 0)
    }

    @Test func hiddenStoreSkipsMalformedEntries() {
        let defaults = makeDefaults()
        defaults.set([["pid": 5], ["name": "x"], "junk", ["pid": 6, "startedAt": 9]], forKey: HiddenSessions.key)
        #expect(HiddenSessions(defaults: defaults).entries == [.init(key: 5, startedAt: nil), .init(key: 6, startedAt: 9)])
    }

    @Test func pruneDropsSessionsThatLeftOrWhosePidWasReused() {
        let defaults = makeDefaults()
        let started = Date(timeIntervalSince1970: 1_700_000_000)
        let hidden = HiddenSessions(defaults: defaults)
        hidden.hide(key: 1, startedAt: started)
        hidden.hide(key: 2, startedAt: started)
        hidden.hide(key: 3, startedAt: started)
        hidden.prune(keeping: [(key: 1, startedAt: started), (key: 3, startedAt: started.addingTimeInterval(5))])
        #expect(hidden.entries == [.init(key: 1, startedAt: 1_700_000_000_000)])
        #expect(HiddenSessions(defaults: defaults).count == 1, "the pruned list is saved")
    }

    // MARK: Model

    /// A store with two live desktop sessions (synthetic fixtures: this process and its parent).
    private func makeModel(hidden: HiddenSessions) throws -> (SessionStore, PanelModel, [SessionKey]) {
        let store = SessionStore(folder: URL(filePath: "/nonexistent"), entrypoints: nil)
        var first = try TestSupport.fixtureRecord("idle-desktop")
        first.pid = TestSupport.livePid
        var second = try TestSupport.fixtureRecord("busy-desktop")
        second.pid = getppid()
        store.reconcile(RegistryScanResult(records: [first, second], presentPids: [first.pid, second.pid]))
        let model = PanelModel(store: store, hiddenSessions: hidden)
        model.throwFlyDuration = 0
        model.reduceMotion = { false }
        return (store, model, store.sessions.map(\.key))
    }

    @Test func rowsSkipHiddenSessionsAndTheCapsuleFollows() throws {
        let hidden = HiddenSessions(defaults: makeDefaults())
        let (store, model, pids) = try makeModel(hidden: hidden)
        defer { store.stop() }
        #expect(model.rows.count == 2)
        let tall = model.capsuleHeight

        let session = try #require(store.sessions.first { $0.key == pids[0] })
        hidden.hide(session)
        #expect(model.rows.map(\.key) == [pids[1]])
        #expect(model.capsuleHeight == Theme.capsuleHeight(rows: 1, actions: 0))
        #expect(model.capsuleHeight < tall)
        #expect(model.hiddenCount == 1)

        model.showHiddenSessions()
        #expect(model.rows.count == 2)
        #expect(model.hiddenCount == 0)
    }

    @Test func modelPrunesHiddenSessionsThatLeftTheRegistry() throws {
        let hidden = HiddenSessions(defaults: makeDefaults())
        hidden.hide(key: .claude(TestSupport.deadPid), startedAt: nil)
        let (store, model, pids) = try makeModel(hidden: hidden)
        defer { store.stop() }
        let session = try #require(store.sessions.first { $0.key == pids[1] })
        hidden.hide(session)
        model.pruneHiddenSessions()
        #expect(hidden.entries.map(\.key) == [pids[1]], "the session no longer in the registry is pruned, the live one stays")
    }

    @Test func switchingTheSourceKeepsTheOtherSourcesHiddenSessions() throws {
        let folder = try TestSupport.makeTempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let desktopPid = TestSupport.livePid
        let terminalPid = getppid()
        try TestSupport.writeFixture("idle-desktop", to: folder, pid: desktopPid)
        try TestSupport.writeFixture("idle-cli", to: folder, pid: terminalPid)
        let hidden = HiddenSessions(defaults: makeDefaults())
        var stores: [SessionStore] = []
        defer { stores.forEach { $0.stop() } }
        /// A model on a scanned store of `source`, as `AppDelegate` builds one after a source switch.
        func model(for source: SessionSource) -> PanelModel {
            let store = SessionStore(folder: folder, entrypoints: source.entrypoints, projectsFolder: folder)
            stores.append(store)
            store.reconcile(SessionRegistryScanner.scan(folder: folder, entrypoints: source.entrypoints))
            return PanelModel(store: store, hiddenSessions: hidden)
        }

        let terminal = model(for: .terminal)
        terminal.hideSession(key: .claude(terminalPid))
        #expect(terminal.rows.isEmpty && hidden.count == 1)

        let desktop = model(for: .desktop)
        desktop.pruneHiddenSessions()
        #expect(desktop.rows.map(\.pid) == [desktopPid])
        #expect(hidden.entries.map(\.key) == [.claude(terminalPid)], "a live session of the source not shown stays hidden")

        #expect(model(for: .terminal).rows.isEmpty, "back on the terminal source, it is still hidden")

        try FileManager.default.removeItem(at: folder.appending(path: "\(terminalPid).json"))
        desktop.store.reconcile(SessionRegistryScanner.scan(folder: folder, entrypoints: SessionSource.desktop.entrypoints))
        desktop.pruneHiddenSessions()
        #expect(hidden.count == 0, "once it left the registry, it is pruned from either source")
    }

    @Test func throwTargetIsASessionFaceOnTheCapsuleOnly() throws {
        let hidden = HiddenSessions(defaults: makeDefaults())
        let (store, model, pids) = try makeModel(hidden: hidden)
        defer { store.stop() }
        let size = CGSize(width: Theme.contentWidth + Theme.windowPadding, height: model.capsuleHeight)
        let x = size.width - Theme.capsuleWidth / 2
        #expect(model.throwTarget(atViewPoint: CGPoint(x: x, y: PanelModel.rowCenterY(index: 1)), in: size) == pids[1])
        #expect(model.throwTarget(atViewPoint: CGPoint(x: size.width - Theme.capsuleWidth - 20, y: PanelModel.rowCenterY(index: 0)), in: size) == nil, "the bulge")
        let noStore = PanelModel(store: store)
        #expect(noStore.throwTarget(atViewPoint: CGPoint(x: x, y: PanelModel.rowCenterY(index: 0)), in: size) == nil)
    }

    @Test func throwOutHidesTheSessionAfterTheFlyAndOpensNothing() async throws {
        let hidden = HiddenSessions(defaults: makeDefaults())
        let (store, model, pids) = try makeModel(hidden: hidden)
        defer { store.stop() }
        var opened = 0
        model.open = { _ in opened += 1 }
        let row = try #require(model.rows.first)
        let pid = pids[0]

        model.pressBegan()
        model.throwBegan(key: pid)
        #expect(model.throwingKey == pid)
        #expect(model.isExpanded && !model.isBulgeOpen, "the window stays expanded, the bulge closes")
        #expect(!model.isRowExpanded(pid))
        #expect(model.isLifted(pid))

        var faceThrow = FaceThrow(key: pid, start: CGPoint(x: 1000, y: 500), at: 0)
        faceThrow.moved(to: CGPoint(x: 880, y: 500), at: 0.3)
        model.throwMoved(faceThrow)
        #expect(model.throwPose(for: pid).dx == -120)
        #expect(model.throwPose(for: pids[1]) == .rest, "only the held face moves")
        faceThrow.moved(to: CGPoint(x: 880, y: 500), at: 0.8)
        #expect(model.throwEnded(faceThrow))
        model.tapped(row)
        #expect(opened == 0, "the release of a throw opens nothing")
        #expect(model.throwPose(for: pid).opacity == 0, "flying away")

        // The fly task hides the session on the main actor; under a parallel test run that turn can
        // come late, so wait for it instead of a fixed 50 ms.
        #expect(await TestSupport.waitUntil(timeout: 2) { hidden.count == 1 })
        #expect(model.rows.map(\.key) == [pids[1]])
        #expect(hidden.count == 1)
        #expect(model.throwPose(for: pid).opacity == 0, "the departing face stays gone")

        model.showHiddenSessions()
        #expect(model.rows.count == 2)
        #expect(model.throwPose(for: pid) == .rest, "back in the capsule at rest")
    }

    @Test func throwShortOfTheDistanceSpringsBackAndKeepsTheRow() throws {
        let hidden = HiddenSessions(defaults: makeDefaults())
        let (store, model, pids) = try makeModel(hidden: hidden)
        defer { store.stop() }
        let pid = pids[1]
        model.pressBegan()
        model.throwBegan(key: pid)
        var faceThrow = FaceThrow(key: pid, start: CGPoint(x: 1000, y: 500), at: 0)
        faceThrow.moved(to: CGPoint(x: 970, y: 500), at: 0.4)
        faceThrow.moved(to: CGPoint(x: 970, y: 500), at: 0.9)
        model.throwMoved(faceThrow)
        #expect(!model.throwEnded(faceThrow))
        #expect(model.throwingKey == nil)
        #expect(model.throwPose(for: pid) == .rest)
        #expect(model.rows.count == 2)
        #expect(hidden.count == 0)
    }

    @Test func pointerReportsAreFrozenWhileThrowing() throws {
        let hidden = HiddenSessions(defaults: makeDefaults())
        let (store, model, pids) = try makeModel(hidden: hidden)
        defer { store.stop() }
        let size = CGSize(width: Theme.contentWidth + Theme.windowPadding, height: model.capsuleHeight)
        model.pointerMoved(to: CGPoint(x: size.width - Theme.capsuleWidth / 2, y: PanelModel.rowCenterY(index: 0)), in: size)
        model.throwBegan(key: pids[0])
        model.pointerMoved(to: nil, in: size)
        #expect(model.hoveredRowIndex == 0)
        #expect(model.isExpanded)
    }
}
