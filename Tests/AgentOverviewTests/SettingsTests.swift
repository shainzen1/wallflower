import Foundation
import Testing
@testable import AgentOverview

/// A fresh `UserDefaults` suite per test, removed afterwards.
private final class ScratchDefaults {
    let name = "WallflowerTests-\(UUID().uuidString)"
    let defaults: UserDefaults

    init() {
        defaults = UserDefaults(suiteName: name)!
    }

    deinit {
        defaults.removePersistentDomain(forName: name)
    }
}

@MainActor
struct SettingsPrecedenceTests {
    @Test func themeDefaultsWithNothingStored() {
        let scratch = ScratchDefaults()
        let settings = AppSettings(defaults: scratch.defaults)
        #expect(settings.look == PanelLook.themeDefault)
        #expect(settings.sessionSource == .desktop)
        #expect(settings.actionLauncher == Theme.actionLauncher)
        #expect(settings.hasCompletedOnboarding == false)
        #expect(settings.isAppearanceDefault)
    }

    @Test func storedValueBeatsThemeDefault() {
        let scratch = ScratchDefaults()
        scratch.defaults.set("dotMatrix", forKey: AppSettings.Key.faceStyle)
        scratch.defaults.set("all", forKey: AppSettings.Key.expandMode)
        scratch.defaults.set("everywhere", forKey: AppSettings.Key.sessionSource)
        let settings = AppSettings(defaults: scratch.defaults)
        #expect(settings.faceStyle == .dotMatrix)
        #expect(settings.expandMode == .all)
        #expect(settings.sessionSource == .everywhere)
        #expect(!settings.isAppearanceDefault)
    }

    @Test func launchArgumentBeatsStoredValueAndIsNotWritten() {
        let scratch = ScratchDefaults()
        scratch.defaults.set("dotMatrix", forKey: AppSettings.Key.faceStyle)
        scratch.defaults.set("terminal", forKey: AppSettings.Key.sessionSource)
        let overrides = AppSettings.Overrides(sessionSource: .everywhere, faceStyle: .blob, gooRenderer: .path)
        let settings = AppSettings(defaults: scratch.defaults, overrides: overrides)
        #expect(settings.faceStyle == .blob)
        #expect(settings.sessionSource == .everywhere)
        #expect(settings.gooRenderer == .path)
        // The override is for this run only.
        #expect(scratch.defaults.string(forKey: AppSettings.Key.faceStyle) == "dotMatrix")
        #expect(scratch.defaults.string(forKey: AppSettings.Key.sessionSource) == "terminal")
    }

    @Test func unknownStoredValueFallsBackToTheme() {
        let scratch = ScratchDefaults()
        scratch.defaults.set("sparkles", forKey: AppSettings.Key.faceFilter)
        let settings = AppSettings(defaults: scratch.defaults)
        #expect(settings.faceFilter == Theme.faceFilter)
    }

    @Test func settingAValueStoresIt() {
        let scratch = ScratchDefaults()
        let settings = AppSettings(defaults: scratch.defaults)
        settings.colorMode = .status
        settings.blobShapeMode = .identity
        settings.actionLauncher = .deepLinkAndSend
        let reread = AppSettings(defaults: scratch.defaults)
        #expect(reread.colorMode == .status)
        #expect(reread.blobShapeMode == .identity)
        #expect(reread.actionLauncher == .deepLinkAndSend)
    }

    @Test func restoreDefaultsClearsStoredAppearance() {
        let scratch = ScratchDefaults()
        let settings = AppSettings(defaults: scratch.defaults)
        settings.faceStyle = .dotMatrix
        settings.faceFilter = .scanlines
        settings.hoverEffect = .none
        settings.sessionSource = .terminal
        settings.restoreAppearanceDefaults()
        #expect(settings.isAppearanceDefault)
        for key in AppSettings.Key.appearance {
            #expect(scratch.defaults.object(forKey: key) == nil)
        }
        // Not an appearance value: kept.
        #expect(settings.sessionSource == .terminal)
        #expect(AppSettings(defaults: scratch.defaults).sessionSource == .terminal)
    }

    @Test func setValueByKeyAndName() {
        let scratch = ScratchDefaults()
        let settings = AppSettings(defaults: scratch.defaults)
        #expect(settings.setValue("halftone", forKey: AppSettings.Key.faceFilter))
        #expect(settings.faceFilter == .halftone)
        #expect(settings.setValue("terminal", forKey: AppSettings.Key.sessionSource))
        #expect(settings.sessionSource == .terminal)
        #expect(!settings.setValue("nope", forKey: AppSettings.Key.faceFilter))
        #expect(!settings.setValue("blob", forKey: "unknownKey"))
        #expect(settings.faceFilter == .halftone)
    }

