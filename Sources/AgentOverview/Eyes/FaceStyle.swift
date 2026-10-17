import Foundation

/// The two face styles. `Theme.faceStyle` picks the default; `--face-style` and the playground override it.
enum FaceStyle: String, CaseIterable, Sendable {
    /// Y2K dot-matrix eyes on a glossy dark disc (Phase 3).
    case dotMatrix
    /// Flat blob: one coloured body silhouette with two capsule eyes cut into it.
    case blob

    /// Human label for the playground.
    var label: String {
        switch self {
        case .dotMatrix: "dot matrix"
        case .blob: "blob"
        }
    }

    /// The next style when cycling in the playground.
    var next: FaceStyle {
        let all = Self.allCases
        return all[(all.firstIndex(of: self)! + 1) % all.count]
    }
}
