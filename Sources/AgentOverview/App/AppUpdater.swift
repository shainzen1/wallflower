import AppKit
import Observation
import Sparkle

/// In-app updates through Sparkle's standard updater and its standard windows. Sparkle reads its
/// configuration from `Packaging/Info.plist` (feed URL, public EdDSA key, a check about once an hour,
/// Sparkle's minimum, no system profile, no automatic download) and keeps its own state (last check,
/// the person's choice) in the standard defaults. The hourly check is a one-shot timer inside
/// Sparkle, re-armed after each check (and run at launch when the last one is over an hour old), so
/// nothing of ours runs at rest. An update the hourly check finds opens no window: it only turns the
/// menu bar glyph green and renames the menu item (`sparkleShowsUpdateWindow(userInitiated:)`).
///
/// Off for a scripted launch (`--defaults-suite`) unless `--updates on` turns it on: Sparkle would
/// otherwise write its state into the real app's defaults domain and ask the real feed. Off as well
/// in a build without a real public key (the placeholder in the repo, `swift run`), where Sparkle
/// would refuse to start with an alert. The KVO mirrors below keep the menu and Settings current
/// while the updater changes state.
@Observable @MainActor
final class AppUpdater {
    /// Why the updater does not run in this process.
    enum OffReason: Equatable, Sendable {
        /// `--defaults-suite` without `--updates on`, or `--updates off`.
        case scriptedLaunch
        /// `SUPublicEDKey` is missing or still the placeholder.
        case noPublicKey
    }

    /// `SUPublicEDKey` in `Packaging/Info.plist` until the maintainer pastes the real one; the release
    /// scripts refuse to ship it (`scripts/check-update-key.sh`).
    nonisolated static let publicKeyPlaceholder = "PASTE_THE_PUBLIC_KEY_FROM_generate_keys"

    /// Why the updater is off, nil while it runs. Every control shows disabled while it is off.
    let offReason: OffReason?
    var isRunning: Bool { offReason == nil }
    /// Whether a check can start now (false while one is in progress, and when not running).
    private(set) var canCheckForUpdates = false
    /// "Check for updates automatically", Sparkle's `automaticallyChecksForUpdates`.
    private(set) var automaticallyChecks = false
    /// When Sparkle last asked the feed, nil before the first check.
    private(set) var lastCheckDate: Date?
    /// The newer version the last check found, until the person installs or skips it: the menu offers
    /// it and the menu bar glyph turns green. See `pendingVersion(after:current:)` for when it clears.
    private(set) var pendingVersion: String?

    /// What happened to an update, for `pendingVersion(after:current:)`.
    enum UpdateEvent: Equatable, Sendable {
        /// A check, scheduled or "Check for Updates…", found this version (its display version).
        case found(String)
        /// A check found nothing newer: up to date, or the newer version was skipped before.
        case upToDate
        /// The person's choice in Sparkle's update window.
        case chose(Choice)

        enum Choice: Equatable, Sendable {
            case install, skip
            /// "Remind Me Later", or closing the window.
            case later
        }
    }

    @ObservationIgnored private let controller: SPUStandardUpdaterController?
    @ObservationIgnored private let delegate: Delegate
    @ObservationIgnored private var observations: [NSKeyValueObservation] = []

