import AppKit
import Foundation
import Testing
@testable import AgentOverview

/// The repository root, from this file's path.
private let repositoryRoot = URL(filePath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

/// A changelog in the repository's shape: Unreleased, two releases, a first release with an intro,
/// link references at the bottom.
private let sample = """
# Changelog

All notable changes are documented here.

## [Unreleased]

### Added

- Something on the way.

## [1.5] - 2026-10-27

### Fixed

- The welcome no longer asks for Codex
  when Codex isn't there.

### Added

- A sound when an agent is done. **Settings > Sound** picks it, `--sound` overrides it.
- A second **new** thing.

## [1.4] - 2026-10-23

### Changed

- Auto-hide slides like the Dock.

### Added

- A green menu bar icon.

### Security

- A safer hook.

### Added

- Another addition, under a repeated heading.

## [0.1.0] - 2026-10-17

The first public release.

### Added

- A capsule with faces. See [docs/agents.md](docs/agents.md) and [Sparkle](https://sparkle-project.org).

[Unreleased]: https://github.com/demo/wallflower/compare/v1.5...HEAD
[1.5]: https://github.com/demo/wallflower/compare/v1.4...v1.5
"""

@Suite("What's New: changelog parser")
struct ReleaseNotesParserTests {
    @Test func readsEverySectionInOrder() {
        let releases = ReleaseNotes.parse(sample)
        #expect(releases.map(\.version) == ["Unreleased", "1.5", "1.4", "0.1.0"])
        #expect(releases.map(\.date) == [nil, "2026-10-27", "2026-10-23", "2026-10-17"])
        #expect(releases[0].isUnreleased && !releases[1].isUnreleased)
    }

    @Test func groupsAreNewImprovedFixedAndContinuationLinesJoin() throws {
        let release = try #require(ReleaseNotes.parse(sample).first { $0.version == "1.5" })
        #expect(release.groups.map(\.kind) == [.new, .fixed], "New before Fixed, whatever the file's order")
        #expect(release.groups[1].items == ["The welcome no longer asks for Codex when Codex isn't there."])
        #expect(release.groups[0].items.count == 2)
        #expect(release.intro.isEmpty)
    }

    @Test func repeatedHeadingsMergeAndOtherHeadingsKeepTheirName() throws {
        let release = try #require(ReleaseNotes.parse(sample).first { $0.version == "1.4" })
        #expect(release.groups.map(\.kind) == [.new, .improved, .other("Security")])
        #expect(release.groups[0].items == ["A green menu bar icon.", "Another addition, under a repeated heading."])
        #expect(release.groups.map(\.kind.title) == ["New", "Improved", "Security"])
    }

    @Test func introParagraphsAndLinkReferences() throws {
        let first = try #require(ReleaseNotes.parse(sample).last)
        #expect(first.intro == ["The first public release."])
        #expect(first.groups.count == 1 && first.groups[0].items.count == 1, "the link references are not entries")
    }

    @Test func headingKinds() {
        #expect(ChangeKind(heading: "Added") == .new)
        #expect(ChangeKind(heading: "Changed") == .improved)
        #expect(ChangeKind(heading: "Fixed") == .fixed)
        #expect(ChangeKind(heading: "Removed") == .removed)
        #expect(ChangeKind(heading: "Deprecated") == .other("Deprecated"))
    }

    @Test func emptyAndOddInput() {
        #expect(ReleaseNotes.parse("").isEmpty)
        #expect(ReleaseNotes.parse("# Changelog\n\nNo sections.").isEmpty)
        let windows = ReleaseNotes.parse("## [1.0] - 2026-01-01\r\n\r\n### Added\r\n\r\n- One.\r\n")
        #expect(windows.first?.groups.first?.items == ["One."])
        #expect(ReleaseNotes.parse("## [Unreleased]\n")[0].isEmpty)
    }

    @Test func releaseDate() throws {
        let release = ReleaseNotes(version: "1.5", date: "2026-10-27")
        let date = try #require(release.releaseDate)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        #expect(calendar.dateComponents([.year, .month, .day], from: date) == DateComponents(year: 2026, month: 10, day: 27))
        #expect(ReleaseNotes(version: "1.5", date: "soon").releaseDate == nil)
        #expect(ReleaseNotes(version: "Unreleased").releaseDate == nil)
    }
}

@Suite("What's New: inline Markdown")
struct ReleaseNotesInlineTests {
    @Test func boldRendersWithoutAsterisks() {
        let text = ReleaseNotes.inline("**Settings > Sound** picks the sound.")
        #expect(String(text.characters) == "Settings > Sound picks the sound.")
        let bold = text.runs.filter { $0.inlinePresentationIntent?.contains(.stronglyEmphasized) == true }
        #expect(bold.count == 1)
        #expect(bold.first.map { String(text[$0.range].characters) } == "Settings > Sound")
    }

    @Test func codeRendersWithoutBackticks() {
        let text = ReleaseNotes.inline("Run `wallflower-hook` once.")
        #expect(String(text.characters) == "Run wallflower-hook once.")
        #expect(text.runs.contains { $0.inlinePresentationIntent?.contains(.code) == true })
    }

    @Test func onlyWebLinksStayLinks() {
        let text = ReleaseNotes.inline("See [docs/agents.md](docs/agents.md) and [Sparkle](https://sparkle-project.org).")
        #expect(String(text.characters) == "See docs/agents.md and Sparkle.")
        #expect(text.runs.compactMap(\.link) == [URL(string: "https://sparkle-project.org")!])
    }

    @Test func plainTextAndStrayAsterisksSurvive() {
        #expect(String(ReleaseNotes.inline("Up to 5 MB and 5 seconds.").characters) == "Up to 5 MB and 5 seconds.")
        #expect(String(ReleaseNotes.inline("A * star").characters) == "A * star")
    }

    /// Every entry of the real changelog renders without Markdown markers (what the app bundles).
    @Test func theRepositoryChangelogRendersClean() throws {
        let text = try String(contentsOf: repositoryRoot.appending(path: "CHANGELOG.md"), encoding: .utf8)
        let releases = ReleaseNotes.parse(text)
        let released = releases.filter { !$0.isUnreleased }
        #expect(released.count >= 5)
        for release in released {
            #expect(AppVersion(release.version) != nil, "\(release.version) is a version")
            #expect(release.releaseDate != nil, "\(release.version) has a date")
            #expect(!release.groups.isEmpty, "\(release.version) has changes")
            for item in release.groups.flatMap(\.items) + release.intro {
                let shown = String(ReleaseNotes.inline(item).characters)
                #expect(!shown.contains("**") && !shown.contains("`"), "raw Markdown in \(release.version): \(shown)")
            }
        }
    }

    @Test func bundleScriptCopiesTheChangelog() throws {
        let script = try String(contentsOf: repositoryRoot.appending(path: "scripts/bundle.sh"), encoding: .utf8)
        #expect(script.contains(#"cp "$ROOT/CHANGELOG.md" "$CONTENTS/Resources/CHANGELOG.md""#))
    }
}

@Suite("What's New: versions")
struct AppVersionTests {
    @Test func comparesPartByPartAsNumbers() throws {
        func version(_ text: String) throws -> AppVersion { try #require(AppVersion(text)) }
        #expect(try version("1.4") > version("0.1.3"))
        #expect(try version("1.5") > version("1.4"))
        #expect(try version("1.10") > version("1.9"))
        #expect(try version("0.2") > version("0.1.9"))
        #expect(try version("1.0") == version("1.0.0"))
        #expect(try version("2") == version("2.0"))
        #expect(try !(version("1.5") < version("1.5")))
        #expect(try version("1.5").description == "1.5")
    }

    @Test func rejectsWhatIsNotAVersion() {
        for text in ["dev", "Unreleased", "", "1.x", "1..2", ".1", "1.", "v1.4", "1.4-beta", "١.٢"] {
            #expect(AppVersion(text) == nil, "\(text)")
        }
    }
}

@Suite("What's New: content")
struct WhatsNewContentTests {
    private let releases = ReleaseNotes.parse(sample)

    @Test func theRunningVersionAndTheOnesBefore() {
        let content = WhatsNewContent(version: "1.5", releases: releases)
        #expect(content.current?.version == "1.5")
        #expect(content.earlier.map(\.version) == ["1.4", "0.1.0"], "never Unreleased")
    }

    @Test func anOlderVersionShowsOnlyWhatCameBefore() {
        let content = WhatsNewContent(version: "1.4", releases: releases)
        #expect(content.current?.version == "1.4")
        #expect(content.earlier.map(\.version) == ["0.1.0"])
    }

    /// A build after bump-version.sh, before publish.sh renamed the section: Unreleased is its notes.
    @Test func aNewerVersionTakesTheUnreleasedSection() {
        let content = WhatsNewContent(version: "1.6", releases: releases)
        #expect(content.current?.version == "1.6")
        #expect(content.current?.date == nil)
        #expect(content.current?.groups.first?.items == ["Something on the way."])
        #expect(content.earlier.map(\.version) == ["1.5", "1.4", "0.1.0"])
    }

    @Test func noNotesForAVersionInBetweenOrABareBuild() {
        #expect(WhatsNewContent(version: "1.4.5", releases: releases).current == nil, "Unreleased is not 1.4.5's")
        let bare = WhatsNewContent(version: "dev", releases: releases)
        #expect(bare.current == nil)
        #expect(bare.earlier.map(\.version) == ["1.5", "1.4", "0.1.0"])
        #expect(WhatsNewContent(version: "1.5", releases: []).current == nil)
    }

    @Test func subtitle() {
        #expect(WhatsNewSettingsView.subtitle(WhatsNewContent(version: "dev", releases: [])) == "Release notes come with the app.")
        #expect(WhatsNewSettingsView.subtitle(WhatsNewContent(version: "1.9", releases: [])) == "No release notes for version 1.9.")
        #expect(WhatsNewSettingsView.subtitle(WhatsNewContent(version: "1.6", releases: releases)) == "Version 1.6, not released yet")
        #expect(WhatsNewSettingsView.subtitle(WhatsNewContent(version: "1.5", releases: releases)).hasPrefix("Released "))
    }
}

@Suite("What's New: after an update")
struct WhatsNewLaunchTests {
    private func decide(_ lastSeen: String?, _ current: String, onboarded: Bool = true, notes: Bool = true) -> WhatsNewLaunch.Decision {
        WhatsNewLaunch.decide(lastSeen: lastSeen, current: current, hasCompletedOnboarding: onboarded, hasNotes: notes)
    }

    @Test func aFreshInstallOnlyRecordsTheVersion() {
        #expect(decide(nil, "1.6", onboarded: false) == .init(opens: false, record: "1.6"))
    }

    @Test func anUpdateOpensOnceAndRecords() {
        #expect(decide("1.5", "1.6") == .init(opens: true, record: "1.6"))
        // The next launch of the same version leaves everything alone.
        #expect(decide("1.6", "1.6") == .init(opens: false, record: nil))
        #expect(decide("1.6.0", "1.6") == .init(opens: false, record: nil), "the same version, written longer")
    }

    /// 1.5 and earlier stored no version: an onboarded Mac without one is an update, not a fresh install.
    @Test func anUpdateFromBeforeVersionsWereRecordedOpens() {
        #expect(decide(nil, "1.6") == .init(opens: true, record: "1.6"))
    }

    @Test func theWelcomeComesFirst() {
        #expect(decide("1.5", "1.6", onboarded: false) == .init(opens: false, record: "1.6"))
    }

    @Test func nothingToShowNothingOpens() {
        #expect(decide("1.5", "1.6", notes: false) == .init(opens: false, record: "1.6"))
    }

    @Test func aDowngradeOnlyRecords() {
        #expect(decide("1.6", "1.5") == .init(opens: false, record: "1.5"))
        #expect(decide("1.5", "1.6") == .init(opens: true, record: "1.6"), "and going up again opens")
    }

    @Test func aTwoPartVersionAfterThreePartOnes() {
        #expect(decide("0.1.3", "1.4") == .init(opens: true, record: "1.4"))
    }

    @Test func aBareBuildIsLeftAlone() {
        #expect(decide("1.5", "dev") == .init(opens: false, record: nil))
        #expect(decide(nil, "dev", onboarded: false) == .init(opens: false, record: nil))
    }

    @Test func anUnreadableStoredVersionCountsAsOlder() {
        #expect(decide("garbage", "1.6") == .init(opens: true, record: "1.6"))
    }
}

@Suite("What's New: settings and launch arguments")
@MainActor
struct WhatsNewSettingsTests {
    @Test func lastSeenVersionIsStoredInTheSuite() throws {
        let suite = "WhatsNewTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults)
        #expect(settings.lastSeenVersion == nil)
        settings.lastSeenVersion = "1.6"
        #expect(defaults.string(forKey: AppSettings.Key.lastSeenVersion) == "1.6")
        #expect(AppSettings(defaults: defaults).lastSeenVersion == "1.6")
    }

    @Test func launchArguments() {
        let plain = LaunchArguments(["app"])
        #expect(!plain.whatsNew && plain.checksWhatsNew, "a normal launch applies the rule")
        let scripted = LaunchArguments(["app", "--defaults-suite", "check"])
        #expect(!scripted.checksWhatsNew, "a scripted launch never opens it on its own")
        #expect(!LaunchArguments(["app", "--snapshot", "/tmp/x.png"]).checksWhatsNew)
        #expect(LaunchArguments(["app", "--defaults-suite", "check", "--whats-new-check"]).checksWhatsNew)
        #expect(LaunchArguments(["app", "--whats-new"]).whatsNew)
        #expect(LaunchArguments(["app", "--show-settings", "whats-new"]).showSettings == .whatsNew)
        #expect(LaunchArguments.SnapshotWindow("settings-whats-new") == .settings(.whatsNew))
    }

    @Test func theTabSitsBeforeAbout() {
        #expect(SettingsTab.allCases == [.general, .appearance, .sound, .agents, .whatsNew, .about])
        #expect(SettingsTab.whatsNew.title == "What's New")
        #expect(NSImage(systemSymbolName: SettingsTab.whatsNew.symbolName, accessibilityDescription: nil) != nil)
    }

    @Test func everyGroupSymbolExists() {
        for kind in [ChangeKind.new, .improved, .fixed, .removed, .other("Security")] {
            #expect(NSImage(systemSymbolName: kind.symbolName, accessibilityDescription: nil) != nil, "\(kind.symbolName)")
        }
    }

    /// The real changelog with the newest earlier version open stays within the window's cap (it scrolls past it).
    @Test func theTabStaysUnderTheCap() throws {
        let suite = "WhatsNewHeight-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let text = try String(contentsOf: repositoryRoot.appending(path: "CHANGELOG.md"), encoding: .utf8)
        let controller = SettingsWindowController(
            settings: AppSettings(defaults: defaults), launchAtLogin: LaunchAtLogin(), actions: SettingsActions(),
            tab: .whatsNew, showsAdvanced: true, releaseNotes: ReleaseNotes.parse(text)
        )
        let window = try #require(controller.window)
        defer { window.close() }
        window.layoutIfNeeded()
        #expect(controller.selectedTab == .whatsNew)
        #expect(window.contentLayoutRect.height <= SettingsWindowController.maxContentHeight + 0.5)
    }
}
