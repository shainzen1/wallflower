import Foundation

/// What plays when a session is done or needs input (Settings > Sound). Stored under a short name:
/// `wallflower`, `system:<name>`, `custom` or `none`.
enum SoundChoice: Hashable, Sendable {
    /// "Wallflower ping", the default sound (`Packaging/Sounds/ping.wav`, used with permission, see THIRD_PARTY_NOTICES.md).
    case wallflowerPing
    /// A macOS system sound by name (`Glass`), played from `/System/Library/Sounds`, never bundled.
    case system(String)
    /// The person's own file, copied into the sounds folder (`AppSettings.customSoundName`).
    case custom
    /// Silence.
    case none

    var storedName: String {
        switch self {
        case .wallflowerPing: "wallflower"
        case .system(let name): "system:\(name)"
        case .custom: "custom"
        case .none: "none"
        }
    }

    /// The choice stored under `name`. Also reads what `--sound` accepts: `off` for none, and a
    /// system sound's plain name (`Glass`). Nil for an empty name.
    init?(storedName name: String) {
        switch name {
        case "wallflower": self = .wallflowerPing
        case "custom": self = .custom
        case "none", "off": self = .none
        case "": return nil
        default:
            let system = name.hasPrefix("system:") ? String(name.dropFirst("system:".count)) : name
            guard !system.isEmpty else { return nil }
            self = .system(system)
        }
    }

    /// Label in Settings (a custom file shows its file name instead).
    var settingsTitle: String {
        switch self {
        case .wallflowerPing: "Wallflower ping"
        case .system(let name): name
        case .custom: "Custom"
        case .none: "None"
        }
    }
}
