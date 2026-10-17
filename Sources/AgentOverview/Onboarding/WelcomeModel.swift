import Foundation
import Observation

/// State of the welcome window: the page on screen, the direction of the last step (the slide
/// follows it), and the choices of the last page. `finish` hands the outcome to the owner.
@Observable @MainActor
final class WelcomeModel {
    nonisolated static let pageCount = 4

    /// What closed the window: "Start" with the choices of the last page, or a dismissal (Esc, the
    /// close button, ⌘W). Both count as done.
    enum Outcome: Equatable {
        case started(source: SessionSource, launchAtLogin: Bool)
        case dismissed
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
    @ObservationIgnored private(set) var isFinished = false

    init(
        page: Int = 1, sessionSource: SessionSource, launchAtLogin: Bool = true,
        sessionCount: @escaping (SessionSource) -> Int = { _ in 0 }
    ) {
        self.page = min(max(page, 1), Self.pageCount)
        self.sessionSource = sessionSource
        self.launchAtLogin = launchAtLogin
        self.sessionCount = sessionCount
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

    /// The primary action: the next page, or "Start" on the last one.
    func primary() {
        if isLastPage {
            finish(.started(source: sessionSource, launchAtLogin: launchAtLogin))
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

    /// Esc: closes the window, which counts as done.
    func dismiss() {
        onRequestClose?()
    }

    /// Ends the welcome once; later calls do nothing (the close that follows "Start" is no dismissal).
    func finish(_ outcome: Outcome) {
        guard !isFinished else { return }
        isFinished = true
        onFinish?(outcome)
    }
}
