import Foundation

/// Which sessions the panel shows, by the registry's `entrypoint`.
enum SessionSource: String, CaseIterable, Sendable {
    /// Sessions of the Claude desktop app (`claude-desktop`).
    case desktop
    /// Sessions started in a terminal or an editor (`cli`, `sdk-cli` for `claude -p`, `claude-vscode`).
    case terminal
    /// Every session, whatever started it.
    case everywhere

    /// The entrypoint filter of the session store; nil keeps every session.
    var entrypoints: Set<String>? {
        switch self {
        case .desktop: DataTuning.desktopEntrypoints
        case .terminal: DataTuning.terminalEntrypoints
        case .everywhere: nil
        }
    }

    /// Label in Settings.
    var title: String {
        switch self {
        case .desktop: "Claude app"
        case .terminal: "Terminal & editors"
        case .everywhere: "Everywhere"
        }
    }

    /// Label in the welcome window's segmented control, short enough that the three segments fit
    /// its card (`WelcomeStyle.setUpContentWidth`); "Terminal" covers the editors there too.
    var shortTitle: String {
        switch self {
        case .desktop: "Claude app"
        case .terminal: "Terminal"
        case .everywhere: "Everywhere"
        }
    }
}

/// A setting value stored in `UserDefaults` (and accepted by a launch argument) under a short name.
/// The `Theme` enums without raw values get their names here, so `Theme.swift` stays untouched.
protocol StoredChoice: Equatable {
    static var storedChoices: [Self] { get }
    var storedName: String { get }
}

extension StoredChoice {
    /// The value stored under `name`, nil for an unknown name.
    init?(storedName name: String) {
        guard let value = Self.storedChoices.first(where: { $0.storedName == name }) else { return nil }
        self = value
    }
}

extension StoredChoice where Self: RawRepresentable, Self.RawValue == String, Self: CaseIterable {
    static var storedChoices: [Self] { Array(allCases) }
    var storedName: String { rawValue }
}

extension SessionSource: StoredChoice {}
extension FaceStyle: StoredChoice {}
extension FaceFilter: StoredChoice {}
extension Theme.ColorMode: StoredChoice {}
extension Theme.HoverEffect: StoredChoice {}
extension PanelSide: StoredChoice {}

extension Theme.BlobShapeMode: StoredChoice {
    static var storedChoices: [Theme.BlobShapeMode] { [.status, .identity] }
    var storedName: String {
        switch self {
        case .status: "status"
        case .identity: "identity"
        }
    }
}

extension Theme.ExpandMode: StoredChoice {
    static var storedChoices: [Theme.ExpandMode] { [.row, .all] }
    var storedName: String {
        switch self {
        case .row: "row"
        case .all: "all"
        }
    }
}

extension Theme.GooRenderer: StoredChoice {
    static var storedChoices: [Theme.GooRenderer] { [.blurThreshold, .path, .sdfShader] }
    var storedName: String {
        switch self {
        case .blurThreshold: "blurThreshold"
        case .path: "path"
        case .sdfShader: "sdfShader"
        }
    }
}

extension Theme.ActionLauncher: StoredChoice {
    static var storedChoices: [Theme.ActionLauncher] { [.terminalCommand, .deepLinkAndSend, .deepLinkNew] }
    var storedName: String {
        switch self {
        case .terminalCommand: "terminalCommand"
        case .deepLinkAndSend: "deepLinkAndSend"
        case .deepLinkNew: "deepLinkNew"
        }
    }
}

// MARK: Labels in Settings

extension FaceStyle {
    var settingsTitle: String {
        switch self {
        case .blob: "Blob"
        case .dotMatrix: "Dot matrix"
        }
    }

    /// Settings order: the default first.
    static let settingsOrder: [FaceStyle] = [.blob, .dotMatrix]
}

extension FaceFilter {
    var settingsTitle: String {
        switch self {
        case .none: "None"
        case .dotMatrix: "LED dots"
        case .asciiGrid: "ASCII"
        case .halftone: "Halftone"
        case .scanlines: "Scanlines"
        }
    }
}

extension Theme.ColorMode {
    var settingsTitle: String {
        switch self {
        case .status: "Status"
        case .project: "Project"
        case .identity: "Per session"
        }
    }

    static let settingsOrder: [Theme.ColorMode] = [.status, .project, .identity]
}

extension Theme.BlobShapeMode {
    var settingsTitle: String {
        switch self {
        case .status: "Status"
        case .identity: "Per session"
        }
    }
}

extension Theme.HoverEffect {
    var settingsTitle: String {
        switch self {
        case .magnify: "Magnify"
        case .stretch: "Stretch"
        case .none: "None"
        }
    }
}

extension Theme.GooRenderer {
    var settingsTitle: String {
        switch self {
        case .blurThreshold: "Liquid"
        case .path, .sdfShader: "Crisp path"
        }
    }

    /// The renderers Settings offers (the shader falls back to the path anyway).
    static let settingsChoices: [Theme.GooRenderer] = [.blurThreshold, .path]
}

extension Theme.ExpandMode {
    var settingsTitle: String {
        switch self {
        case .row: "Hovered row"
        case .all: "Whole column"
        }
    }
}

extension Theme.ActionLauncher {
    var settingsTitle: String {
        switch self {
        case .terminalCommand: "Terminal"
        case .deepLinkAndSend, .deepLinkNew: "Claude app"
        }
    }

    /// The launchers Settings offers (the prefill-only deep link stays a launch argument).
    static let settingsChoices: [Theme.ActionLauncher] = [.terminalCommand, .deepLinkAndSend]

    /// Whether this launcher presses Return in Claude, which needs Accessibility.
    var needsAccessibility: Bool { self == .deepLinkAndSend }
}
