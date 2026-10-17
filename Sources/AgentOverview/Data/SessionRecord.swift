import Foundation

/// One registry file, `~/.claude/sessions/<pid>.json`, as written by Claude Code.
/// Required keys are the ones observed in every capture (see `docs/phase0-findings.md`);
/// everything else is optional so a slightly different writer version still decodes.
/// Unknown keys are ignored by `Codable`.
struct SessionRecord: Codable, Sendable, Equatable {
    /// A previous title of the session. `sessionId` can differ from the current one,
    /// because session ids rotate across resumes and compactions.
    struct FormerName: Codable, Sendable, Equatable {
        var name: String
        var until: Int?
        var sessionId: String?
    }

    var pid: pid_t
    var sessionId: String
    var cwd: String
    /// Epoch milliseconds.
    var startedAt: Int
    var procStart: String?
    var version: String?
    var peerProtocol: Int?
    var peerFeatures: [String]?
    var kind: String?
    var entrypoint: String
    /// `local_<uuid>`; absent for CLI sessions.
    var hostSessionId: String?
    var pidDomain: String?
    var messagingSocketPath: String?
    var name: String?
    /// `"user"`, `"derived"` or absent.
    var nameSource: String?
    var nameSince: Int?
    var status: RegistryStatus
    /// Present only while `status == .waiting`.
    var waitingFor: String?
    var updatedAt: Int?
    var statusUpdatedAt: Int?
    var formerNames: [FormerName]?

    /// Classification of `waitingFor`.
    var waitingKind: WaitingKind { WaitingKind(waitingFor: waitingFor) }

    var startedDate: Date { Self.date(fromMilliseconds: startedAt) }

    /// When the current status began. Falls back to `updatedAt`, then `startedAt`.
    var statusUpdatedDate: Date {
        Self.date(fromMilliseconds: statusUpdatedAt ?? updatedAt ?? startedAt)
    }

    private static func date(fromMilliseconds ms: Int) -> Date {
        Date(timeIntervalSince1970: TimeInterval(ms) / 1000)
    }
}
