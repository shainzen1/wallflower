import CoreGraphics
import Foundation
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

@Suite("Blob silhouettes")
struct BlobShapeTests {
    @Test("Every silhouette, every morph midpoint and every squash share one path structure")
    func constantElementCount() {
        let reference = signature(of: BlobShape.round.profile.path(size: 44))
        #expect(reference.count == BlobProfile.sampleCount + 2, "one move, one curve per sample, one close")
        for shape in BlobShape.allCases {
            #expect(signature(of: shape.profile.path(size: 44)) == reference, "\(shape)")
            #expect(signature(of: shape.profile.path(size: 120)) == reference, "\(shape) at 120")
            for other in BlobShape.allCases {
                let mid = BlobProfile.lerp(shape.profile, other.profile, t: 0.5)
                #expect(signature(of: mid.path(size: 44)) == reference, "\(shape) to \(other)")
            }
            for squash in [Theme.blobSleepySquash, Theme.blobEndedSquash] {
                #expect(signature(of: shape.profile.squashed(squash).path(size: 44)) == reference, "\(shape) squashed \(squash)")
            }
        }
    }

    @Test("Radii are positive, inside the cell, and fill about 0.86 of it")
    func radiiBounded() {
        for shape in BlobShape.allCases {
            let radii = shape.profile.radii
            #expect(radii.count == BlobProfile.sampleCount)
            #expect(radii.allSatisfy { $0 > 0.25 && $0 < 0.5 }, "\(shape): \(radii.min() ?? 0) ... \(radii.max() ?? 0)")
            let bounds = shape.profile.path(size: 100).boundingBoxOfPath
            #expect(bounds.minX >= 0 && bounds.maxX <= 100 && bounds.minY >= 0 && bounds.maxY <= 100, "\(shape) inside the cell")
            #expect(bounds.width >= 60 || bounds.height >= 60, "\(shape) fills the cell")
        }
        #expect(abs(BlobShape.round.profile.radii[0] - Theme.blobRadius) < 0.000_001)
        #expect(BlobShape.round.profile.path(size: 100).boundingBoxOfPath.width > 85)
    }

    @Test("The cloud has lobes on top and a flatter bottom; the capsule is wider than tall")
    func shapeCharacter() {
        let cloud = BlobShape.cloud.profile
        let top = (12...20).map { cloud.radii[$0] }
        let bottom = (44...52).map { cloud.radii[$0] }
        let topVariation = (top.max() ?? 0) - (top.min() ?? 0)
        let bottomVariation = (bottom.max() ?? 0) - (bottom.min() ?? 0)
        #expect(topVariation > bottomVariation * 1.5, "lobes on top, smoother below")
        let pill = BlobShape.pill.profile
        #expect(pill.radii[0] > pill.radii[16] * 1.25, "capsule is horizontal")
        let drop = BlobShape.drop.profile
        #expect(drop.radii[16] > drop.radii[48] * 1.15, "drop points up")
    }

    @Test("Squashing keeps the width and scales the height; lerp ends return the inputs")
    func squashAndLerp() {
        let pill = BlobShape.pill.profile
        let flat = pill.squashed(Theme.blobEndedSquash)
        #expect(abs(flat.radii[0] - pill.radii[0]) < 0.001)
        #expect(abs(flat.radii[16] - pill.radii[16] * Theme.blobEndedSquash) < 0.002)
        #expect(BlobProfile.lerp(pill, BlobShape.cloud.profile, t: 0) == pill)
        #expect(BlobProfile.lerp(pill, BlobShape.cloud.profile, t: 1) == BlobShape.cloud.profile)
        #expect(abs(pill.radius(at: 0) - pill.radii[0]) < 0.000_001)
        #expect(abs(pill.radius(at: 2 * .pi) - pill.radii[0]) < 0.000_001)
    }
}

@Suite("Blob identity")
struct BlobIdentityTests {
    @Test("Identity is stable per seed and 64 seeds cover every silhouette and palette colour")
    func stableAndCovering() {
        let seed = "0A1B2C3D-session"
        #expect(FaceIdentity(seed: seed).shape == FaceIdentity(seed: seed).shape)
        #expect(FaceIdentity(seed: seed).blobColor == FaceIdentity(seed: seed).blobColor)
        #expect(FaceIdentity(seed: seed).blobTiltDelta == FaceIdentity(seed: seed).blobTiltDelta)
        let identities = (0..<64).map { FaceIdentity(seed: "session-\($0)") }
        #expect(Set(identities.map(\.shape)).count == BlobShape.identityShapes.count)
        #expect(!identities.map(\.shape).contains(.star), "the star is the action faces' own")
        #expect(Set(identities.map(\.blobColor)).count == Theme.blobPalette.count)
        for identity in identities {
            #expect(Theme.blobIdentityTiltRange.contains(identity.blobTiltDelta))
            #expect(Theme.blobIdentitySplitRange.contains(identity.blobSplitDelta))
        }
        #expect(FaceIdentity(seed: seed, shape: .cloud).shape == .cloud)
    }

