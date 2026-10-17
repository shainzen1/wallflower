import CoreGraphics
import Foundation
import Testing
@testable import AgentOverview

@Suite("Working substates")
struct WorkingSubstateTests {
    private let identity = FaceIdentity(seed: "substates")

    private func working(_ activity: SessionActivity) -> BlobProgram {
        BlobProgramBuilder.program(for: .status(.working), identity: identity, activity: activity)
    }

    @Test("Every activity yields its own working track: distinct keys and distinct keyframes")
    func distinctTracks() {
        let programs = SessionActivity.allCases.map { ($0, working($0)) }
        for (activity, program) in programs {
            #expect(program.tracks.count == 1, "\(activity)")
            #expect(program.tracks[0].repeats, "\(activity) loops")
            #expect(program.bodyLoop == Theme.blobWorkingBreath, "\(activity) keeps the breath")
            #expect(program.body == BlobBody(shape: Theme.blobWorkingShape) && program.color == Theme.workingColor, "\(activity) stays on the cyan cloud")
            #expect(program.tracks[0].samples.first?.pose == program.pose, "\(activity): the loop starts at the rest pose")
            #expect(program.tracks[0].samples.contains { $0.pose.lid <= Theme.blobClosedLid + 0.000_001 }, "\(activity) blinks")
        }
        let keys = Set(programs.map { $0.1.tracks[0].key })
        #expect(keys.count == SessionActivity.allCases.count, "one key per activity: \(keys)")
        for (a, pa) in programs {
            for (b, pb) in programs where a != b {
                #expect(pa.tracks[0].samples.map(\.pose) != pb.tracks[0].samples.map(\.pose), "\(a) and \(b) share keyframes")
            }
        }
        #expect(working(.thinking).tracks[0].key == "loop.drift", "thinking is the existing working loop")
    }

    @Test("Coding narrows the eyes and steps left to right; running sits down-left and pulses; reading sweeps two lines; delegating looks up")
    func substateCharacter() {
        let focused = BlobProgramBuilder.resolved(.focused, identity)

        let coding = working(.coding)
        #expect(coding.pose.left.height < focused.left.height, "narrowed")
        let codingYaws = coding.tracks[0].samples.map(\.pose.yaw)
        #expect(codingYaws.min()! <= focused.yaw + Theme.blobCodingYawRange.lowerBound + 0.01)
        #expect(codingYaws.max()! >= focused.yaw + Theme.blobCodingYawRange.upperBound - 0.01)
        let tempo = identity.hash.value(in: Theme.blobActivityTempo, slot: 60)
        let line = coding.tracks[0].samples.filter { $0.time <= Theme.blobCodingLineDuration * tempo - 0.001 }
        #expect(zip(line, line.dropFirst()).allSatisfy { $0.pose.yaw <= $1.pose.yaw + 0.000_001 }, "the line is read left to right")

        let running = working(.running)
        #expect(running.pose.yaw < focused.yaw && running.pose.pitch < focused.pitch, "down-left")
        #expect(running.eyePulse == Theme.blobRunningEyePulse)
        #expect(running.tracks[0].samples.contains { abs($0.pose.yaw - focused.yaw) < 0.5 }, "glances back to centre once per loop")
        for activity in SessionActivity.allCases where activity != .running {
            #expect(working(activity).eyePulse == nil, "\(activity) has no cursor pulse")
        }

        let reading = working(.reading)
        let pitches = reading.tracks[0].samples.map(\.pose.pitch)
        #expect(abs(reading.tracks[0].duration - Theme.blobReadingPeriod * identity.hash.value(in: Theme.blobActivityTempo, slot: 60)) < 0.002)
        #expect(pitches.max()! - pitches.min()! >= (Theme.blobReadingLinePitch.upperBound - Theme.blobReadingLinePitch.lowerBound) - 0.01, "two lines")
        let yaws = reading.tracks[0].samples.map(\.pose.yaw)
        let rises = zip(yaws, yaws.dropFirst()).filter { $1 > $0 + 0.5 }.count
        let falls = zip(yaws, yaws.dropFirst()).filter { $1 < $0 - 0.5 }.count
        #expect(rises > falls * 2, "sweeps are slow, returns are quick")

        let delegating = working(.delegating)
        #expect(delegating.pose.pitch > focused.pitch && delegating.pose.split > focused.split, "up and apart")
        let blinkSamples = delegating.tracks[0].samples.filter { $0.pose.lid < 1 }
        let blinkSpan = (blinkSamples.last?.time ?? 0) - (blinkSamples.first?.time ?? 0)
        #expect(blinkSpan > (Theme.blobBlinkClose + Theme.blobBlinkHold + Theme.blobBlinkOpen) * 1.5, "a slow blink")
    }

