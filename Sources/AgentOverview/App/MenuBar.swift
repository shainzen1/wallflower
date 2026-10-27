import AppKit
import Observation

/// The status item: the blob glyph (`MenuBarIcon`, the drop while a session needs input, green while
/// an update waits) and the app menu. The menu is rebuilt each time it opens: a status line, the
/// sessions themselves (click opens one like the panel does), panel visibility and position,
/// Settings, the update check, What's New, the welcome, Quit.
///
/// The glyph follows the sessions and the updater: `observe()` tracks `Actions.needsInputCount`
/// (whatever it reads, the store's sessions and their states) and `Actions.pendingUpdate` (the
/// updater's waiting version, green while there is one), and redraws the image only when the
/// aggregate (any session needs input, which update waits) changes. No timers. `AppDelegate` calls
/// `observe()` again whenever the source of the rows changed (the store or the panel model was replaced).
@MainActor
final class MenuBar: NSObject, NSMenuDelegate {
    /// What the menu items do. `AppDelegate` fills it in.
    struct Actions {
        /// The sessions the panel shows, in its order (read when the menu opens).
        var rows: () -> [SessionRow] = { [] }
        /// Shown sessions waiting for input (read under observation: the glyph follows it).
        var needsInputCount: () -> Int = { 0 }
        var openSession: (SessionRow) -> Void = { _ in }
        /// Sessions thrown out of the panel; "Show hidden sessions (n)" appears while there are any.
        var hiddenCount: () -> Int = { 0 }
        var showHiddenSessions: () -> Void = {}
        var togglePanel: () -> Void = {}
        var isPanelVisible: () -> Bool = { true }
        var resetPosition: () -> Void = {}
        var openSettings: () -> Void = {}
        var showWelcome: () -> Void = {}
        /// Settings on What's New.
        var showWhatsNew: () -> Void = {}
        /// "Check for Updates…", or the update a check found (`AppUpdater.menuTitle`).
        var updateTitle: () -> String = { AppUpdater.menuTitle(pendingVersion: nil) }
        /// The update waiting to be installed (read under observation: the glyph turns green).
        var pendingUpdate: () -> String? = { nil }
        var canCheckForUpdates: () -> Bool = { false }
        var checkForUpdates: () -> Void = {}
    }

    /// Most sessions listed in the menu; the status line still counts them all.
    static let maxListedSessions = 10

    let menu = NSMenu()
    var actions: Actions
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    /// The glyph on screen, so an unchanged aggregate never redraws it.
    private(set) var icon: MenuBarIcon.State?
    /// Rows by menu item tag while the menu is open.
    private var listedRows: [Int: SessionRow] = [:]
    /// Bumped per `observe()`, so a change reported for a replaced store or model is dropped.
    private var observationGeneration = 0

    init(actions: Actions = Actions()) {
        self.actions = actions
        super.init()
        menu.delegate = self
        menu.autoenablesItems = false
        statusItem.menu = menu
        setIcon(MenuBarIcon.State(glyph: .calm))
    }

    /// Follows `actions.needsInputCount` and `actions.pendingUpdate` (again after their source was
    /// replaced): the glyph, its colour and the tooltip.
    func observe() {
        observationGeneration += 1
        track(generation: observationGeneration)
    }

    // MARK: Status text

    /// The disabled first line: "No sessions", "1 session", "3 sessions · 1 needs you".
    static func statusText(sessionCount: Int, needsInputCount: Int) -> String {
        guard sessionCount > 0 else { return "No sessions" }
        let sessions = sessionCount == 1 ? "1 session" : "\(sessionCount) sessions"
        guard needsInputCount > 0 else { return sessions }
        return "\(sessions) · \(needsInputCount) \(needsInputCount == 1 ? "needs" : "need") you"
    }

    /// "Show hidden sessions (2)".
    static func hiddenItemTitle(count: Int) -> String {
        "Show hidden sessions (\(count))"
    }

    // MARK: NSMenuDelegate

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        listedRows = [:]
        let rows = actions.rows().filter { !$0.ended }
        let needsInput = rows.filter { $0.status.isNeedsInput }.count

        let status = NSMenuItem(title: Self.statusText(sessionCount: rows.count, needsInputCount: needsInput), action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)

        for (index, row) in rows.prefix(Self.maxListedSessions).enumerated() {
            let item = NSMenuItem(title: row.name, action: #selector(openSession(_:)), keyEquivalent: "")
            item.target = self
            item.tag = index
            item.subtitle = row.label
            item.image = MenuBarIcon.statusImage(for: row.status)
            item.toolTip = row.name
            listedRows[index] = row
            menu.addItem(item)
        }

        menu.addItem(.separator())
        menu.addItem(item(actions.isPanelVisible() ? "Hide panel" : "Show panel", #selector(togglePanel)))
        let hidden = actions.hiddenCount()
        if hidden > 0 {
            menu.addItem(item(Self.hiddenItemTitle(count: hidden), #selector(showHiddenSessions)))
        }
        menu.addItem(item("Reset position", #selector(resetPosition)))
        menu.addItem(.separator())
        menu.addItem(item("Settings…", #selector(openSettings), key: ","))
        let update = item(actions.updateTitle(), #selector(checkForUpdates))
        update.isEnabled = actions.canCheckForUpdates()
        menu.addItem(update)
        menu.addItem(item("What's New…", #selector(showWhatsNew)))
        menu.addItem(item("Show welcome…", #selector(showWelcome)))
        menu.addItem(.separator())
        menu.addItem(item("Quit \(AppInfo.name)", #selector(quit), key: "q"))
    }

    // MARK: Glyph

    private func track(generation: Int) {
        let count = actions.needsInputCount
        let update = actions.pendingUpdate
        let (needsInput, pendingUpdate) = withObservationTracking {
            (count(), update())
        } onChange: { [weak self] in
            // Fires once, before the change lands: read the new state on the next turn, then track again.
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, generation == self.observationGeneration else { return }
                    self.track(generation: generation)
                }
            }
        }
        setIcon(MenuBarIcon.State(glyph: MenuBarIcon.glyph(needsInputCount: needsInput), pendingUpdate: pendingUpdate))
    }

    private func setIcon(_ new: MenuBarIcon.State) {
        guard new != icon else { return }
        icon = new
        statusItem.button?.image = MenuBarIcon.image(new)
        statusItem.button?.toolTip = new.accessibilityDescription
    }

    // MARK: Items

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    @objc private func openSession(_ sender: NSMenuItem) {
        guard let row = listedRows[sender.tag] else { return }
        actions.openSession(row)
    }

    @objc private func togglePanel() { actions.togglePanel() }
    @objc private func showHiddenSessions() { actions.showHiddenSessions() }
    @objc private func resetPosition() { actions.resetPosition() }
    @objc private func openSettings() { actions.openSettings() }
    @objc private func showWelcome() { actions.showWelcome() }
    @objc private func showWhatsNew() { actions.showWhatsNew() }
    @objc private func checkForUpdates() { actions.checkForUpdates() }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
