import Foundation

/// Every expression the eyes can show. Status maps to a small subset; the rest are for
/// identity, idle variety and the playground.
enum Expression: String, CaseIterable, Sendable {
    case normal
    case happy
    case glee
    case sad
    case worried
    case focused
    case annoyed
    case surprised
    case skeptic
    case frustrated
    case unimpressed
    case sleepy
    case suspicious
    case squint
    case angry
    case furious
    case scared
    case awe

    /// The tuned pose for this expression (values live in `ExpressionPoses.swift`).
    var pose: FacePose {
        ExpressionPoses.pose(for: self)
    }

    /// Human label for the playground.
    var label: String {
        rawValue
    }
}
