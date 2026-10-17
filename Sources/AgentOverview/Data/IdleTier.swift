import Foundation

/// Where an idle session stands. A turn that just ended waits for the person's next instruction
/// (`yourTurn`) for `Theme.yourTurnFor`, unless the person already opened the chat after the idle
/// began; after that, or once acknowledged, it is parked (`idle`). The one rule behind both the
/// face status (`SessionRow`) and the panel order (`SessionStore.sorted`).
enum IdleTier: Sendable, Hashable {
    case yourTurn
    case idle

    /// The tier of an idle period that began at `idleSince`. An acknowledgement at or after the
    /// idle start parks it; a later idle period (a newer `idleSince`) is eligible again.
    static func tier(idleSince: Date, acknowledgedAt: Date?, now: Date, yourTurnFor: TimeInterval = Theme.yourTurnFor) -> IdleTier {
        if let acknowledgedAt, acknowledgedAt >= idleSince { return .idle }
        return now.timeIntervalSince(idleSince) < yourTurnFor ? .yourTurn : .idle
    }
}
