import Foundation

/// When the panel slides off its screen edge (Settings > General > Hide the panel, `panelAutoHide`),
/// the way the Dock hides: hidden, it comes back while the pointer rests at that edge in the panel's
/// band (`PanelWindow`'s edge trigger) and slides away again once the pointer left it.
enum PanelAutoHide: String, CaseIterable, Sendable {
    /// Always on the edge (the behaviour before auto-hide).
    case never
    /// Off the edge while nothing runs: no session faces and no action faces. The new session button
    /// alone counts as nothing; the reveal is how the person reaches it.
    case empty
    /// Off the edge whatever runs, for a free edge, except while a session needs input.
    case always

    /// The `Theme` default.
    static let `default` = Theme.panelAutoHide

    /// Whether the panel rests hidden with `sessions` session faces and `actions` action faces shown,
    /// `needsInput` saying whether any of those sessions waits for the person.
    ///
    /// In `.always` a session that needs input brings the whole panel out and keeps it out until
    /// nothing waits any more: such a session is blocked until the person answers, the face hops as
    /// it arrives, and the amber face is the panel's loudest signal. A your-turn session does not:
    /// it is not blocked, it comes after every finished turn, and someone who picked `.always` asked
    /// for a free edge. The menu bar glyph carries the needs-input signal as well.
    func restsHidden(sessions: Int, actions: Int, needsInput: Bool) -> Bool {
        switch self {
        case .never: false
        case .empty: sessions == 0 && actions == 0
        case .always: !needsInput
        }
    }

    /// Label in Settings.
    var title: String {
        switch self {
        case .never: "Never"
        case .empty: "When nothing is running"
        case .always: "Always"
        }
    }

    /// The Settings footnote sentence for this choice, nil for `.never`.
    var footnote: String? {
        switch self {
        case .never: nil
        case .empty: "With nothing running it slides off the edge; rest the pointer on that edge to bring it back."
        case .always: "It stays off the edge until the pointer rests there, or until a session needs you."
        }
    }
}

/// The auto-hide sequencing, free of AppKit so tests drive it: whether the panel is out or slid off
/// the edge (`setConcealed`), from the mode's rule (`PanelAutoHide.restsHidden`), the pointer and the
/// welcome window. `AppDelegate` feeds it the store counts, the edge trigger and the pointer moves,
/// and applies the result to `PanelWindow`.
///
/// Out while the rule says hidden: the pointer brought it out at the edge (`edgeReached`), or the rule
/// turned to hidden while the panel was out (the last face left, nothing waits any more). Either way
/// it is held by the pointer: it slides away `hideDelay` after the pointer left it (no button down),
/// or `lingerDelay` after the rule turned when the pointer was elsewhere, so the last face is seen
/// leaving. While held, `watchPointer(true)` asks for pointer moves (`pointerChanged`); at rest nothing
/// runs: each delay is one sleeping task, cancelled or done.
@MainActor
final class AutoHideController {
    /// The mode; a change applies at once (a panel that has to hide lingers first).
    var mode: PanelAutoHide {
        didSet { if mode != oldValue { apply() } }
    }
    /// Slides the panel off the edge (true) or back (false); `animated` is false for the first state at launch.
    var setConcealed: (@MainActor (_ concealed: Bool, _ animated: Bool) -> Void)?
    /// Whether the pointer is on the panel's window right now.
    var pointerIsOnPanel: @MainActor () -> Bool = { false }
    /// Whether a mouse button is down (a drag or a throw in progress keeps the panel out).
    var isButtonDown: @MainActor () -> Bool = { false }
    /// Starts (true) or stops (false) the pointer reports to `pointerChanged`, while the pointer holds the panel out.
    var watchPointer: (@MainActor (Bool) -> Void)?
    /// Receives one line per decision (`--log-frame`).
    var log: (@MainActor (String) -> Void)?
    /// After the pointer left the panel (`Theme.autoHideDelay`; tests shorten it).
    var hideDelay: TimeInterval = Theme.autoHideDelay
    /// After the rule turned to hidden while the panel was out (`Theme.autoHideLinger`; tests shorten it).
    var lingerDelay: TimeInterval = Theme.autoHideLinger

