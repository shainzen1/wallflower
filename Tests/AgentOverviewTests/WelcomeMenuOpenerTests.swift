import AppKit
import Foundation
import Testing
@testable import AgentOverview

@MainActor
struct WelcomeModelTests {
    @Test func stepsThroughThePages() {
        let model = WelcomeModel(sessionSource: .desktop)
        #expect(model.page == 1)
        #expect(model.isFirstPage)
        #expect(model.primaryTitle == "Next")
        model.primary()
        #expect(model.page == 2)
        #expect(model.movesForward)
        model.back()
        #expect(model.page == 1)
        #expect(!model.movesForward)
        model.back()
        #expect(model.page == 1)
        model.go(to: 99)
        #expect(model.page == WelcomeModel.pageCount)
        #expect(model.isLastPage)
        #expect(model.primaryTitle == "Start")
    }

    @Test func startReportsTheChoicesOnce() {
        let model = WelcomeModel(page: WelcomeModel.pageCount, sessionSource: .desktop)
        var outcomes: [WelcomeModel.Outcome] = []
        model.onFinish = { outcomes.append($0) }
        model.sessionSource = .everywhere
        model.launchAtLogin = false
        model.primary()
        // The window's close after "Start" is no dismissal.
        model.finish(.dismissed)
        #expect(outcomes == [.started(source: .everywhere, launchAtLogin: false)])
    }

    @Test func dismissalCountsAsDone() {
        let model = WelcomeModel(page: 2, sessionSource: .terminal)
        var outcomes: [WelcomeModel.Outcome] = []
        model.onFinish = { outcomes.append($0) }
        model.finish(.dismissed)
        model.primary()
        #expect(outcomes == [.dismissed])
    }

    @Test func launchAtLoginDefaultsOn() {
        #expect(WelcomeModel(sessionSource: .desktop).launchAtLogin)
    }

    @Test func rerunKeepsLaunchAtLoginAsTheSystemHasIt() {
        #expect(WelcomeModel.initialLaunchAtLogin(hasCompletedOnboarding: false, isEnabled: false), "first launch: on")
        #expect(!WelcomeModel.initialLaunchAtLogin(hasCompletedOnboarding: true, isEnabled: false), "turned off since: stays off")
        #expect(WelcomeModel.initialLaunchAtLogin(hasCompletedOnboarding: true, isEnabled: true))

        let model = WelcomeModel(page: WelcomeModel.pageCount, sessionSource: .desktop, launchAtLogin: false)
        var outcomes: [WelcomeModel.Outcome] = []
        model.onFinish = { outcomes.append($0) }
        model.primary()
        #expect(outcomes == [.started(source: .desktop, launchAtLogin: false)], "Start does not turn it back on")
    }

    @Test func noSessionsHintFollowsTheChosenSource() {
        let model = WelcomeModel(sessionSource: .desktop) { source in source == .everywhere ? 2 : 0 }
        #expect(model.showsNoSessionsHint)
        model.sessionSource = .everywhere
        #expect(!model.showsNoSessionsHint)
    }

    @Test func pageArgumentIsClamped() {
        #expect(WelcomeModel(page: 0, sessionSource: .desktop).page == 1)
        #expect(WelcomeModel(page: 7, sessionSource: .desktop).page == WelcomeModel.pageCount)
    }
}

struct MenuStatusTests {
    @Test @MainActor func statusLine() {
        #expect(MenuBar.statusText(sessionCount: 0, needsInputCount: 0) == "No sessions")
        #expect(MenuBar.statusText(sessionCount: 1, needsInputCount: 0) == "1 session")
        #expect(MenuBar.statusText(sessionCount: 3, needsInputCount: 0) == "3 sessions")
        #expect(MenuBar.statusText(sessionCount: 3, needsInputCount: 1) == "3 sessions · 1 needs you")
        #expect(MenuBar.statusText(sessionCount: 4, needsInputCount: 2) == "4 sessions · 2 need you")
        #expect(MenuBar.statusText(sessionCount: 1, needsInputCount: 1) == "1 session · 1 needs you")
    }

    @Test func glyphFollowsNeedsInput() {
        #expect(MenuBarIcon.glyph(needsInputCount: 0) == .calm)
        #expect(MenuBarIcon.glyph(needsInputCount: 2) == .needsYou)
        #expect(MenuBarIcon.Glyph.calm.shape == Theme.blobIdleShape)
        #expect(MenuBarIcon.Glyph.needsYou.shape == Theme.blobNeedsInputShape)
    }

    @Test func glyphSitsOnWholePointsInsideTheImage() {
        let rect = CGRect(origin: .zero, size: MenuBarIcon.size)
        for glyph in MenuBarIcon.Glyph.allCases {
            let box = MenuBarIcon.path(glyph, in: rect).boundingBoxOfPath
            #expect(rect.contains(box))
            // The body's top and bottom land on whole points (crisp at 1x).
            #expect(abs(box.minY - box.minY.rounded()) < 0.01)
            #expect(abs(box.maxY - box.maxY.rounded()) < 0.01)
        }
        let image = MenuBarIcon.image(.calm)
        #expect(image.isTemplate)
        #expect(image.size == MenuBarIcon.size)
    }

