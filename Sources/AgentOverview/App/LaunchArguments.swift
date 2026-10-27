import Foundation

/// Hidden launch arguments for scripted checks (no Accessibility permission needed).
struct LaunchArguments {
    /// `--sessions-folder <path>`: read this registry folder instead of `~/.claude/sessions`.
    var sessionsFolder: URL?
    /// `--external-sessions-folder <path>`: read the external sessions (other tools' files) from this
    /// folder instead of `~/Library/Application Support/Wallflower/sessions`.
    var externalSessionsFolder: URL?
    /// `--external-sessions <on|off>`: show sessions from other tools or not, overriding the stored setting.
    var externalSessions: Bool?
    /// `--sounds-folder <path>`: keep the custom sound's copy in this folder instead of
    /// `~/Library/Application Support/Wallflower/Sounds`.
    var soundsFolder: URL?
    /// `--sound <wallflower|custom|off|<system sound name>>`: the notification sound, overriding the stored setting.
    var sound: SoundChoice?
    /// `--sound-file <path>`: right after launch, install this file as the custom sound, as Choose
    /// File… would (checks, copy into the sounds folder), and log the result. Meant for `--sounds-folder` runs.
    var soundFile: URL?
    /// `--play-sound`: after the first scan, play the chosen sound once at the chosen volume and log it.
    var playSound = false
    /// `--tools-home <dir>`: detect and connect agents in this folder instead of the home folder (its
    /// `.codex`, `.gemini`, ... and `Applications`), keep Wallflower's side of it (helper, backups,
    /// manifest) inside it too, and read external sessions from its sessions folder unless
    /// `--external-sessions-folder` says otherwise. For checks that must never touch a real setup.
    var toolsHome: URL?
    /// `--agent-sheet <tool>`: with the Agents tab open, start Connect for that tool (its consent sheet,
    /// or the add-by-hand sheet), so a `settings-agents` snapshot captures it.
    var agentSheet: String?
    /// `--connect-agents <tool,tool,...>` and `--disconnect-agents <tool,...|all>`: right after launch,
    /// connect or disconnect these agents as the Agents tab would (plan, backup, write), log each
    /// result, and go on. Meant for `--tools-home` runs.
    var connectAgents: [String] = []
    var disconnectAgents: [String] = []
    /// `--open-first`: after the first scan, click the top row (synthetic event, falling back to the
    /// action itself), log the frontmost app before and after, then quit.
    var openFirst = false
    /// `--playground`: open the eye playground at launch.
    var playground = false
    /// `--goo <blurThreshold|path>`: goo renderer, overriding `Theme.gooRenderer`.
    var gooRenderer: Theme.GooRenderer?
    /// `--expand <row|all>`: expand mode, overriding `Theme.expandMode`.
    var expandMode: Theme.ExpandMode?
    /// `--face-style <dotMatrix|blob>`: face style, overriding `Theme.faceStyle`.
    var faceStyle: FaceStyle?
    /// `--face-filter <none|dotMatrix|asciiGrid|halftone|scanlines>`: screen filter, overriding `Theme.faceFilter`.
    var faceFilter: FaceFilter?
    /// `--blob-shape <status|identity>`: what the blob silhouette means, overriding `Theme.blobShapeMode`.
    var blobShapeMode: Theme.BlobShapeMode?
    /// `--color-mode <status|identity|project>`: what the body colour means, overriding `Theme.colorMode`.
    var colorMode: Theme.ColorMode?
    /// `--hover-effect <magnify|stretch|none>`: what a hover does to the faces, overriding `Theme.hoverEffect`.
    var hoverEffect: Theme.HoverEffect?
    /// `--action-launcher <terminalCommand|deepLinkAndSend|deepLinkNew>`: how action faces start their
    /// session, overriding the stored setting (and `Theme.actionLauncher`).
    var actionLauncher: Theme.ActionLauncher?
    /// `--session-source <desktop|terminal|everywhere>`: which sessions the panel shows, overriding the stored setting.
    var sessionSource: SessionSource?
    /// `--side <left|right>`: the screen edge the panel docks to, overriding the stored setting.
    var panelSide: PanelSide?
    /// `--autohide <never|empty|always>`: when the panel slides off its edge, overriding the stored setting.
    var panelAutoHide: PanelAutoHide?
    /// `--defaults-suite <name>`: read and write the settings in this `UserDefaults` suite instead of the
    /// standard defaults, so a scripted check starts from a known state and leaves the real settings alone.
    var defaultsSuite: String?
    /// `--updates <on|off>`: run the updater or not. Default: on, but off with `--defaults-suite`, since
    /// Sparkle keeps its state in the bundle's standard defaults and asks the real feed. Turn it on in a
    /// scripted launch only for a build with its own bundle id (see docs/DEVELOPMENT.md).
    var updates: Bool?
    /// `--check-for-updates <ui|background>`: check right after launch, as "Check Now" does (Sparkle's
    /// windows) or as the hourly schedule does (no window; a find only tints the menu bar glyph).
    var checkForUpdates: UpdateCheck?

