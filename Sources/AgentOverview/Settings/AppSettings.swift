import Foundation
import Observation

/// The person's settings, stored in `UserDefaults` (the standard defaults in the app, a suite in tests).
///
/// Precedence per value: a launch argument (`Overrides`) wins, then the stored value, then the `Theme`
/// default; `Theme` stays the one source of defaults. A launch argument is never written back; a value
/// set here (from Settings or the welcome window) is stored and replaces it for the rest of the run.
/// `AppDelegate` observes the panel values and applies a change live.
@Observable @MainActor
final class AppSettings {
    /// Values a launch argument forces for this run.
    struct Overrides: Equatable {
        var sessionSource: SessionSource?
        var faceStyle: FaceStyle?
        var faceFilter: FaceFilter?
        var colorMode: Theme.ColorMode?
        var blobShapeMode: Theme.BlobShapeMode?
        var hoverEffect: Theme.HoverEffect?
        var gooRenderer: Theme.GooRenderer?
        var expandMode: Theme.ExpandMode?
        var actionLauncher: Theme.ActionLauncher?
        var newSessionButton: Bool?
        var panelSide: PanelSide?
        var panelAutoHide: PanelAutoHide?
        var externalSessions: Bool?
        var sound: SoundChoice?
    }

    /// `UserDefaults` keys.
    enum Key {
        static let sessionSource = "sessionSource"
        static let faceStyle = "faceStyle"
        static let faceFilter = "faceFilter"
        static let colorMode = "colorMode"
        static let blobShapeMode = "blobShapeMode"
        static let hoverEffect = "hoverEffect"
        static let gooRenderer = "gooRenderer"
        static let expandMode = "expandMode"
        static let actionLauncher = "actionLauncher"
        static let newSessionButton = "newSessionButton"
        static let panelSide = "panelSide"
        static let panelAutoHide = "panelAutoHide"
        static let externalSessions = "externalSessions"
        static let hasCompletedOnboarding = "hasCompletedOnboarding"
        static let lastSeenVersion = "lastSeenVersion"
        static let hiddenAgentTools = "hiddenAgentTools"
        static let sound = "sound"
        static let customSoundName = "customSoundName"
        static let soundVolume = "soundVolume"
        static let soundOnDone = "soundOnDone"
        static let soundOnNeedsInput = "soundOnNeedsInput"
        static let soundSkipsFrontmost = "soundSkipsFrontmost"

        /// Every appearance key ("Restore defaults" clears these).
        static let appearance = [faceStyle, faceFilter, colorMode, blobShapeMode, hoverEffect, gooRenderer, expandMode]
    }

