import Foundation

/// Counts the live subagents of a session from its `subagents` folder.
///
/// Liveness rule (verified 13-10-26 against a session with twelve subagents, ten finished, two running):
/// - `agent-<id>.meta.json` holds only launch data (`agentType`, `description`, `toolUseId`, `spawnDepth`,
///   `requestShape`, `requestNonInteractive`, optional `worktreePath` / `worktreeBranch` / `spawnedWithWorktree`);
///   no status, no end time. Its mtime is the launch time.
/// - A finished subagent's `agent-<id>.jsonl` ends with an assistant `tool_use` named `SubagentHandback`
///   followed by the `user` line holding its `tool_result`. Every finished agent looked like that; the two
///   running ones ended with an ordinary tool call or an attachment. `stop_reason` is unreliable in these
///   files (mostly null), so it is not used.
/// - Claude Code also writes `agent-<id>.prefix.json` when the agent completes (its mtime equals the
///   transcript's final mtime, give or take a second). It is absent for running agents. It serves as the
///   cheap first check and as the fallback for an agent that ended without a hand-back call.
/// - A subagent that was stopped or lost mid-flight keeps counting as live until its transcript changes;
///   a continued (resumed) subagent appends to the same file and so becomes live again.
///
/// Verdicts are cached per file by size and mtime, so an event that changed nothing costs one
/// directory listing plus a stat per file.
enum SubagentScanner {
    /// Cache entry: the file stamp the verdict was computed for.
    struct Verdict: Equatable, Sendable {
        var stamp: FileStamp
        var finished: Bool
    }

    /// Number of `agent-*.jsonl` files in `folder` whose agent has not finished. 0 when the folder is missing.
    static func liveCount(in folder: URL, tailBytes: Int, cache: inout [String: Verdict]) -> Int {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        ) else {
            cache.removeAll()
            return 0
        }
        var live = 0
        var seen: Set<String> = []
        for url in entries where url.pathExtension == "jsonl" && url.lastPathComponent.hasPrefix("agent-") {
            let id = String(url.deletingPathExtension().lastPathComponent.dropFirst("agent-".count))
            seen.insert(id)
            guard let stamp = FileStamp(path: url.path) else { continue }
            if let known = cache[id], known.stamp == stamp {
                if !known.finished { live += 1 }
                continue
            }
            let finished = isFinished(transcript: url, modified: stamp.modified, tailBytes: tailBytes)
            cache[id] = Verdict(stamp: stamp, finished: finished)
            if !finished { live += 1 }
        }
        for id in cache.keys where !seen.contains(id) { cache[id] = nil }
        return live
    }

    /// The prefix file written at completion is checked first (one stat); otherwise the tail decides.
    static func isFinished(transcript url: URL, modified: Date, tailBytes: Int) -> Bool {
        let prefix = url.deletingPathExtension().appendingPathExtension("prefix.json")
        if let prefixModified = FileStamp(path: prefix.path)?.modified, prefixModified.addingTimeInterval(2) >= modified {
            return true
        }
        guard let tail = try? TranscriptTail.read(url: url, maxBytes: tailBytes) else { return false }
        return isFinished(tail: tail.data, startsMidFile: tail.startsMidFile)
    }

    /// Pure rule on a transcript tail: the last message line is a `user` line whose `tool_result`
    /// answers a `SubagentHandback` call of an earlier assistant line.
    static func isFinished(tail data: Data, startsMidFile: Bool) -> Bool {
        var handbackResultIds: Set<String> = []
        var sawUserLine = false
        for line in lines(of: data, startsMidFile: startsMidFile) {
            guard line.range(of: assistantMarker) != nil || line.range(of: userMarker) != nil else { continue }
            guard let object = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any],
                  let type = object["type"] as? String else { continue }
            let blocks = (object["message"] as? [String: Any])?["content"] as? [[String: Any]] ?? []
            switch type {
            case "user":
                // The last message line must be the tool result; anything else means the agent moved on.
                guard !sawUserLine else { return false }
                sawUserLine = true
                for block in blocks where block["type"] as? String == "tool_result" {
                    if let id = block["tool_use_id"] as? String { handbackResultIds.insert(id) }
                }
                if handbackResultIds.isEmpty { return false }
            case "assistant":
                guard sawUserLine else { return false }
                for block in blocks where block["type"] as? String == "tool_use" {
                    if block["name"] as? String == "SubagentHandback", let id = block["id"] as? String,
                       handbackResultIds.contains(id) {
                        return true
                    }
                }
                // Parallel calls: keep looking through the same message's other blocks.
            default:
                continue
            }
        }
        return false
    }

    // MARK: Private

    private static let assistantMarker = Data("\"type\":\"assistant\"".utf8)
    private static let userMarker = Data("\"type\":\"user\"".utf8)

    /// Complete lines, last first.
    private static func lines(of data: Data, startsMidFile: Bool) -> [Data] {
        var start = data.startIndex
        if startsMidFile {
            guard let newline = data.firstIndex(of: 0x0A) else { return [] }
            start = newline + 1
        }
        return data[start...].split(separator: 0x0A, omittingEmptySubsequences: true).reversed().map { Data($0) }
    }
}