    /// What `--check-for-updates` runs.
    enum UpdateCheck: String, Equatable {
        case ui, background
    }

    /// Whether this launch runs the updater (`--updates`, else off for a scripted launch).
    var runsUpdater: Bool {
        updates ?? (defaultsSuite == nil)
    }

    /// `--fake-pending-update <version>`: start as if a check had found this version, so the green
    /// menu bar glyph and the "Install Wallflower <version>…" item show without a feed. Only with
    /// `--defaults-suite`: a launch on the real settings ignores it.
    var fakePendingUpdate: String?

    /// `fakePendingUpdate` where it applies (a scripted launch), else nil.
    var pendingUpdateOverride: String? {
        defaultsSuite == nil ? nil : fakePendingUpdate
    }

    /// `--show-settings <general|appearance|sound|agents|whats-new|about>`: open the Settings window on that tab at launch.
    var showSettings: SettingsTab?
    /// `--whats-new`: open Settings on What's New at launch, as the first launch after an update does.
    var whatsNew = false
    /// `--whats-new-check`: run the after-update rule (`WhatsNewLaunch`) in a scripted launch too, on
    /// the suite's stored version, and log its decision.
    var whatsNewCheck = false

    /// Whether this launch applies the after-update rule: always, except in a scripted launch
    /// (`--defaults-suite`, `--snapshot`) unless `--whats-new-check` asks.
    var checksWhatsNew: Bool {
        whatsNewCheck || (defaultsSuite == nil && snapshot == nil)
    }
    /// `--welcome-keys <return,escape,...>`: with `--welcome`, press these keys in the welcome window one
    /// after the other (key equivalents first, as AppKit dispatches them), log the page after each, then quit.
    var welcomeKeys: [String] = []
    /// `--log-menu`: after the first scan, build the status menu once and log every item (title,
    /// subtitle, enabled, key equivalent), since a menu cannot be captured offscreen.
    var logMenu = false
    /// `--settings-advanced`: the Settings window opens with the Appearance tab's Advanced section
    /// expanded, and the Agents tab's Not possible popover open.
    var settingsAdvanced = false
    /// `--settings-scroll <points>`: with Settings open, scroll the tab down that far (at most to its end),
    /// so a snapshot shows the bottom of a tab taller than the window.
    var settingsScroll: Double?
    /// `--edit-action <index|new|select:<index>>`: with the General tab open, select that action and
    /// open its editor sheet, open the sheet for a new one, or only select the row. A `settings-general`
    /// snapshot then captures the sheet when one is open.
    var editAction: SettingsActionTarget?

    /// What `--edit-action` opens.
    enum SettingsActionTarget: Equatable {
        case new
        case edit(Int)
        case select(Int)

