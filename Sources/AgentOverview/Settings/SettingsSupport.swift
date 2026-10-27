import AppKit
import Observation
import ServiceManagement

/// The tabs of the Settings window.
enum SettingsTab: String, CaseIterable, Sendable {
    case general, appearance, sound, agents
    case whatsNew = "whats-new"
    case about

    var title: String {
        switch self {
        case .general: "General"
        case .appearance: "Appearance"
        case .sound: "Sound"
        case .agents: "Agents"
        case .whatsNew: "What's New"
        case .about: "About"
        }
    }

    /// SF Symbol of the toolbar item.
    var symbolName: String {
        switch self {
        case .general: "gearshape"
        case .appearance: "paintpalette"
        case .sound: "speaker.wave.2"
        case .agents: "person.2"
        case .whatsNew: "sparkles"
        case .about: "info.circle"
        }
    }
}

/// What the Settings window can ask the app to do. `AppDelegate` fills it in.
@MainActor
struct SettingsActions {
    var resetPosition: () -> Void = {}
    var editActions: () -> Void = {}
    var openPlayground: () -> Void = {}
    var showWelcome: () -> Void = {}
}

/// "Launch at login" through `SMAppService.mainApp`. Only an app bundle registers: a bare build
/// (`swift run`, the debug binary) would otherwise become a login item itself, and a translocated
/// copy (a download run from where it landed) from a path that is gone after the next launch, so both
/// get the note instead, as does a failed registration.
@Observable @MainActor
final class LaunchAtLogin {
    /// Whether the app is registered as a login item right now.
    private(set) var isEnabled = false
    /// A short inline explanation when the last change did not take, nil otherwise.
    private(set) var note: String?
    /// The system wants the person to approve the login item in System Settings.
    private(set) var needsApproval = false

    static let moveNote = "Move \(AppInfo.name) to Applications to launch at login."
    static let approvalNote = "Allow \(AppInfo.name) in Login Items to launch at login."

    init() {
        refresh()
    }

    /// Whether this process runs from an app bundle, the only thing that should launch at login.
    static var isAvailable: Bool {
        isRegistrable(bundleURL: Bundle.main.bundleURL)
    }

    /// Whether the app at `bundleURL` may become a login item: an app bundle, and not a translocated
    /// copy (macOS runs an unmoved quarantined download from a random path under `/AppTranslocation/`).
    nonisolated static func isRegistrable(bundleURL: URL) -> Bool {
        bundleURL.pathExtension == "app" && !bundleURL.path.contains("/AppTranslocation/")
    }

    /// Reads the service status again (the person may have changed it in System Settings).
    func refresh() {
        let status = SMAppService.mainApp.status
        isEnabled = status == .enabled
        needsApproval = status == .requiresApproval
        if needsApproval { note = Self.approvalNote } else if isEnabled { note = nil }
    }

    /// Registers or unregisters the app. Returns whether the requested state holds afterwards.
    @discardableResult
    func set(_ enabled: Bool) -> Bool {
        let service = SMAppService.mainApp
        guard Self.isAvailable || !enabled else {
            note = Self.moveNote
            refresh()
            return false
        }
        do {
            if enabled { try service.register() } else { try service.unregister() }
            note = nil
        } catch {
            NSLog("\(AppInfo.name): launch at login change failed: %@", error.localizedDescription)
            note = enabled ? Self.moveNote : nil
        }
        refresh()
        NSLog("\(AppInfo.name): launch at login %@: status %d", enabled ? "on" : "off", SMAppService.mainApp.status.rawValue)
        return isEnabled == enabled
    }

    func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}

/// Whether action clicks may press Return in Claude (Accessibility). Read again whenever the
/// Settings window becomes key, so a change in System Settings shows up when the person comes back.
@Observable @MainActor
final class AccessibilityAccess {
    private(set) var isTrusted = false

    init() {
        refresh()
    }

    func refresh() {
        let trusted = ActionSender.isTrusted(prompt: false)
        if trusted != isTrusted { isTrusted = trusted }
    }

    func openSettings() {
        ActionSender.openAccessibilitySettings()
    }
}
