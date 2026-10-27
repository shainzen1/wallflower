import Foundation
import Observation
import WallflowerHookCore

/// State of the welcome window: the page on screen, the direction of the last step (the slide
/// follows it), the look and the sound picked on their pages (applied as they change), the agents
/// ticked and the choices of the last page. `finish` hands the outcome to the owner.
@Observable @MainActor
final class WelcomeModel {
    /// The pages in order, 1-based.
    enum Page: Int, CaseIterable {
        case hello = 1
        /// "Shape is status": what the faces mean.
        case status
        case look
        case sound
        /// "Hover, click, drag".
        case gestures
        /// "Action faces": the saved prompts below the sessions.
        case actions
        case agents
        case setUp
    }

    nonisolated static let pageCount = Page.allCases.count
    /// "Pick a look", "Pick a sound" and "Which agents do you use?".
    nonisolated static let lookPage = Page.look.rawValue
    nonisolated static let soundPage = Page.sound.rawValue
    nonisolated static let agentsPage = Page.agents.rawValue

    /// "Pick a sound": the sound, volume and the two moments of Settings > Sound.
    struct SoundChoices: Equatable {
        var sound: SoundChoice
        var volume: Double
        var onDone: Bool
        var onNeedsInput: Bool

        /// The defaults of a first launch (`Theme`).
        static let standard = SoundChoices(sound: Theme.sound, volume: Theme.soundVolume, onDone: Theme.soundOnDone, onNeedsInput: Theme.soundOnNeedsInput)
    }

    /// What closed the window: "Start" with the choices of the last page and the agent plans the
    /// person confirmed, or a dismissal (Esc, the close button, ⌘W). Both count as done.
    enum Outcome: Equatable {
        case started(source: SessionSource, launchAtLogin: Bool, agents: [ChangePlan] = [])
        case dismissed
    }

    /// One row of "Which agents do you use?". Only what exists on this Mac is known here (folders
    /// and apps); no file of a tool is read before the person ticks it and presses Start.
    struct AgentChoice: Identifiable, Equatable {
        enum Kind: Equatable {
            /// Claude Code: always on, nothing to set up.
            case builtIn
            /// Wallflower connects it once ticked.
            case connectable(AgentTool)
            /// Shown greyed with its reason (coming soon, or not possible).
            case unavailable
        }

        let id: String
        let name: String
        let kind: Kind
        /// Under the name: what the faces can show, or why it is greyed.
        let note: String
        var isExperimental = false

        var tool: AgentTool? {
            if case .connectable(let tool) = kind { return tool }
            return nil
        }
    }

    /// One line of the confirmation that follows Start.
    enum AgentPlanItem: Equatable {
        /// These files change.
        case plan(ChangePlan)
        /// Wallflower can't write this one; the reason, and it is left for Settings > Agents.
        case manual(AgentTool, String)
    }

