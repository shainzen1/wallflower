import AppKit
import Foundation
import Testing
@testable import AgentOverview

/// Auto-hide: which states rest hidden in which mode, the sequencing of reveal, hold and hide
/// (`AutoHideController` with fake pointer and window), the edge trigger's place, and the setting.
@Suite("Auto-hide: the rule per mode, reveal and hide, the edge trigger, the setting")
@MainActor
struct AutoHideTests {
    // MARK: The rule

    @Test("Never keeps the panel out; when empty hides with no faces (the button alone counts as empty); always hides unless a session needs input")
    func restRules() {
        for sessions in 0...2 {
            for actions in 0...1 {
                for needsInput in [false, true] where !(needsInput && sessions == 0) {
                    let empty = sessions == 0 && actions == 0
                    #expect(!PanelAutoHide.never.restsHidden(sessions: sessions, actions: actions, needsInput: needsInput))
                    #expect(PanelAutoHide.empty.restsHidden(sessions: sessions, actions: actions, needsInput: needsInput) == empty)
                    #expect(PanelAutoHide.always.restsHidden(sessions: sessions, actions: actions, needsInput: needsInput) == !needsInput)
                }
            }
        }
        #expect(PanelAutoHide.default == .empty)
        #expect(PanelAutoHide.never.footnote == nil && PanelAutoHide.empty.footnote != nil && PanelAutoHide.always.footnote != nil)
        #expect(PanelAutoHide.allCases.map(\.title) == ["Never", "When nothing is running", "Always"])
    }

    // MARK: Sequencing

    /// A controller wired to a fake window: the applied states, the pointer and the monitors.
    @MainActor
    final class Rig {
        let controller: AutoHideController
        var applied: [(concealed: Bool, animated: Bool)] = []
        var pointerOnPanel = false
        var buttonDown = false
        var watching = false

        init(mode: PanelAutoHide, delay: TimeInterval = 0.05, linger: TimeInterval = 0.1) {
            controller = AutoHideController(mode: mode)
            controller.hideDelay = delay
            controller.lingerDelay = linger
            controller.setConcealed = { [unowned self] in self.applied.append(($0, $1)) }
            controller.pointerIsOnPanel = { [unowned self] in self.pointerOnPanel }
            controller.isButtonDown = { [unowned self] in self.buttonDown }
            controller.watchPointer = { [unowned self] in self.watching = $0 }
        }

        var concealed: Bool? { applied.last?.concealed }
    }

    @Test("At launch the first state applies without animation; a face arriving slides the panel out, animated")
    func launchAndArrival() async {
        let rig = Rig(mode: .empty)
        rig.controller.update(sessions: 0, actions: 0, needsInput: false)
        #expect(rig.applied.count == 1 && rig.applied[0] == (true, false))
        rig.controller.update(sessions: 1, actions: 0, needsInput: false)
        #expect(rig.applied.count == 2 && rig.applied[1] == (false, true))
        // Never: out at launch, and nothing to watch.
        let never = Rig(mode: .never)
        never.controller.update(sessions: 0, actions: 0, needsInput: false)
        #expect(never.applied.count == 1 && never.applied[0] == (false, false) && !never.watching)
    }

    @Test("The edge brings it out, held by the pointer: it stays while the pointer is on it and slides away after the delay once it left")
    func edgeRevealAndHide() async {
        let rig = Rig(mode: .empty)
        rig.controller.update(sessions: 0, actions: 0, needsInput: false)
        rig.pointerOnPanel = true
        rig.controller.edgeReached()
        #expect(rig.concealed == false && rig.watching && rig.controller.isHeldByPointer)
        try? await Task.sleep(for: .milliseconds(150))
        #expect(rig.concealed == false, "on the panel it stays")
        // A drag or a throw past the window's edge: still out while the button is down.
        rig.pointerOnPanel = false
        rig.buttonDown = true
        rig.controller.pointerChanged()
        try? await Task.sleep(for: .milliseconds(150))
        #expect(rig.concealed == false, "a press holds it")
        rig.buttonDown = false
        rig.controller.pointerChanged()
        #expect(await TestSupport.waitUntil(timeout: 1) { rig.concealed == true })
        #expect(!rig.watching && !rig.controller.isHeldByPointer)
        #expect(rig.applied.last?.animated == true)
    }

    @Test("Back on the panel before the delay ran out: it stays")
    func pointerComesBack() async {
        let rig = Rig(mode: .always, delay: 0.15)
        rig.controller.update(sessions: 2, actions: 0, needsInput: false)
        rig.controller.edgeReached()
        rig.controller.pointerChanged()
        try? await Task.sleep(for: .milliseconds(50))
        rig.pointerOnPanel = true
        rig.controller.pointerChanged()
        try? await Task.sleep(for: .milliseconds(250))
        #expect(rig.concealed == false)
    }