    /// Which sessions the panel shows. Default: the Claude app's.
    var sessionSource: SessionSource { didSet { store(sessionSource, Key.sessionSource) } }
    var faceStyle: FaceStyle { didSet { store(faceStyle, Key.faceStyle) } }
    var faceFilter: FaceFilter { didSet { store(faceFilter, Key.faceFilter) } }
    var colorMode: Theme.ColorMode { didSet { store(colorMode, Key.colorMode) } }
    var blobShapeMode: Theme.BlobShapeMode { didSet { store(blobShapeMode, Key.blobShapeMode) } }
    var hoverEffect: Theme.HoverEffect { didSet { store(hoverEffect, Key.hoverEffect) } }
    var gooRenderer: Theme.GooRenderer { didSet { store(gooRenderer, Key.gooRenderer) } }
    var expandMode: Theme.ExpandMode { didSet { store(expandMode, Key.expandMode) } }
    /// How an action face starts its session: in a terminal, or in the Claude app (prefill plus Return).
    /// Read at click time, so a change needs no rebuild.
    var actionLauncher: Theme.ActionLauncher { didSet { store(actionLauncher, Key.actionLauncher) } }
    /// Whether the new session button shows at the top of the column. Default: `Theme.newSessionButton` (on).
    var newSessionButton: Bool {
        didSet { defaults.set(newSessionButton, forKey: Key.newSessionButton) }
    }
    /// Whether sessions from other tools (the external sessions folder) show. Default:
    /// `Theme.externalSessions` (on). Not filtered by `sessionSource`, which is about Claude sessions only.
    var externalSessions: Bool {
        didSet { defaults.set(externalSessions, forKey: Key.externalSessions) }
    }
    /// The screen edge the panel docks to (Settings > General > Panel side). Default: the right edge.
    /// A change moves the panel live (`AppDelegate`); not an appearance value, so "Restore defaults"
    /// in the Appearance tab leaves it alone.
    var panelSide: PanelSide { didSet { store(panelSide, Key.panelSide) } }
    /// When the panel slides off its edge (Settings > General > Hide the panel). Default: while nothing
    /// runs (`Theme.panelAutoHide`). Applied live by `AutoHideController`, no rebuild.
    var panelAutoHide: PanelAutoHide { didSet { store(panelAutoHide, Key.panelAutoHide) } }
    /// Agents whose faces are hidden (Settings > Agents, a tool's Show switch off), by tool id. Hiding
    /// only filters the faces; the tool's hooks stay connected.
    var hiddenAgentTools: Set<String> {
        didSet { defaults.set(hiddenAgentTools.sorted(), forKey: Key.hiddenAgentTools) }
    }
    /// What plays when a session is done or needs input (Settings > Sound). Default: `Theme.sound`.
    var sound: SoundChoice {
        didSet { defaults.set(sound.storedName, forKey: Key.sound) }
    }
    /// The file name of the custom sound's copy in the sounds folder; nil until one was chosen.
    var customSoundName: String? {
        didSet { defaults.set(customSoundName, forKey: Key.customSoundName) }
    }
    /// Playback volume, 0 to 1. Default: `Theme.soundVolume`.
    var soundVolume: Double {
        didSet { defaults.set(soundVolume, forKey: Key.soundVolume) }
    }
    /// Whether a session turning to your turn plays the sound. Default: `Theme.soundOnDone` (on).
    var soundOnDone: Bool {
        didSet { defaults.set(soundOnDone, forKey: Key.soundOnDone) }
    }
    /// Whether a session starting to wait for input plays the sound. Default: `Theme.soundOnNeedsInput` (on).
    var soundOnNeedsInput: Bool {
        didSet { defaults.set(soundOnNeedsInput, forKey: Key.soundOnNeedsInput) }
    }
    /// "Not while the agent's app is in front". Default: `Theme.soundSkipsFrontmost` (on).
    var soundSkipsFrontmost: Bool {
        didSet { defaults.set(soundSkipsFrontmost, forKey: Key.soundSkipsFrontmost) }
    }
    /// Set when the welcome window was finished or dismissed; until then it shows at launch.
    var hasCompletedOnboarding: Bool {
        didSet { defaults.set(hasCompletedOnboarding, forKey: Key.hasCompletedOnboarding) }
    }

