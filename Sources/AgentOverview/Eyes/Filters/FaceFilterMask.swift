import CoreGraphics
import Foundation

/// The mask image of a screen filter for a face of `size` points on a display of `scale`.
/// Every filter is a cached pre-rendered image (see each mask type), so switching filters is a
/// `contents` change on one static mask layer and nothing runs per frame.
@MainActor
enum FaceFilterMask {
    static func image(for filter: FaceFilter, size: CGFloat, scale: CGFloat) -> CGImage? {
        switch filter {
        case .none: nil
        case .dotMatrix: DotGridMask.image(size: size, scale: scale)
        case .asciiGrid: AsciiGridMask.image(size: size, scale: scale)
        case .halftone: HalftoneMask.image(size: size, scale: scale)
        case .scanlines: ScanlineMask.image(size: size, scale: scale)
        }
    }
}
