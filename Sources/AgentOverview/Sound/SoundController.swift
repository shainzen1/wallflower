import AppKit
import Observation
import os

/// Plays the notification sound when a session is done or needs input (Settings > Sound). Listens
/// to the session store's state changes (`SessionStore.onStateChanges`), so only real transitions
/// count, never the states a scan finds; weighs them with `SoundAnnouncer`; plays through one cached
/// `SoundPlayer`. Nothing runs between events.
///
/// Focus (Do Not Disturb) is not followed: the one public way to read it, `INFocusStatusCenter`,
/// needs the Communication Notifications entitlement and the person's permission.
@Observable @MainActor
final class SoundController {
    static let log = Logger(subsystem: AppInfo.bundleIdentifier, category: "sound")

    @ObservationIgnored let settings: AppSettings
    /// Why the last custom file was refused, shown in Settings until another one is chosen.
    private(set) var problem: CustomSound.Problem?
    /// Where the custom sound's copy lives (`--sounds-folder`, else `SoundLibrary.defaultFolder`).
    let folder: URL
    /// The sessions thrown out of the capsule: their changes play nothing.
    @ObservationIgnored var hiddenSessions: HiddenSessions?

    @ObservationIgnored private var announcer = SoundAnnouncer()
    @ObservationIgnored private let player = SoundPlayer()
    @ObservationIgnored private let now: () -> Date

    init(settings: AppSettings, folder: URL, now: @escaping () -> Date = Date.init) {
        self.settings = settings
        self.folder = folder
        self.now = now
    }

    /// Listens to `store`'s state changes (a replaced store is watched anew).
    func watch(_ store: SessionStore) {
        store.onStateChanges = { [weak self] changes in self?.handle(changes) }
    }

    /// One scan's changes: the sound for the most urgent one that passes, if any. Returns the event
    /// that sounded (nil for silence), whether or not a file played.
    @discardableResult
    func handle(_ changes: [SessionStateChange]) -> SoundEvent? {
        let options = settings.soundOptions
        let candidates = changes.compactMap { change -> SoundAnnouncer.Candidate? in
            guard let event = SoundEvent.event(from: change.from, to: change.to), options.allows(event) else { return nil }
            let hidden = hiddenSessions?.contains(change.session) ?? false
            // Only looked up when it matters: a walk up the process tree for a terminal session.
            let frontmost = options.skipsFrontmost && !hidden ? hostIsFrontmost(change.session) : nil
            return SoundAnnouncer.Candidate(event: event, isHidden: hidden, hostIsFrontmost: frontmost)
        }
        guard !candidates.isEmpty else { return nil }
        guard let event = announcer.announce(candidates, options: options, at: now()) else {
            Self.log.notice("sound: \(candidates.count, privacy: .public) change(s) stayed quiet (hidden, app in front, or within the collapse window)")
            return nil
        }
        let played = play()
        Self.log.notice("sound: \(event.name, privacy: .public) (\(played ? "played" : "silent", privacy: .public))")
        return event
    }

    /// Plays the chosen sound at the chosen volume (Preview, `--play-sound`). Returns whether it played.
    @discardableResult
    func play() -> Bool {
        guard settings.soundVolume > 0,
              let url = SoundLibrary.url(for: settings.sound, customName: settings.customSoundName, folder: folder) else { return false }
        return player.play(url, volume: settings.soundVolume)
    }

    /// Copies a custom file into the sounds folder and makes it the sound. Returns the problem when
    /// the file was refused (the previous sound then stays).
    @discardableResult
    func installCustomSound(from url: URL) -> CustomSound.Problem? {
        do {
            let name = try CustomSound.install(url, into: folder)
            player.invalidate()
            settings.customSoundName = name
            settings.sound = .custom
            problem = nil
            Self.log.notice("sound: custom file installed")
            return nil
        } catch {
            Self.log.notice("sound: custom file refused: \(error.message, privacy: .public)")
            problem = error
            return error
        }
    }

    /// Whether the session's app is frontmost; nil when Wallflower does not know its app.
    private func hostIsFrontmost(_ session: Session) -> Bool? {
        guard let front = NSWorkspace.shared.frontmostApplication else { return nil }
        switch SoundHost(route: SessionOpener.route(for: SessionRow(session: session))) {
        case .bundle(let bundleID):
            return front.bundleIdentifier == bundleID
        case .process(let pid):
            guard let app = ProcessAncestry.hostApplication(of: pid) else { return nil }
            return app.processIdentifier == front.processIdentifier
        case .unknown:
            return nil
        }
    }
}