    @Test("Expression mode and the other statuses ignore the activity")
    func activityOnlyWhileWorking() {
        for status: FaceStatus in [.needsInput(kind: .question), .idle(since: Date()), .ended] {
            let a = BlobProgramBuilder.program(for: .status(status), identity: identity, activity: .coding, now: Date(timeIntervalSince1970: 0))
            let b = BlobProgramBuilder.program(for: .status(status), identity: identity, activity: .reading, now: Date(timeIntervalSince1970: 0))
            #expect(a.pose == b.pose && a.tracks.map(\.key) == b.tracks.map(\.key))
        }
        let config = FaceConfiguration(identity: identity, mode: .status(.working), size: 44, filter: .none, satellites: 3)
        #expect(BlobLayerTree.satelliteCount(for: config) == 3)
        var idle = config
        idle.mode = .status(.idle(since: Date()))
        #expect(BlobLayerTree.satelliteCount(for: idle) == 0, "satellites only while working")
    }
}

@Suite("Subagent satellites")
struct SatelliteTests {
    @Test("Count caps at the maximum; phases are evenly spaced; newcomers fill the largest gap")
    func countAndPhases() {
        #expect((0...4).map { BlobSatelliteLayout.count(for: $0) } == [0, 1, 2, 3, 4])
        #expect(BlobSatelliteLayout.count(for: 6) == Theme.satelliteMax)
        #expect(BlobSatelliteLayout.count(for: -2) == 0)
        for count in 0...Theme.satelliteMax {
            let phases = BlobSatelliteLayout.phases(count: count)
            #expect(phases.count == count)
            for (index, phase) in phases.enumerated() {
                #expect(abs(phase - Double(index) / Double(count)) < 0.000_001, "\(count) satellites")
            }
        }
        #expect(BlobSatelliteLayout.nextPhase(existing: []) == 0)
        #expect(abs(BlobSatelliteLayout.nextPhase(existing: [0]) - 0.5) < 0.000_001)
        #expect(abs(BlobSatelliteLayout.nextPhase(existing: [0, 0.5]) - 0.25) < 0.000_001)
        #expect(abs(BlobSatelliteLayout.nextPhase(existing: [0, 0.5, 0.25]) - 0.75) < 0.000_001)
        #expect(abs(BlobSatelliteLayout.nextPhase(existing: [0.9, 0.1]) - 0.5) < 0.000_001, "the gap across 0 counts")
    }

    @Test("Positions lie on the orbit ellipse, inside the row cell plus the capsule's black, for 0 to 4 and the cap at 6")
    func positionsOnTheEllipseAndInBounds() {
        let size = Theme.faceSize
        let radii = BlobSatelliteLayout.radii(size: size)
        let half = BlobSatelliteLayout.diameter(size: size) / 2
        let sideRoom = (Theme.capsuleWidth - size) / 2
        let rowRoom = (Theme.rowPitch - size) / 2
        for subagents in [0, 1, 2, 3, 4, 6] {
            let count = BlobSatelliteLayout.count(for: subagents)
            for phase in BlobSatelliteLayout.phases(count: count) {
                let p = BlobSatelliteLayout.position(phase: phase, size: size)
                let dx = (p.x - size / 2) / radii.x
                let dy = (p.y - size / 2) / radii.y
                #expect(abs(dx * dx + dy * dy - 1) < 0.000_001, "on the ellipse")
                #expect(p.x - half >= -sideRoom && p.x + half <= size + sideRoom, "inside the capsule's width: \(p)")
                #expect(p.y - half >= -rowRoom && p.y + half <= size + rowRoom, "inside the row pitch band: \(p)")
            }
        }
        let extent = BlobSatelliteLayout.extent(size: size)
        #expect(extent.x <= size / 2 + sideRoom && extent.y <= size / 2 + rowRoom)
        #expect(radii.x - half >= Theme.blobRadius * size * 0.95, "the orbit clears the round body")
        let box = BlobSatelliteLayout.orbitPath(size: size).boundingBoxOfPath
        #expect(abs(box.width - 2 * radii.x) < 0.01 && abs(box.height - 2 * radii.y) < 0.01, "the orbit path is the ellipse")
        let start = BlobSatelliteLayout.position(phase: 0, size: size)
        #expect(abs(start.x - (size / 2 + radii.x)) < 0.000_001 && abs(start.y - size / 2) < 0.000_001, "phase 0 is the right end")
        #expect(BlobSatelliteLayout.bodyPath(size: size).boundingBoxOfPath.width == BlobSatelliteLayout.diameter(size: size))
        #expect(BlobSatelliteLayout.eyesPath(size: size).boundingBoxOfPath.width < BlobSatelliteLayout.diameter(size: size))
    }
}

@Suite("Project dots, labels and the hop")
struct ProjectAndLabelTests {
    private let since = Date(timeIntervalSince1970: 1_700_000_000)

