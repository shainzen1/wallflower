import Foundation
import Testing
@testable import AgentOverview

/// The repository root, from this file's path.
private let repositoryRoot = URL(filePath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

/// A base64 Ed25519 public key shape: 32 bytes.
private let sampleKey = Data(repeating: 7, count: 32).base64EncodedString()

@Suite("Updates: Info.plist")
struct UpdaterInfoPlistTests {
    private func info() throws -> [String: Any] {
        let data = try Data(contentsOf: repositoryRoot.appending(path: "Packaging/Info.plist"))
        return try #require(try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
    }

    @Test func sparkleSettings() throws {
        let info = try info()
        #expect(info["SUFeedURL"] as? String == "https://github.com/shainzen1/wallflower/releases/latest/download/appcast.xml")
        #expect(info["SUEnableAutomaticChecks"] as? Bool == true, "checks without asking first")
        #expect(info["SUScheduledCheckInterval"] as? Int == 604_800, "once a week")
        #expect(info["SUEnableSystemProfiling"] as? Bool == false, "no system profile")
        #expect(info["SUAutomaticallyUpdate"] as? Bool == false, "the person confirms every install")
        #expect(info["SUVerifyUpdateBeforeExtraction"] as? Bool == true)
        #expect(info["CFBundleIdentifier"] as? String == AppInfo.bundleIdentifier)
    }

    /// The repo carries the placeholder until the maintainer pastes the real key; either is fine
    /// here, anything else (a typo, a private key) is not.
    @Test func publicKeyIsThePlaceholderOrARealKey() throws {
        let key = try #require(try info()["SUPublicEDKey"] as? String)
        #expect(key == AppUpdater.publicKeyPlaceholder || AppUpdater.hasPublicKey(["SUPublicEDKey": key]))
    }
}

@Suite("Updates: updater")
@MainActor
struct UpdaterTests {
    @Test func publicKeyCheck() {
        #expect(AppUpdater.hasPublicKey(["SUPublicEDKey": sampleKey]))
        #expect(!AppUpdater.hasPublicKey(["SUPublicEDKey": AppUpdater.publicKeyPlaceholder]))
        #expect(!AppUpdater.hasPublicKey(nil))
        #expect(!AppUpdater.hasPublicKey([:]))
        #expect(!AppUpdater.hasPublicKey(["SUPublicEDKey": "not base64!"]))
        #expect(!AppUpdater.hasPublicKey(["SUPublicEDKey": Data(count: 64).base64EncodedString()]), "a private key is 64 bytes")
    }

    /// Neither case creates Sparkle's updater, so nothing is written to the test runner's defaults.
    @Test func offWithoutStartOrKey() {
        let scripted = AppUpdater(start: false, info: ["SUPublicEDKey": sampleKey])
        #expect(scripted.offReason == .scriptedLaunch && !scripted.isRunning && !scripted.canCheckForUpdates)
        let unsigned = AppUpdater(start: true, info: ["SUPublicEDKey": AppUpdater.publicKeyPlaceholder])
        #expect(unsigned.offReason == .noPublicKey && !unsigned.isRunning)
        unsigned.checkForUpdates()
        unsigned.setAutomaticallyChecks(true)
        #expect(!unsigned.automaticallyChecks, "inert while off")
    }

    @Test func texts() {
        #expect(AppUpdater.menuTitle(pendingVersion: nil) == "Check for Updates…")
        #expect(AppUpdater.menuTitle(pendingVersion: "0.1.2") == "Install Wallflower 0.1.2…")
        #expect(AppUpdater.lastCheckText(nil, offReason: nil) == "Never checked")
        #expect(AppUpdater.lastCheckText(Date(), offReason: nil).hasPrefix("Last checked "))
        #expect(AppUpdater.lastCheckText(Date(), offReason: .scriptedLaunch) == "Updates are off in this launch")
        #expect(AppUpdater.lastCheckText(nil, offReason: .noPublicKey) == "Updates are off in this build")
        #expect(GeneralSettingsView.updatesFootnote.contains("GitHub"))
    }

    @Test func launchArguments() {
        #expect(LaunchArguments(["app"]).runsUpdater, "on in a normal launch")
        #expect(!LaunchArguments(["app", "--defaults-suite", "check"]).runsUpdater, "off in a scripted one")
        #expect(LaunchArguments(["app", "--defaults-suite", "check", "--updates", "on"]).runsUpdater)
        #expect(!LaunchArguments(["app", "--updates", "off"]).runsUpdater)
        #expect(LaunchArguments(["app", "--check-for-updates", "ui"]).checkForUpdates == .ui)
        #expect(LaunchArguments(["app", "--check-for-updates", "background"]).checkForUpdates == .background)
        #expect(LaunchArguments(["app", "--check-for-updates", "later"]).checkForUpdates == nil)
        #expect(LaunchArguments(["app", "--defaults-suite", "check", "--fake-pending-update", "1.4"]).pendingUpdateOverride == "1.4")
        #expect(LaunchArguments(["app", "--fake-pending-update", "1.4"]).pendingUpdateOverride == nil, "only in a scripted launch")
    }

    /// The green glyph and "Install Wallflower 1.4…" share `pendingVersion`: they show from the find
    /// until the person installs (the relaunch ends the process) or skips it.
    @Test func pendingVersionLifecycle() {
        func after(_ events: [AppUpdater.UpdateEvent], from start: String? = nil) -> String? {
            events.reduce(start) { AppUpdater.pendingVersion(after: $1, current: $0) }
        }
        #expect(after([.found("1.4")]) == "1.4")
        #expect(after([.found("1.4"), .chose(.later)]) == "1.4", "Remind Me Later keeps it")
        #expect(after([.found("1.4"), .chose(.install)]) == "1.4", "a failed install leaves it waiting")
        #expect(after([.found("1.4"), .chose(.skip)]) == nil)
        #expect(after([.found("1.4"), .upToDate]) == nil)
        #expect(after([.found("1.4"), .found("1.5")]) == "1.5")
        #expect(after([.chose(.later)]) == nil)
        #expect(after([.found("1.4"), .chose(.skip), .found("1.5"), .chose(.later)]) == "1.5")
    }

    /// A scripted launch with `--fake-pending-update` starts with the version waiting, updater off.
    @Test func fakePendingVersion() {
        let updater = AppUpdater(start: false, fakePendingVersion: "1.4")
        #expect(updater.pendingVersion == "1.4" && !updater.isRunning)
        #expect(AppUpdater.menuTitle(pendingVersion: updater.pendingVersion) == "Install Wallflower 1.4…")
        #expect(AppUpdater(start: false).pendingVersion == nil)
    }
}