        init?(_ text: String) {
            if text == "new" { self = .new; return }
            if text.hasPrefix("select:"), let index = Int(text.dropFirst("select:".count)), index >= 0 {
                self = .select(index)
                return
            }
            guard let index = Int(text), index >= 0 else { return nil }
            self = .edit(index)
        }
    }
    /// `--welcome-agents <tool,...>`: tick these agents in the welcome; on the last page (`--welcome 8`)
    /// also press Start, so the confirmation of every file change shows (for snapshots).
    var welcomeAgents: [String] = []
    /// `--welcome <1-8>`: open the welcome window on that page at launch, whether or not it was completed.
    var welcomePage: Int?
    /// `--no-welcome`: never show the welcome window on its own at launch (scripted runs).
    var noWelcome = false
    /// `--set <key>=<value>` (repeatable): one second after the first scan, change these settings as
    /// Settings would (`AppSettings.Key` names, `StoredChoice` values; `launchAtLogin=on|off`), so the
    /// live rebuild can be checked.
    var scriptedSettings: [(key: String, value: String)] = []
    /// `--pointer-glide <fromRowIndex>,<toRowIndex>,<seconds>`: after the first scan, move the model's
    /// pointer smoothly down the capsule column from one slot centre to another over that long, hold
    /// briefly, then release it (a pointer cannot be scripted from outside). Debug only: it steps every 16 ms.
    var pointerGlide: PointerGlide?
    /// Step of `--pointer-glide`, and how long the pointer rests at the end before it is released.
    static let pointerGlideStep: TimeInterval = 0.016
    static let pointerGlideHold: TimeInterval = 0.4

    /// The scripted pointer glide: slot to slot over a duration.
    struct PointerGlide: Equatable {
        var fromSlot: Int
        var toSlot: Int
        var duration: TimeInterval

        init?(_ text: String) {
            let parts = text.split(separator: ",")
            guard parts.count == 3, let from = Int(parts[0]), let to = Int(parts[1]), let seconds = TimeInterval(parts[2]),
                  from >= 0, to >= 0, seconds > 0 else { return nil }
            fromSlot = from
            toSlot = to
            duration = seconds
        }
    }
    /// `--actions-file <path>`: read the action faces from this file instead of the Application Support one.
    var actionsFile: URL?
    /// `--run-action <index>`: after the first scan, click that action row (the real launcher runs).
    var runAction: Int?
    /// `--hover <rowIndex|action:<index>|new|none>`: hover that row (or action row, or the new session
    /// button) after the first scan,
    /// with the model's pointer on its centre (hover cannot be scripted from outside).
    var hover: HoverTarget?
    /// `--hover-sequence 0,2,none`: step through these hover targets after the first scan, one every
    /// `hoverSequenceInterval`, and stay on the last.
    var hoverSequence: [HoverTarget] = []
    /// `--excite <seconds>`: that long after the first scan, every working row's face plays the excited
    /// reaction as if its session had just started working (the playground reads the same argument
    /// for its heroes). For snapshots of the reaction; the real trigger is a status change.
    var exciteDelay: TimeInterval?
    /// Seconds between two steps of `--hover-sequence`.
    static let hoverSequenceInterval: TimeInterval = 1.2
    /// `--snapshot <path>`: after the first scan, the scripted hover and `snapshotDelay`, capture the
    /// panel window (or another target of `--snapshot-window`, which also opens it) to this PNG, then quit. `--snapshot-burst <count>:<milliseconds>` writes a numbered series
    /// (`<path>-1.png` ...) that many frames apart. `--snapshot-scale <factor>` sets the pixels per point (default 2).
    var snapshot: URL?
    var snapshotWindow: SnapshotWindow = .panel
    var snapshotDelay: TimeInterval = 1.5
    var snapshotBurst: (count: Int, interval: TimeInterval)?
    var snapshotScale: CGFloat = 2
    /// `--snapshot-method <layer|view|screenCaptureKit>`: in-process render of the presentation tree, AppKit's
    /// own drawing of the window's views, or the window server. Default: per target (`SnapshotWindow.method`).
    var snapshotMethod: WindowSnapshot.Method?
    /// `--snapshot-grow <start>:<step>`: burst frames show the attention grow at `start + i * step` seconds (rendered from the loop's curve).
    var snapshotGrow: (start: TimeInterval, step: TimeInterval)?