    @Test("The edge does nothing while the panel is out anyway or the mode keeps it out")
    func edgeIgnoredWhenShown() {
        let rig = Rig(mode: .empty)
        rig.controller.update(sessions: 1, actions: 0, needsInput: false)
        rig.controller.edgeReached()
        #expect(!rig.watching && rig.applied.count == 1)
    }

    @Test("When the last face leaves, the panel lingers, then slides away; with the pointer on it, only after the pointer left")
    func lingerAfterLastFace() async {
        let rig = Rig(mode: .empty, delay: 0.05, linger: 0.2)
        rig.controller.update(sessions: 1, actions: 0, needsInput: false)
        rig.controller.update(sessions: 0, actions: 0, needsInput: false)
        #expect(rig.concealed == false && rig.watching)
        try? await Task.sleep(for: .milliseconds(80))
        #expect(rig.concealed == false, "still lingering")
        #expect(await TestSupport.waitUntil(timeout: 1) { rig.concealed == true })

        let held = Rig(mode: .empty, delay: 0.05, linger: 0.05)
        held.pointerOnPanel = true
        held.controller.update(sessions: 1, actions: 0, needsInput: false)
        held.controller.update(sessions: 0, actions: 0, needsInput: false)
        try? await Task.sleep(for: .milliseconds(200))
        #expect(held.concealed == false)
        held.pointerOnPanel = false
        held.controller.pointerChanged()
        #expect(await TestSupport.waitUntil(timeout: 1) { held.concealed == true })
    }

    @Test("Always: a session that needs input brings the panel out and keeps it out; once answered it lingers and goes")
    func attentionInAlways() async {
        let rig = Rig(mode: .always, delay: 0.05, linger: 0.1)
        rig.controller.update(sessions: 2, actions: 1, needsInput: false)
        #expect(rig.concealed == true)
        rig.controller.update(sessions: 2, actions: 1, needsInput: true)
        #expect(rig.concealed == false && !rig.watching)
        try? await Task.sleep(for: .milliseconds(200))
        #expect(rig.concealed == false, "out while it waits")
        rig.controller.update(sessions: 2, actions: 1, needsInput: false)
        #expect(rig.concealed == false)
        #expect(await TestSupport.waitUntil(timeout: 1) { rig.concealed == true })
    }

    @Test("A face arriving while the pointer holds the panel out ends the hold; a mode change applies at once")
    func arrivalAndModeChange() async {
        let rig = Rig(mode: .empty)
        rig.controller.update(sessions: 0, actions: 0, needsInput: false)
        rig.controller.edgeReached()
        #expect(rig.watching)
        rig.controller.update(sessions: 1, actions: 0, needsInput: false)
        #expect(!rig.watching && rig.concealed == false)
        try? await Task.sleep(for: .milliseconds(150))
        #expect(rig.concealed == false)
        rig.controller.mode = .always
        #expect(rig.concealed == false && rig.watching, "out, lingering, when the mode turns to hide it")
        #expect(await TestSupport.waitUntil(timeout: 1) { rig.concealed == true })
        rig.controller.mode = .never
        #expect(rig.concealed == false && rig.applied.last?.animated == true)
    }

    @Test("The welcome window pins the panel out; closing it lets the panel go after the linger")
    func welcomePin() async {
        let rig = Rig(mode: .empty, linger: 0.05)
        rig.controller.update(sessions: 0, actions: 0, needsInput: false)
        rig.controller.setPinned(true)
        #expect(rig.concealed == false)
        try? await Task.sleep(for: .milliseconds(150))
        #expect(rig.concealed == false)
        rig.controller.setPinned(false)
        #expect(await TestSupport.waitUntil(timeout: 1) { rig.concealed == true })
    }

    // MARK: Edge trigger

