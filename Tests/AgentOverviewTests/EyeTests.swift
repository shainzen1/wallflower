import CoreGraphics
import Foundation
import SwiftUI
import Testing
@testable import AgentOverview

/// The element types of a path in order, as a comparable signature.
private func signature(of path: CGPath) -> [CGPathElementType] {
    var types: [CGPathElementType] = []
    path.applyWithBlock { element in
        types.append(element.pointee.type)
    }
    return types
}

@Suite("Eye paths")
struct EyePathTests {
    @Test("Every expression, preset, eye and the closed pose share one element structure")
    func structureIsConstant() {
        let reference = signature(of: EyePathBuilder.path(for: EyeParameters(), faceSize: 40, mirrored: false))
        #expect(reference.count == 14)
        for expression in Expression.allCases {
            for preset in EyePreset.allCases {
                let pose = expression.pose.applying(preset)
                for mirrored in [false, true] {
                    let open = mirrored ? pose.right : pose.left
                    let openPath = EyePathBuilder.path(for: open, faceSize: 40, mirrored: mirrored)
                    #expect(signature(of: openPath) == reference, "\(expression) \(preset) mirrored=\(mirrored)")
                    let closedPath = EyePathBuilder.path(for: open.closed(), faceSize: 120, mirrored: mirrored)
                    #expect(signature(of: closedPath) == reference, "\(expression) \(preset) closed mirrored=\(mirrored)")
                }
            }
        }
        // The exclamation bar and its blink (the bar squashed to a dash) are regular eye paths too.
        for mirrored in [false, true] {
            let bar = EyePathBuilder.path(for: ExclamationPose.bar, faceSize: 44, mirrored: mirrored)
            #expect(signature(of: bar) == reference, "exclamation bar mirrored=\(mirrored)")
            let dash = EyePathBuilder.path(for: ExclamationPose.bar.closed(), faceSize: 44, mirrored: mirrored)
            #expect(signature(of: dash) == reference, "exclamation dash mirrored=\(mirrored)")
        }
    }

    @Test("Exclamation dots sit below the bars, inside the face, mirrored, with a constant path")
    func exclamationDots() {
        let size: CGFloat = 44
        let dotSignature = signature(of: ExclamationPose.dotPath(faceSize: size))
        #expect(dotSignature == signature(of: ExclamationPose.dotPath(faceSize: 120)))
        let left = ExclamationPose.dotRect(faceSize: size, mirrored: false)
        let right = ExclamationPose.dotRect(faceSize: size, mirrored: true)
        let bar = EyePathBuilder.path(for: ExclamationPose.bar, faceSize: size, mirrored: false).boundingBoxOfPath
        #expect(abs(left.midX - bar.midX) < 0.001, "dot is centred under the bar")
        #expect(left.maxY < bar.minY, "dot is below the bar (layer y is up)")
        #expect(left.minY >= 0 && bar.maxY <= size, "the whole ! is inside the face")
        #expect(abs((size - right.maxX) - left.minX) < 0.001, "right dot mirrors the left")
        let centre = (bar.maxY + left.minY) / 2
        #expect(abs(centre - size / 2) < size * 0.05, "the ! is roughly centred vertically")
    }

    @Test("Paths stay inside the face and the right eye mirrors the left")
    func pathsAreInsideTheFace() {
        let size: CGFloat = 40
        for expression in Expression.allCases {
            let pose = expression.pose
            let left = EyePathBuilder.path(for: pose.left, faceSize: size, mirrored: false).boundingBoxOfPath
            let right = EyePathBuilder.path(for: pose.right, faceSize: size, mirrored: true).boundingBoxOfPath
            #expect(left.minX >= 0 && left.maxX <= size && left.minY >= 0 && left.maxY <= size, "\(expression) left")
            #expect(right.minX >= 0 && right.maxX <= size && right.minY >= 0 && right.maxY <= size, "\(expression) right")
            #expect(left.maxX <= right.minX, "\(expression): eyes overlap")
            if pose.left == pose.right {
                #expect(abs((size - right.maxX) - left.minX) < 0.001, "\(expression): not mirrored")
            }
        }
    }

    @Test("Interpolation at the ends returns the inputs")
    func lerpEndpoints() {
        let a = Expression.normal.pose.left
        let b = Expression.happy.pose.left
        #expect(EyeParameters.lerp(a, b, t: 0) == a)
        #expect(EyeParameters.lerp(a, b, t: 1) == b)
        let mid = EyeParameters.lerp(a, b, t: 0.5)
        #expect(abs(mid.bottomInverseOffset - (a.bottomInverseOffset + b.bottomInverseOffset) / 2) < 0.000_001)
    }
}

@Suite("Face identity")
struct FaceIdentityTests {
    @Test("FNV-1a known vectors")
    func hashVectors() {
        #expect(SeedHash("").value == 0xcbf2_9ce4_8422_2325)
        #expect(SeedHash("a").value == 0xaf63_dc4c_8601_ec8c)
    }

