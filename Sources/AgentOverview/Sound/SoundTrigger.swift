import Foundation

/// The two moments that play a sound. Ordered by urgency: needs input wins when both come at once.
enum SoundEvent: Int, Comparable, Sendable, CaseIterable {
    /// A turn ended: the session went from working to idle (your turn).
    case done
    /// The session started waiting for the person (a question or a permission prompt).
    case needsInput

    static func < (lhs: SoundEvent, rhs: SoundEvent) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var name: String {
        switch self {
        case .done: "done"
        case .needsInput: "needsInput"
        }
    }

    /// The event a state change is, nil for any other change. Working to idle is done (the turn
    /// ended; a prompt dismissed without an answer is not); anything else to needs input is needs
    /// input. A change within needs input (a question, then a permission prompt) is no new event.
    static func event(from old: SessionState, to new: SessionState) -> SoundEvent? {
        switch new {
        case .needsInput: old.isNeedsInput ? nil : .needsInput
        case .idle: old == .working ? .done : nil
        case .working: nil
        }
    }
}

/// Where a session's app is, for "Not while the agent's app is in front": derived from the route a
/// click takes (`SessionOpener.route(for:)`), so it knows exactly what a click knows. A session that
/// opens a URL or runs a command has no known app; the check is then skipped rather than guessed.
enum SoundHost: Equatable, Sendable {
    /// The app with this bundle id (the Claude app, or an external session's `open.app`).
    case bundle(String)
    /// The regular app hosting this process (`ProcessAncestry.hostApplication(of:)`).
    case process(pid_t)
    case unknown

    init(route: SessionOpener.Route) {
        switch route {
        case .claudeDeepLink, .claudeApp: self = .bundle(SessionOpener.claudeBundleIdentifier)
        case .hostApp(let pid, _): self = .process(pid)
        case .app(let bundleID): self = .bundle(bundleID)
        case .url, .command, .nothing: self = .unknown
        }
    }
}

/// The rule behind the sounds: which of a batch of state changes play, and how often. Pure value with
/// the clock passed in, owned by `SoundController`.
///
/// A change plays when its switch is on, its session is not hidden, and (with `skipsFrontmost`) its
/// app is not known to be frontmost. Of the changes that pass, the most urgent one plays, unless a
/// sound already played less than `window` ago: several transitions within that window play one sound.
struct SoundAnnouncer: Sendable {
    struct Options: Equatable, Sendable {
        var onDone = Theme.soundOnDone
        var onNeedsInput = Theme.soundOnNeedsInput
        var skipsFrontmost = Theme.soundSkipsFrontmost

        func allows(_ event: SoundEvent) -> Bool {
            switch event {
            case .done: onDone
            case .needsInput: onNeedsInput
            }
        }
    }

    /// One session's change as the announcer weighs it.
    struct Candidate: Equatable, Sendable {
        var event: SoundEvent
        /// The person threw the session out of the capsule.
        var isHidden = false
        /// Whether the session's app is frontmost; nil when its app is not known.
        var hostIsFrontmost: Bool?
    }

    var window: TimeInterval = Theme.soundCollapseWindow
    /// When the last sound played.
    private(set) var lastPlayed: Date?

    /// Whether a candidate may play at all, before collapsing.
    static func passes(_ candidate: Candidate, options: Options) -> Bool {
        guard options.allows(candidate.event), !candidate.isHidden else { return false }
        return !(options.skipsFrontmost && candidate.hostIsFrontmost == true)
    }

    /// The event to play for one batch of changes seen at `now`, nil for silence. Records the sound.
    mutating func announce(_ candidates: [Candidate], options: Options, at now: Date) -> SoundEvent? {
        guard let event = candidates.filter({ Self.passes($0, options: options) }).map(\.event).max() else { return nil }
        if let lastPlayed, now.timeIntervalSince(lastPlayed) < window, now >= lastPlayed { return nil }
        lastPlayed = now
        return event
    }
}
