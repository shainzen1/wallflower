import Foundation

/// One eye of a blob face: a tall capsule. Width and height are fractions of the face size,
/// the tilt is in degrees; positive leans the top outward (the left eye like \, the right like /).
struct BlobEye: Equatable, Sendable {
    var width: Double = 0.13
    var height: Double = 0.32
    var tilt: Double = 14

    static func lerp(_ a: BlobEye, _ b: BlobEye, t: Double) -> BlobEye {
        BlobEye(width: a.width + (b.width - a.width) * t, height: a.height + (b.height - a.height) * t, tilt: a.tilt + (b.tilt - a.tilt) * t)
    }
}