    @Test("Identity is stable for a seed")
    func stableForSeed() {
        let seed = "0A1B2C3D-session"
        let first = FaceIdentity(seed: seed)
        let second = FaceIdentity(seed: seed)
        #expect(first == second)
        #expect(first.blinkPhase == second.blinkPhase)
        #expect(first.blinkInterval(in: Theme.idleBlinkInterval) == second.blinkInterval(in: Theme.idleBlinkInterval))
    }

    @Test("Identity differs across seeds")
    func differsAcrossSeeds() {
        let seeds = (0..<64).map { "session-\($0)" }
        let identities = seeds.map { FaceIdentity(seed: $0) }
        let hashes = Set(identities.map(\.hash))
        #expect(hashes.count == seeds.count)
        let colours = Set(identities.map(\.color))
        let presets = Set(identities.map(\.preset))
        #expect(colours.count == Theme.eyePalette.count)
        #expect(presets.count == EyePreset.allCases.count)
        let phases = Set(identities.map(\.blinkPhase))
        #expect(phases.count > seeds.count / 2)
    }

    @Test("Palette never yields amber")
    func paletteNeverAmber() {
        #expect(!Theme.eyePalette.contains(Theme.needsInputColor))
        for index in 0..<500 {
            let identity = FaceIdentity(seed: "seed-\(index)")
            #expect(identity.color != Theme.needsInputColor)
            #expect(Theme.eyePalette.contains(identity.color))
        }
    }

    @Test("Blink intervals stay inside their ranges")
    func intervalsInRange() {
        for index in 0..<200 {
            let identity = FaceIdentity(seed: "seed-\(index)")
            #expect(Theme.idleBlinkInterval.contains(identity.blinkInterval(in: Theme.idleBlinkInterval)))
            #expect((0..<1).contains(identity.blinkPhase))
        }
    }
}

@Suite("Face program")
struct FaceProgramTests {
    @Test("Needs input is amber and pulses, as eyes or exclamation marks per Theme; nothing else is amber")
    func needsInputIsAmber() {
        let identity = FaceIdentity(seed: "x")
        let program = FaceProgramBuilder.program(for: .status(.needsInput(kind: .question)), identity: identity)
        #expect(program.color == Theme.needsInputColor)
        if Theme.needsInputStyle == .exclamation {
            #expect(program.pose.left == ExclamationPose.bar && program.pose.right == ExclamationPose.bar)
            #expect(program.exclamation)
        } else {
            let surprised = FaceProgramBuilder.resolved(.surprised, identity)
            let awe = FaceProgramBuilder.resolved(.awe, identity)
            #expect(program.pose.left == surprised.left || program.pose.left == awe.left)
            #expect(!program.exclamation)
        }
        #expect(program.pulse)
        #expect(program.tracks.first?.steps.first?.pose == program.pose, "the blink keyframes use the bar pose")
        for status: FaceStatus in [.working, .idle(since: Date()), .justFinished, .ended] {
            let other = FaceProgramBuilder.program(for: .status(status), identity: identity)
            #expect(other.color != Theme.needsInputColor)
            #expect(!other.exclamation)
        }
    }

    @Test("Status colour mode: colour is the status, identity is the shape only")
    func statusColours() {
        let identity = FaceIdentity(seed: "x")
        func color(_ status: FaceStatus) -> EyeColor {
            FaceProgramBuilder.program(for: .status(status), identity: identity).color
        }
        switch Theme.colorMode {
        case .status:
            #expect(color(.working) == Theme.workingColor)
            #expect(color(.idle(since: Date())) == Theme.idleColor)
            #expect(color(.ended) == Theme.endedColor)
            let finished = FaceProgramBuilder.program(for: .status(.justFinished), identity: identity)
            #expect(finished.color == Theme.idleColor)
            #expect(finished.flashColor == Theme.justFinishedColor)
            #expect(FaceProgramBuilder.program(for: .expression(.happy), identity: identity).color == Theme.idleColor)
            #expect(FaceProgramBuilder.program(for: .status(.idle(since: Date())), identity: identity).glow < Theme.glowOpacity)
        case .identity:
            for status: FaceStatus in [.working, .idle(since: Date()), .justFinished, .ended] {
                #expect(color(status) == identity.color)
            }
        case .project:
            #expect(color(.working) == Theme.workingColor, "no project key: the status colours")
            #expect(color(.ended) == Theme.endedColor)
        }
        #expect(Set([Theme.workingColor, Theme.yourTurnColor, Theme.idleColor, Theme.justFinishedColor, Theme.endedColor, Theme.needsInputColor]).count == 6)
    }

    @Test("Working and idle carry their liveliness loops")
    func livelinessLoops() {
        let identity = FaceIdentity(seed: "x")
        let working = FaceProgramBuilder.program(for: .status(.working), identity: identity)
        #expect(working.dart && working.scan && working.breath?.scale == Theme.workingBreathScale)
        #expect(Theme.dartInterval.contains(identity.dartInterval))
        #expect(Theme.workingPoseInterval.contains(identity.workingPoseInterval))
        let idle = FaceProgramBuilder.program(for: .status(.idle(since: Date())), identity: identity)
        #expect(idle.wander && idle.breath?.scale == Theme.idleBreathScale && !idle.dart)
        let idleTrack = idle.tracks[0]
        #expect(idleTrack.key == "loop.idle" && idleTrack.repeats)
        #expect(abs(idleTrack.duration - identity.idleMoodInterval) < 0.5, "one idle loop is about one mood interval")
        let mood = FaceProgramBuilder.resolved(identity.idleMood, identity)
        #expect(idleTrack.steps.contains { $0.pose == mood }, "the mood flicker is in the loop")
        let closed = FaceProgramBuilder.resolved(.normal, identity).closed()
        #expect(idleTrack.steps.filter { $0.pose == closed }.count >= 2, "blinks are in the loop")
    }

