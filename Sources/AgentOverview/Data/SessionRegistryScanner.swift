import Foundation
import Synchronization

/// Reads every `<pid>.json` in the registry folder. Pure: give it a folder, get a result.
/// `.key` files and anything that is not `.json` are ignored, undecodable files are
/// dropped (logged once per file name at debug level), files of dead processes are stale and skipped.
enum SessionRegistryScanner {
    /// - Parameter entrypoints: keep only records whose `entrypoint` is in the set; `nil` keeps all.
    static func scan(
        folder: URL,
        entrypoints: Set<String>? = DataTuning.defaultEntrypoints
    ) -> RegistryScanResult {
        var result = RegistryScanResult()
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        ) else {
            return result
        }

        var byPid: [pid_t: SessionRecord] = [:]
        for url in entries where url.pathExtension == "json" {
            result.fileURLs.append(url)
            let namePid = pid_t(url.deletingPathExtension().lastPathComponent)
            guard let data = try? Data(contentsOf: url), let record = decode(data, fileName: url.lastPathComponent) else {
                if let namePid, isAlive(namePid) { result.presentPids.insert(namePid) }
                continue
            }
            guard isAlive(record.pid) else { continue }
            result.presentPids.insert(record.pid)
            guard entrypoints?.contains(record.entrypoint) ?? true else { continue }
            // Two files naming the same pid: keep the most recently updated one.
            if let existing = byPid[record.pid], (existing.updatedAt ?? 0) > (record.updatedAt ?? 0) { continue }
            byPid[record.pid] = record
        }
        result.records = byPid.values.sorted { $0.pid < $1.pid }
        return result
    }

    /// `kill(pid, 0)` succeeds for our own processes; `EPERM` means it exists but belongs to someone else.
    static func isAlive(_ pid: pid_t) -> Bool {
        guard pid > 0 else { return false }
        if kill(pid, 0) == 0 { return true }
        return errno == EPERM
    }

    static func decode(_ data: Data, fileName: String? = nil) -> SessionRecord? {
        do {
            return try JSONDecoder().decode(SessionRecord.self, from: data)
        } catch {
            if let fileName { reportUndecodable(fileName) }
            return nil
        }
    }

    // MARK: Private

    private static let reportedFiles = Mutex<Set<String>>([])

    private static func reportUndecodable(_ fileName: String) {
        let firstTime = reportedFiles.withLock { $0.insert(fileName).inserted }
        if firstTime {
            DataLog.registry.debug("Skipping undecodable registry file \(fileName, privacy: .public)")
        }
    }
}