    @Test func onboardingFlagPersists() {
        let scratch = ScratchDefaults()
        let settings = AppSettings(defaults: scratch.defaults)
        #expect(!settings.hasCompletedOnboarding)
        settings.hasCompletedOnboarding = true
        #expect(AppSettings(defaults: scratch.defaults).hasCompletedOnboarding)
    }

    @Test func lookAppliesToFaceLook() {
        let saved = (FaceLook.style, FaceLook.filter, FaceLook.blobShapeMode, FaceLook.colorMode, FaceLook.hoverEffect)
        defer { (FaceLook.style, FaceLook.filter, FaceLook.blobShapeMode, FaceLook.colorMode, FaceLook.hoverEffect) = saved }
        var look = PanelLook.themeDefault
        look.faceStyle = .dotMatrix
        look.faceFilter = .asciiGrid
        look.colorMode = .identity
        look.hoverEffect = .stretch
        look.applyToFaceLook()
        #expect(FaceLook.style == .dotMatrix)
        #expect(FaceLook.filter == .asciiGrid)
        #expect(FaceLook.colorMode == .identity)
        #expect(FaceLook.hoverEffect == .stretch)
    }
}

struct SessionSourceTests {
    @Test func entrypointMapping() {
        #expect(SessionSource.desktop.entrypoints == ["claude-desktop"])
        #expect(SessionSource.terminal.entrypoints == ["cli", "sdk-cli", "claude-vscode"])
        #expect(SessionSource.everywhere.entrypoints == nil)
        #expect(DataTuning.defaultEntrypoints == SessionSource.desktop.entrypoints)
    }

