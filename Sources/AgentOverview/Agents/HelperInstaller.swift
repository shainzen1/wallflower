import Foundation
import WallflowerHookCore

/// Keeps the hook helper at its stable path, `~/.local/share/wallflower/bin/wallflower-hook`, the
/// path every hook command names: the app carries it in `Contents/Helpers`, and a copy outside the
/// app survives moving or updating the app. Copied on Connect, refreshed at launch only when a copy
/// exists and differs, removed with the last disconnect.
struct HelperInstaller: Sendable {
    let environment: AgentEnvironment
    /// The helper that ships with this build.
    let source: URL?

    /// `Contents/Helpers/wallflower-hook` in the app bundle, else next to the executable (a bare
    /// `swift build`, where SwiftPM puts both products in one folder).
    static var bundledHelper: URL? {
        let bundled = Bundle.main.bundleURL.appending(path: "Contents/Helpers/\(HelperLayout.helperName)")
        if FileManager.default.isExecutableFile(atPath: bundled.path) { return bundled }
        let sibling = Bundle.main.executableURL?.deletingLastPathComponent().appending(path: HelperLayout.helperName)
        return sibling.flatMap { FileManager.default.isExecutableFile(atPath: $0.path) ? $0 : nil }
    }

    enum InstallError: Error, LocalizedError {
        case missingHelper

        var errorDescription: String? { "This copy of Wallflower has no hook helper. Reinstall Wallflower and try again." }
    }

    var isInstalled: Bool {
        FileManager.default.isExecutableFile(atPath: environment.helperURL.path)
    }

    /// Copies the helper into place when it is missing or differs. Returns the folders it created.
    @discardableResult
    func install() throws -> [URL] {
        guard let source, let data = try? Data(contentsOf: source) else { throw InstallError.missingHelper }
        let target = environment.helperURL
        if (try? Data(contentsOf: target)) == data { return [] }
        var created: [URL] = []
        var folder = target.deletingLastPathComponent()
        while folder.path.count > environment.home.path.count, !FileManager.default.fileExists(atPath: folder.path) {
            created.insert(folder, at: 0)
            folder = folder.deletingLastPathComponent()
        }
        for directory in created {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        }
        let temp = target.deletingLastPathComponent().appending(path: ".\(HelperLayout.helperName).tmp")
        try data.write(to: temp)
        try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: 0o755)], ofItemAtPath: temp.path)
        if rename(temp.path, target.path) != 0 {
            try? FileManager.default.removeItem(at: temp)
            throw CocoaError(.fileWriteUnknown)
        }
        return created
    }

    /// At launch: replaces an installed helper that differs from this build's (an update). Does
    /// nothing when no helper is installed, so a Mac that never connected an agent gets no file.
    func refreshIfInstalled() {
        guard isInstalled else { return }
        _ = try? install()
    }

    /// Removes the helper and the folders Wallflower created for it, if they are empty then.
    func uninstall(createdDirectories: [String]) {
        try? FileManager.default.removeItem(at: environment.helperURL)
        IntegrationStore(environment: environment).removeEmptyDirectories(createdDirectories)
    }
}
