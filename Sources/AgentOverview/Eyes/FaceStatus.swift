import Foundation

/// The session state a face shows. In `.status` colour mode the colour is the status too.
enum FaceStatus: Equatable, Sendable {
    /// Waiting for the person: amber surprised/awe eyes looking at you, glow pulse, occasional
    /// double blink. A permission prompt pulses and grows faster than a question.
    case needsInput(kind: WaitingKind)
    /// Busy: focused with occasional squint or skeptic, glances and a reading scan, thinking breath. Cyan.
    case working
    /// Waiting for the next instruction since the given date (the idle start): a fresh idle period,
    /// younger than `Theme.yourTurnFor` and not yet acknowledged. Calm and present: muted mint, normal
    /// eyes looking at you, a soft breathing halo and a quiet edge cue. Below amber in urgency.
    case yourTurn(since: Date)
    /// Idle since the given date: normal, drifting gaze, slow blink and mood flicker, sleepy after `Theme.sleepyAfter`. Muted warm grey.
    case idle(since: Date)
    /// Transition after work finished: happy or glee with one bounce, a burst of dots and a mint flash, then on to your turn.
    case justFinished
    /// Process exited: eyes close to a dim grey line. The caller fades the row.
    case ended

    /// Whether the session waits for the person, whatever it waits for.
    var isNeedsInput: Bool {
        if case .needsInput = self { return true }
        return false
    }

    /// Whether the session's turn ended and it waits for the person's next instruction.
    var isYourTurn: Bool {
        if case .yourTurn = self { return true }
        return false
    }

    /// What a waiting session waits for; nil for every other status.
    var waitingKind: WaitingKind? {
        if case .needsInput(let kind) = self { return kind }
        return nil
    }
}
