import CryptoKit
import Darwin
import Foundation
import WallflowerHookCore

/// What Wallflower wrote into other tools' folders, kept in its own folder (`integrations.json`), so
/// a disconnect removes exactly that: the files it created, the keys it added, and a backup of every
/// file it changed.
struct IntegrationManifest: Codable, Equatable, Sendable {
    struct FileRecord: Codable, Equatable, Sendable {
        var path: String
        /// Wallflower created the file (it did not exist): a disconnect may delete it.
        var createdFile: Bool
        var createdDirectories: [String] = []
        var createdKeys: [[String]] = []
        /// SHA-256 of the file before and right after Wallflower's write.
        var beforeHash: String?
        var writtenHash: String
        /// The copy of the file before the write, in Wallflower's backups folder.
        var backup: String?
    }

    struct ToolRecord: Codable, Equatable, Sendable {
        var connectedAt: Date
        var files: [FileRecord]

        func file(_ url: URL) -> FileRecord? {
            files.first { $0.path == url.path }
        }
    }

    var tools: [String: ToolRecord] = [:]
    /// Folders Wallflower created for the helper (`~/.local/share/wallflower/bin` and its parents).
    var helperDirectories: [String] = []
}

/// Applies change plans safely: the conflict check, the backup, the atomic write, the manifest.
struct IntegrationStore: Sendable {
    let environment: AgentEnvironment
    /// Backups kept per file.
    static let backupsKept = 5

    enum ApplyError: Error, Equatable, LocalizedError {
        /// The file changed between the plan and the write: nothing was written.
        case changedSinceRead(URL)
        case writeFailed(URL, String)

        var errorDescription: String? {
            switch self {
            case .changedSinceRead(let url): "\(url.lastPathComponent) changed while Wallflower was about to write it. Nothing was changed; try again."
            case .writeFailed(let url, let reason): "Couldn't write \(url.lastPathComponent): \(reason)"
            }
        }
    }

    // MARK: Manifest

