import Foundation

/// Maps a registry record (cwd, sessionId) to the files Claude Code writes for that session.
///
/// Layout (verified 13-10-26, Claude Code 2.1.29x):
/// - transcript: `~/.claude/projects/<slug>/<sessionId>.jsonl`
/// - subagents:  `~/.claude/projects/<slug>/<sessionId>/subagents/agent-<id>.jsonl` (+ `.meta.json`, `.prefix.json`)
///
/// `<slug>` is the cwd with every character that is not an ASCII letter or digit replaced by `-`
/// (so `/` and `.` and `_` all become `-`; verified with a cwd containing a dot and an underscore).
/// Session ids rotate across resumes, so callers must resolve from the current registry record.
struct TranscriptLocator: Sendable, Equatable {
    let projectsFolder: URL

    static var defaultProjectsFolder: URL {
        FileManager.default.homeDirectoryForCurrentUser.appending(path: ".claude/projects", directoryHint: .isDirectory)
    }

    init(projectsFolder: URL = TranscriptLocator.defaultProjectsFolder) {
        self.projectsFolder = projectsFolder
    }

    /// Claude Code's project slug: `cwd.replace(/[^a-zA-Z0-9]/g, "-")`, applied per UTF-16 code unit.
    static func projectSlug(for cwd: String) -> String {
        var slug = String.UnicodeScalarView()
        for unit in cwd.utf16 {
            let isAlphanumeric = (0x30...0x39).contains(unit) || (0x41...0x5A).contains(unit) || (0x61...0x7A).contains(unit)
            slug.append(isAlphanumeric ? Unicode.Scalar(UInt8(unit)) : "-")
        }
        return String(slug)
    }

    func projectFolder(cwd: String) -> URL {
        projectsFolder.appending(path: Self.projectSlug(for: cwd), directoryHint: .isDirectory)
    }

    func transcriptURL(cwd: String, sessionId: String) -> URL {
        projectFolder(cwd: cwd).appending(path: "\(sessionId).jsonl", directoryHint: .notDirectory)
    }

    /// `<slug>/<sessionId>/`, created when the first subagent (or tool result file) is written.
    func sessionFolder(cwd: String, sessionId: String) -> URL {
        projectFolder(cwd: cwd).appending(path: sessionId, directoryHint: .isDirectory)
    }

    func subagentsFolder(cwd: String, sessionId: String) -> URL {
        sessionFolder(cwd: cwd, sessionId: sessionId).appending(path: "subagents", directoryHint: .isDirectory)
    }
}
