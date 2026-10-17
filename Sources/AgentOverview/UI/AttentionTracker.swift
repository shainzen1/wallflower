import Foundation

/// The rule behind the attention hop: a face hops once each time its session enters needs
/// input, never for a session that is already waiting when first seen (launch, or a row that
/// appears waiting). Pure value, owned by `PanelModel`.
struct AttentionTracker: Equatable, Sendable {
    /// The hop token per session; the face hops when its token changes.
    private(set) var tokens: [SessionKey: Int] = [:]
    /// Whether each session was in needs input when last observed.
    private var waiting: [SessionKey: Bool] = [:]

    /// Records the status a row shows now. Returns true when the token was bumped (entered needs input).
    @discardableResult
    mutating func observe(key: SessionKey, status: FaceStatus) -> Bool {
        let isWaiting = status.isNeedsInput
        let wasWaiting = waiting[key]
        waiting[key] = isWaiting
        guard let wasWaiting, !wasWaiting, isWaiting else { return false }
        tokens[key, default: 0] += 1
        return true
    }

    /// The current token of a session (0 until it ever hopped).
    func token(for key: SessionKey) -> Int {
        tokens[key] ?? 0
    }

    /// Forgets sessions that left the panel.
    mutating func keep(keys: Set<SessionKey>) {
        tokens = tokens.filter { keys.contains($0.key) }
        waiting = waiting.filter { keys.contains($0.key) }
    }
}