    func loadManifest() -> IntegrationManifest {
        guard let data = try? Data(contentsOf: environment.manifestURL) else { return IntegrationManifest() }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(IntegrationManifest.self, from: data)) ?? IntegrationManifest()
    }

    func saveManifest(_ manifest: IntegrationManifest) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try FileManager.default.createDirectory(at: environment.supportFolder, withIntermediateDirectories: true)
        try encoder.encode(manifest).write(to: environment.manifestURL, options: .atomic)
    }

    // MARK: Applying

    /// Writes a connect plan and records it. Every file is checked first; one that changed since the
    /// plan aborts the whole plan before anything is written.
    func applyConnect(_ plan: ChangePlan) throws {
        try checkUnchanged(plan)
        var manifest = loadManifest()
        var record = manifest.tools[plan.tool.rawValue] ?? IntegrationManifest.ToolRecord(connectedAt: Date(), files: [])
        for change in plan.changes {
            let backup = try change.before.map { try backUp($0, of: change.url, tool: plan.tool) }
            let created = try createDirectories(change.createdDirectories)
            try write(change)
            guard let after = change.after else { continue }
            let previous = record.file(change.url)
            let file = IntegrationManifest.FileRecord(
                path: change.url.path,
                createdFile: previous?.createdFile ?? change.createsFile,
                createdDirectories: (previous?.createdDirectories ?? []) + created.map(\.path),
                createdKeys: (previous?.createdKeys ?? []) + change.createdKeys,
                // A repair keeps the first backup: the file as it was before Wallflower ever touched it.
                beforeHash: previous == nil ? change.before.map(Self.hash) : previous?.beforeHash,
                writtenHash: Self.hash(after),
                backup: previous == nil ? backup?.path : previous?.backup
            )
            record.files.removeAll { $0.path == change.url.path }
            record.files.append(file)
        }
        record.connectedAt = Date()
        manifest.tools[plan.tool.rawValue] = record
        try saveManifest(manifest)
    }

    /// Writes a disconnect plan, removes folders Wallflower created that are empty now, and forgets the tool.
    func applyDisconnect(_ plan: ChangePlan) throws {
        try checkUnchanged(plan)
        var manifest = loadManifest()
        let record = manifest.tools[plan.tool.rawValue]
        for change in plan.changes {
            if let before = change.before, change.after != nil { _ = try backUp(before, of: change.url, tool: plan.tool) }
            try write(change)
        }
        let directories = (record?.files ?? []).flatMap(\.createdDirectories) + plan.changes.flatMap { $0.createdDirectories.map(\.path) }
        removeEmptyDirectories(directories)
        manifest.tools[plan.tool.rawValue] = nil
        try saveManifest(manifest)
    }

    static func hash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// The file's bytes, nil when it does not exist.
    static func read(_ url: URL) -> Data? {
        FileManager.default.fileExists(atPath: url.path) ? try? Data(contentsOf: url) : nil
    }

    static func isSymlink(_ url: URL) -> Bool {
        (try? FileManager.default.destinationOfSymbolicLink(atPath: url.path)) != nil
    }

    /// Removes the given folders, deepest first, each only if it is empty.
    func removeEmptyDirectories(_ paths: [String]) {
        for path in Set(paths).sorted(by: { $0.count > $1.count }) {
            guard path.hasPrefix(environment.home.path), let contents = try? FileManager.default.contentsOfDirectory(atPath: path),
                  contents.allSatisfy({ $0 == ".DS_Store" }) else { continue }
            try? FileManager.default.removeItem(atPath: path)
        }
    }

    // MARK: Private

    private func checkUnchanged(_ plan: ChangePlan) throws {
        for change in plan.changes where Self.read(change.url) != change.before {
            throw ApplyError.changedSinceRead(change.url)
        }
    }

    /// Copies `data` into `backups/<tool>/<file name>.<timestamp>` and keeps the newest `backupsKept`.
    private func backUp(_ data: Data, of url: URL, tool: AgentTool) throws -> URL {
        let folder = environment.backupsFolder.appending(path: tool.rawValue, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss-SSS"
        let name = url.lastPathComponent
        let backup = folder.appending(path: "\(name).\(formatter.string(from: Date()))")
        try data.write(to: backup, options: .atomic)
        let existing = ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [])
            .filter { $0.hasPrefix(name + ".") }
            .sorted()
        for old in existing.dropLast(Self.backupsKept) {
            try? FileManager.default.removeItem(at: folder.appending(path: old))
        }
        return backup
    }

    /// Creates the folders that are missing, returns the ones it created.
    private func createDirectories(_ directories: [URL]) throws -> [URL] {
        var created: [URL] = []
        for directory in directories where !FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
            created.append(directory)
        }
        return created
    }

    /// Replaces the file atomically (temp file in the same folder, then rename), keeping its
    /// permissions; deletes it for `after == nil`. Checks once more right before the rename.
    private func write(_ change: FileChange) throws {
        let url = change.url
        guard let after = change.after else {
            if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
            return
        }
        let folder = url.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: folder.path) {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        let temp = folder.appending(path: ".\(url.lastPathComponent).wallflower-\(getpid()).tmp")
        do {
            try after.write(to: temp)
            let permissions = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.posixPermissions] as? NSNumber
            try FileManager.default.setAttributes([.posixPermissions: permissions ?? NSNumber(value: 0o644)], ofItemAtPath: temp.path)
            guard Self.read(url) == change.before else {
                try? FileManager.default.removeItem(at: temp)
                throw ApplyError.changedSinceRead(url)
            }
            guard rename(temp.path, url.path) == 0 else {
                throw ApplyError.writeFailed(url, String(cString: strerror(errno)))
            }
        } catch let error as ApplyError {
            try? FileManager.default.removeItem(at: temp)
            throw error
        } catch {
            try? FileManager.default.removeItem(at: temp)
            throw ApplyError.writeFailed(url, error.localizedDescription)
        }
    }
}