    @Test("The blob palette has eight colours and never amber")
    func paletteNeverAmber() {
        #expect(Theme.blobPalette.count == 8)
        #expect(!Theme.blobPalette.contains(Theme.needsInputColor))
        #expect(Set(Theme.blobPalette.map(\.name)).count == 8)
        for color in Theme.blobPalette {
            // Amber is red high, green mid, blue low; nothing in the palette sits in that corner.
            let amberish = color.red > 0.9 && color.green > 0.55 && color.green < 0.8 && color.blue < 0.4
            #expect(!amberish, "\(color.name)")
        }
    }
}

@Suite("Blob programs")
struct BlobProgramTests {
    @Test("Status shape mode: the silhouette is the status; identity mode: the seed's silhouette")
    func statusToShape() {
        let identity = FaceIdentity(seed: "x")
        func body(_ status: FaceStatus, _ mode: Theme.BlobShapeMode) -> BlobBody {
            BlobProgramBuilder.program(for: .status(status), identity: identity, shapeMode: mode).body
        }
        #expect(body(.needsInput(kind: .question), .status) == BlobBody(shape: Theme.blobNeedsInputShape))
        #expect(body(.working, .status) == BlobBody(shape: .cloud))
        #expect(body(.idle(since: Date()), .status) == BlobBody(shape: .pill))
        #expect(body(.justFinished, .status) == BlobBody(shape: .pill))
        #expect(body(.ended, .status) == BlobBody(shape: .pill, squash: Theme.blobEndedSquash))
        let longIdle = FaceStatus.idle(since: Date().addingTimeInterval(-Theme.sleepyAfter - 60))
        #expect(body(longIdle, .status) == BlobBody(shape: .pill, squash: Theme.blobSleepySquash))
        for status: FaceStatus in [.needsInput(kind: .permission), .working, .idle(since: Date()), .justFinished, .ended] {
            #expect(body(status, .identity).shape == identity.shape)
        }
        #expect(body(.ended, .identity).squash == 1, "identity mode never flattens")
        #expect(BlobProgramBuilder.program(for: .expression(.happy), identity: identity, bodyOverride: BlobBody(shape: .drop)).body.shape == .drop)
    }

    @Test("Status colour mode: the body colour is the status, needs input amber, nothing else")
    func statusColours() {
        let identity = FaceIdentity(seed: "x")
        func color(_ status: FaceStatus) -> EyeColor {
            BlobProgramBuilder.program(for: .status(status), identity: identity).color
        }
        #expect(color(.needsInput(kind: .question)) == Theme.needsInputColor && color(.needsInput(kind: .permission)) == Theme.needsInputColor)
        switch Theme.colorMode {
        case .status:
            #expect(color(.working) == Theme.workingColor)
            #expect(color(.idle(since: Date())) == Theme.idleColor)
            #expect(color(.ended) == Theme.endedColor)
            let finished = BlobProgramBuilder.program(for: .status(.justFinished), identity: identity)
            #expect(finished.color == Theme.idleColor && finished.flashColor == Theme.justFinishedColor && finished.bounce)
            #expect(BlobProgramBuilder.program(for: .expression(.happy), identity: identity).color == Theme.idleColor)
        case .identity:
            #expect(color(.working) == identity.blobColor)
        case .project:
            // Without a project key the project mode falls back to the status colours.
            #expect(color(.working) == Theme.workingColor)
            #expect(color(.ended) == Theme.endedColor)
        }
        for status: FaceStatus in [.working, .idle(since: Date()), .justFinished, .ended] {
            #expect(color(status) != Theme.needsInputColor)
        }
    }

