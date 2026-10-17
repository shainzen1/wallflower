import Foundation
import Testing
@testable import AgentOverview

@Suite("Project colour mode")
struct ProjectColorModeTests {
    private let identity = FaceIdentity(seed: "project-mode")
    private let key = "web-app"

    /// Hue in degrees, 0 to 360.
    private static func hue(_ color: EyeColor) -> Double {
        let (r, g, b) = (color.red, color.green, color.blue)
        let maxChannel = max(r, g, b)
        let minChannel = min(r, g, b)
        let delta = maxChannel - minChannel
        guard delta > 0 else { return 0 }
        var hue: Double
        if maxChannel == r { hue = (g - b) / delta }
        else if maxChannel == g { hue = 2 + (b - r) / delta }
        else { hue = 4 + (r - g) / delta }
        hue *= 60
        return hue < 0 ? hue + 360 : hue
    }

    @Test("The palette has 10 to 12 vivid hues, none amber-like, and the mode is the default")
    func palette() {
        #expect(Theme.colorMode == .project)
        #expect(Theme.ColorMode.allCases == [.status, .identity, .project])
        #expect(Theme.ColorMode.project.next == .status && Theme.ColorMode.status.next == .identity)
        let amberHue = Self.hue(Theme.needsInputColor)
        let actionHue = Self.hue(Theme.actionColor)
        #expect(amberHue > 25 && amberHue < 45)
        #expect(actionHue > 240 && actionHue < 275, "lavender")
        for color in Theme.projectPalette {
            let maxChannel = max(color.red, color.green, color.blue)
            let minChannel = min(color.red, color.green, color.blue)
            #expect(maxChannel >= 0.84, "\(color.name) is bright enough on black")
            #expect(maxChannel - minChannel >= 0.4, "\(color.name) is saturated")
            let hue = Self.hue(color)
            // Orange, amber, yellow and lime: the wedge from 20 to 120 degrees stays empty.
            #expect(hue < 20 || hue > 120, "\(color.name) at \(Int(hue)) degrees is amber-like")
            #expect(abs(hue - actionHue) > 15, "\(color.name) at \(Int(hue)) degrees sits on the action lavender")
        }
        let keys = ProjectColor.sampleKeys(count: 5)
        #expect(keys.count == 5 && Set(keys.map(ProjectColor.color(for:))).count == 5)
        #expect(ProjectColor.sampleKeys(count: 100).count == Theme.projectPalette.count, "capped at the palette")
    }

    @Test("Body colour per status: amber waiting, project working and finished, dimmed idle, grey ended")
    func statusMapping() {
        let project = ProjectColor.color(for: key)
        #expect(ProjectColor.color(for: .needsInput(kind: .question), projectKey: key) == Theme.needsInputColor)
        #expect(ProjectColor.color(for: .working, projectKey: key) == project)
        #expect(ProjectColor.color(for: .justFinished, projectKey: key) == project)
        #expect(ProjectColor.color(for: .idle(since: Date()), projectKey: key) == project.dimmed(Theme.projectIdleDim))
        #expect(ProjectColor.color(for: .ended, projectKey: key) == Theme.endedColor)
        let dim = project.dimmed(Theme.projectIdleDim)
        #expect(dim.red < project.red && dim.green < project.green && dim.blue < project.blue)
        #expect(abs(dim.red / max(project.red, 0.001) - (1 - Theme.projectIdleDim)) < 0.001)
        #expect(ProjectColor.color(for: "a") == ProjectColor.color(for: "a"))
        #expect(EyeColor(hex: "#8C7CFF", name: "x") == EyeColor(name: "x", red: 140.0 / 255, green: 124.0 / 255, blue: 1))
        #expect(EyeColor(hex: "8C7CFF", name: "x") != nil && EyeColor(hex: "#8C7C", name: "x") == nil && EyeColor(hex: "zzzzzz", name: "x") == nil)
    }

