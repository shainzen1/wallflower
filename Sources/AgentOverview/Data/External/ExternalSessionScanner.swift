import Foundation
import Synchronization

/// Outcome of one pass over the external sessions folder.
struct ExternalScanResult: Sendable, Equatable {
    /// Decoded records of live sessions, by id.
    var records: [ExternalSessionRecord] = []
    /// Ids of every live session file, decodable or not (an undecodable file counts by its name while
    /// it is fresh): a session whose id is here but not in `records` is mid-rewrite, not gone.
    var presentIDs: Set<String> = []
    /// Every `.json` file seen, for the per-file watchers.
    var fileURLs: [URL] = []
    /// When the next pid-less record runs out of its TTL: the watcher rescans then, once.
    var nextExpiry: Date?
}

/// Reads every `<id>.json` in the external sessions folder (`docs/external-sessions.md`). Pure: give
/// it a folder and a time, get a result. Hidden files and anything that is not `.json` are ignored,
/// undecodable files are logged once per name and skipped. Liveness: a record with a `pid` lives while
/// that process does; one without lives for `ttl` after its last write (`updatedAt` or the file's
/// modification date, whichever is later).
enum ExternalSessionScanner {
    static func scan(folder: URL, now: Date = Date(), ttl: TimeInterval = DataTuning.externalSessionTTL) -> ExternalScanResult {
        var result = ExternalScanResult()
        let keys: [URLResourceKey] = [.contentModificationDateKey, .creationDateKey]
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]
        ) else {
            return result
        }

        var byID: [String: ExternalSessionRecord] = [:]
        for url in entries where url.pathExtension == "json" {
            result.fileURLs.append(url)
            let values = try? url.resourceValues(forKeys: Set(keys))
            guard let data = try? Data(contentsOf: url), var record = decode(data, fileName: url.lastPathComponent) else {
                // Mid-rewrite (or broken): keep a session of that name for as long as the file is fresh.
                if let modified = values?.contentModificationDate, now.timeIntervalSince(modified) < ttl {
                    result.presentIDs.insert(url.deletingPathExtension().lastPathComponent)
                }
                continue
            }
            record.fileModified = values?.contentModificationDate
            record.fileCreated = values?.creationDate

            if let pid = record.pid {
                guard SessionRegistryScanner.isAlive(pid) else { continue }
            } else {
                guard let fresh = record.freshness else { continue }
                let expiry = fresh.addingTimeInterval(ttl)
                guard expiry > now else { continue }
                result.nextExpiry = min(result.nextExpiry ?? expiry, expiry)
            }
            result.presentIDs.insert(record.id)
            // Two files naming the same id: keep the most recently written one.
            if let existing = byID[record.id], (existing.freshness ?? .distantPast) > (record.freshness ?? .distantPast) { continue }
            byID[record.id] = record
        }
        result.records = byID.values.sorted { $0.id < $1.id }
        return result
    }

    static func decode(_ data: Data, fileName: String? = nil) -> ExternalSessionRecord? {
        do {
            return try JSONDecoder().decode(ExternalSessionRecord.self, from: data)
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
            DataLog.registry.debug("Skipping malformed external session file \(fileName, privacy: .public)")
        }
    }
}