    @Test("Status loops: needs input pulses and looks left, working drifts and breathes, idle wanders and schedules sleepy, ended closes")
    func statusLoops() {
        let identity = FaceIdentity(seed: "x")
        let needs = BlobProgramBuilder.program(for: .status(.needsInput(kind: .question)), identity: identity)
        #expect(needs.bodyLoop == Theme.blobNeedsInputPulse)
        #expect(needs.pose.yaw < 0, "looks toward the screen")
        #expect(needs.tracks.map(\.key) == ["loop.blink"])
        #expect(needs.tracks[0].samples.contains { $0.pose.lid == Theme.blobClosedLid }, "blinks are in the loop")
        let working = BlobProgramBuilder.program(for: .status(.working), identity: identity)
        #expect(working.bodyLoop == Theme.blobWorkingBreath)
        #expect(working.tracks[0].repeats && working.tracks[0].samples.contains { $0.pose.yaw < -5 } && working.tracks[0].samples.contains { $0.pose.yaw > 5 })
        #expect(working.tracks[0].samples.first?.pose == working.pose, "the loop starts at the rest pose")
        let idle = BlobProgramBuilder.program(for: .status(.idle(since: Date())), identity: identity)
        #expect(idle.tracks.map(\.key) == ["loop.idle", "sched.sleepy", "loop.sleepy"])
        #expect(idle.tracks[1].delay > Theme.sleepyAfter - 5 && idle.scheduledBody?.body.squash == Theme.blobSleepySquash)
        #expect(idle.tracks[0].samples.contains { $0.pose.lid == Theme.blobClosedLid })
        #expect(idle.tracks[0].samples.first?.pose == idle.pose)
        let ended = BlobProgramBuilder.program(for: .status(.ended), identity: identity)
        #expect(ended.pose.lid == Theme.blobClosedLid && ended.tracks.isEmpty)
        let finished = BlobProgramBuilder.program(for: .status(.justFinished), identity: identity)
        #expect(finished.tracks.map(\.key) == ["sched.return", "loop.idle"])
        #expect(finished.tracks[0].delay == Theme.justFinishedHold)
    }

    @Test("Blink schedules and swaps keep the lid in range and hide the swap while closed")
    func blinks() {
        let schedule = BlobBlinkSchedule(interval: 8, count: 3, phase: 0.3, doubleEvery: 3)
        #expect(schedule.starts.count == 4, "three blinks, the last one double")
        for t in stride(from: 0.0, through: 24, by: 0.01) {
            let lid = schedule.lid(at: t)
            #expect(lid >= Theme.blobClosedLid - 0.000_001 && lid <= 1)
        }
        let a = BlobExpressions.pose(for: .normal)
        let b = BlobExpressions.pose(for: .angry)
        let swap = BlobTrack.blinkSwap(key: "k", from: a, to: b)
        #expect(swap.samples.first?.pose == a)
        #expect(swap.samples.last?.pose == b)
        let closedSamples = swap.samples.filter { $0.pose.lid <= Theme.blobClosedLid + 0.000_001 }
        #expect(closedSamples.contains { $0.pose.left == a.left } && closedSamples.contains { $0.pose.left == b.left }, "the swap happens while closed")
        #expect(abs(swap.duration - (Theme.blobBlinkClose + Theme.blobBlinkHold + Theme.blobBlinkOpen)) < 0.000_001)
        #expect(swap.duration <= 0.18 && swap.duration >= 0.12, "a blink is 120 to 180 ms")
    }
}

@Suite("Blob eyes")
struct BlobEyeTests {
    @Test("Every expression yields eye paths inside the face, mirrored, with a constant structure")
    func eyesInsideTheFace() {
        let size: CGFloat = 44
        let reference = signature(of: BlobEyes.path(for: BlobEyePose(), profile: BlobShape.round.profile, faceSize: size, mirrored: false))
        #expect(reference.count == 10, "one move, four lines, four quarter circles, one close")
        for shape in BlobShape.allCases {
            for expression in Expression.allCases {
                let pose = BlobExpressions.pose(for: expression)
                let left = BlobEyes.path(for: pose, body: BlobBody(shape: shape), faceSize: size, mirrored: false)
                let right = BlobEyes.path(for: pose, body: BlobBody(shape: shape), faceSize: size, mirrored: true)
                for (path, name) in [(left, "left"), (right, "right")] {
                    let box = path.boundingBoxOfPath
                    #expect(box.minX >= 0 && box.maxX <= size && box.minY >= 0 && box.maxY <= size, "\(expression) \(name) on \(shape): \(box)")
                    #expect(signature(of: path) == reference, "\(expression) \(name)")
                    #expect(signature(of: BlobEyes.path(for: pose.closed(), profile: shape.profile, faceSize: size, mirrored: name == "right")) == reference)
                }
                #expect(left.boundingBoxOfPath.midX < right.boundingBoxOfPath.midX, "\(expression): left eye is left of the right eye")
                let symmetric: [BlobShape] = [.round, .squircle, .drop, .pill, .softHex]
                if pose.left == pose.right, pose.yaw == 0, pose.roll == 0, symmetric.contains(shape) {
                    #expect(abs((size - right.boundingBoxOfPath.maxX) - left.boundingBoxOfPath.minX) < 0.01, "\(expression): not mirrored")
                }
            }
        }
    }