    /// `--log-frame`: log the panel's frame whenever it is set and on every screen-parameter or Space change (`DataLog.panel`).
    var logFrame = false
    /// `--gesture-script <step;step;...>`: after the first scan, press, move and release on the panel with
    /// synthetic left-button events posted to the app's event queue (the path a real pointer takes
    /// through `PanelDragController`), one step after the other. Steps: `drag:<slot>:<dx>,<dy>:<ms>`
    /// presses on that session face, moves the pointer by dx, dy (points, right and down) eased in and
    /// out over ms and releases at rest; `flick:<slot>:<dx>,<dy>:<ms>` the same at constant speed,
    /// released while moving; `wait:<ms>`; `menu` logs the "Show hidden sessions" item; `unhide`
    /// chooses it; `edge` clicks the hidden panel's edge trigger (auto-hide). Row clicks only log in this
    /// mode. Debug only.
    var gestureScript: [GestureStep] = []

    /// One step of `--gesture-script`.
    enum GestureStep: Equatable {
        case drag(slot: Int, dx: CGFloat, dy: CGFloat, duration: TimeInterval, eased: Bool)
        case wait(TimeInterval)
        case menu
        case unhide
        /// A click in the edge trigger of the hidden panel (`edge`): the path a pointer at the edge
        /// takes when it clicks there, which brings the panel out at once.
        case edge

        init?(_ text: String) {
            let parts = text.split(separator: ":").map(String.init)
            switch parts.first {
            case "drag", "flick":
                guard parts.count == 4, let slot = Int(parts[1]), let ms = Double(parts[3]), ms > 0 else { return nil }
                let delta = parts[2].split(separator: ",").compactMap { Double($0) }
                guard delta.count == 2 else { return nil }
                self = .drag(slot: slot, dx: delta[0], dy: delta[1], duration: ms / 1000, eased: parts[0] == "drag")
            case "wait":
                guard parts.count == 2, let ms = Double(parts[1]) else { return nil }
                self = .wait(ms / 1000)
            case "menu": self = .menu
            case "unhide": self = .unhide
            case "edge": self = .edge
            default: return nil
            }
        }
    }

    /// `--vertical-offset <pt>`: place the panel this far above the screen's vertical centre (negative is
    /// below), overriding the stored position without writing it; drags and resets are not persisted either.
    var verticalOffset: CGFloat?

    /// Which window `--snapshot` captures: `panel`, `playground`, `settings-<tab>`, `welcome-<page>`, or
    /// `menu-glyph` (the status item image in both states at 1x and 2x, plus an enlarged contact sheet).
    enum SnapshotWindow: Equatable {
        case panel
        case playground
        case settings(SettingsTab)
        case welcome(page: Int)
        case menuGlyph

        init?(_ text: String) {
            switch text {
            case "panel": self = .panel
            case "playground": self = .playground
            case "menu-glyph": self = .menuGlyph
            default:
                if text.hasPrefix("settings-"), let tab = SettingsTab(rawValue: String(text.dropFirst("settings-".count))) {
                    self = .settings(tab)
                } else if text.hasPrefix("welcome-"), let page = Int(text.dropFirst("welcome-".count)), (1...WelcomeModel.pageCount).contains(page) {
                    self = .welcome(page: page)
                } else {
                    return nil
                }
            }
        }

        var name: String {
            switch self {
            case .panel: "panel"
            case .playground: "playground"
            case .settings(let tab): "settings-\(tab.rawValue)"
            case .welcome(let page): "welcome-\(page)"
            case .menuGlyph: "menu-glyph"
            }
        }

        /// The capture method that renders this target correctly: the layer walk for the panel and the
        /// playground (running loops, transforms), AppKit's own drawing where controls matter.
        var method: WindowSnapshot.Method {
            switch self {
            case .panel, .playground, .menuGlyph: .layer
            case .settings, .welcome: .view
            }
        }
    }

