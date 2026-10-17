import CoreGraphics
import Foundation
import Testing
@testable import AgentOverview

@Suite("Attention: labels, kinds, halo, burst, edge cue and the genie")
struct AttentionTests {
    private let identity = FaceIdentity(seed: "attention")
    private let since = Date(timeIntervalSince1970: 1_700_000_000)

    @Test("The label says what a waiting session waits for; both kinds stay amber")
    func labelsPerWaitingKind() {
        #expect(SessionRow.label(for: .needsInput(kind: .question)) == "Needs input")
        #expect(SessionRow.label(for: .needsInput(kind: .permission)) == "Needs permission")
        #expect(SessionRow.label(for: .needsInput(kind: .other)) == "Needs you")
        #expect(SessionRow.label(for: .needsInput(kind: .permission), activity: .coding) == "Needs permission")
        let row = SessionRow(pid: 1, name: "A", status: .needsInput(kind: .permission), stateSince: since, hostSessionId: nil, ended: false)
        #expect(row.label == "Needs permission" && row.status.isNeedsInput && row.status.waitingKind == .permission)
        #expect(FaceStatus.working.waitingKind == nil && !FaceStatus.working.isNeedsInput)
        for kind in [WaitingKind.question, .permission, .other] {
            #expect(BlobProgramBuilder.program(for: .status(.needsInput(kind: kind)), identity: identity).color == Theme.needsInputColor)
        }
    }

    @Test("Permission pulses faster and grows every 2 s; question keeps the 3 s grow; both carry the amber halo and the rest scale")
    func permissionTempo() {
        let question = BlobProgramBuilder.program(for: .status(.needsInput(kind: .question)), identity: identity)
        let permission = BlobProgramBuilder.program(for: .status(.needsInput(kind: .permission)), identity: identity)
        #expect(question.bodyLoop == Theme.blobNeedsInputPulse && question.grow == Theme.attentionGrow)
        #expect(permission.bodyLoop?.period == Theme.permissionPulsePeriod && permission.grow?.interval == Theme.permissionGrowInterval)
        #expect(permission.bodyLoop!.period < question.bodyLoop!.period && permission.grow!.interval < question.grow!.interval)
        for program in [question, permission] {
            #expect(program.halo?.color == Theme.needsInputColor && program.halo?.grow == program.grow && program.restScale == Theme.attentionScale)
            #expect(program.halo?.opacity == Theme.attentionHaloOpacity)
        }
        #expect(DataTuning.justFinishedDuration == Theme.doneHold, "the data hold and the UI hold agree")
    }

    @Test("Just finished bursts, bounces and holds a mint halo; idle and working have no halo and the plain rest scale")
    func doneMoment() {
        let finished = BlobProgramBuilder.program(for: .status(.justFinished), identity: identity, colorMode: .status)
        #expect(finished.burst && finished.bounce && finished.flashColor == Theme.justFinishedColor)
        #expect(finished.halo == .done && finished.halo?.color == Theme.justFinishedColor && finished.halo?.breath == Theme.doneHaloPulse)
        for status: FaceStatus in [.working, .idle(since: since), .ended] {
            let program = BlobProgramBuilder.program(for: .status(status), identity: identity)
            #expect(program.halo == nil && program.restScale == 1 && !program.burst, "\(status)")
        }
        let identityMode = BlobProgramBuilder.program(for: .status(.justFinished), identity: identity, colorMode: .identity)
        #expect(identityMode.halo == nil, "no mint flash, no mint halo")
    }

    @Test("The burst is six dots on evenly spaced rays from inside the rim to 0.7 of the face")
    func burstGeometry() {
        let size: CGFloat = 44
        let rays = BlobBurst.rays(size: size)
        #expect(rays.count == Theme.doneBurstCount && Theme.doneBurstCount == 6)
        for ray in rays {
            #expect(abs(hypot(ray.end.x, ray.end.y) - size * Theme.doneBurstDistance) < 0.001)
            #expect(abs(hypot(ray.start.x, ray.start.y) - size * Theme.doneBurstStart) < 0.001)
            #expect(hypot(ray.start.x, ray.start.y) < Theme.blobRadius * size, "starts behind the body")
        }
        let angles = rays.map { atan2($0.end.y, $0.end.x) }.sorted()
        for (a, b) in zip(angles, angles.dropFirst()) {
            #expect(abs((b - a) - 2 * .pi / Double(rays.count)) < 0.001, "evenly spaced")
        }
        #expect(abs(BlobBurst.dotPath(size: size).boundingBoxOfPath.width - size * Theme.doneBurstDotSize) < 0.001)
    }

