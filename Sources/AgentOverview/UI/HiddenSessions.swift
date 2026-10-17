import Foundation
import Observation

/// The sessions the person threw out of the capsule: no longer watched, persisted across launches.
///
/// Stored in the given defaults under `hiddenSessionPids` (the name predates external sessions) as an
/// array of dictionaries, one per session: `pid` for a Claude session or `external` (the file's id)
/// for a session from another tool, and, when known, `startedAt` (epoch milliseconds). A pid alone
/// would hide whatever process reuses it later; with `startedAt` only that very session matches.
/// Entries whose session left the registry are pruned (`prune(keeping:otherKeys:keepsExternal:)`,
/// `PanelModel` calls it on every change of the session list once the first scan is in), so the list
/// never grows stale. Sessions of the other session sources stay hidden while they live, so switching
/// the source and back keeps them hidden.
@Observable @MainActor
final class HiddenSessions {
    /// Defaults key of the list.
    static let key = "hiddenSessionPids"

    struct Entry: Equatable, Sendable {
        var key: SessionKey
        /// The session's start, epoch milliseconds; nil matches any session with this key.
        var startedAt: Int?

        /// Whether this entry hides the session `key` started at `startedAt` (epoch milliseconds).
        func matches(key: SessionKey, startedAt: Int) -> Bool {
            self.key == key && (self.startedAt == nil || self.startedAt == startedAt)
        }
    }

    private(set) var entries: [Entry]
    @ObservationIgnored let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        entries = Self.load(from: defaults)
    }

    var count: Int { entries.count }

    /// Epoch milliseconds of a date, as the registry writes `startedAt`.
    nonisolated static func milliseconds(_ date: Date) -> Int {
        Int((date.timeIntervalSince1970 * 1000).rounded())
    }

    func contains(key: SessionKey, startedAt: Date) -> Bool {
        let ms = Self.milliseconds(startedAt)
        return entries.contains { $0.matches(key: key, startedAt: ms) }
    }

    func contains(_ session: Session) -> Bool {
        contains(key: session.key, startedAt: session.startedAt)
    }

    /// Stops watching the session `key` that started at `startedAt` (nil: any session with this key).
    func hide(key: SessionKey, startedAt: Date?) {
        let entry = Entry(key: key, startedAt: startedAt.map(Self.milliseconds))
        guard !entries.contains(entry) else { return }
        entries.removeAll { $0.key == key }
        entries.append(entry)
        save()
    }

    func hide(_ session: Session) {
        hide(key: session.key, startedAt: session.startedAt)
    }

    /// Watches every session again.
    func clear() {
        guard !entries.isEmpty else { return }
        entries = []
        save()
    }

    /// Drops the entries that match none of `sessions` (key and start): the session ended and left
    /// the registry, or its pid now belongs to another session. Entries whose key is in `otherKeys`
    /// stay: live sessions the caller only knows by key (another session source's). With
    /// `keepsExternal` every external entry stays: the store does not watch those sessions at all.
    func prune(keeping sessions: [(key: SessionKey, startedAt: Date)], otherKeys: Set<SessionKey> = [], keepsExternal: Bool = false) {
        let live = sessions.map { ($0.key, Self.milliseconds($0.startedAt)) }
        let kept = entries.filter { entry in
            (keepsExternal && !entry.key.isClaude) || otherKeys.contains(entry.key)
                || live.contains { entry.matches(key: $0.0, startedAt: $0.1) }
        }
        guard kept != entries else { return }
        entries = kept
        save()
    }

    // MARK: Storage

    private func save() {
        let list: [[String: Any]] = entries.map { entry in
            var item: [String: Any]
            switch entry.key {
            case .claude(let pid): item = ["pid": Int(pid)]
            case .external(let id): item = ["external": id]
            }
            if let startedAt = entry.startedAt { item["startedAt"] = startedAt }
            return item
        }
        defaults.set(list, forKey: Self.key)
    }

    /// The stored list; anything that is not a dictionary with an integer `pid` or a string
    /// `external` is skipped.
    private static func load(from defaults: UserDefaults) -> [Entry] {
        guard let list = defaults.array(forKey: key) else { return [] }
        return list.compactMap { item in
            guard let item = item as? [String: Any] else { return nil }
            let startedAt = (item["startedAt"] as? NSNumber)?.intValue
            if let pid = (item["pid"] as? NSNumber)?.int32Value { return Entry(key: .claude(pid), startedAt: startedAt) }
            if let id = item["external"] as? String, !id.isEmpty { return Entry(key: .external(id), startedAt: startedAt) }
            return nil
        }
    }
}