    @Test("Blob programs in project mode: body colour by project, flash mint when finished, status shapes kept")
    func blobPrograms() {
        func program(_ status: FaceStatus) -> BlobProgram {
            BlobProgramBuilder.program(for: .status(status), identity: identity, colorMode: .project, projectKey: key)
        }
        let project = ProjectColor.color(for: key)
        #expect(program(.needsInput(kind: .question)).color == Theme.needsInputColor && program(.needsInput(kind: .permission)).body.shape == .drop)
        #expect(program(.working).color == project && program(.working).body.shape == .cloud)
        #expect(program(.idle(since: Date())).color == project.dimmed(Theme.projectIdleDim) && program(.idle(since: Date())).body.shape == .pill)
        let finished = program(.justFinished)
        #expect(finished.color == project && finished.flashColor == Theme.justFinishedColor && finished.bounce)
        #expect(program(.ended).color == Theme.endedColor)
        for activity in SessionActivity.allCases {
            let working = BlobProgramBuilder.program(for: .status(.working), identity: identity, activity: activity, colorMode: .project, projectKey: key)
            #expect(working.color == project, "\(activity) keeps the project colour")
        }
        #expect(BlobProgramBuilder.program(for: .expression(.happy), identity: identity, colorMode: .project, projectKey: key).color == project)
        #expect(BlobProgramBuilder.program(for: .status(.working), identity: identity, colorMode: .status, projectKey: key).color == Theme.workingColor, "status mode ignores the key")
        #expect(BlobProgramBuilder.program(for: .status(.working), identity: identity, colorMode: .identity, projectKey: key).color == identity.blobColor)
    }

    @Test("Dot-matrix programs follow the same mapping")
    func dotMatrixPrograms() {
        func program(_ status: FaceStatus) -> FaceProgram {
            FaceProgramBuilder.program(for: .status(status), identity: identity, colorMode: .project, projectKey: key)
        }
        let project = ProjectColor.color(for: key)
        #expect(program(.needsInput(kind: .question)).color == Theme.needsInputColor)
        #expect(program(.working).color == project)
        #expect(program(.idle(since: Date())).color == project.dimmed(Theme.projectIdleDim))
        #expect(program(.justFinished).flashColor == Theme.justFinishedColor)
        #expect(program(.ended).color == Theme.endedColor)
    }

    @Test("Launch argument and face configuration carry the mode")
    func launchArgument() {
        #expect(LaunchArguments(["app", "--color-mode", "identity"]).colorMode == .identity)
        #expect(LaunchArguments(["app", "--color-mode", "project"]).colorMode == .project)
        #expect(LaunchArguments(["app", "--color-mode", "nope"]).colorMode == nil)
        let config = FaceConfiguration(identity: identity, mode: .status(.working), size: 44, filter: .none)
        #expect(config.colorMode == Theme.colorMode && config.projectKey == nil)
    }
}

@Suite("Attention grow")
struct AttentionGrowTests {
    @Test("The needs-input programs carry the grow loop; nothing else does")
    func programsCarryTheLoop() {
        let identity = FaceIdentity(seed: "grow")
        #expect(Theme.attentionGrow == AttentionGrow(scale: 1.12, duration: 0.6, interval: 3, upFraction: Theme.attentionGrowUpFraction))
        #expect(BlobProgramBuilder.program(for: .status(.needsInput(kind: .question)), identity: identity).grow == Theme.attentionGrow)
        #expect(FaceProgramBuilder.program(for: .status(.needsInput(kind: .question)), identity: identity).grow == Theme.attentionGrow)
        for status: FaceStatus in [.working, .idle(since: Date()), .justFinished, .ended] {
            #expect(BlobProgramBuilder.program(for: .status(status), identity: identity).grow == nil, "\(status)")
            #expect(FaceProgramBuilder.program(for: .status(status), identity: identity).grow == nil, "\(status)")
        }
        #expect(BlobProgramBuilder.program(for: .action(ActionFace(phase: .resting)), identity: identity).grow == nil)
    }

    @Test("The loop: additive scale up and back within the duration, still for the rest of the interval, phase shifted")
    func keyframes() {
        let grow = Theme.attentionGrow
        let animation = BlobAnimations.grow(grow, phase: 0.25)
        #expect(animation.keyPath == "transform.scale" && animation.isAdditive && animation.repeatCount == .infinity)
        #expect(animation.duration == grow.interval)
        #expect(abs(animation.timeOffset - 0.25 * grow.interval) < 0.000_001)
        let values = animation.values as? [Double] ?? []
        #expect(values.count == 4 && values[0] == 0 && abs(values[1] - (grow.scale - 1)) < 0.000_001 && values[2] == 0 && values[3] == 0)
        let times = animation.keyTimes?.map(\.doubleValue) ?? []
        #expect(abs(times[1] - grow.duration * grow.upFraction / grow.interval) < 0.000_001)
        #expect(abs(times[2] - grow.duration / grow.interval) < 0.000_001 && times[3] == 1)
        #expect(animation.timingFunctions?.count == 3)
    }
}
