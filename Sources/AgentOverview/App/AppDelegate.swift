import AppKit
import SwiftUI
import WallflowerHookCore

/// Owns the panel, its model, the menu bar item, the Settings and welcome windows for the life of
/// the process, and applies settings changes live: an appearance change or the new session button
/// switch rebuilds the panel content, a panel side change moves the window to the other edge and
/// rebuilds the content mirrored, a session source change replaces the store and rebuilds once its
/// first scan is in. Nothing relaunches.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let arguments = LaunchArguments()
    private var panel: PanelWindow?
    private var hosting: PanelHostingView?
    /// Moves the panel along the edge when a press on it turns into a vertical drag.
    private var drag: PanelDragController?
    private var menuBar: MenuBar?
    private var playground: PlaygroundWindowController?
    private var settingsWindow: SettingsWindowController?
    private var welcomeWindow: WelcomeWindowController?
    /// The persisted vertical position of the panel (`panelVerticalOffset`).
    private var positionStore = PanelPositionStore()
    /// The person's settings (launch arguments over stored values over `Theme`).
    private(set) var settings: AppSettings!
    /// "Launch at login", shared by Settings, the welcome and `--set`.
    private let launchAtLogin = LaunchAtLogin()
    /// In-app updates (Sparkle), shared by the menu and Settings.
    private(set) var updater: AppUpdater!
    /// What the panel content was last built with; a settings change rebuilds only when these differ.
    private var appliedLook = PanelLook.themeDefault
    private var appliedSource = SessionSource.desktop
    private var appliedNewSessionButton = Theme.newSessionButton
    private var appliedSide = PanelSide.default
    /// Whether the current store watches the external sessions folder ("Sessions from other tools").
    private var appliedExternalSessions = Theme.externalSessions
    /// The agents whose faces the current store leaves out (Settings > Agents).
    private var appliedHiddenTools: Set<String> = []
    /// A settings change is waiting for the store's first scan to rebuild the panel content.
    private var installsOnFirstScan = false
    /// Live sessions from the registry.
    private(set) var store: SessionStore!
    /// Action faces from `actions.json`.
    private(set) var actionStore: ActionStore!
    /// Panel UI state; derives the rows from the store.
    private(set) var model: PanelModel!
    /// Sessions thrown out of the capsule (`hiddenSessionPids`).
    private(set) var hiddenSessions: HiddenSessions!
    /// Slides the panel off its edge and back (Settings > General > Hide the panel).
    private var autoHide: AutoHideController?
    /// The pointer monitors while the pointer holds the auto-hidden panel out (`watchPointer`).
    private var pointerMonitors: [Any] = []
    /// Bumped on every `observeAutoHideInputs`, so an observation of a replaced model goes quiet.
    private var autoHideObservation = 0
    /// Where agents are detected and connected: the home folder, or `--tools-home`.
    private(set) lazy var agentEnvironment: AgentEnvironment = arguments.toolsHome.map(AgentEnvironment.fixture(home:)) ?? .live

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Belt and braces next to LSUIElement in Info.plist: no Dock icon, no app menu.
        NSApp.setActivationPolicy(.accessory)
        installMainMenu()

        let defaults = arguments.defaultsSuite.flatMap { UserDefaults(suiteName: $0) } ?? .standard
        positionStore = PanelPositionStore(defaults: defaults)
        let settings = AppSettings(defaults: defaults, overrides: arguments.settingsOverrides)
        self.settings = settings
        appliedLook = settings.look
        appliedSource = settings.sessionSource
        appliedNewSessionButton = settings.newSessionButton
        appliedSide = settings.panelSide
        appliedExternalSessions = settings.externalSessions
        appliedHiddenTools = settings.hiddenAgentTools
        appliedLook.applyToFaceLook()

        let updater = AppUpdater(
            start: arguments.runsUpdater, relaunches: arguments.defaultsSuite == nil, fakePendingVersion: arguments.pendingUpdateOverride
        )
        self.updater = updater

        let store = makeStore(for: appliedSource)
        let actionStore = ActionStore(fileURL: arguments.actionsFile ?? ActionStore.defaultFileURL)
        actionStore.start()
        let hiddenSessions = HiddenSessions(defaults: defaults)
        self.hiddenSessions = hiddenSessions
        self.store = store
        self.actionStore = actionStore

        let panel = PanelWindow(
            capsuleHeight: Theme.capsuleHeight(rows: 0, actions: actionStore.visibleActions.count, newSession: appliedNewSessionButton),
            verticalOffset: arguments.verticalOffset ?? positionStore.load() ?? 0,
            side: appliedSide,
            logsFrame: arguments.logFrame
        )
        self.panel = panel
        installAutoHide(panel: panel, settings: settings)
        installPanelContent()
        panel.show()

        store.onFirstScan = { [weak self] count in
            NSLog("\(AppInfo.name): first registry scan found %d session(s)", count)
            self?.installDeferredContent()
            if self?.arguments.openFirst == true { self?.openFirstRowAndQuit() }
            self?.runScriptedHover()
            self?.runScriptedExcite()
            self?.runScriptedGlide()
            self?.runScriptedAction()
            self?.runScriptedSettings()
            self?.logMenuIfAsked()
            self?.runWelcomeKeys()
            self?.runScriptedSnapshot()
            self?.runGestureScript()
        }
        store.start()

        let menuBar = MenuBar(actions: MenuBar.Actions(
            rows: { [weak self] in self?.model.rows ?? [] },
            needsInputCount: { [weak self] in
                self?.model.visibleSessions.filter { !$0.ended && $0.state.isNeedsInput }.count ?? 0
            },
            openSession: { [weak self] row in self?.model.open(row) },
            hiddenCount: { [weak self] in self?.model.hiddenCount ?? 0 },
            showHiddenSessions: { [weak self] in self?.model.showHiddenSessions() },
            togglePanel: { [weak self] in self?.togglePanel() },
            isPanelVisible: { [weak self] in self?.panel?.isHiddenByUser == false },
            resetPosition: { [weak self] in self?.resetPosition() },
            openSettings: { [weak self] in self?.openSettings() },
            showWelcome: { [weak self] in self?.showWelcome() },
            updateTitle: { [weak self] in AppUpdater.menuTitle(pendingVersion: self?.updater.pendingVersion) },
            pendingUpdate: { [weak self] in self?.updater.pendingVersion },
            canCheckForUpdates: { [weak self] in self?.updater.canCheckForUpdates == true },
            checkForUpdates: { [weak self] in self?.updater.checkForUpdates() }
        ))
        self.menuBar = menuBar
        menuBar.observe()
        observeSettings()

        if arguments.playground {
            openPlayground()
        }
        runScriptedAgents()
        openLaunchWindows()
        runScriptedUpdateCheck()
        refreshHookHelper()
    }

    /// After an update, the installed hook helper is replaced by this build's (only when one is
    /// installed: a Mac that never connected an agent gets no file).
    private func refreshHookHelper() {
        let installer = HelperInstaller(environment: agentEnvironment, source: HelperInstaller.bundledHelper)
        DispatchQueue.global(qos: .utility).async { installer.refreshIfInstalled() }
    }

    // MARK: Panel content

    /// A store for a session source, on the registry folder of this run, plus the external sessions
    /// folder while sessions from other tools are on.
    private func makeStore(for source: SessionSource) -> SessionStore {
        SessionStore(
            folder: arguments.sessionsFolder ?? SessionStore.defaultFolder,
            entrypoints: source.entrypoints,
            externalFolder: appliedExternalSessions
                ? (arguments.externalSessionsFolder ?? arguments.toolsHome.map { HelperLayout.sessionsFolder(home: $0) } ?? SessionStore.defaultExternalFolder)
                : nil,
            hiddenTools: appliedHiddenTools
        )
    }

    /// Builds the panel content for the current store, look and side: a new `PanelModel`, a new root
    /// view in the existing hosting view, the drag controller and the callbacks rewired to them. The
    /// window (moved to the side's edge), the action store and the vertical position stay; the old model is released with the old root view. The root
    /// view takes its identity from the model, so every face is built anew with the new look and the
    /// capsule's first-layout hook sizes the window for the new model.
    private func installPanelContent() {
        guard let panel else { return }
        // A panel side change moves the window to the other edge in the same turn as the new content.
        panel.side = appliedSide
        let model = PanelModel(
            store: store,
            actionStore: actionStore,
            hiddenSessions: hiddenSessions,
            expandMode: appliedLook.expandMode,
            gooRenderer: appliedLook.gooRenderer,
            hoverEffect: appliedLook.hoverEffect,
            newSessionButton: appliedNewSessionButton,
            sessionSource: appliedSource,
            side: appliedSide
        )
        let hosting: PanelHostingView
        if let existing = self.hosting {
            hosting = existing
            hosting.rootView = PanelRootView(model: model)
        } else {
            hosting = PanelHostingView(rootView: PanelRootView(model: model))
            hosting.sizingOptions = []
            panel.capsuleHeight = model.capsuleHeight
            panel.setFrame(for: .collapsed)
            panel.install(hosting)
            self.hosting = hosting
        }
        model.runAction = { [weak self] item, report in
            ActionLaunch.run(item, using: self?.settings.actionLauncher ?? Theme.actionLauncher, report: report)
        }
        model.setWindowHeight = { [weak panel] height in panel?.capsuleHeight = height }
        model.setWindowState = { [weak panel] state in panel?.setFrame(for: state) }
        hosting.pointerHandler = { [weak model] point, size in model?.pointerMoved(to: point, in: size) }
        let drag = PanelDragController(panel: panel, hostingView: hosting, model: model)
        drag.onDragEnded = { [weak self] offset in self?.persist(offset: offset) }
        let isRebuild = self.model != nil
        self.drag = drag
        self.model = model
        observeAutoHideInputs()
        guard isRebuild else { return }
        // The menu's glyph and hidden count read the model: track the new one.
        menuBar?.observe()
        panel.setFrame(for: .collapsed)
    }

    /// Re-arms the observation of the panel settings. A change lands in `settingsDidChange` on the next
    /// turn of the main queue, so a burst of changes (Restore defaults) rebuilds once.
    private func observeSettings() {
        guard let settings else { return }
        withObservationTracking {
            _ = settings.look
            _ = settings.sessionSource
            _ = settings.externalSessions
            _ = settings.hiddenAgentTools
            _ = settings.newSessionButton
            _ = settings.panelSide
        } onChange: { [weak self] in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.settingsDidChange() }
            }
        }
    }

    private func settingsDidChange() {
        observeSettings()
        let look = settings.look
        let source = settings.sessionSource
        let newSessionButton = settings.newSessionButton
        let side = settings.panelSide
        let externalSessions = settings.externalSessions
        let hiddenTools = settings.hiddenAgentTools
        guard look != appliedLook || source != appliedSource || newSessionButton != appliedNewSessionButton || side != appliedSide
            || externalSessions != appliedExternalSessions || hiddenTools != appliedHiddenTools else { return }
        appliedNewSessionButton = newSessionButton
        // The window moves to the other edge together with the content (`installPanelContent`), so the
        // two never disagree, even while a new store's first scan is pending.
        appliedSide = side
        if look != appliedLook {
            appliedLook = look
            look.applyToFaceLook()
        }
        if source != appliedSource || externalSessions != appliedExternalSessions || hiddenTools != appliedHiddenTools {
            appliedSource = source
            appliedExternalSessions = externalSessions
            appliedHiddenTools = hiddenTools
            replaceStore()
        }
        // A new store starts empty: content built now would shrink the panel to the empty stub at once
        // (clipping the departing faces) and grow it again with the scan. The old content stays until then.
        if store.hasScanned {
            installPanelContent()
        } else {
            installsOnFirstScan = true
        }
    }

    /// Stops the store and starts one with the new source's entrypoint filter (and the external folder or not). The panel content and
    /// the menu bar follow it from its first scan on (`installDeferredContent`).
    private func replaceStore() {
        store.onFirstScan = nil
        store.stop()
        let store = makeStore(for: appliedSource)
        store.onFirstScan = { [weak self] _ in self?.installDeferredContent() }
        self.store = store
        store.start()
    }

    /// Builds the content a settings change deferred until the store's first scan, if any.
    private func installDeferredContent() {
        guard installsOnFirstScan else { return }
        installsOnFirstScan = false
        installPanelContent()
    }

    // MARK: Auto-hide

    /// The auto-hide controller, wired to the panel: it conceals the window's content, the panel's edge
    /// trigger brings it out, and while the pointer holds it out a global and a local monitor report
    /// pointer moves and button releases (no permission needed for mouse events; nothing at rest, and
    /// none while the panel is simply shown or hidden).
    private func installAutoHide(panel: PanelWindow, settings: AppSettings) {
        let autoHide = AutoHideController(mode: settings.panelAutoHide)
        autoHide.setConcealed = { [weak panel] concealed, animated in panel?.setConcealed(concealed, animated: animated) }
        autoHide.pointerIsOnPanel = { [weak panel] in panel?.isPointerOnPanel ?? false }
        autoHide.isButtonDown = { NSEvent.pressedMouseButtons != 0 }
        autoHide.watchPointer = { [weak self] on in self?.watchPointer(on) }
        if arguments.logFrame {
            autoHide.log = { DataLog.panel.notice("\($0, privacy: .public)") }
        }
        panel.onEdgeReveal = { [weak autoHide] in autoHide?.edgeReached() }
        self.autoHide = autoHide
    }

    /// Feeds the auto-hide the face counts and the needs-input state of the current model, and the
    /// mode from the settings, now and on every change. A rebuild calls it again for the new model;
    /// the old observation then goes quiet.
    private func observeAutoHideInputs() {
        guard let autoHide, let model, let settings else { return }
        autoHideObservation += 1
        let generation = autoHideObservation
        let inputs = withObservationTracking {
            let sessions = model.visibleSessions
            return (
                sessions: sessions.count, actions: model.actionRows.count,
                needsInput: sessions.contains { !$0.ended && $0.state.isNeedsInput }, mode: settings.panelAutoHide
            )
        } onChange: { [weak self] in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, self.autoHideObservation == generation else { return }
                    self.observeAutoHideInputs()
                }
            }
        }
        autoHide.mode = inputs.mode
        autoHide.update(sessions: inputs.sessions, actions: inputs.actions, needsInput: inputs.needsInput)
    }

    /// Starts or stops the pointer reports to the auto-hide while the pointer holds the panel out.
    private func watchPointer(_ on: Bool) {
        guard on else {
            pointerMonitors.forEach(NSEvent.removeMonitor)
            pointerMonitors = []
            return
        }
        guard pointerMonitors.isEmpty else { return }
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .leftMouseUp, .rightMouseUp, .otherMouseUp]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.autoHide?.pointerChanged() }
        }) {
            pointerMonitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.autoHide?.pointerChanged() }
            return event
        }) {
            pointerMonitors.append(local)
        }
    }

    // MARK: Windows

    /// Opens the eye playground window (created once, reused).
    @objc func openPlayground() {
        if playground == nil {
            playground = PlaygroundWindowController()
        }
        playground?.show()
    }

    /// Opens the Settings window (created on demand, released when closed), on `tab` if given.
    func openSettings(tab: SettingsTab? = nil) {
        if settingsWindow == nil {
            let agents = AgentsModel(environment: agentEnvironment, settings: settings)
            agents.showsImpossible = arguments.settingsAdvanced
            let controller = SettingsWindowController(
                settings: settings, launchAtLogin: launchAtLogin, updater: updater, actions: settingsActions, actionStore: actionStore,
                agents: agents, tab: tab ?? .general,
                showsAdvanced: arguments.settingsAdvanced
            )
            controller.onClose = { [weak self] in
                // Released on the next turn: the window is still inside its own close call.
                DispatchQueue.main.async { MainActor.assumeIsolated { self?.settingsWindow = nil } }
            }
            settingsWindow = controller
        }
        settingsWindow?.show(tab: tab)
    }

    @objc private func openSettingsFromMenu() {
        openSettings()
    }

    private var settingsActions: SettingsActions {
        SettingsActions(
            resetPosition: { [weak self] in self?.resetPosition() },
            editActions: { [weak self] in self?.editActions() },
            openPlayground: { [weak self] in self?.openPlayground() },
            showWelcome: { [weak self] in self?.showWelcome() }
        )
    }

    /// Opens the welcome window on `page` (or brings the open one forward on it).
    func showWelcome(page: Int = 1) {
        if let welcomeWindow {
            welcomeWindow.model.go(to: page)
            welcomeWindow.show()
            return
        }
        launchAtLogin.refresh()
        let agents = WelcomeModel.agentChoices(environment: agentEnvironment)
        let model = WelcomeModel(
            page: page, sessionSource: settings.sessionSource,
            launchAtLogin: WelcomeModel.initialLaunchAtLogin(
                hasCompletedOnboarding: settings.hasCompletedOnboarding, isEnabled: launchAtLogin.isEnabled
            ),
            faceStyle: settings.faceStyle, colorMode: settings.colorMode, agentChoices: agents.choices, missingAgents: agents.missing
        ) { [weak self] source in
            self?.sessionCount(for: source) ?? 0
        }
        model.onFinish = { [weak self] outcome in self?.welcomeFinished(outcome) }
        model.onLookChange = { [weak self] style, colorMode in
            self?.settings.faceStyle = style
            self?.settings.colorMode = colorMode
        }
        let connector = AgentConnector(environment: agentEnvironment)
        model.agentsHome = agentEnvironment.home
        model.planAgents = { tools in
            tools.sorted { $0.rawValue < $1.rawValue }.map { tool in
                do {
                    return .plan(try connector.plan(tool))
                } catch let manual as ManualSetup {
                    return .manual(tool, manual.reason)
                } catch {
                    return .manual(tool, error.localizedDescription)
                }
            }
        }
        let controller = WelcomeWindowController(model: model, look: settings.look)
        controller.onClose = { [weak self] in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.welcomeWindow = nil } }
            // The tour points at the edge: the panel stays out while it is open.
            self?.autoHide?.setPinned(false)
        }
        autoHide?.setPinned(true)
        welcomeWindow = controller
        controller.show()
        if !arguments.welcomeAgents.isEmpty {
            arguments.welcomeAgents.compactMap(AgentTool.init(rawValue:)).forEach { model.setPicked($0, true) }
            if model.isLastPage { model.primary() }
        }
    }

    /// "Start" applies the last page's choices; any way out counts as done.
    private func welcomeFinished(_ outcome: WelcomeModel.Outcome) {
        settings.hasCompletedOnboarding = true
        guard case .started(let source, let launchAtLogin, let agents) = outcome else { return }
        settings.sessionSource = source
        if self.launchAtLogin.isEnabled != launchAtLogin { self.launchAtLogin.set(launchAtLogin) }
        // The agents the person ticked and confirmed, each through the same safe path as Settings.
        let connector = AgentConnector(environment: agentEnvironment)
        for plan in agents {
            do {
                try connector.connect(plan)
                NSLog("\(AppInfo.name): connected %@", plan.tool.rawValue)
            } catch {
                NSLog("\(AppInfo.name): connecting %@ failed: %@", plan.tool.rawValue, error.localizedDescription)
            }
        }
        welcomeWindow?.close()
    }

    /// Live Claude sessions for a source: the store's when it is the one shown, else a scan of the folder.
    private func sessionCount(for source: SessionSource) -> Int {
        if source == appliedSource { return store.sessions.filter { !$0.ended && $0.source.isClaude }.count }
        return SessionRegistryScanner.scan(folder: store.folder, entrypoints: source.entrypoints).records.count
    }

    /// The windows a launch argument asks for, and the welcome on a first launch (after the panel is up).
    private func openLaunchWindows() {
        switch arguments.snapshotWindow {
        case .settings(let tab) where arguments.snapshot != nil: openSettings(tab: tab)
        case .welcome(let page) where arguments.snapshot != nil: showWelcome(page: page)
        default: break
        }
        if let tab = arguments.showSettings { openSettings(tab: tab) }
        if let name = arguments.agentSheet, let agents = settingsWindow?.agents {
            agents.refresh()
            if let tool = AgentTool(rawValue: name) {
                agents.requestConnect(tool)
            } else if name == "disconnect-all" {
                agents.requestDisconnectAll()
            } else if name.hasPrefix("changes:"), let tool = AgentTool(rawValue: String(name.dropFirst("changes:".count))) {
                agents.showChanges(tool)
            } else if name == "codex-trust" {
                agents.sheet = .codexTrustHelp
            }
        }
        if let target = arguments.editAction, let editor = settingsWindow?.actionEditor {
            switch target {
            case .new: editor.startAdding()
            case .edit(let index) where editor.items.indices.contains(index): editor.startEditing(editor.items[index].id)
            case .select(let index) where editor.items.indices.contains(index):
                editor.selection = editor.items[index].id
                editor.reveal()
            case .edit, .select: NSLog("\(AppInfo.name): --edit-action found no such action")
            }
        }
        if let points = arguments.settingsScroll, let window = settingsWindow?.window {
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(0.5))
                Self.scrollSettings(points, in: window)
            }
        }
        if let page = arguments.welcomePage {
            showWelcome(page: page)
        } else if !settings.hasCompletedOnboarding, !arguments.noWelcome, arguments.snapshot == nil {
            showWelcome()
        }
    }

    // MARK: Panel actions

    /// Opens `actions.json` in the default editor for JSON files.
    @objc func editActions() {
        NSWorkspace.shared.open(actionStore.fileURL)
    }

    /// "Hide panel" / "Show panel".
    private func togglePanel() {
        guard let panel else { return }
        panel.isHiddenByUser.toggle()
    }

    /// "Reset position": forgets the stored offset and moves the panel back to the vertical centre.
    /// With `--vertical-offset` nothing is stored, so nothing is cleared either.
    @objc func resetPosition() {
        if arguments.verticalOffset == nil { positionStore.clear() }
        panel?.resetPosition()
    }

    /// Stores the offset a drag ended at, unless `--vertical-offset` overrides the stored position.
    private func persist(offset: CGFloat) {
        guard arguments.verticalOffset == nil else { return }
        positionStore.save(offset)
    }

    // MARK: Main menu

    /// The app is an accessory, so its main menu never shows; it exists for the key equivalents of
    /// the Settings and welcome windows while they are key: ⌘, Settings, ⌘W close, ⌘Q quit, copy.
    private func installMainMenu() {
        let main = NSMenu()
        let appMenu = NSMenu(title: AppInfo.name)
        appMenu.addItem(withTitle: "Settings…", action: #selector(openSettingsFromMenu), keyEquivalent: ",").target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit \(AppInfo.name)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        for submenu in [appMenu, editMenu, windowMenu] {
            let item = NSMenuItem(title: submenu.title, action: nil, keyEquivalent: "")
            item.submenu = submenu
            main.addItem(item)
        }
        NSApp.mainMenu = main
    }

    // MARK: `--connect-agents`, `--disconnect-agents`

    /// Connects, then disconnects, the agents the launch arguments name, through the same path as
    /// the Agents tab, and logs each result.
    private func runScriptedAgents() {
        guard !arguments.connectAgents.isEmpty || !arguments.disconnectAgents.isEmpty else { return }
        let connector = AgentConnector(environment: agentEnvironment)
        for name in arguments.connectAgents {
            guard let tool = AgentTool(rawValue: name) else { continue }
            do {
                try connector.connect(tool)
                NSLog("\(AppInfo.name): --connect-agents %@: connected", name)
            } catch {
                NSLog("\(AppInfo.name): --connect-agents %@: %@", name, "\(error)")
            }
        }
        if arguments.disconnectAgents == ["all"] {
            let failures = connector.disconnectAll()
            NSLog("\(AppInfo.name): --disconnect-agents all: %d failure(s)", failures.count)
        } else {
            for name in arguments.disconnectAgents {
                guard let tool = AgentTool(rawValue: name) else { continue }
                do {
                    try connector.disconnect(tool)
                    NSLog("\(AppInfo.name): --disconnect-agents %@: disconnected", name)
                } catch {
                    NSLog("\(AppInfo.name): --disconnect-agents %@: %@", name, "\(error)")
                }
            }
        }
    }

    // MARK: `--welcome-keys`

    /// Presses `--welcome-keys` in the welcome window, logs the page after each key, then quits.
    private func runWelcomeKeys() {
        let keys = arguments.welcomeKeys
        guard !keys.isEmpty else { return }
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1))
            for key in keys {
                guard let self, let controller = self.welcomeWindow, let window = controller.window else {
                    NSLog("\(AppInfo.name): welcome keys: window closed, onboarding done %d", self?.settings.hasCompletedOnboarding == true ? 1 : 0)
                    break
                }
                let (code, characters): (UInt16, String) = switch key {
                case "return": (36, "\r")
                case "escape": (53, "\u{1B}")
                default: (49, " ")
                }
                if let event = NSEvent.keyEvent(
                    with: .keyDown, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                    windowNumber: window.windowNumber, context: nil, characters: characters,
                    charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code
                ) {
                    if !window.performKeyEquivalent(with: event) { window.sendEvent(event) }
                }
                try? await Task.sleep(for: .milliseconds(600))
                NSLog("\(AppInfo.name): welcome keys: %@ -> page %d, open %d", key, controller.model.page, self.welcomeWindow == nil ? 0 : 1)
            }
            NSLog("\(AppInfo.name): welcome keys: onboarding done %d", self?.settings.hasCompletedOnboarding == true ? 1 : 0)
            NSApp.terminate(nil)
        }
    }

    // MARK: `--check-for-updates`

    /// Starts the `--check-for-updates` check a second after launch, once Sparkle has settled.
    private func runScriptedUpdateCheck() {
        guard let check = arguments.checkForUpdates else { return }
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard let self else { return }
            NSLog("\(AppInfo.name): --check-for-updates %@ (updater running: %d)", check.rawValue, self.updater.isRunning ? 1 : 0)
            switch check {
            case .ui: self.updater.checkForUpdates()
            case .background: self.updater.checkInBackground()
            }
        }
    }

    // MARK: `--log-menu`

    /// Builds the status menu as if it opened and logs its items, half a second after the first scan.
    private func logMenuIfAsked() {
        guard arguments.logMenu, let menuBar else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(500))
            menuBar.menuNeedsUpdate(menuBar.menu)
            NSLog("\(AppInfo.name): menu glyph %@%@", menuBar.icon.map { "\($0.glyph)" } ?? "none",
                  menuBar.icon?.pendingUpdate.map { " (green, update \($0))" } ?? "")
            for item in menuBar.menu.items {
                if item.isSeparatorItem {
                    NSLog("\(AppInfo.name): menu ----")
                } else {
                    let key = item.keyEquivalent.isEmpty ? "" : " [cmd-\(item.keyEquivalent)]"
                    let subtitle = item.subtitle.map { " / \($0)" } ?? ""
                    NSLog("\(AppInfo.name): menu %@%@%@%@", item.title, subtitle, key, item.isEnabled ? "" : " (disabled)")
                }
            }
        }
    }

    // MARK: `--set`

    /// Changes the `--set` settings one second after the first scan, as Settings would.
    private func runScriptedSettings() {
        let changes = arguments.scriptedSettings
        guard !changes.isEmpty else { return }
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard let self else { return }
            for change in changes {
                if change.key == "launchAtLogin" {
                    self.launchAtLogin.set(change.value == "on")
                    continue
                }
                let applied = self.settings.setValue(change.value, forKey: change.key)
                NSLog("\(AppInfo.name): --set %@=%@ %@", change.key, change.value, applied ? "applied" : "unknown")
            }
        }
    }

    // MARK: `--hover`, `--hover-sequence`

    /// Drives the hover state from the launch arguments (a pointer cannot be scripted without
    /// Accessibility): each target puts the model's pointer on that slot's centre. Each step logs the window state the panel is in afterwards.
    private func runScriptedHover() {
        var steps = arguments.hoverSequence
        if let hover = arguments.hover { steps.insert(hover, at: 0) }
        guard !steps.isEmpty else { return }
        Task { @MainActor [weak self] in
            for (index, step) in steps.enumerated() {
                if index > 0 { try? await Task.sleep(for: .seconds(LaunchArguments.hoverSequenceInterval)) }
                guard let self else { return }
                let slot = step.slotIndex(rowCount: self.model.rows.count)
                // A real hover comes with a pointer: put it on the slot's centre (the magnification
                // follows it); without the hosting view, fall back to the hover alone.
                if let slot, let hosting = self.hosting, self.model.containsSlot(slot) {
                    let size = hosting.bounds.size
                    self.model.pointerMoved(to: CGPoint(x: self.model.capsuleCenterX(inViewWidth: size.width), y: self.model.slotCenterY(slot: slot)), in: size)
                } else {
                    self.model.hover(rowIndex: slot)
                }
                NSLog("\(AppInfo.name): scripted hover %@ (expanded: %d, key: %d)", slot.map(String.init) ?? "none", self.model.isExpanded ? 1 : 0, self.panel?.isKeyWindow == true ? 1 : 0)
            }
        }
    }

    // MARK: `--excite`

    /// After `--excite <seconds>`, every working row's face perks up once (`PanelModel.exciteWorkingRows`).
    private func runScriptedExcite() {
        guard let delay = arguments.exciteDelay else { return }
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard let self else { return }
            let count = self.model.exciteWorkingRows()
            NSLog("\(AppInfo.name): scripted excite on %d working row(s)", count)
        }
    }

    // MARK: `--pointer-glide`

    /// Feeds the model pointer positions down the capsule's centre line from one slot centre to
    /// another, one every `LaunchArguments.pointerGlideStep` (the same path a real move takes through
    /// `pointerMoved`), rests `pointerGlideHold` at the end, then releases the pointer. Debug only.
    private func runScriptedGlide() {
        guard let glide = arguments.pointerGlide else { return }
        Task { @MainActor [weak self] in
            guard let self, let hosting = self.hosting else { return }
            let size = hosting.bounds.size
            let x = self.model.capsuleCenterX(inViewWidth: size.width)
            let fromY = self.model.slotCenterY(slot: glide.fromSlot)
            let toY = self.model.slotCenterY(slot: glide.toSlot)
            let steps = max(Int(glide.duration / LaunchArguments.pointerGlideStep), 1)
            NSLog("\(AppInfo.name): pointer glide slot %d to %d over %.2f s (%d steps)", glide.fromSlot, glide.toSlot, glide.duration, steps)
            for step in 0...steps {
                let t = CGFloat(step) / CGFloat(steps)
                // Ease in and out, like a hand moving a mouse.
                let eased = t * t * (3 - 2 * t)
                self.model.pointerMoved(to: CGPoint(x: x, y: fromY + (toY - fromY) * eased), in: size)
                try? await Task.sleep(for: .seconds(LaunchArguments.pointerGlideStep))
            }
            try? await Task.sleep(for: .seconds(LaunchArguments.pointerGlideHold))
            self.model.pointerMoved(to: nil, in: size)
            NSLog("\(AppInfo.name): pointer glide released")
        }
    }

    // MARK: `--run-action`

    /// Clicks an action row through the model (the launcher really runs) and logs the session count
    /// a few seconds later, so a scripted check can see whether the new session reached the registry.
    private func runScriptedAction() {
        guard let index = arguments.runAction else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .seconds(1))
            guard self.model.actionRows.indices.contains(index) else {
                NSLog("\(AppInfo.name): --run-action %d: no such action", index)
                return
            }
            let before = self.store.sessions.count
            let row = self.model.actionRows[index]
            NSLog("\(AppInfo.name): running action %@ (%@ in %@)", row.name, row.prompt, row.cwd)
            self.model.tappedAction(row)
            try? await Task.sleep(for: .seconds(5))
            NSLog("\(AppInfo.name): sessions before %d, after %d", before, self.store.sessions.count)
        }
    }

    /// `--settings-scroll`: moves the Settings tab's scroll view (the outermost one, `SettingsTabRoot`) down
    /// by that many points, at most to the end, so a snapshot shows the bottom of a capped tab. A
    /// programmatic scroll: synthetic wheel events never reach SwiftUI's scroll view in a scripted launch.
    private static func scrollSettings(_ points: Double, in window: NSWindow) {
        func firstScrollView(_ view: NSView) -> NSScrollView? {
            (view as? NSScrollView) ?? view.subviews.lazy.compactMap(firstScrollView).first
        }
        guard let scrollView = window.contentView.flatMap(firstScrollView), let document = scrollView.documentView else {
            NSLog("\(AppInfo.name): --settings-scroll found no scroll view")
            return
        }
        let range = max(document.frame.height - scrollView.contentView.bounds.height, 0)
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: min(max(points, 0), range)))
        scrollView.reflectScrolledClipView(scrollView.contentView)
        NSLog("\(AppInfo.name): Settings scrolled to %.0f of %.0f pt (content %.0f pt, window content %.0f pt)",
              scrollView.contentView.bounds.origin.y, range, document.frame.height, scrollView.frame.height)
    }

    // MARK: `--snapshot`

    /// Captures the snapshot target after the scripted hover settled, one frame or a burst, then quits.
    /// The menu bar glyph is drawn straight to files; every other target is a window.
    private func runScriptedSnapshot() {
        guard let url = arguments.snapshot else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .seconds(self.arguments.snapshotDelay))
            let target = self.arguments.snapshotWindow
            if target == .menuGlyph {
                do {
                    let written = try WindowSnapshot.writeMenuBarGlyphs(to: url)
                    written.forEach { NSLog("\(AppInfo.name): snapshot written to %@", $0.path) }
                } catch {
                    NSLog("\(AppInfo.name): snapshot failed: %@", "\(error)")
                }
                NSApp.terminate(nil)
                return
            }
            let window: NSWindow? = switch target {
            case .panel: self.panel
            case .playground: self.playground?.window
            case .settings: self.settingsWindow?.window.map { $0.attachedSheet ?? $0 }
            case .welcome: self.welcomeWindow?.window
            case .menuGlyph: nil
            }
            guard let window else {
                NSLog("\(AppInfo.name): --snapshot found no %@ window", target.name)
                NSApp.terminate(nil)
                return
            }
            let method = self.arguments.snapshotMethod ?? target.method
            let frames = self.arguments.snapshotBurst
            let count = frames?.count ?? 1
            for index in 0..<count {
                let file = frames == nil ? url : url.deletingPathExtension().appendingPathExtension("\(index + 1).png")
                if let grow = self.arguments.snapshotGrow {
                    WindowSnapshot.growTime = grow.start + Double(index) * grow.step
                }
                do {
                    try await WindowSnapshot.capture(window, to: file, scale: self.arguments.snapshotScale, method: method)
                    NSLog("\(AppInfo.name): snapshot written to %@", file.path)
                } catch {
                    NSLog("\(AppInfo.name): snapshot failed: %@", "\(error)")
                }
                if let frames, index + 1 < count {
                    try? await Task.sleep(for: .seconds(frames.interval))
                }
            }
            // AppKit does not quit while a sheet is attached (`--edit-action`).
            window.sheetParent?.endSheet(window)
            NSApp.terminate(nil)
        }
    }

    // MARK: `--gesture-script`

    /// Runs the `--gesture-script` steps: presses, moves and releases as synthetic left-button events
    /// posted to the app's event queue at the panel's current frame (so a panel drag sees the window
    /// move under the pointer as with a real mouse), one event every 16 ms. Logs each step's outcome.
    private func runGestureScript() {
        let steps = arguments.gestureScript
        guard !steps.isEmpty else { return }
        model.open = { row in NSLog("\(AppInfo.name): gesture script: row click for %@ (not opened)", row.key.description) }
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1))
            for step in steps {
                guard let self else { return }
                switch step {
                case .wait(let seconds):
                    try? await Task.sleep(for: .seconds(seconds))
                case .menu:
                    let count = self.model.hiddenCount
                    NSLog("\(AppInfo.name): gesture script: menu item \"%@\" enabled %d", count > 0 ? MenuBar.hiddenItemTitle(count: count) : "(none)", count > 0 ? 1 : 0)
                case .edge:
                    self.clickEdgeTrigger()
                case .unhide:
                    self.model.showHiddenSessions()
                    NSLog("\(AppInfo.name): gesture script: show hidden sessions, rows now %d", self.model.rows.count)
                case let .drag(slot, dx, dy, duration, eased):
                    await self.scriptedDrag(slot: slot, dx: dx, dy: dy, duration: duration, eased: eased)
                }
            }
            NSLog("\(AppInfo.name): gesture script done")
        }
    }

    /// Clicks the middle of the hidden panel's edge trigger with a synthetic press and release posted
    /// to the app's event queue (the path a real click there takes), and logs whether one was there.
    private func clickEdgeTrigger() {
        guard let trigger = panel?.visibleEdgeTrigger else {
            NSLog("\(AppInfo.name): gesture script: no edge trigger (panel not concealed)")
            return
        }
        let point = NSPoint(x: trigger.frame.width / 2, y: trigger.frame.height / 2)
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            if let event = NSEvent.mouseEvent(
                with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: trigger.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0
            ) {
                NSApp.postEvent(event, atStart: false)
            }
        }
        NSLog("\(AppInfo.name): gesture script: clicked the edge trigger at %@", NSStringFromRect(trigger.frame))
    }

    /// One press on a session face's centre, a move by dx, dy (points, right and down) and a release.
    private func scriptedDrag(slot: Int, dx: CGFloat, dy: CGFloat, duration: TimeInterval, eased: Bool) async {
        guard let panel, slot < model.rows.count else {
            NSLog("\(AppInfo.name): gesture script: no row %d", slot)
            return
        }
        let frame = panel.frame
        // Screen point of the face centre (y up).
        let start = CGPoint(x: frame.minX + model.capsuleCenterX(inViewWidth: frame.width), y: frame.maxY - model.slotCenterY(slot: slot))
        let rowsBefore = model.rows.count
        let offsetBefore = panel.appliedOffset
        func post(_ type: NSEvent.EventType, at screen: CGPoint) {
            let origin = panel.frame.origin
            let location = NSPoint(x: screen.x - origin.x, y: screen.y - origin.y)
            if let event = NSEvent.mouseEvent(
                with: type, location: location, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: panel.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: type == .leftMouseUp ? 0 : 1
            ) {
                NSApp.postEvent(event, atStart: false)
            }
        }
        post(.leftMouseDown, at: start)
        let step = LaunchArguments.pointerGlideStep
        let count = max(Int(duration / step), 1)
        var point = start
        for index in 1...count {
            try? await Task.sleep(for: .seconds(step))
            let t = CGFloat(index) / CGFloat(count)
            let progress = eased ? t * t * (3 - 2 * t) : t
            point = CGPoint(x: start.x + dx * progress, y: start.y - dy * progress)
            post(.leftMouseDragged, at: point)
        }
        try? await Task.sleep(for: .seconds(step))
        post(.leftMouseUp, at: point)
        try? await Task.sleep(for: .milliseconds(50))
        NSLog(
            "\(AppInfo.name): gesture script: %@ slot %d by %.0f,%.0f over %.2f s: rows %d -> %d, offset %.0f -> %.0f, hidden %d",
            eased ? "drag" : "flick", slot, dx, dy, duration, rowsBefore, model.rows.count, offsetBefore, panel.appliedOffset, model.hiddenCount
        )
    }

    // MARK: `--open-first`

    /// Clicks the top face with a synthetic mouse event sent through the panel window (the
    /// path a real click takes inside the app); if the row action does not fire, calls it
    /// directly. The deep link is opened exactly once either way. Logs the frontmost app.
    private func openFirstRowAndQuit() {
        guard let panel, let model, let first = model.rows.first else {
            NSLog("\(AppInfo.name): --open-first found no rows, quitting")
            NSApp.terminate(nil)
            return
        }
        let realOpen = model.open
        var fired = false
        model.open = { row in
            fired = true
            NSLog("\(AppInfo.name): row action fired for %@, route %@", row.key.description, String(describing: SessionOpener.route(for: row)))
            realOpen(row)
        }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1))
            NSLog("\(AppInfo.name): frontmost before: %@", Self.frontmostDescription)
            let frame = panel.frame
            // The top row's centre (below the new session button when it shows).
            let point = NSPoint(x: model.capsuleCenterX(inViewWidth: frame.width), y: frame.height - model.slotCenterY(slot: 0))
            for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                if let event = NSEvent.mouseEvent(
                    with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                    windowNumber: panel.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0
                ) {
                    panel.sendEvent(event)
                }
                try? await Task.sleep(for: .milliseconds(80))
            }
            try? await Task.sleep(for: .milliseconds(400))
            if fired {
                NSLog("\(AppInfo.name): synthetic click reached the row action (panel key: %d)", panel.isKeyWindow ? 1 : 0)
            } else {
                NSLog("\(AppInfo.name): synthetic click did not fire the action, calling it directly")
                model.tapped(first)
            }
            try? await Task.sleep(for: .seconds(2))
            NSLog("\(AppInfo.name): frontmost after: %@", Self.frontmostDescription)
            NSApp.terminate(nil)
        }
    }

    private static var frontmostDescription: String {
        let app = NSWorkspace.shared.frontmostApplication
        return "\(app?.localizedName ?? "?") (\(app?.bundleIdentifier ?? "?"))"
    }
}
