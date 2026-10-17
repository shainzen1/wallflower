import Foundation

/// Outcome of one pass over the registry folder.
struct RegistryScanResult: Sendable, Equatable {
    /// Decoded records of live processes that pass the entrypoint filter.
    var records: [SessionRecord] = []
    /// Pids of every `<pid>.json` whose process is alive, decodable or not.
    /// A session whose pid is here but not in `records` is mid-rewrite, not gone.
    var presentPids: Set<pid_t> = []
    /// Every `.json` file seen, for the per-file watchers.
    var fileURLs: [URL] = []
}
