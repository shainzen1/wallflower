import Foundation

/// Branch of a working directory from `.git/HEAD`, without spawning `git`.
/// Fallback for sessions whose transcript carries no `gitBranch` yet (first lines of a new session,
/// or a transcript that does not exist yet).
///
/// - Walks up from `cwd` to the first `.git` entry (a cwd inside the repo still resolves).
/// - `.git` may be a file `gitdir: <path>` (worktrees, submodules); relative paths resolve against
///   the folder holding the `.git` file. A worktree's HEAD lives in that gitdir.
/// - `ref: refs/heads/<name>` gives the branch; a detached HEAD (bare SHA, or a ref literally
///   named `HEAD`) gives `nil` (`GitBranchName`).
enum GitHeadReader {
    static func branch(cwd: String) -> String? {
        guard let gitDirectory = gitDirectory(startingAt: URL(filePath: cwd, directoryHint: .isDirectory)) else {
            return nil
        }
        let head = gitDirectory.appending(path: "HEAD", directoryHint: .notDirectory)
        guard let contents = try? String(contentsOf: head, encoding: .utf8) else { return nil }
        return branch(headContents: contents)
    }

    /// `ref: refs/heads/feature/x` → `feature/x`; anything else → `nil`.
    static func branch(headContents: String) -> String? {
        let line = headContents.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        guard line.hasPrefix("ref: ") else { return nil }
        let ref = line.dropFirst("ref: ".count).trimmingCharacters(in: .whitespaces)
        let prefix = "refs/heads/"
        guard ref.hasPrefix(prefix) else { return nil }
        return GitBranchName.normalized(String(ref.dropFirst(prefix.count)))
    }

    /// The directory holding `HEAD` for the repository containing `folder`, resolving `gitdir:` pointers.
    static func gitDirectory(startingAt folder: URL) -> URL? {
        var current = folder.standardizedFileURL
        while true {
            let dotGit = current.appending(path: ".git", directoryHint: .checkFileSystem)
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: dotGit.path, isDirectory: &isDirectory) {
                if isDirectory.boolValue { return dotGit }
                return resolveGitdirPointer(at: dotGit)
            }
            let parent = current.deletingLastPathComponent()
            if parent.path == current.path { return nil }
            current = parent
        }
    }

    // MARK: Private

    private static func resolveGitdirPointer(at file: URL) -> URL? {
        guard let contents = try? String(contentsOf: file, encoding: .utf8) else { return nil }
        let line = contents.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        guard line.hasPrefix("gitdir:") else { return nil }
        let path = line.dropFirst("gitdir:".count).trimmingCharacters(in: .whitespaces)
        guard !path.isEmpty else { return nil }
        if path.hasPrefix("/") { return URL(filePath: path, directoryHint: .isDirectory) }
        return file.deletingLastPathComponent().appending(path: path, directoryHint: .isDirectory).standardizedFileURL
    }
}