    @Test("The edge trigger: a strip on the panel's edge, in its band, on either side")
    func triggerFrame() {
        let screen = NSRect(x: 0, y: 0, width: 2560, height: 1440)
        let panel = NSRect(x: 2492, y: 430, width: 68, height: 80)
        #expect(EdgeTriggerPlacement.frame(panelFrame: panel, screenFrame: screen, side: .right, width: 2) == NSRect(x: 2558, y: 430, width: 2, height: 80))
        let left = NSRect(x: 0, y: 300, width: 68, height: 146)
        #expect(EdgeTriggerPlacement.frame(panelFrame: left, screenFrame: screen, side: .left, width: 6) == NSRect(x: 0, y: 300, width: 6, height: 146))
        // A secondary screen whose origin is not 0.
        let second = NSRect(x: -1512, y: 0, width: 1512, height: 982)
        #expect(EdgeTriggerPlacement.frame(panelFrame: panel, screenFrame: second, side: .left, width: 2).minX == -1512)
        #expect(EdgeTriggerPlacement.width(sharesEdge: false) == Theme.autoHideTriggerWidth)
        #expect(EdgeTriggerPlacement.width(sharesEdge: true) == Theme.autoHideSharedEdgeTriggerWidth)
        #expect(Theme.autoHideSharedEdgeTriggerWidth > Theme.autoHideTriggerWidth)
    }

    @Test("A shared edge: another display beside the panel's edge, overlapping its band")
    func sharedEdge() {
        let main = NSRect(x: 0, y: 0, width: 2560, height: 1440)
        let laptopLeft = NSRect(x: -1512, y: 0, width: 1512, height: 982)
        let band = NSRect(x: 0, y: 430, width: 68, height: 80)
        #expect(EdgeTriggerPlacement.sharesEdge(screenFrame: main, side: .left, band: band, otherScreens: [laptopLeft]))
        #expect(!EdgeTriggerPlacement.sharesEdge(screenFrame: main, side: .right, band: band, otherScreens: [laptopLeft]))
        // Above the neighbour's top: the edge is outer in the band.
        let high = NSRect(x: 0, y: 1100, width: 68, height: 80)
        #expect(!EdgeTriggerPlacement.sharesEdge(screenFrame: main, side: .left, band: high, otherScreens: [laptopLeft]))
        let right = NSRect(x: 2560, y: 200, width: 1920, height: 1080)
        #expect(EdgeTriggerPlacement.sharesEdge(screenFrame: main, side: .right, band: band, otherScreens: [right]))
        // A display above the main one shares no side edge.
        let above = NSRect(x: 0, y: 1440, width: 2560, height: 1440)
        #expect(!EdgeTriggerPlacement.sharesEdge(screenFrame: main, side: .right, band: band, otherScreens: [above]))
        #expect(!EdgeTriggerPlacement.sharesEdge(screenFrame: main, side: .right, band: band, otherScreens: []))
    }

    @Test("The trigger's dwell is short and the slide is a short ease-out; the hide waits longer than the dwell")
    func timings() {
        #expect(Theme.autoHideDwell >= 0.1 && Theme.autoHideDwell <= 0.3)
        #expect(Theme.autoHideSlideDuration >= 0.25 && Theme.autoHideSlideDuration <= 0.3)
        #expect(Theme.autoHideDelay > Theme.autoHideDwell && Theme.autoHideLinger > Theme.autoHideDelay)
        // Ease-out: the curve's first control point rises faster than it advances.
        let curve = Theme.autoHideSlideCurve
        #expect(curve.1 > curve.0 && curve.3 >= curve.2)
    }

    // MARK: Setting

    @Test("The setting round-trips: stored, read back, set by key, overridden by --autohide without being written")
    func settingRoundTrip() {
        let name = "AutoHideTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }

        let settings = AppSettings(defaults: defaults)
        #expect(settings.panelAutoHide == .empty)
        settings.panelAutoHide = .always
        #expect(defaults.string(forKey: AppSettings.Key.panelAutoHide) == "always")
        #expect(AppSettings(defaults: defaults).panelAutoHide == .always)
        #expect(settings.setValue("never", forKey: "panelAutoHide"))
        #expect(settings.panelAutoHide == .never)
        #expect(!settings.setValue("sometimes", forKey: "panelAutoHide"))

        let arguments = LaunchArguments(["Wallflower", "--autohide", "always"])
        #expect(arguments.panelAutoHide == .always)
        #expect(AppSettings(defaults: defaults, overrides: arguments.settingsOverrides).panelAutoHide == .always)
        #expect(defaults.string(forKey: "panelAutoHide") == "never", "a launch argument is never written back")
        #expect(LaunchArguments(["Wallflower", "--autohide", "empty"]).panelAutoHide == .empty)
        #expect(LaunchArguments(["Wallflower", "--autohide", "maybe"]).panelAutoHide == nil)
        #expect(LaunchArguments(["Wallflower", "--gesture-script", "wait:10;edge"]).gestureScript == [.wait(0.01), .edge])

        settings.restoreAppearanceDefaults()
        #expect(settings.panelAutoHide == .never, "not an appearance value: Restore defaults leaves it")
    }
}
