import CoreGraphics
import Foundation

/// Places the two capsule eyes of a pose on an imaginary sphere and projects them orthographically
/// into the face square (layer coordinates, y up). The head frame is yawed, pitched and rolled; each
/// eye is the forward vector rotated about the head's right axis by half the split. The projected
/// tangent frame of that surface point becomes the capsule's 2 x 2 matrix, so an eye nearer the rim
/// narrows on its own (foreshortening), no separate squeeze. Positions follow the body's local
/// radius a little on non-round silhouettes. Clipping at the silhouette is the layer mask's job.
enum BlobEyes {
    private struct V3 {
        var x: Double, y: Double, z: Double
        static func + (a: V3, b: V3) -> V3 { V3(x: a.x + b.x, y: a.y + b.y, z: a.z + b.z) }
        static func - (a: V3, b: V3) -> V3 { V3(x: a.x - b.x, y: a.y - b.y, z: a.z - b.z) }
        static func * (a: V3, s: Double) -> V3 { V3(x: a.x * s, y: a.y * s, z: a.z * s) }
    }

    /// Rotates `a` toward `b` by `angle` radians (a plane rotation of the two basis vectors).
    private static func rotate(_ a: inout V3, _ b: inout V3, by angle: Double) {
        let (c, s) = (cos(angle), sin(angle))
        let na = a * c + b * s
        let nb = b * c - a * s
        a = na
        b = nb
    }

    /// Centre and matrix of one eye in the face square.
    struct Placement {
        var centre: CGPoint
        var transform: CGAffineTransform
        var depth: Double
    }

    /// The left (`mirrored == false`) or right eye placement for a pose on a body profile.
    static func placement(for pose: BlobEyePose, profile: BlobProfile, faceSize: CGFloat, mirrored: Bool, lift: Double = 0) -> Placement {
        let size = Double(faceSize)
        let radians = Double.pi / 180
        var forward = V3(x: 0, y: 0, z: 1)
        var right = V3(x: 1, y: 0, z: 0)
        var up = V3(x: 0, y: 1, z: 0)
        rotate(&forward, &right, by: pose.yaw * radians)
        rotate(&forward, &up, by: pose.pitch * radians)
        rotate(&right, &up, by: pose.roll * radians)

        let sign: Double = mirrored ? 1 : -1
        let a = sign * pose.split / 2 * radians
        let point = forward * cos(a) + right * sin(a)
        let horizontal = right * cos(a) - forward * sin(a)
        let vertical = up

        let eye = mirrored ? pose.right : pose.left
        let sphere = Theme.blobSphereRadius * size
        var x = point.x * sphere
        var y = point.y * sphere
        let angle = atan2(y, x)
        let follow = 1 + (profile.radius(at: angle) / Theme.blobRadius - 1) * Theme.blobEdgeFollow
        x *= follow
        y *= follow
        let centre = CGPoint(x: size / 2 + x, y: size / 2 + y + (pose.lift + lift) * size)

        // Capsule local frame: rotate by the tilt (left eye counter-clockwise, right clockwise),
        // then map local x to the horizontal tangent and local y to the vertical one.
        let tilt = -sign * eye.tilt * radians
        let (ct, st) = (cos(tilt), sin(tilt))
        let m00 = horizontal.x * ct + vertical.x * st
        let m01 = -horizontal.x * st + vertical.x * ct
        let m10 = horizontal.y * ct + vertical.y * st
        let m11 = -horizontal.y * st + vertical.y * ct
        let transform = CGAffineTransform(a: m00, b: m10, c: m01, d: m11, tx: centre.x, ty: centre.y)
        return Placement(centre: centre, transform: transform, depth: point.z)
    }

    /// The path of one eye for a pose, in the face square, on a body.
    static func path(for pose: BlobEyePose, body: BlobBody, faceSize: CGFloat, mirrored: Bool) -> CGPath {
        path(for: pose, profile: body.profile, faceSize: faceSize, mirrored: mirrored, lift: body.eyeLift)
    }

    /// The path of one eye for a pose, in the face square.
    static func path(for pose: BlobEyePose, profile: BlobProfile, faceSize: CGFloat, mirrored: Bool, lift: Double = 0) -> CGPath {
        let eye = mirrored ? pose.right : pose.left
        let placement = placement(for: pose, profile: profile, faceSize: faceSize, mirrored: mirrored, lift: lift)
        let size = Double(faceSize)
        return BlobCapsulePath.path(width: eye.width * size, height: eye.height * size * pose.lid, transform: placement.transform)
    }
}