    /// 1-based page number.
    private(set) var page: Int
    /// True when the last step went forward (the new page slides in from the trailing edge).
    private(set) var movesForward = true
    /// "Where do you run Claude Code?"
    var sessionSource: SessionSource
    /// "Launch at login": on for a first launch, the login item's current state when the welcome runs
    /// again (`initialLaunchAtLogin`).
    var launchAtLogin: Bool
    /// "Pick a look": the Face and Colour of Settings > Appearance, written through `onLookChange`
    /// as they change, so the panel behind follows.
    var faceStyle: FaceStyle {
        didSet { if faceStyle != oldValue { onLookChange?(faceStyle, colorMode) } }
    }
    var colorMode: Theme.ColorMode {
        didSet { if colorMode != oldValue { onLookChange?(faceStyle, colorMode) } }
    }
    /// "Pick a sound": written through `onSoundChange` as it changes. Nothing plays by itself; only a
    /// picked sound and Preview do (`pickSound`, `previewSound`).
    var sound: SoundChoices {
        didSet { if sound != oldValue { onSoundChange?(sound) } }
    }
    /// The macOS sounds the picker offers, and the custom file's name when one was chosen in Settings.
    let systemSounds: [String]
    let customSoundName: String?
    /// "Which agents do you use?": Claude Code, then what was found on this Mac.
    let agentChoices: [AgentChoice]
    /// Agents Wallflower supports that are not on this Mac.
    let missingAgents: [String]
    /// Ticked agents: none until the person ticks one, so nothing is written without a tick.
    var pickedAgents: Set<AgentTool> = []
    /// The confirmation after Start while it shows (every file each ticked agent changes), else nil.
    private(set) var confirmation: [AgentPlanItem]?
    /// When the idle faces fell idle: when the window opened (fixed, so re-renders keep their loops).
    let idleSince = Date()
    /// Live sessions for a source, for the "No sessions yet" line of the last page.
    @ObservationIgnored var sessionCount: (SessionSource) -> Int
    /// Receives the outcome once; the window closes afterwards.
    @ObservationIgnored var onFinish: ((Outcome) -> Void)?
    /// Closes the window (Esc); the close then reports the dismissal.
    @ObservationIgnored var onRequestClose: (() -> Void)?
    /// Called right before the page changes, while the leaving page is still the one on screen.
    @ObservationIgnored var onPageWillChange: (() -> Void)?
    /// Writes a new face style or colour mode to the settings.
    @ObservationIgnored var onLookChange: ((FaceStyle, Theme.ColorMode) -> Void)?
    /// Writes the sound choices to the settings.
    @ObservationIgnored var onSoundChange: ((SoundChoices) -> Void)?
    /// Plays the sound in the settings once, at their volume.
    @ObservationIgnored var onPlaySound: (() -> Void)?
    /// The home the agents' paths are shown relative to (`~/.codex/hooks.json`).
    @ObservationIgnored var agentsHome = FileManager.default.homeDirectoryForCurrentUser
    /// Plans Connect for the ticked agents (the owner reads their files only now).
    @ObservationIgnored var planAgents: (Set<AgentTool>) -> [AgentPlanItem] = { _ in [] }
    @ObservationIgnored private(set) var isFinished = false

    init(
        page: Int = 1, sessionSource: SessionSource, launchAtLogin: Bool = true,
        faceStyle: FaceStyle = Theme.faceStyle, colorMode: Theme.ColorMode = Theme.colorMode,
        sound: SoundChoices = .standard, systemSounds: [String] = [], customSoundName: String? = nil,
        agentChoices: [AgentChoice] = [], missingAgents: [String] = [],
        sessionCount: @escaping (SessionSource) -> Int = { _ in 0 }
    ) {
        self.page = min(max(page, 1), Self.pageCount)
        self.sessionSource = sessionSource
        self.launchAtLogin = launchAtLogin
        self.faceStyle = faceStyle
        self.colorMode = colorMode
        self.sound = sound
        self.systemSounds = systemSounds
        self.customSoundName = customSoundName
        self.agentChoices = agentChoices
        self.missingAgents = missingAgents
        self.sessionCount = sessionCount
    }

    /// The welcome's agent list from the catalog: Claude Code, the agents found on this Mac (by
    /// folder or app only), then ChatGPT greyed, since that is what people ask about first. Without
    /// Codex on this Mac, Codex shows greyed above it with how to get it, so the ChatGPT line never
    /// points at a box that isn't there.
    static func agentChoices(environment: AgentEnvironment) -> (choices: [AgentChoice], missing: [String]) {
        var choices = [AgentChoice(
            id: "claude", name: "Claude Code", kind: .builtIn,
            note: AgentCatalog.hasClaudeCode(in: environment) ? "Built in, nothing to set up." : "Not found yet. Its sessions show once you use it."
        )]
        var missing: [String] = []
        for entry in AgentCatalog.entries {
            guard entry.isInstalled(in: environment) else {
                if entry.tool != nil { missing.append(entry.name) }
                continue
            }
            switch entry.kind {
            case .integration(let integration):
                choices.append(AgentChoice(id: entry.id, name: entry.name, kind: .connectable(integration.tool), note: entry.note, isExperimental: entry.isExperimental))
            case .comingSoon:
                choices.append(AgentChoice(id: entry.id, name: entry.name, kind: .unavailable, note: entry.note))
            }
        }
        let hasCodex = choices.contains { $0.tool == .codex }
        if !hasCodex {
            missing.removeAll { $0 == "Codex" }
            choices.append(AgentChoice(id: "codex", name: "Codex", kind: .unavailable, note: Self.codexMissingNote))
        }
        if let chatGPT = AgentCatalog.impossible.first {
            choices.append(AgentChoice(id: chatGPT.id, name: "ChatGPT", kind: .unavailable, note: hasCodex ? chatGPT.reason : Self.chatGPTWithoutCodexNote))
        }
        return (choices, missing)
    }