    /// The version the last launch ran (`CFBundleShortVersionString`); nil before the first launch that
    /// recorded one. A newer running version opens What's New once (`WhatsNewLaunch`).
    var lastSeenVersion: String? {
        didSet { defaults.set(lastSeenVersion, forKey: Key.lastSeenVersion) }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard, overrides: Overrides = Overrides()) {
        self.defaults = defaults
        sessionSource = overrides.sessionSource ?? Self.read(defaults, Key.sessionSource) ?? .desktop
        faceStyle = overrides.faceStyle ?? Self.read(defaults, Key.faceStyle) ?? Theme.faceStyle
        faceFilter = overrides.faceFilter ?? Self.read(defaults, Key.faceFilter) ?? Theme.faceFilter
        colorMode = overrides.colorMode ?? Self.read(defaults, Key.colorMode) ?? Theme.colorMode
        blobShapeMode = overrides.blobShapeMode ?? Self.read(defaults, Key.blobShapeMode) ?? Theme.blobShapeMode
        hoverEffect = overrides.hoverEffect ?? Self.read(defaults, Key.hoverEffect) ?? Theme.hoverEffect
        gooRenderer = overrides.gooRenderer ?? Self.read(defaults, Key.gooRenderer) ?? Theme.gooRenderer
        expandMode = overrides.expandMode ?? Self.read(defaults, Key.expandMode) ?? Theme.expandMode
        actionLauncher = overrides.actionLauncher ?? Self.read(defaults, Key.actionLauncher) ?? Theme.actionLauncher
        newSessionButton = overrides.newSessionButton
            ?? (defaults.object(forKey: Key.newSessionButton) as? Bool)
            ?? Theme.newSessionButton
        panelSide = overrides.panelSide ?? Self.read(defaults, Key.panelSide) ?? .default
        panelAutoHide = overrides.panelAutoHide ?? Self.read(defaults, Key.panelAutoHide) ?? .default
        externalSessions = overrides.externalSessions
            ?? (defaults.object(forKey: Key.externalSessions) as? Bool)
            ?? Theme.externalSessions
        sound = overrides.sound ?? defaults.string(forKey: Key.sound).flatMap { SoundChoice(storedName: $0) } ?? Theme.sound
        customSoundName = defaults.string(forKey: Key.customSoundName).flatMap { $0.isEmpty ? nil : $0 }
        soundVolume = (defaults.object(forKey: Key.soundVolume) as? Double).map { min(max($0, 0), 1) } ?? Theme.soundVolume
        soundOnDone = (defaults.object(forKey: Key.soundOnDone) as? Bool) ?? Theme.soundOnDone
        soundOnNeedsInput = (defaults.object(forKey: Key.soundOnNeedsInput) as? Bool) ?? Theme.soundOnNeedsInput
        soundSkipsFrontmost = (defaults.object(forKey: Key.soundSkipsFrontmost) as? Bool) ?? Theme.soundSkipsFrontmost
        hasCompletedOnboarding = defaults.bool(forKey: Key.hasCompletedOnboarding)
        lastSeenVersion = defaults.string(forKey: Key.lastSeenVersion).flatMap { $0.isEmpty ? nil : $0 }
        hiddenAgentTools = Set(defaults.stringArray(forKey: Key.hiddenAgentTools) ?? [])
    }

    /// Everything the panel is drawn with, as one value: a change of any of it rebuilds the panel content.
    var look: PanelLook {
        PanelLook(
            faceStyle: faceStyle, faceFilter: faceFilter, colorMode: colorMode, blobShapeMode: blobShapeMode,
            hoverEffect: hoverEffect, gooRenderer: gooRenderer, expandMode: expandMode
        )
    }

    /// "Restore defaults" in the Appearance tab: the `Theme` values, and nothing stored any more.
    func restoreAppearanceDefaults() {
        faceStyle = Theme.faceStyle
        faceFilter = Theme.faceFilter
        colorMode = Theme.colorMode
        blobShapeMode = Theme.blobShapeMode
        hoverEffect = Theme.hoverEffect
        gooRenderer = Theme.gooRenderer
        expandMode = Theme.expandMode
        Key.appearance.forEach(defaults.removeObject(forKey:))
    }

    /// The sound switches as the announcer reads them.
    var soundOptions: SoundAnnouncer.Options {
        SoundAnnouncer.Options(onDone: soundOnDone, onNeedsInput: soundOnNeedsInput, skipsFrontmost: soundSkipsFrontmost)
    }

    /// Whether every appearance value is the `Theme` default ("Restore defaults" is disabled then).
    var isAppearanceDefault: Bool {
        look == PanelLook.themeDefault
    }

