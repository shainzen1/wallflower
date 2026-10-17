import Observation
import SwiftUI

/// State of the playground controls. An observable object rather than `@State` because the
/// Command Line Tools ship without the SwiftUI macro plugin that `@State` needs.
/// `--activity <thinking|coding|running|reading|delegating>` and `--satellites <0...4>` set the
/// working hero's substate and satellites at launch, `--waiting-kind <question|permission>` the
/// needs-input hero's wait, `--hovered` the hover on every hero and `--excite <seconds>` plays the
/// excited reaction once (read here, so screenshots can be scripted).
/// The hero row also follows the real pointer (`heroPointer`), so the hover effect can be felt at hero size.
@Observable
@MainActor
final class PlaygroundModel {
    var expressionIndex = 0
    var blinkToken = 0
    var replayToken = 0
    var attentionToken = 0
    var excitedToken = 0
    var style = FaceLook.style
    var filter = FaceLook.filter
    var shapeMode = FaceLook.blobShapeMode
    var colorMode = FaceLook.colorMode
    var activity: SessionActivity = .thinking
    var satellites = 0
    var waitingKind: WaitingKind = .question
    var hovered = false
    var hoverEffect = FaceLook.hoverEffect
    /// The pointer over the hero row, in the row's coordinates; nil when it is elsewhere.
    var heroPointer: CGPoint?
    var seedField = "session-42"
    var seed = "session-42"

    /// `--hop <seconds>`: bump the attention token once, that long after launch (scripted screenshots).
    private(set) var scriptedHopDelay: TimeInterval?
    /// `--excite <seconds>`: bump the excited token once, that long after launch (scripted screenshots).
    private(set) var scriptedExciteDelay: TimeInterval?

    init(arguments: [String] = CommandLine.arguments) {
        var iterator = arguments.dropFirst().makeIterator()
        while let argument = iterator.next() {
            switch argument {
            case "--activity":
                if let text = iterator.next(), let activity = SessionActivity(rawValue: text) { self.activity = activity }
            case "--satellites":
                if let text = iterator.next(), let count = Int(text) { satellites = min(max(count, 0), Theme.satelliteMax) }
            case "--hop":
                if let text = iterator.next(), let delay = TimeInterval(text) { scriptedHopDelay = delay }
            case "--excite":
                if let text = iterator.next(), let delay = TimeInterval(text) { scriptedExciteDelay = delay }
            case "--waiting-kind":
                switch iterator.next() {
                case "question": waitingKind = .question
                case "permission": waitingKind = .permission
                default: break
                }
            case "--hovered": hovered = true
            default: break
            }
        }
        if let delay = scriptedHopDelay {
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(delay))
                self?.hop()
            }
        }
        if let delay = scriptedExciteDelay {
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(delay))
                self?.excite()
            }
        }
    }

    var expression: Expression {
        Expression.allCases[expressionIndex % Expression.allCases.count]
    }

    func cycleExpression() {
        expressionIndex += 1
    }

    func blinkNow() {
        blinkToken += 1
    }

    func replayFinished() {
        replayToken += 1
    }

    /// Bumps the attention token: the needs-input hero hops once.
    func hop() {
        attentionToken += 1
    }

    /// Bumps the excited token: the working hero perks up as if the person's message had just
    /// arrived. Every status hero gets the token; only a program with the excited reaction plays it.
    func excite() {
        excitedToken += 1
    }

    func cycleStyle() {
        style = style.next
    }

    func cycleFilter() {
        filter = filter.next
    }

    func toggleShapeMode() {
        shapeMode = shapeMode == .status ? .identity : .status
    }

    func cycleColorMode() {
        colorMode = colorMode.next
    }

    /// Working substate of the working hero: thinking, coding, running, reading, delegating.
    func cycleActivity() {
        let all = SessionActivity.allCases
        activity = all[(all.firstIndex(of: activity)! + 1) % all.count]
    }

    /// Satellites on the working hero: 0 to `Theme.satelliteMax`.
    func cycleSatellites() {
        satellites = (satellites + 1) % (Theme.satelliteMax + 1)
    }

    /// What the needs-input hero waits for: a question (grow every 3 s) or a permission (faster pulse, grow every 2 s).
    func toggleWaitingKind() {
        waitingKind = waitingKind == .question ? .permission : .question
    }

    /// Every hero as if hovered (the genie under `.stretch`).
    func toggleHovered() {
        hovered.toggle()
    }

    /// What a hover does to the heroes: magnify, stretch or nothing.
    func cycleHoverEffect() {
        hoverEffect = hoverEffect.next
    }

    /// The pointer over the hero row moved (nil: it left).
    func heroPointerMoved(to point: CGPoint?) {
        if heroPointer != point { heroPointer = point }
    }

    func applySeed() {
        seed = seedField
    }

    var seedBinding: Binding<String> {
        Binding(get: { self.seedField }, set: { self.seedField = $0 })
    }

    /// The look every face in the playground is rendered with.
    var look: PlaygroundLook {
        PlaygroundLook(
            style: style, filter: filter, shapeMode: shapeMode, colorMode: colorMode, blinkToken: blinkToken, replayToken: replayToken,
            activity: activity, satellites: satellites, attentionToken: attentionToken, excitedToken: excitedToken, waitingKind: waitingKind, hovered: hovered,
            hoverEffect: hoverEffect
        )
    }
}
