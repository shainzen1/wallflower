import Foundation

/// The rule behind the excited reaction: a face perks up once each time its session starts working
/// after resting or waiting for the person (idle, sleepy, your turn, just finished or needs input),
/// which is the moment the person's message arrives (typing itself cannot be seen from outside the
/// session). Never for a session that is already working when first seen (launch, or a row that
/// appears working), and never between two working states (a new activity). Pure value, owned by
/// `PanelModel`, like `AttentionTracker`.
struct ExcitedTracker: Equatable, Sendable {
    /// The excited token per session; the face reacts when its token changes.
    private(set) var tokens: [SessionKey: Int] = [:]
    /// The status each session showed when last observed.
    private var last: [SessionKey: FaceStatus] = [:]

    /// Whether going from `old` to `new` is the person's message arriving: a resting or waiting
    /// session (registry idle or waiting) starts working.
    static func excites(from old: FaceStatus, to new: FaceStatus) -> Bool {
        guard new == .working else { return false }
        switch old {
        case .idle, .yourTurn, .justFinished, .needsInput: return true
        case .working, .ended: return false
        }
    }

    /// Records the status a row shows now. Returns true when the token was bumped.
    @discardableResult
    mutating func observe(key: SessionKey, status: FaceStatus) -> Bool {
        let previous = last[key]
        last[key] = status
        guard let previous, Self.excites(from: previous, to: status) else { return false }
        tokens[key, default: 0] += 1
        return true
    }

    /// The current token of a session (0 until it ever got excited).
    func token(for key: SessionKey) -> Int {
        tokens[key] ?? 0
    }

    /// Forgets sessions that left the panel.
    mutating func keep(keys: Set<SessionKey>) {
        tokens = tokens.filter { keys.contains($0.key) }
        last = last.filter { keys.contains($0.key) }
    }
}