    @Test func storedNamesRoundTrip() {
        for source in SessionSource.allCases { #expect(SessionSource(storedName: source.storedName) == source) }
        for style in FaceStyle.allCases { #expect(FaceStyle(storedName: style.storedName) == style) }
        for filter in FaceFilter.allCases { #expect(FaceFilter(storedName: filter.storedName) == filter) }
        for mode in Theme.ColorMode.allCases { #expect(Theme.ColorMode(storedName: mode.storedName) == mode) }
        for effect in Theme.HoverEffect.allCases { #expect(Theme.HoverEffect(storedName: effect.storedName) == effect) }
        for mode in Theme.BlobShapeMode.storedChoices { #expect(Theme.BlobShapeMode(storedName: mode.storedName) == mode) }
        for mode in Theme.ExpandMode.storedChoices { #expect(Theme.ExpandMode(storedName: mode.storedName) == mode) }
        for renderer in Theme.GooRenderer.storedChoices { #expect(Theme.GooRenderer(storedName: renderer.storedName) == renderer) }
        for launcher in Theme.ActionLauncher.storedChoices { #expect(Theme.ActionLauncher(storedName: launcher.storedName) == launcher) }
        #expect(Theme.ExpandMode(storedName: "sideways") == nil)
    }

    @Test func storeFiltersByTheSourcesEntrypoints() throws {
        let folder = try TestSupport.makeTempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        try TestSupport.writeFixture("busy-desktop", to: folder, pid: TestSupport.livePid)
        let desktop = SessionRegistryScanner.scan(folder: folder, entrypoints: SessionSource.desktop.entrypoints)
        let terminal = SessionRegistryScanner.scan(folder: folder, entrypoints: SessionSource.terminal.entrypoints)
        let everywhere = SessionRegistryScanner.scan(folder: folder, entrypoints: SessionSource.everywhere.entrypoints)
        #expect(desktop.records.count == 1)
        #expect(terminal.records.isEmpty)
        #expect(everywhere.records.count == 1)
    }
}

struct SettingsLaunchArgumentTests {
    @Test func overridesFromArguments() {
        let arguments = LaunchArguments([
            "app", "--session-source", "terminal", "--face-style", "dotMatrix", "--expand", "all",
            "--goo", "path", "--blob-shape", "identity", "--action-launcher", "deepLinkAndSend",
        ])
        let overrides = arguments.settingsOverrides
        #expect(overrides.sessionSource == .terminal)
        #expect(overrides.faceStyle == .dotMatrix)
        #expect(overrides.expandMode == .all)
        #expect(overrides.gooRenderer == .path)
        #expect(overrides.blobShapeMode == .identity)
        #expect(overrides.actionLauncher == .deepLinkAndSend)
        #expect(overrides.faceFilter == nil)
    }

    @Test func windowsAndScriptedSettings() {
        let arguments = LaunchArguments([
            "app", "--show-settings", "appearance", "--welcome", "3", "--no-welcome",
            "--set", "colorMode=status", "--set", "faceFilter=halftone", "--defaults-suite", "check",
        ])
        #expect(arguments.showSettings == .appearance)
        #expect(arguments.welcomePage == 3)
        #expect(arguments.noWelcome)
        #expect(arguments.scriptedSettings.map(\.key) == ["colorMode", "faceFilter"])
        #expect(arguments.scriptedSettings.map(\.value) == ["status", "halftone"])
        #expect(arguments.defaultsSuite == "check")
        #expect(LaunchArguments(["app", "--welcome", "9"]).welcomePage == nil)
        #expect(LaunchArguments(["app", "--settings-scroll", "400"]).settingsScroll == 400)
        #expect(LaunchArguments(["app", "--settings-scroll", "far"]).settingsScroll == nil)
    }

    @Test func snapshotTargets() {
        #expect(LaunchArguments.SnapshotWindow("panel") == .panel)
        #expect(LaunchArguments.SnapshotWindow("settings-about") == .settings(.about))
        #expect(LaunchArguments.SnapshotWindow("welcome-4") == .welcome(page: 4))
        #expect(LaunchArguments.SnapshotWindow("welcome-6") == .welcome(page: 6))
        #expect(LaunchArguments.SnapshotWindow("welcome-7") == nil)
        #expect(LaunchArguments.SnapshotWindow("settings-agents") == .settings(.agents))
        #expect(LaunchArguments.SnapshotWindow("menu-glyph") == .menuGlyph)
        #expect(LaunchArguments.SnapshotWindow("settings-nope") == nil)
        #expect(LaunchArguments.SnapshotWindow.settings(.general).method == .view)
        #expect(LaunchArguments.SnapshotWindow.panel.method == .layer)
    }
}

struct AboutTests {
    @Test func donateButtonIsNamedAfterThePage() throws {
        func title(_ string: String) throws -> String {
            AboutSettingsView.sponsorTitle(for: try #require(URL(string: string)))
        }
        #expect(try title("https://buymeacoffee.com/demo") == "Buy me a coffee")
        #expect(try title("https://www.buymeacoffee.com/demo") == "Buy me a coffee")
        #expect(try title("https://github.com/sponsors/demo") == "Sponsor on GitHub")
        #expect(try title("https://ko-fi.com/demo") == "Support on Ko-fi")
        #expect(try title("https://example.com/donate") == "Support \(AppInfo.name)")
    }

    @Test func theCreditLinksAreWebAddresses() {
        #expect(AppInfo.authorName == "Shain Gerstner")
        #expect(AppInfo.authorGitHubURL.scheme == "https")
        #expect(AppInfo.authorGitHubURL.host() == "github.com")
        #expect(AppInfo.authorGitHubURL.path() == "/shainzen1")
        #expect(AppInfo.studioName == "osoro.studio")
        #expect(AppInfo.studioURL.scheme == "https")
        #expect(AppInfo.studioURL.host() == AppInfo.studioName)
        for url in [AppInfo.repositoryURL, AppInfo.sponsorURL].compactMap(\.self) {
            #expect(url.scheme == "https")
        }
    }

    @Test func theCoffeeButtonShowsBeforeThePageExists() throws {
        // Disabled placeholder in debug builds, left out of a release published without a page.
        #expect(AboutSettingsView.showsSponsorButton(url: nil, placeholder: true))
        #expect(!AboutSettingsView.showsSponsorButton(url: nil, placeholder: false))
        #expect(AboutSettingsView.showsSponsorButton(url: URL(string: "https://buymeacoffee.com/demo"), placeholder: false))
        #expect(AboutSettingsView.showsSponsorPlaceholder)  // `swift test` builds debug

        #expect(AboutSettingsView.sponsorTitle(for: nil as URL?) == "Buy me a coffee")
        #expect(AboutSettingsView.sponsorSymbol(for: nil) == "cup.and.saucer.fill")
        #expect(AboutSettingsView.sponsorHelp(for: nil) == "Set in release builds")

        let coffee = try #require(URL(string: "https://buymeacoffee.com/demo"))
        #expect(AboutSettingsView.sponsorTitle(for: Optional(coffee)) == "Buy me a coffee")
        #expect(AboutSettingsView.sponsorSymbol(for: coffee) == "cup.and.saucer.fill")
        #expect(AboutSettingsView.sponsorHelp(for: coffee) == "buymeacoffee.com/demo")
        #expect(AboutSettingsView.sponsorSymbol(for: URL(string: "https://ko-fi.com/demo")) == "cup.and.saucer.fill")
        #expect(AboutSettingsView.sponsorSymbol(for: URL(string: "https://github.com/sponsors/demo")) == "heart.fill")
        #expect(AboutSettingsView.sponsorSymbol(for: URL(string: "https://example.com/donate")) == "heart.fill")
    }

    @Test func linkTooltipsDropTheSchemeAndTrailingSlash() throws {
        func help(_ string: String) throws -> String {
            AboutSettingsView.linkHelp(for: try #require(URL(string: string)))
        }
        #expect(try help("https://github.com/demo") == "github.com/demo")
        #expect(try help("https://osoro.studio/") == "osoro.studio")
        #expect(try help("http://example.com/a/") == "example.com/a")
        #expect(AboutSettingsView.linkHelp(for: AppInfo.authorGitHubURL) == "github.com/shainzen1")
        #expect(AboutSettingsView.linkHelp(for: AppInfo.studioURL) == "osoro.studio")
    }
}

@MainActor
struct LaunchAtLoginTests {
    @Test func aBareBuildNeverRegistersAndExplainsWhy() {
        // The test runner is no app bundle, like `swift run` and the debug binary.
        #expect(!LaunchAtLogin.isAvailable)
        let login = LaunchAtLogin()
        #expect(!login.set(true))
        #expect(login.note == LaunchAtLogin.moveNote)
        #expect(LaunchAtLogin.moveNote == "Move \(AppInfo.name) to Applications to launch at login.")
    }

    @Test func onlyAnUnmovedAppBundleRegisters() {
        #expect(LaunchAtLogin.isRegistrable(bundleURL: URL(filePath: "/Applications/Wallflower.app")))
        #expect(LaunchAtLogin.isRegistrable(bundleURL: URL(filePath: "/Users/demo/Applications/Wallflower.app")))
        #expect(!LaunchAtLogin.isRegistrable(bundleURL: URL(filePath: "/Users/demo/Developer/wallflower/.build/debug")))
        #expect(!LaunchAtLogin.isRegistrable(
            bundleURL: URL(filePath: "/private/var/folders/xy/abc/T/AppTranslocation/0F3A9C1E-2B4D-4E5F-8A6B-7C8D9E0F1A2B/d/Wallflower.app")
        ), "a quarantined download run from Downloads is translocated")
    }
}

/// The Settings window fits a 13-inch display: a tab taller than the cap scrolls instead.
@MainActor
struct SettingsWindowHeightTests {
    @Test func theCapIsFixedOnALargeScreenAndShrinksOnASmallOne() {
        let cap = SettingsWindowController.maxContentHeight
        #expect(SettingsTabViewController.maxContentHeight(visibleScreenHeight: 1_400, chrome: 90) == cap)
        // 1440 x 900 at default scaling, menu bar and Dock taken: still the full cap.
        #expect(SettingsTabViewController.maxContentHeight(visibleScreenHeight: 800, chrome: 90) == cap)
        // A shorter screen: what is left after the chrome and a margin top and bottom.
        #expect(SettingsTabViewController.maxContentHeight(visibleScreenHeight: 600, chrome: 90) == 600 - 90 - 2 * SettingsWindowController.screenMargin)
        #expect(SettingsTabViewController.maxContentHeight(visibleScreenHeight: 100, chrome: 90) == 200, "never collapses")
    }

    @Test func theAgentsTabWithEveryAgentFoundStaysUnderTheCap() throws {
        let suite = "SettingsWindowHeight-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let home = FileManager.default.temporaryDirectory.appending(path: "SettingsWindowHeight-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: home) }
        for folder in [".codex", ".gemini/tmp", ".cursor", ".copilot", ".config/opencode", ".codeium/windsurf", ".config/goose", ".config/devin", ".config/amp", ".kiro"] {
            try FileManager.default.createDirectory(at: home.appending(path: folder), withIntermediateDirectories: true)
        }
        let settings = AppSettings(defaults: defaults)
        let agents = AgentsModel(environment: .fixture(home: home), settings: settings)
        let controller = SettingsWindowController(
            settings: settings, launchAtLogin: LaunchAtLogin(), actions: SettingsActions(), agents: agents, tab: .agents
        )
        let window = try #require(controller.window)
        defer { window.close() }
        window.layoutIfNeeded()
        let height = window.contentLayoutRect.height
        #expect(height <= SettingsWindowController.maxContentHeight + 0.5)
        #expect(height >= SettingsTabViewController.maxContentHeight(in: window) - 0.5, "taller than the cap: the window is at the cap and the tab scrolls")
    }
}