    /// What was last applied: nil before the first decision, then whether the panel is off the edge.
    private(set) var isConcealed: Bool?
    /// The last store counts (`update`).
    private var inputs = (sessions: 0, actions: 0, needsInput: false)
    /// The mode's rule for the current stores.
    var restsHidden: Bool {
        mode.restsHidden(sessions: inputs.sessions, actions: inputs.actions, needsInput: inputs.needsInput)
    }
    /// Out until the pointer is away from it.
    private(set) var isHeldByPointer = false
    /// Out whatever the rule says (the welcome window is open).
    private(set) var isPinned = false
    private var hideTask: Task<Void, Never>?

    init(mode: PanelAutoHide) {
        self.mode = mode
    }

    /// The stores changed: `sessions` session faces, `actions` action faces, `needsInput` whether any waits.
    func update(sessions: Int, actions: Int, needsInput: Bool) {
        let rested = restsHidden
        inputs = (sessions, actions, needsInput)
        guard restsHidden != rested || isConcealed == nil else { return }
        apply()
    }

    /// Keeps the panel out while the welcome window is open (and lets it go after).
    func setPinned(_ pinned: Bool) {
        guard pinned != isPinned else { return }
        isPinned = pinned
        apply()
    }

    /// The pointer rested at the edge in the panel's band (the edge trigger): out it comes.
    func edgeReached() {
        guard restsHidden, isConcealed == true else { return }
        log?("auto-hide: edge reached, revealing")
        hold(after: hideDelay)
        apply()
    }

    /// The pointer moved or a button came up while it holds the panel out: it slides away `hideDelay`
    /// after the pointer is off the panel with no button down; back on it, it stays.
    func pointerChanged() {
        guard isHeldByPointer else { return }
        if pointerIsOnPanel() || isButtonDown() {
            cancelHide()
        } else if hideTask == nil {
            scheduleHide(after: hideDelay)
        }
    }

    // MARK: Private

    /// Applies the rule. `lingers`: a panel that is out when the rule says hidden waits `lingerDelay`
    /// first (false once that wait, or the pointer's hold, is over).
    private func apply(lingers: Bool = true) {
        let animated = isConcealed != nil
        guard restsHidden else {
            release()
            conceal(false, animated: animated)
            return
        }
        if isPinned {
            conceal(false, animated: animated)
            return
        }
        if isHeldByPointer {
            conceal(false, animated: animated)
            return
        }
        if isConcealed == false, lingers {
            // The rule turned to hidden while the panel was out: it lingers, held by the pointer.
            hold(after: lingerDelay)
            return
        }
        conceal(true, animated: animated)
    }

    /// The pointer holds the panel out from now on; it goes `delay` from now unless the pointer is on it.
    private func hold(after delay: TimeInterval) {
        if !isHeldByPointer {
            isHeldByPointer = true
            watchPointer?(true)
        }
        cancelHide()
        if !pointerIsOnPanel() { scheduleHide(after: delay) }
    }

    private func release() {
        cancelHide()
        guard isHeldByPointer else { return }
        isHeldByPointer = false
        watchPointer?(false)
    }

    private func scheduleHide(after delay: TimeInterval) {
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self else { return }
            self.hideTask = nil
            // Still on the panel (no move reported yet) or pressed: the next report decides.
            guard !self.pointerIsOnPanel(), !self.isButtonDown() else { return }
            self.release()
            self.apply(lingers: false)
        }
    }

    private func cancelHide() {
        hideTask?.cancel()
        hideTask = nil
    }

    private func conceal(_ concealed: Bool, animated: Bool) {
        guard isConcealed != concealed else { return }
        isConcealed = concealed
        log?("auto-hide: \(concealed ? "concealed" : "revealed") (mode \(mode.rawValue), rests hidden \(restsHidden), held \(isHeldByPointer), pinned \(isPinned), animated \(animated))")
        setConcealed?(concealed, animated)
    }
}
