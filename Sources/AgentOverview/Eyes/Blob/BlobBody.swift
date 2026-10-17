import Foundation

/// The body of a blob face: a silhouette and a vertical squash (1 = as drawn; ended flattens
/// the capsule toward a line, sleepy sags a little). Resolves to a profile for the path.
struct BlobBody: Equatable, Sendable {
    var shape: BlobShape
    var squash: Double = 1

    var profile: BlobProfile {
        shape.profile.squashed(squash)
    }

    /// Vertical eye offset of this body (the silhouette's lift, squashed with it).
    var eyeLift: Double {
        shape.eyeLift * squash
    }

    /// The silhouette a status takes in `.status` shape mode (the shape carries the status). Your turn
    /// rests on the first of `Theme.yourTurnShapes` and swaps to the second on its loop.
    static func forStatus(_ status: FaceStatus, sleepy: Bool = false) -> BlobBody {
        switch status {
        case .needsInput: BlobBody(shape: Theme.blobNeedsInputShape)
        case .working: BlobBody(shape: Theme.blobWorkingShape)
        case .idle: BlobBody(shape: Theme.blobIdleShape, squash: sleepy ? Theme.blobSleepySquash : 1)
        case .justFinished: BlobBody(shape: Theme.blobIdleShape)
        case .yourTurn: BlobBody(shape: Theme.yourTurnShapes.0)
        case .ended: BlobBody(shape: Theme.blobIdleShape, squash: Theme.blobEndedSquash)
        }
    }

    /// The status row of the playground in `.status` shape mode: one body per status, labelled by status.
    static let statusPresets: [(label: String, body: BlobBody)] = [
        ("needs input", forStatus(.needsInput(kind: .question))),
        ("working", forStatus(.working)),
        ("idle", forStatus(.idle(since: Date()))),
        ("just finished", forStatus(.justFinished)),
        ("ended", forStatus(.ended)),
    ]
}
