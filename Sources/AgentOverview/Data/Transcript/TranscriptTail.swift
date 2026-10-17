import Foundation

/// Reads the end of a transcript and extracts `TranscriptFacts` from it.
///
/// Transcript lines (verified 13-10-26): one JSON object per line, compact (no spaces after
/// colons). Every assistant line carries exactly one content block (`thinking`, `text` or
/// `tool_use`), so a message with parallel tool calls spans several consecutive assistant lines
/// that share `message.id`. A finished call is a later `user` line whose `message.content[]` holds
/// a `tool_result` with the matching `tool_use_id` (`is_error` absent, false or true). Lines of
/// type `attachment`, `system`, `atis-latch`, `last-prompt`, `custom-title`, `agent-name`,
/// `queue-operation`, `file-history-snapshot`, `mode`, `cost-state` sit in between and are skipped,
/// except that `attachment` and `system` lines also carry `gitBranch`.
///
/// Scan rules, from the file end backwards:
/// - branch: the first line with a non-empty top-level `gitBranch` (user, assistant, attachment, system);
///   `HEAD` (a detached head) counts as no branch and the scan keeps looking (`GitBranchName`).
/// - error flag: `is_error` of the first `tool_result` block met.
/// - tool state: the first assistant line met starts the "last message" group; consecutive assistant
///   lines with the same `message.id` join it. Its `tool_use` ids minus the `tool_result` ids met
///   so far are the calls in flight. No `tool_use` in the group (text or thinking only), or all
///   of them answered: nothing in flight, the model is thinking.
/// The scan stops as soon as all three facts are settled, normally after a handful of lines.
/// A line is only JSON-parsed when a cheap byte search says it can contribute, and lines that fail
/// to parse (a write in progress) are skipped.
enum TranscriptTail {
    /// Reads at most `maxBytes` from the end of the file. `startsMidFile` is true when the data
    /// begins somewhere inside the file, so its first line is incomplete and must be dropped.
    static func read(url: URL, maxBytes: Int) throws -> (data: Data, startsMidFile: Bool) {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let size = try handle.seekToEnd()
        guard size > UInt64(maxBytes) else {
            try handle.seek(toOffset: 0)
            return (try handle.readToEnd() ?? Data(), false)
        }
        try handle.seek(toOffset: size - UInt64(maxBytes))
        return (try handle.readToEnd() ?? Data(), true)
    }

    static func facts(from data: Data, startsMidFile: Bool) -> TranscriptFacts {
        var facts = TranscriptFacts()
        var needBranch = true
        var needResult = true
        var needGroup = true
        var resultIds: Set<String> = []
        var groupMessageId: String?
        var groupToolUses: [(id: String, name: String)] = []  // tail first

        func finishGroup() {
            needGroup = false
            let inFlight = groupToolUses.filter { !resultIds.contains($0.id) }
            facts.inFlightToolUseIds = Set(inFlight.map(\.id))
            facts.lastToolInFlight = !inFlight.isEmpty
            facts.lastToolName = inFlight.first?.name ?? groupToolUses.first?.name
        }

        for line in LineRanges(data: data, dropFirst: startsMidFile) {
            if !needBranch, !needResult, !needGroup { break }
            facts.scannedLines += 1
            let wantsBranch = needBranch && line.contains(Self.branchMarker)
            let isMessage = (needResult || needGroup)
                && (line.contains(Self.assistantMarker) || line.contains(Self.userMarker))
            guard wantsBranch || isMessage else { continue }
            guard let object = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any] else { continue }

            if needBranch, let branch = GitBranchName.normalized(object["gitBranch"] as? String) {
                facts.gitBranch = branch
                needBranch = false
            }
            guard isMessage, let type = object["type"] as? String else { continue }
            let blocks = (object["message"] as? [String: Any])?["content"] as? [[String: Any]] ?? []

            switch type {
            case "user":
                if groupMessageId != nil { finishGroup() }
                for block in blocks where block["type"] as? String == "tool_result" {
                    if needResult {
                        facts.lastResultFailed = block["is_error"] as? Bool ?? false
                        needResult = false
                    }
                    if needGroup, let id = block["tool_use_id"] as? String { resultIds.insert(id) }
                }
            case "assistant":
                guard needGroup else { continue }
                let messageId = (object["message"] as? [String: Any])?["id"] as? String ?? ""
                if let current = groupMessageId, current != messageId {
                    finishGroup()
                    continue
                }
                groupMessageId = messageId
                for block in blocks where block["type"] as? String == "tool_use" {
                    if let id = block["id"] as? String, let name = block["name"] as? String {
                        groupToolUses.append((id, name))
                    }
                }
            default:
                continue
            }
        }
        if needGroup { finishGroup() }
        return facts
    }

    // MARK: Private

    private static let assistantMarker = Data("\"type\":\"assistant\"".utf8)
    private static let userMarker = Data("\"type\":\"user\"".utf8)
    private static let branchMarker = Data("\"gitBranch\":\"".utf8)

    /// Complete lines of `data`, last line first. Empty lines are skipped.
    private struct LineRanges: Sequence, IteratorProtocol {
        private let data: Data
        private var end: Int
        private let stop: Int

        init(data: Data, dropFirst: Bool) {
            self.data = data
            end = data.endIndex
            if dropFirst, let newline = data.firstIndex(of: 0x0A) {
                stop = newline + 1
            } else if dropFirst {
                stop = data.endIndex
            } else {
                stop = data.startIndex
            }
        }

        mutating func next() -> Data? {
            while end > stop {
                let lineEnd = end
                var lineStart = end
                while lineStart > stop, data[lineStart - 1] != 0x0A { lineStart -= 1 }
                end = Swift.max(lineStart - 1, stop)
                let line = data[lineStart..<lineEnd]
                if !line.isEmpty, !(line.count == 1 && line.first == 0x0D) { return line }
            }
            return nil
        }
    }
}

private extension Data {
    func contains(_ needle: Data) -> Bool {
        range(of: needle) != nil
    }
}