    /// A scripted hover target: a session row index, an action row index (`action:<index>`), the new
    /// session button (`new`) or none.
    enum HoverTarget: Equatable {
        case row(Int)
        case action(Int)
        case newSession
        case none

        init?(_ text: String) {
            if text == "none" { self = .none; return }
            if text == "new" { self = .newSession; return }
            if text.hasPrefix("action:"), let index = Int(text.dropFirst("action:".count)), index >= 0 {
                self = .action(index)
                return
            }
            guard let index = Int(text), index >= 0 else { return nil }
            self = .row(index)
        }

        /// The slot index for a panel with `rowCount` session rows (actions come after them).
        func slotIndex(rowCount: Int) -> Int? {
            switch self {
            case .row(let index): index
            case .action(let index): rowCount + index
            case .newSession: PanelModel.newSessionSlot
            case .none: nil
            }
        }
    }

    /// The settings this run forces (launch argument over stored value over `Theme` default).
    var settingsOverrides: AppSettings.Overrides {
        AppSettings.Overrides(
            sessionSource: sessionSource, faceStyle: faceStyle, faceFilter: faceFilter, colorMode: colorMode,
            blobShapeMode: blobShapeMode, hoverEffect: hoverEffect, gooRenderer: gooRenderer, expandMode: expandMode,
            actionLauncher: actionLauncher, panelSide: panelSide, panelAutoHide: panelAutoHide, externalSessions: externalSessions,
            sound: sound
        )
    }