    /// Sets one value by its key and stored name, as Settings would (`--set <key>=<value>`).
    /// Returns false for an unknown key or value.
    @discardableResult
    func setValue(_ name: String, forKey key: String) -> Bool {
        func set<Value: StoredChoice>(_ path: ReferenceWritableKeyPath<AppSettings, Value>) -> Bool {
            guard let value = Value(storedName: name) else { return false }
            self[keyPath: path] = value
            return true
        }
        switch key {
        case Key.sessionSource: return set(\.sessionSource)
        case Key.faceStyle: return set(\.faceStyle)
        case Key.faceFilter: return set(\.faceFilter)
        case Key.colorMode: return set(\.colorMode)
        case Key.blobShapeMode: return set(\.blobShapeMode)
        case Key.hoverEffect: return set(\.hoverEffect)
        case Key.gooRenderer: return set(\.gooRenderer)
        case Key.expandMode: return set(\.expandMode)
        case Key.actionLauncher: return set(\.actionLauncher)
        case Key.panelSide: return set(\.panelSide)
        case Key.panelAutoHide: return set(\.panelAutoHide)
        case Key.newSessionButton:
            guard let value = Self.switchValue(name) else { return false }
            newSessionButton = value
            return true
        case Key.externalSessions:
            guard let value = Self.switchValue(name) else { return false }
            externalSessions = value
            return true
        case Key.sound:
            guard let value = SoundChoice(storedName: name) else { return false }
            sound = value
            return true
        case Key.soundVolume:
            guard let value = Double(name), value.isFinite, (0...1).contains(value) else { return false }
            soundVolume = value
            return true
        case Key.soundOnDone, Key.soundOnNeedsInput, Key.soundSkipsFrontmost:
            guard let value = Self.switchValue(name) else { return false }
            switch key {
            case Key.soundOnDone: soundOnDone = value
            case Key.soundOnNeedsInput: soundOnNeedsInput = value
            default: soundSkipsFrontmost = value
            }
            return true
        case Key.hasCompletedOnboarding:
            guard let value = Bool(name) else { return false }
            hasCompletedOnboarding = value
            return true
        default: return false
        }
    }

    /// A switch value by name: `on` or `true`, `off` or `false`; nil for anything else.
    nonisolated static func switchValue(_ name: String) -> Bool? {
        switch name.lowercased() {
        case "on", "true": true
        case "off", "false": false
        default: nil
        }
    }

    // MARK: Private

    private func store<Value: StoredChoice>(_ value: Value, _ key: String) {
        defaults.set(value.storedName, forKey: key)
    }

    private static func read<Value: StoredChoice>(_ defaults: UserDefaults, _ key: String) -> Value? {
        // A direct call, not `flatMap(Value.init(storedName:))`: that method reference would carry this
        // actor's isolation into a nonisolated closure.
        guard let name = defaults.string(forKey: key) else { return nil }
        return Value(storedName: name)
    }
}

/// The values the panel content is built with. `AppDelegate` compares the applied one with the
/// settings' one and rebuilds once per change.
struct PanelLook: Equatable {
    var faceStyle: FaceStyle
    var faceFilter: FaceFilter
    var colorMode: Theme.ColorMode
    var blobShapeMode: Theme.BlobShapeMode
    var hoverEffect: Theme.HoverEffect
    var gooRenderer: Theme.GooRenderer
    var expandMode: Theme.ExpandMode

    static let themeDefault = PanelLook(
        faceStyle: Theme.faceStyle, faceFilter: Theme.faceFilter, colorMode: Theme.colorMode, blobShapeMode: Theme.blobShapeMode,
        hoverEffect: Theme.hoverEffect, gooRenderer: Theme.gooRenderer, expandMode: Theme.expandMode
    )

    /// Puts the face values into `FaceLook`, where every `FaceView` reads them.
    @MainActor
    func applyToFaceLook() {
        FaceLook.style = faceStyle
        FaceLook.filter = faceFilter
        FaceLook.blobShapeMode = blobShapeMode
        FaceLook.colorMode = colorMode
        FaceLook.hoverEffect = hoverEffect
    }
}