    /// Codex greyed: not on this Mac yet.
    static let codexMissingNote = "Not found on this Mac. Install the Codex CLI or the ChatGPT app, then connect it in Settings > Agents."
    /// ChatGPT greyed while Codex isn't installed either.
    static let chatGPTWithoutCodexNote = "ChatGPT doesn't share chat status with other apps. Codex does, once it's installed."

    /// The sound the picker shows (the ping for a custom sound without a file or a system sound this
    /// macOS lacks, as in Settings).
    var shownSound: SoundChoice {
        SoundSettingsView.shownChoice(sound.sound, customName: customSoundName, systemSounds: systemSounds)
    }

    /// The picker: writes the new sound and plays it once, so the person hears what they picked.
    func pickSound(_ choice: SoundChoice) {
        guard choice != sound.sound else { return }
        sound.sound = choice
        previewSound()
    }

    /// Preview (and the volume slider let go): plays the sound once, unless it is None or muted.
    func previewSound() {
        guard sound.sound != .none, sound.volume > 0 else { return }
        onPlaySound?()
    }

    func isPicked(_ tool: AgentTool) -> Bool {
        pickedAgents.contains(tool)
    }

    func setPicked(_ tool: AgentTool, _ picked: Bool) {
        if picked { pickedAgents.insert(tool) } else { pickedAgents.remove(tool) }
    }

    /// The confirmation's Connect: starts with the plans the person saw.
    func confirmStart() {
        let plans = (confirmation ?? []).compactMap { item -> ChangePlan? in
            if case .plan(let plan) = item { return plan }
            return nil
        }
        finish(.started(source: sessionSource, launchAtLogin: launchAtLogin, agents: plans))
    }

    /// Back from the confirmation to the last page.
    func cancelConfirmation() {
        confirmation = nil
    }

    /// The "Launch at login" switch's first value: on for a first launch; once onboarding was done,
    /// whether the app is a login item now, so "Start" on a re-run changes nothing the person set.
    nonisolated static func initialLaunchAtLogin(hasCompletedOnboarding: Bool, isEnabled: Bool) -> Bool {
        hasCompletedOnboarding ? isEnabled : true
    }

    var isFirstPage: Bool { page == 1 }
    var isLastPage: Bool { page == Self.pageCount }

    /// Title of the primary button.
    var primaryTitle: String { isLastPage ? "Start" : "Next" }

    /// Whether the last page says that no session runs yet (for the chosen source).
    var showsNoSessionsHint: Bool {
        sessionCount(sessionSource) == 0
    }

    /// The primary action: the next page, or "Start" on the last one. With agents ticked, Start first
    /// shows every file change in one confirmation.
    func primary() {
        if isLastPage {
            if confirmation != nil {
                confirmStart()
            } else if !pickedAgents.isEmpty {
                confirmation = planAgents(pickedAgents)
            } else {
                finish(.started(source: sessionSource, launchAtLogin: launchAtLogin))
            }
        } else {
            go(to: page + 1)
        }
    }

    func back() {
        go(to: page - 1)
    }

    func go(to target: Int) {
        let clamped = min(max(target, 1), Self.pageCount)
        guard clamped != page else { return }
        onPageWillChange?()
        movesForward = clamped > page
        page = clamped
    }

    /// Esc: back out of the confirmation, else close the window, which counts as done.
    func dismiss() {
        if confirmation != nil {
            confirmation = nil
            return
        }
        onRequestClose?()
    }

    /// Ends the welcome once; later calls do nothing (the close that follows "Start" is no dismissal).
    func finish(_ outcome: Outcome) {
        guard !isFinished else { return }
        isFinished = true
        onFinish?(outcome)
    }
}
