import Foundation

/// A screen filter laid over a face, whatever its style. All of them are pre-rendered mask
/// images (see `FaceFilterMask`), so they cost nothing per frame.
enum FaceFilter: String, CaseIterable, Sendable {
    case none
    /// The LED dot grid (what `Theme.dotMatrix` used to switch).
    case dotMatrix
    /// A grid of tiny monospaced glyphs the face shows through.
    case asciiGrid
    /// A 45 degree halftone screen, dots large at the centre and thinning toward the rim.
    case halftone
    /// Horizontal CRT scanlines.
    case scanlines

    /// Human label for the playground.
    var label: String {
        switch self {
        case .none: "none"
        case .dotMatrix: "dot matrix"
        case .asciiGrid: "ascii"
        case .halftone: "halftone"
        case .scanlines: "scanlines"
        }
    }

    /// The next filter when cycling in the playground.
    var next: FaceFilter {
        let all = Self.allCases
        return all[(all.firstIndex(of: self)! + 1) % all.count]
    }
}