    @Test func updateTintsTheGlyph() {
        for glyph in MenuBarIcon.Glyph.allCases {
            let image = MenuBarIcon.image(glyph, pendingUpdate: "1.4")
            #expect(!image.isTemplate, "coloured, not tinted by the bar")
            #expect(image.size == MenuBarIcon.size)
            #expect(image.accessibilityDescription?.hasSuffix("update 1.4 ready to install") == true)
        }
        #expect(MenuBarIcon.State(glyph: .calm).accessibilityDescription == "Wallflower")
        #expect(MenuBarIcon.State(glyph: .needsYou, pendingUpdate: "1.4").accessibilityDescription
            == "Wallflower, a session needs you, update 1.4 ready to install")
        #expect(MenuBarIcon.State(glyph: .calm, pendingUpdate: "1.4") != MenuBarIcon.State(glyph: .calm), "a new update redraws")
        #expect(MenuBarIcon.updateInk(darkBar: true) == Theme.emeraldColor.cgColor)
    }

    /// The green follows the appearance the glyph is drawn in: the emerald on a dark bar, the deeper
    /// green on a light one, from one image (the bar changes with the wallpaper, the image stays).
    @Test @MainActor func updateGreenFollowsTheBar() throws {
        let image = MenuBarIcon.image(.calm, pendingUpdate: "1.4")
        func centre(in name: NSAppearance.Name) throws -> NSColor {
            let rep = try #require(NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: 18, pixelsHigh: 18, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
            ))
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
            try #require(NSAppearance(named: name)).performAsCurrentDrawingAppearance {
                image.draw(in: CGRect(origin: .zero, size: MenuBarIcon.size))
            }
            NSGraphicsContext.restoreGraphicsState()
            // Below the eyes, inside the body.
            return try #require(rep.colorAt(x: 9, y: 13)?.usingColorSpace(.sRGB))
        }
        let dark = try centre(in: .vibrantDark)
        let light = try centre(in: .vibrantLight)
        let darkAgain = try centre(in: .darkAqua)
        let emerald = Theme.emeraldColor
        let deep = emerald.dimmed(MenuBarIcon.lightBarUpdateDim)
        #expect(dark.alphaComponent > 0.99 && light.alphaComponent > 0.99)
        #expect(abs(dark.greenComponent - emerald.green) < 0.03 && abs(dark.redComponent - emerald.red) < 0.03)
        #expect(abs(light.greenComponent - deep.green) < 0.03 && abs(light.blueComponent - deep.blue) < 0.03)
        #expect(abs(darkAgain.greenComponent - emerald.green) < 0.03, "not stuck on the first appearance")
    }
}

struct ProcessAncestryTests {
    /// claude (500) -> zsh (400) -> login (300) -> Terminal (200) -> launchd (1).
    private let terminalChain: [pid_t: pid_t] = [500: 400, 400: 300, 300: 200, 200: 1]

    @Test func findsTheFirstAppAncestor() {
        let found = ProcessAncestry.firstAncestor(of: 500, parent: { terminalChain[$0] }, isApp: { $0 == 200 })
        #expect(found == 200)
    }

    @Test func skipsHelpersThatAreNotRegularApps() {
        // claude (50) -> node (40, extension host) -> Code Helper (30) -> Code (20) -> launchd.
        let chain: [pid_t: pid_t] = [50: 40, 40: 30, 30: 20, 20: 1]
        let regularApps: Set<pid_t> = [20]
        #expect(ProcessAncestry.firstAncestor(of: 50, parent: { chain[$0] }, isApp: { regularApps.contains($0) }) == 20)
    }

    @Test func theSessionProcessItselfIsNotItsHost() {
        #expect(ProcessAncestry.firstAncestor(of: 200, parent: { terminalChain[$0] }, isApp: { $0 == 200 }) == nil)
    }

    @Test func stopsAtLaunchdAndAtUnknownProcesses() {
        // A detached tmux server: its parent is launchd.
        #expect(ProcessAncestry.firstAncestor(of: 500, parent: { terminalChain[$0] }, isApp: { _ in false }) == nil)
        #expect(ProcessAncestry.firstAncestor(of: 77, parent: { _ in nil }, isApp: { _ in true }) == nil)
    }

    @Test func survivesACycle() {
        let cycle: [pid_t: pid_t] = [10: 11, 11: 10]
        var steps = 0
        let found = ProcessAncestry.firstAncestor(of: 10, parent: { steps += 1; return cycle[$0] }, isApp: { _ in false })
        #expect(found == nil)
        #expect(steps <= ProcessAncestry.maxDepth)
    }

    @Test func realParentOfThisProcess() {
        let me = ProcessInfo.processInfo.processIdentifier
        #expect(ProcessAncestry.parentPid(of: me) == getppid())
        #expect(ProcessAncestry.parentPid(of: TestSupport.deadPid) == nil)
    }
}

struct SessionOpenerTests {
    private func row(hostSessionId: String?, entrypoint: String) -> SessionRow {
        SessionRow(pid: 42, name: "Fix flaky tests", status: .working, stateSince: Date(), hostSessionId: hostSessionId, ended: false, entrypoint: entrypoint)
    }

    @Test func desktopSessionWithIdOpensTheChat() {
        let desktop = row(hostSessionId: "local_abc", entrypoint: "claude-desktop")
        #expect(SessionOpener.deepLink(for: desktop)?.absoluteString == "claude://code/continue?session=local_abc")
        #expect(!SessionOpener.opensHostApp(desktop))
    }

    @Test func terminalSessionLooksForItsApp() {
        #expect(SessionOpener.opensHostApp(row(hostSessionId: nil, entrypoint: "cli")))
        #expect(SessionOpener.opensHostApp(row(hostSessionId: "", entrypoint: "claude-vscode")))
        #expect(SessionOpener.deepLink(for: row(hostSessionId: nil, entrypoint: "cli")) == nil)
    }

    @Test func desktopSessionWithoutIdFallsBackToClaude() {
        #expect(!SessionOpener.opensHostApp(row(hostSessionId: nil, entrypoint: "claude-desktop")))
    }
}
