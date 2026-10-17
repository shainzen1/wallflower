/// The state the UI shows for a session, derived from the registry status (Claude or external).
enum SessionState: Sendable, Hashable {
    case needsInput(kind: WaitingKind)
    case working
    case idle

    init(record: SessionRecord) {
        self.init(status: record.status, waitingKind: record.waitingKind)
    }

    /// The registry status as a state; `waitingKind` only matters while waiting.
    init(status: RegistryStatus, waitingKind: WaitingKind) {
        switch status {
        case .waiting: self = .needsInput(kind: waitingKind)
        case .busy: self = .working
        case .idle: self = .idle
        }
    }

    /// Group order in the panel: needs input on top, then working, then your turn, then idle.
    /// `idleTier` only matters for an idle session (`IdleTier.tier`).
    func sortRank(idleTier: IdleTier) -> Int {
        switch self {
        case .needsInput: 0
        case .working: 1
        case .idle: idleTier == .yourTurn ? 2 : 3
        }
    }

    var isNeedsInput: Bool {
        if case .needsInput = self { return true }
        return false
    }
}