    @Test("The genie stretch is asymmetric (left grows, right does not), keeps the element count, and tapers")
    func genieStretch() {
        let profile = Theme.blobIdleShape.profile
        let stretched = BlobGenie.stretched(profile)
        let n = BlobProfile.sampleCount
        #expect(stretched.radii.count == n)
        let left = n / 2
        #expect(abs(stretched.radii[left] / profile.radii[left] - (1 + Theme.genieStretch)) < 0.000_001, "full stretch at the leftmost point")
        #expect(stretched.radii[0] == profile.radii[0], "nothing on the right")
        #expect(stretched.radii[n / 4] == profile.radii[n / 4] && stretched.radii[3 * n / 4] == profile.radii[3 * n / 4], "nothing at the top and bottom")
        #expect(BlobGenie.weight(at: .pi) == 1 && BlobGenie.weight(at: 0) == 0 && BlobGenie.weight(at: .pi / 2) == 0)
        #expect(BlobGenie.weight(at: 3 * .pi / 4) < 0.7, "less than the plain smoothstep (0.79) halfway round: the stretch sits near the tip")
        let weights = stride(from: Double.pi / 2, through: .pi, by: 0.1).map(BlobGenie.weight(at:))
        #expect(zip(weights, weights.dropFirst()).allSatisfy { $0 <= $1 }, "monotonic from the top round to the left")
        func elements(_ path: CGPath) -> Int {
            var count = 0
            path.applyWithBlock { _ in count += 1 }
            return count
        }
        for shape in BlobShape.allCases {
            #expect(elements(BlobGenie.stretched(shape.profile).path(size: 44)) == elements(shape.profile.path(size: 44)), "\(shape)")
        }
        let pose = BlobLayerTree.geniePose(hovered: true, size: 44)
        #expect(pose.shift == -44 * Theme.genieShift && pose.squeeze == Theme.genieSqueeze && pose.lean == -44 * Theme.genieEyeLean)
        let rest = BlobLayerTree.geniePose(hovered: false, size: 44)
        #expect(rest.shift == 0 && rest.squeeze == 1 && rest.lean == 0)
    }

    @Test("The edge cue sits flush with the capsule's left edge, centred on its slot, inside the row pitch")
    @MainActor
    func edgeCueSlots() {
        for (slot, rows, actions) in [(0, 1, 0), (1, 3, 0), (2, 3, 2), (0, 2, 1)] {
            let rect = AttentionEdgeLayout.rect(slot: slot, rows: rows, actions: actions)
            #expect(rect.minX == Theme.contentWidth - Theme.capsuleWidth + Theme.attentionEdgeInset)
            #expect(rect.width == Theme.attentionEdgeWidth)
            #expect(abs(rect.midY - PanelModel.slotCenterY(slot: slot, rows: rows, actions: actions)) < 0.000_001)
            #expect(rect.height < Theme.rowPitch && rect.height > Theme.faceSize / 2)
        }
        let first = AttentionEdgeLayout.rect(slot: 0, rows: 2, actions: 0)
        let second = AttentionEdgeLayout.rect(slot: 1, rows: 2, actions: 0)
        #expect(abs(second.midY - first.midY - Theme.rowPitch) < 0.000_001, "one pitch apart")
        #expect(first.maxY <= second.minY, "cues of neighbouring rows never touch")
    }

    @Test("Playground arguments pick the waiting kind and the hover; the look carries both")
    @MainActor
    func playgroundToggles() {
        let model = PlaygroundModel(arguments: ["app", "--waiting-kind", "permission", "--hovered"])
        #expect(model.waitingKind == .permission && model.hovered && model.look.waitingKind == .permission && model.look.hovered)
        model.toggleWaitingKind()
        model.toggleHovered()
        #expect(model.waitingKind == .question && !model.hovered)
        var config = FaceConfiguration(identity: identity, mode: .status(.working), size: 44, filter: .none)
        #expect(!config.hovered)
        config.hovered = true
        #expect(config != FaceConfiguration(identity: identity, mode: .status(.working), size: 44, filter: .none), "a hover change reaches the layer tree")
    }
}
