import Foundation

/// Normalises a branch name from either source (transcript `gitBranch`, `.git/HEAD`): a detached
/// head reports as `HEAD` in transcripts and as a bare SHA in `.git/HEAD`, and neither is a branch
/// the panel should show. Empty and whitespace-only values are no branch either.
enum GitBranchName {
    /// The literal Claude Code writes for a detached head.
    static let detached = "HEAD"

    static func normalized(_ raw: String?) -> String? {
        guard let name = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty, name != detached else {
            return nil
        }
        return name
    }
}
