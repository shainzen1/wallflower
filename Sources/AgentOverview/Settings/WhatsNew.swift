import Foundation

/// What Settings > What's New shows for the running version: its notes, and the versions before it.
struct WhatsNewContent: Equatable, Sendable {
    /// The running version (`AppInfo.version`).
    var version: String
    /// The running version's notes, nil when the changelog has none (a bare build has no changelog).
    var current: ReleaseNotes?
    /// The released versions before it, newest first.
    var earlier: [ReleaseNotes]

    /// The running version's section. Without one, a version newer than every release takes the
    /// [Unreleased] section, as `scripts/appcast.sh` does: a maintainer's build after
    /// `bump-version.sh` still has its notes there (publish.sh renames the section only in the export).
    init(version: String, releases: [ReleaseNotes]) {
        self.version = version
        let running = AppVersion(version)
        let released = releases.filter { !$0.isUnreleased && !$0.isEmpty && AppVersion($0.version) != nil }
        if let running, let match = released.first(where: { AppVersion($0.version) == running }) {
            current = match
        } else if let running, let unreleased = releases.first(where: { $0.isUnreleased && !$0.isEmpty }),
                  released.allSatisfy({ AppVersion($0.version)! < running }) {
            current = ReleaseNotes(version: version, date: nil, intro: unreleased.intro, groups: unreleased.groups)
        } else {
            current = nil
        }
        earlier = released.filter { release in
            guard let running else { return true }
            return AppVersion(release.version)! < running
        }
    }
}

/// When Settings opens on What's New by itself: once, on the first launch after the version went up.
/// `AppSettings.lastSeenVersion` holds the version of the last launch.
enum WhatsNewLaunch {
    struct Decision: Equatable {
        /// Open Settings on What's New now.
        var opens: Bool
        /// Store this as the last seen version (nil: leave it).
        var record: String?
    }

    /// - Parameters:
    ///   - lastSeen: the version the last launch recorded, nil before the first.
    ///   - current: the running version; one that is not a version ("dev", a bare build) is left alone.
    ///   - hasCompletedOnboarding: the welcome was finished once. With no version recorded it tells an
    ///     update from a version before this existed (open) from a fresh install (the welcome's turn:
    ///     record only). Not finished, the welcome shows again, and What's New waits for the next update.
    ///   - hasNotes: the changelog has notes for `current`; without them there is nothing to show.
    static func decide(lastSeen: String?, current: String, hasCompletedOnboarding: Bool, hasNotes: Bool) -> Decision {
        guard let running = AppVersion(current) else { return Decision(opens: false, record: nil) }
        guard let lastSeen else {
            return Decision(opens: hasCompletedOnboarding && hasNotes, record: current)
        }
        guard let previous = AppVersion(lastSeen) else {
            return Decision(opens: hasCompletedOnboarding && hasNotes, record: current)
        }
        if running == previous { return Decision(opens: false, record: nil) }
        // A downgrade only records: the older version has nothing new to tell.
        return Decision(opens: running > previous && hasCompletedOnboarding && hasNotes, record: current)
    }
}