    /// - Parameters:
    ///   - start: whether this launch may run the updater (`LaunchArguments.runsUpdater`).
    ///   - relaunches: whether "Install and Relaunch" opens the new version. A scripted launch says no:
    ///     the relaunched app would come up without its launch arguments, on the real data.
    ///   - info: the bundle's Info.plist, for the public key.
    ///   - fakePendingVersion: start as if a check had found this version (`--fake-pending-update`).
    init(start: Bool, relaunches: Bool = true, info: [String: Any]? = Bundle.main.infoDictionary, fakePendingVersion: String? = nil) {
        delegate = Delegate(relaunches: relaunches)
        pendingVersion = fakePendingVersion
        let reason: OffReason? = !start ? .scriptedLaunch : !Self.hasPublicKey(info) ? .noPublicKey : nil
        offReason = reason
        guard reason == nil else {
            controller = nil
            NSLog("\(AppInfo.name): updates off (%@)", "\(reason!)")
            return
        }
        let controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: delegate, userDriverDelegate: delegate)
        self.controller = controller
        delegate.owner = self
        let updater = controller.updater
        observations = [
            updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
                MainActor.assumeIsolated { self?.canCheckForUpdates = updater.canCheckForUpdates }
            },
            updater.observe(\.automaticallyChecksForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
                MainActor.assumeIsolated { self?.automaticallyChecks = updater.automaticallyChecksForUpdates }
            },
            updater.observe(\.lastUpdateCheckDate, options: [.initial, .new]) { [weak self] updater, _ in
                MainActor.assumeIsolated { self?.lastCheckDate = updater.lastUpdateCheckDate }
            },
        ]
        controller.startUpdater()
    }

    /// "Check for Updates…", "Install Wallflower x…" and "Check Now": Sparkle's own window shows the
    /// result, or the update. While an update the hourly check found waits unseen, Sparkle brings that
    /// update's window up instead of checking again (`showUpdateInFocus`).
    func checkForUpdates() {
        guard let controller else { return }
        // An accessory app's windows open behind the frontmost app unless it is active.
        NSApp.activate()
        controller.checkForUpdates(nil)
    }

    /// A check as the hourly schedule runs it: no window, a find only tints the glyph
    /// (`--check-for-updates background`).
    func checkInBackground() {
        controller?.updater.checkForUpdatesInBackground()
    }

    /// Turns the hourly check on or off (stored by Sparkle as `SUEnableAutomaticChecks`; the interval
    /// itself is never written, so `SUScheduledCheckInterval` in Info.plist stays in charge).
    func setAutomaticallyChecks(_ enabled: Bool) {
        guard let controller else { return }
        controller.updater.automaticallyChecksForUpdates = enabled
        automaticallyChecks = controller.updater.automaticallyChecksForUpdates
    }

    /// The waiting version after `event`. It stays through everything that leaves the update offered:
    /// "Remind Me Later" (Sparkle drops the update then and finds it again at the next hourly check,
    /// which only tints again), merely looking at the window, a failed download, a failed check. An
    /// hourly check that finds the same version changes nothing. Install keeps it too:
    /// the relaunch into the new version ends this process, and if the install fails the update still
    /// waits. It clears when the person skips the version or a check finds nothing newer (the hourly
    /// check counts a skipped version as nothing newer), and a newer find replaces it.
    nonisolated static func pendingVersion(after event: UpdateEvent, current: String?) -> String? {
        switch event {
        case .found(let version): version
        case .upToDate, .chose(.skip): nil
        case .chose(.install), .chose(.later): current
        }
    }

    /// Whether Sparkle opens its update window by itself when a check finds an update: only for a check
    /// the person started ("Check for Updates…", "Check Now"). A scheduled find (the hourly check,
    /// `--check-for-updates background`) leaves the window unshown, even right after launch or when the
    /// Mac is idle, where Sparkle would otherwise bring it to the front; the green glyph and "Install
    /// Wallflower x…" are the only cue until the person clicks. Sparkle keeps that session open, so no
    /// further scheduled check runs (or shows anything) until the person answers the window.
    nonisolated static func sparkleShowsUpdateWindow(userInitiated: Bool) -> Bool {
        userInitiated
    }

    private func record(_ event: UpdateEvent) {
        let new = Self.pendingVersion(after: event, current: pendingVersion)
        // Only a change reaches the observers (the menu bar glyph redraws on it).
        if new != pendingVersion { pendingVersion = new }
    }

    /// The menu item: the waiting update while there is one, else the plain check.
    nonisolated static func menuTitle(pendingVersion: String?) -> String {
        pendingVersion.map { "Install \(AppInfo.name) \($0)…" } ?? "Check for Updates…"
    }

    /// The line next to "Check Now": "Last checked 22 Oct 2026 at 14:05", "Never checked", or why
    /// updates are off.
    nonisolated static func lastCheckText(_ date: Date?, offReason: OffReason?) -> String {
        switch offReason {
        case .scriptedLaunch: return "Updates are off in this launch"
        case .noPublicKey: return "Updates are off in this build"
        case nil: break
        }
        guard let date else { return "Never checked" }
        return "Last checked \(date.formatted(date: .abbreviated, time: .shortened))"
    }

    /// Whether `SUPublicEDKey` is a real Ed25519 public key: base64 of 32 bytes, not the placeholder.
    nonisolated static func hasPublicKey(_ info: [String: Any]?) -> Bool {
        guard let key = info?["SUPublicEDKey"] as? String, key != publicKeyPlaceholder,
              let data = Data(base64Encoded: key) else { return false }
        return data.count == 32
    }

    // MARK: Sparkle delegates

    /// Sparkle's delegates must be `NSObject`s. Logs what the updater does (one line per event, no
    /// personal data) and keeps the gentle reminder: an update a check found shows in the menu and
    /// tints the menu bar glyph until the person installs or skips it (`pendingVersion(after:current:)`).
    @MainActor
    private final class Delegate: NSObject, SPUUpdaterDelegate, @preconcurrency SPUStandardUserDriverDelegate {
        let relaunches: Bool
        weak var owner: AppUpdater?

        init(relaunches: Bool) {
            self.relaunches = relaunches
        }

        func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
            NSLog("\(AppInfo.name): update found: %@ (build %@)", item.displayVersionString, item.versionString)
            owner?.record(.found(item.displayVersionString))
        }

        func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
            NSLog("\(AppInfo.name): update check: up to date")
            owner?.record(.upToDate)
        }

        func updater(_ updater: SPUUpdater, userDidMake choice: SPUUserUpdateChoice, forUpdate updateItem: SUAppcastItem, state: SPUUserUpdateState) {
            let made: UpdateEvent.Choice = switch choice {
            case .install: .install
            case .skip: .skip
            default: .later
            }
            NSLog("\(AppInfo.name): update %@: %@", updateItem.displayVersionString, "\(made)")
            owner?.record(.chose(made))
        }

        func updater(_ updater: SPUUpdater, didDownloadUpdate item: SUAppcastItem) {
            NSLog("\(AppInfo.name): update downloaded: %@", item.displayVersionString)
        }

        func updater(_ updater: SPUUpdater, willInstallUpdate item: SUAppcastItem) {
            NSLog("\(AppInfo.name): installing update %@", item.displayVersionString)
        }

        func updater(_ updater: SPUUpdater, didAbortWithError error: any Error) {
            // "You're up to date" arrives here too; `updaterDidNotFindUpdate` has logged it.
            let error = error as NSError
            guard error.domain != SUSparkleErrorDomain || error.code != Int(SUError.noUpdateError.rawValue) else { return }
            NSLog("\(AppInfo.name): update check stopped: %@", error.localizedDescription)
        }

        func updaterShouldRelaunchApplication(_ updater: SPUUpdater) -> Bool {
            if !relaunches { NSLog("\(AppInfo.name): update installs without a relaunch (scripted launch)") }
            return relaunches
        }

        var supportsGentleScheduledUpdateReminders: Bool { true }

        /// Asked only for scheduled checks: the window stays unshown (`sparkleShowsUpdateWindow`).
        func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool) -> Bool {
            AppUpdater.sparkleShowsUpdateWindow(userInitiated: false)
        }

        /// The gentle reminder's entry point, for every find: the same version `didFindValidUpdate`
        /// recorded (no second change). For a scheduled find Sparkle shows nothing; the menu item
        /// brings the window up through `checkForUpdates()`. Neither looking at the window nor the end of
        /// the session clears it (see `pendingVersion(after:current:)`).
        func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
            if !handleShowingUpdate { NSLog("\(AppInfo.name): update %@ waits in the menu", update.displayVersionString) }
            owner?.record(.found(update.displayVersionString))
        }
    }
}