    init(_ arguments: [String] = CommandLine.arguments) {
        var iterator = arguments.dropFirst().makeIterator()
        while let argument = iterator.next() {
            switch argument {
            case "--sessions-folder":
                if let path = iterator.next() { sessionsFolder = URL(filePath: path, directoryHint: .isDirectory) }
            case "--external-sessions-folder":
                if let path = iterator.next() { externalSessionsFolder = URL(filePath: path, directoryHint: .isDirectory) }
            case "--external-sessions":
                if let text = iterator.next() { externalSessions = AppSettings.switchValue(text) }
            case "--sounds-folder":
                if let path = iterator.next() { soundsFolder = URL(filePath: path, directoryHint: .isDirectory) }
            case "--sound":
                if let text = iterator.next() { sound = SoundChoice(storedName: text) }
            case "--sound-file":
                if let path = iterator.next() { soundFile = URL(filePath: path, directoryHint: .notDirectory) }
            case "--play-sound": playSound = true
            case "--tools-home":
                if let path = iterator.next() { toolsHome = URL(filePath: path, directoryHint: .isDirectory) }
            case "--agent-sheet":
                agentSheet = iterator.next()
            case "--connect-agents":
                if let text = iterator.next() { connectAgents = text.split(separator: ",").map(String.init) }
            case "--disconnect-agents":
                if let text = iterator.next() { disconnectAgents = text.split(separator: ",").map(String.init) }
            case "--open-first": openFirst = true
            case "--log-frame": logFrame = true
            case "--vertical-offset":
                if let text = iterator.next(), let value = Double(text), value.isFinite { verticalOffset = CGFloat(value) }
            case "--playground": playground = true
            case "--goo":
                if let text = iterator.next() { gooRenderer = Theme.GooRenderer(storedName: text) }
            case "--expand":
                if let text = iterator.next() { expandMode = Theme.ExpandMode(storedName: text) }
            case "--face-style":
                if let text = iterator.next() { faceStyle = FaceStyle(rawValue: text) }
            case "--face-filter":
                if let text = iterator.next() { faceFilter = FaceFilter(rawValue: text) }
            case "--blob-shape":
                if let text = iterator.next() { blobShapeMode = Theme.BlobShapeMode(storedName: text) }
            case "--color-mode":
                if let text = iterator.next() { colorMode = Theme.ColorMode(rawValue: text) }
            case "--hover-effect":
                if let text = iterator.next() { hoverEffect = Theme.HoverEffect(rawValue: text) }
            case "--action-launcher":
                if let text = iterator.next() { actionLauncher = Theme.ActionLauncher(storedName: text) }
            case "--session-source":
                if let text = iterator.next() { sessionSource = SessionSource(rawValue: text) }
            case "--side":
                if let text = iterator.next() { panelSide = PanelSide(rawValue: text) }
            case "--autohide":
                if let text = iterator.next() { panelAutoHide = PanelAutoHide(rawValue: text) }
            case "--defaults-suite":
                if let text = iterator.next(), !text.isEmpty { defaultsSuite = text }
            case "--updates":
                if let text = iterator.next() { updates = AppSettings.switchValue(text) }
            case "--check-for-updates":
                if let text = iterator.next() { checkForUpdates = UpdateCheck(rawValue: text) }
            case "--fake-pending-update":
                if let text = iterator.next(), !text.isEmpty { fakePendingUpdate = text }
            case "--show-settings":
                if let text = iterator.next() { showSettings = SettingsTab(rawValue: text) }
            case "--whats-new": whatsNew = true
            case "--whats-new-check": whatsNewCheck = true
            case "--welcome":
                if let text = iterator.next(), let page = Int(text), (1...WelcomeModel.pageCount).contains(page) { welcomePage = page }
            case "--no-welcome": noWelcome = true
            case "--welcome-agents":
                if let text = iterator.next() { welcomeAgents = text.split(separator: ",").map(String.init) }
            case "--settings-advanced": settingsAdvanced = true
            case "--settings-scroll":
                if let text = iterator.next(), let points = Double(text) { settingsScroll = points }
            case "--edit-action":
                if let text = iterator.next() { editAction = SettingsActionTarget(text) }
            case "--log-menu": logMenu = true
            case "--welcome-keys":
                if let text = iterator.next() { welcomeKeys = text.split(separator: ",").map(String.init) }
            case "--set":
                if let text = iterator.next(), let equals = text.firstIndex(of: "=") {
                    scriptedSettings.append((String(text[..<equals]), String(text[text.index(after: equals)...])))
                }
            case "--pointer-glide":
                if let text = iterator.next() { pointerGlide = PointerGlide(text) }
            case "--actions-file":
                if let path = iterator.next() { actionsFile = URL(filePath: path, directoryHint: .notDirectory) }
            case "--run-action":
                if let text = iterator.next(), let index = Int(text), index >= 0 { runAction = index }
            case "--snapshot":
                if let path = iterator.next() { snapshot = URL(filePath: path, directoryHint: .notDirectory) }
            case "--snapshot-window":
                if let text = iterator.next(), let window = SnapshotWindow(text) { snapshotWindow = window }
            case "--snapshot-delay":
                if let text = iterator.next(), let delay = TimeInterval(text) { snapshotDelay = delay }
            case "--snapshot-method":
                if let text = iterator.next(), let method = WindowSnapshot.Method(rawValue: text) { snapshotMethod = method }
            case "--snapshot-grow":
                if let text = iterator.next() {
                    let parts = text.split(separator: ":")
                    if parts.count == 2, let start = Double(parts[0]), let step = Double(parts[1]) { snapshotGrow = (start, step) }
                }
            case "--snapshot-scale":
                if let text = iterator.next(), let scale = Double(text), scale > 0 { snapshotScale = scale }
            case "--snapshot-burst":
                if let text = iterator.next() {
                    let parts = text.split(separator: ":")
                    if parts.count == 2, let count = Int(parts[0]), let ms = Double(parts[1]), count > 0 {
                        snapshotBurst = (count, ms / 1000)
                    }
                }
            case "--gesture-script":
                if let text = iterator.next() { gestureScript = text.split(separator: ";").compactMap { GestureStep(String($0)) } }
            case "--hover":
                if let text = iterator.next() { hover = HoverTarget(text) }
            case "--excite":
                if let text = iterator.next(), let delay = TimeInterval(text), delay >= 0 { exciteDelay = delay }
            case "--hover-sequence":
                if let text = iterator.next() {
                    hoverSequence = text.split(separator: ",").compactMap { HoverTarget(String($0)) }
                }
            default: break
            }
        }
    }
}
