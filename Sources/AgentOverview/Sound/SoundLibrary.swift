import Foundation

/// Where the sounds come from: the bundled ping, the macOS system sounds (read from
/// `/System/Library/Sounds` at runtime, never copied) and the custom file in the sounds folder.
enum SoundLibrary {
    /// The bundled ping's file name in `Contents/Resources` (`scripts/bundle.sh`).
    static let pingResource = "ping"
    static let pingExtension = "wav"
    /// The macOS system sounds.
    static let systemFolder = URL(filePath: "/System/Library/Sounds", directoryHint: .isDirectory)

    /// `~/Library/Application Support/Wallflower/Sounds/`: the copy of the custom sound (`--sounds-folder` overrides it).
    static var defaultFolder: URL {
        AppInfo.supportFolder.appending(path: "Sounds", directoryHint: .isDirectory)
    }

    /// The ping in the app bundle. A debug build outside a bundle (`swift run`, tests) uses the
    /// checkout's `Packaging` copy; a release binary never carries the source path.
    static var pingURL: URL? {
        if let url = Bundle.main.url(forResource: pingResource, withExtension: pingExtension) { return url }
        #if DEBUG
        let checkout = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let url = checkout.appending(path: "Packaging/Sounds/\(pingResource).\(pingExtension)")
        if FileManager.default.fileExists(atPath: url.path) { return url }
        #endif
        return nil
    }

    /// The system sounds' names (`Basso`, `Blow`, ... `Tink`), sorted, from `folder`.
    static func systemSoundNames(in folder: URL = systemFolder) -> [String] {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        let names = files.filter { CustomSound.allowedExtensions.contains($0.pathExtension.lowercased()) }
            .map { $0.deletingPathExtension().lastPathComponent }
        return Array(Set(names)).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    /// The file of the system sound `name`, nil when this macOS has none by that name.
    static func systemSoundURL(named name: String, in folder: URL = systemFolder) -> URL? {
        guard !name.contains("/") else { return nil }
        for ext in ["aiff", "aif", "caf", "wav"] {
            let url = folder.appending(path: "\(name).\(ext)")
            if FileManager.default.fileExists(atPath: url.path) { return url }
        }
        return nil
    }

    /// The file a choice plays. A missing system sound or custom file falls back to the ping, so a
    /// renamed sound in a later macOS or a deleted copy never silences the app; `.none` is nil.
    static func url(for choice: SoundChoice, customName: String?, folder: URL) -> URL? {
        switch choice {
        case .none:
            return nil
        case .wallflowerPing:
            return pingURL
        case .system(let name):
            return systemSoundURL(named: name) ?? pingURL
        case .custom:
            guard let customName, let url = CustomSound.installedURL(named: customName, in: folder) else { return pingURL }
            return url
        }
    }
}