    @Test("Looking sideways narrows the eye nearer the rim; a blink leaves a sliver; the eyes lean \\ and /")
    func projection() {
        let profile = BlobShape.round.profile
        let centre = BlobEyePose()
        let left = BlobEyes.path(for: centre.looking(yaw: -25, pitch: 0), profile: profile, faceSize: 100, mirrored: false).boundingBoxOfPath
        let right = BlobEyes.path(for: centre.looking(yaw: -25, pitch: 0), profile: profile, faceSize: 100, mirrored: true).boundingBoxOfPath
        #expect(left.width < right.width, "the eye nearer the rim is narrower")
        #expect(left.midX < 50 && right.midX < 50 + 20, "both moved left")
        let open = BlobEyes.path(for: centre, profile: profile, faceSize: 100, mirrored: false).boundingBoxOfPath
        let closed = BlobEyes.path(for: centre.closed(), profile: profile, faceSize: 100, mirrored: false).boundingBoxOfPath
        #expect(closed.height < open.height * 0.5 && closed.height > 0)
        let leftPlacement = BlobEyes.placement(for: centre, profile: profile, faceSize: 100, mirrored: false)
        let rightPlacement = BlobEyes.placement(for: centre, profile: profile, faceSize: 100, mirrored: true)
        // Local +y (the capsule's top) maps to the screen through the matrix: the left eye's top leans left, the right eye's right.
        let leftTop = CGPoint(x: 0, y: 1).applying(leftPlacement.transform)
        let rightTop = CGPoint(x: 0, y: 1).applying(rightPlacement.transform)
        #expect(leftTop.x < leftPlacement.centre.x && rightTop.x > rightPlacement.centre.x)
        let up = BlobEyes.placement(for: centre.looking(yaw: 0, pitch: 20), profile: profile, faceSize: 100, mirrored: false)
        #expect(up.centre.y > leftPlacement.centre.y, "positive pitch looks up")
    }
}

@Suite("Screen filters")
struct FaceFilterTests {
    @Test("Every filter mask is cached and sized to the face in device pixels")
    @MainActor
    func masksCachedAndSized() {
        for filter in FaceFilter.allCases where filter != .none {
            for (size, scale) in [(CGFloat(44), CGFloat(2)), (CGFloat(120), CGFloat(2)), (CGFloat(44), CGFloat(1))] {
                let first = FaceFilterMask.image(for: filter, size: size, scale: scale)
                let second = FaceFilterMask.image(for: filter, size: size, scale: scale)
                #expect(first != nil, "\(filter)")
                #expect(first === second, "\(filter) at \(size)x\(scale) is cached")
                let pixels = Int((size * scale).rounded(.up))
                #expect(first?.width == pixels && first?.height == pixels, "\(filter) at \(size)x\(scale)")
            }
        }
        #expect(FaceFilterMask.image(for: .none, size: 44, scale: 2) == nil)
        #expect(Theme.dotMatrix == (Theme.faceFilter == .dotMatrix))
    }

    @Test("Launch arguments pick the style, filter and shape mode")
    func launchArguments() {
        let arguments = LaunchArguments(["app", "--face-style", "blob", "--face-filter", "halftone", "--blob-shape", "identity"])
        #expect(arguments.faceStyle == .blob && arguments.faceFilter == .halftone && arguments.blobShapeMode == .identity)
        let other = LaunchArguments(["app", "--face-style", "dotMatrix", "--face-filter", "none"])
        #expect(other.faceStyle == .dotMatrix && other.faceFilter == FaceFilter.none && other.blobShapeMode == nil)
        #expect(LaunchArguments(["app", "--face-style", "bogus"]).faceStyle == nil)
    }

    @Test("ASCII glyph choice is seeded and favours dense glyphs")
    @MainActor
    func asciiGlyphs() {
        #expect(AsciiGridMask.glyph(row: 3, column: 7) == AsciiGridMask.glyph(row: 3, column: 7))
        var dense = 0
        let total = 400
        for row in 0..<20 {
            for column in 0..<20 where Theme.asciiGlyphs.prefix(4).contains(AsciiGridMask.glyph(row: row, column: column)) {
                dense += 1
            }
        }
        #expect(dense > total / 3, "dense glyphs are common: \(dense) of \(total)")
    }
}
