import Foundation

/// When the person last opened each session's chat (a row click). An idle period that began
/// before its acknowledgement is no longer "your turn" (`IdleTier.tier`). Pure value, owned by
/// `PanelModel`, pruned with the other per-session state when sessions leave.
struct Acknowledgements: Equatable, Sendable {
    private(set) var times: [SessionKey: Date] = [:]

    var isEmpty: Bool { times.isEmpty }

    /// The last acknowledgement of a session, nil if the person never opened it from the panel.
    func time(for key: SessionKey) -> Date? {
        times[key]
    }

    /// The person opened the session's chat at `date`.
    mutating func acknowledge(key: SessionKey, at date: Date) {
        times[key] = date
    }

    /// The same acknowledgements without the sessions that left the panel.
    func keeping(keys: Set<SessionKey>) -> Acknowledgements {
        var kept = self
        kept.times = times.filter { keys.contains($0.key) }
        return kept
    }
}