    @Test("Project colour is stable per key, comes from the palette, and a few hundred keys cover every colour")
    func projectColours() {
        let count = Theme.projectPalette.count
        #expect(ProjectColor.color(for: "web-app") == ProjectColor.color(for: "web-app"))
        #expect(Theme.projectPalette.contains(ProjectColor.color(for: "agent-overview")))
        #expect(count >= 10 && count <= 12 && Set(Theme.projectPalette.map(\.name)).count == count)
        #expect(!Theme.projectPalette.contains(Theme.needsInputColor))
        var seen: Set<EyeColor> = []
        var tries = 0
        while seen.count < count, tries < 400 {
            seen.insert(ProjectColor.color(for: "repo-\(tries)"))
            tries += 1
        }
        #expect(seen.count == count, "every colour reachable within \(tries) keys")
        #expect(SessionRow.projectKey(cwd: "/Users/demo/Developer/web-app") == "web-app")
        #expect(SessionRow.projectKey(cwd: "/Users/demo/Developer/web-app/") == "web-app")
        #expect(SessionRow.projectKey(cwd: "") == "")
    }

    @Test("Label composition: activity only while working; the branch is its own line")
    @MainActor func labels() {
        #expect(SessionRow.label(for: .working, activity: .coding) == "Working · Coding")
        #expect(SessionRow.label(for: .working, activity: .thinking) == "Working · Thinking")
        #expect(SessionRow.label(for: .working) == "Working")
        #expect(SessionRow.label(for: .needsInput(kind: .question), activity: .coding) == "Needs input")
        #expect(SessionRow.label(for: .idle(since: since), activity: .reading) == "Idle")
        let row = SessionRow(pid: 1, name: "A", status: .working, stateSince: since, hostSessionId: nil, ended: false, activity: .coding, gitBranch: "main")
        #expect(StateDurationText.text(label: row.label, since: since, now: since.addingTimeInterval(2 * 60)) == "Working · Coding · 2m")
        #expect(BulgeContentView.branchText("main") == "⎇ main")
        let plain = SessionRow(pid: 1, name: "A", status: .working, stateSince: since, hostSessionId: nil, ended: false)
        #expect(plain.label == "Working · Thinking" && plain.gitBranch == nil && plain.subagentCount == 0)
        #expect(row.demo().subagentCount == RowDemo.subagentCount && row.demo().activity == RowDemo.activity && row.demo().status == .working)
        let second = row.demo(activity: RowDemo.secondActivity, subagentCount: RowDemo.secondSubagentCount)
        #expect(second.activity == .coding && second.subagentCount == 0 && second.gitBranch == "main")
    }

    @Test("Hop token: never for a session already waiting when first seen, once per entry into needs input")
    func hopTokenRule() {
        var tracker = AttentionTracker()
        /// Feeds the statuses in order and returns which of them bumped the token.
        func bumps(pid: SessionKey, _ statuses: [FaceStatus]) -> [Bool] {
            statuses.map { tracker.observe(key: pid, status: $0) }
        }
        #expect(bumps(pid: 1, [.needsInput(kind: .question), .needsInput(kind: .question)]) == [false, false], "already waiting at launch, still waiting")
        #expect(tracker.token(for: 1) == 0)
        #expect(bumps(pid: 1, [.working, .needsInput(kind: .question), .needsInput(kind: .permission)]) == [false, true, false], "entered needs input once; a change of kind is no new entry")
        #expect(tracker.token(for: 1) == 1)
        #expect(bumps(pid: 1, [.idle(since: since), .idle(since: since.addingTimeInterval(5)), .needsInput(kind: .other)]) == [false, false, true])
        #expect(tracker.token(for: 1) == 2)
        #expect(bumps(pid: 2, [.working, .needsInput(kind: .permission)]) == [false, true], "a new session starting busy")
        #expect(tracker.token(for: 2) == 1 && tracker.token(for: 1) == 2, "tokens are per session")
        tracker.keep(keys: [2])
        #expect(tracker.token(for: 1) == 0 && tracker.token(for: 2) == 1)
    }

    @Test("The panel model bumps a row's token on entry into needs input and prunes gone sessions")
    @MainActor
    func panelModelTokens() {
        let store = SessionStore(folder: URL(filePath: "/nonexistent"), entrypoints: nil)
        defer { store.stop() }
        let model = PanelModel(store: store)
        model.noteStatus(key: 7, status: .needsInput(kind: .question))
        #expect(model.attentionToken(for: 7) == 0, "waiting at launch never hops")
        model.noteStatus(key: 7, status: .working)
        model.noteStatus(key: 7, status: .needsInput(kind: .question))
        #expect(model.attentionToken(for: 7) == 1)
        model.noteStatus(key: 7, status: .needsInput(kind: .question))
        #expect(model.attentionToken(for: 7) == 1)
        model.rowCountDidChange(0)
        #expect(model.attentionToken(for: 7) == 0, "a session that left is forgotten")
    }

    @Test("Playground arguments pick the activity and satellites; the demo row is off by default")
    @MainActor
    func playgroundArguments() {
        let model = PlaygroundModel(arguments: ["app", "--activity", "reading", "--satellites", "9"])
        #expect(model.activity == .reading && model.satellites == Theme.satelliteMax)
        let plain = PlaygroundModel(arguments: ["app"])
        #expect(plain.activity == .thinking && plain.satellites == 0)
        #expect(RowDemo.enabled == CommandLine.arguments.contains("--demo-states"))
    }
}