    @Test("Idle schedules the sleepy drift and a long idle starts sleepy")
    func idleDrift() {
        let identity = FaceIdentity(seed: "x")
        let fresh = FaceProgramBuilder.program(for: .status(.idle(since: Date())), identity: identity)
        #expect(fresh.tracks.map(\.key) == ["loop.idle", "sched.drift", "loop.blinkSleepy"])
        let drift = fresh.tracks[1]
        #expect(drift.delay > Theme.sleepyAfter - 5 && drift.delay <= Theme.sleepyAfter)
        let old = FaceProgramBuilder.program(for: .status(.idle(since: Date().addingTimeInterval(-Theme.sleepyAfter - 60))), identity: identity)
        #expect(old.tracks.map(\.key) == ["loop.blinkSleepy"])
        #expect(old.pose == FaceProgramBuilder.resolved(.sleepy, identity))
    }

    @Test("Track durations add up")
    func trackDurations() {
        let open = Expression.normal.pose
        let blink = PathTrack.blink(key: "k", open: open, interval: 8, phase: 0)
        #expect(abs(blink.duration - 8) < 0.000_001)
        let double = PathTrack.blink(key: "k", open: open, interval: 8, phase: 0, doubleEvery: 2)
        #expect(abs(double.duration - 16) < 0.000_001)
        let move = PathTrack.move(key: "k", from: open, to: open.closed(), after: 3, duration: 1.5, transition: .ease)
        #expect(abs(move.duration - 1.5) < 0.000_001)
        let triple = PathTrack.blink(key: "k", open: open, interval: 8, phase: 0, doubleEvery: 3)
        #expect(abs(triple.duration - 24) < 0.000_001)
        #expect(triple.steps.filter { $0.pose == open.closed() }.count == 4, "two singles and one double")
    }
}

@Suite("Capsule shape")
struct CapsuleShapeTests {
    @Test("Height includes the fillets and the path fills exactly the frame")
    func heightAndBounds() {
        let rows = 3
        let body = Theme.capsuleBodyHeight(rows: rows)
        #expect(Theme.capsuleHeight(rows: rows) == body + Theme.edgeFilletRadius * 2)
        let shape = CapsuleShape(cornerRadius: Theme.capsuleCornerRadius, filletRadius: Theme.edgeFilletRadius, bodyHeight: body)
        let rect = CGRect(x: 0, y: 0, width: Theme.capsuleWidth, height: Theme.capsuleHeight(rows: rows))
        let bounds = shape.path(in: rect).boundingRect
        #expect(abs(bounds.minX) < 0.01 && abs(bounds.maxX - rect.width) < 0.01)
        #expect(abs(bounds.minY) < 0.01 && abs(bounds.maxY - rect.height) < 0.01)
        #expect(shape.animatableData == body)
    }

    @Test("The fillet is concave: just inside the screen edge, the top of the capsule is black only below the fillet")
    func filletIsConcave() {
        let f = Theme.edgeFilletRadius
        let body: CGFloat = 100
        let shape = CapsuleShape(cornerRadius: 16, filletRadius: f, bodyHeight: body)
        let rect = CGRect(x: 0, y: 0, width: 60, height: body + f * 2)
        let path = shape.path(in: rect).cgPath
        // The arc is tangent to the screen edge at y = 0: just inside the edge the fill starts a little lower,
        // half a fillet in it starts at 0.87 f, and a full fillet in at y = f (the body's top edge).
        #expect(!path.contains(CGPoint(x: 59.9, y: 1.0)))
        #expect(path.contains(CGPoint(x: 59.9, y: 2.0)))
        #expect(!path.contains(CGPoint(x: 60 - f / 2, y: f * 0.8)))
        #expect(path.contains(CGPoint(x: 60 - f / 2, y: f * 0.95)))
        #expect(!path.contains(CGPoint(x: 60 - f - 1, y: f - 0.5)))
        #expect(path.contains(CGPoint(x: 60 - f - 1, y: f + 0.5)))
        // Mirrored at the bottom.
        #expect(!path.contains(CGPoint(x: 59.9, y: rect.height - 1.0)))
        #expect(path.contains(CGPoint(x: 59.9, y: rect.height - 2.0)))
        #expect(!path.contains(CGPoint(x: 60 - f / 2, y: rect.height - f * 0.8)))
        // Left corners are rounded, not square.
        #expect(!path.contains(CGPoint(x: 0.5, y: f + 0.5)))
        #expect(path.contains(CGPoint(x: 16, y: f + 0.5)))
    }
}
