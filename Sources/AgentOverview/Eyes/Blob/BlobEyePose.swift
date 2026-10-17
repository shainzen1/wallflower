import Foundation

/// A complete eye pose: both capsules, their spacing on the sphere, a vertical lift, where the
/// pair looks (yaw, pitch, roll of the head) and how open the lids are. Linearly interpolable.
struct BlobEyePose: Equatable, Sendable {
    var left = BlobEye()
    var right = BlobEye()
    /// Angle between the two eyes on the sphere, degrees (spacing).
    var split: Double = 50
    /// Vertical offset of the pair, fraction of the face size (positive is up).
    var lift: Double = 0.02
    /// Head gaze, degrees. Positive yaw looks right (away from the screen), positive pitch looks up.
    var yaw: Double = 0
    var pitch: Double = 0
    var roll: Double = 0
    /// 1 open, `Theme.blobClosedLid` closed (the blink sliver).
    var lid: Double = 1

    /// A symmetric pose.
    init(both eye: BlobEye = BlobEye(), split: Double = 50, lift: Double = 0.02, yaw: Double = 0, pitch: Double = 0, roll: Double = 0) {
        self.left = eye
        self.right = eye
        self.split = split
        self.lift = lift
        self.yaw = yaw
        self.pitch = pitch
        self.roll = roll
    }

    /// An asymmetric pose.
    init(left: BlobEye, right: BlobEye, split: Double = 50, lift: Double = 0.02, yaw: Double = 0, pitch: Double = 0, roll: Double = 0) {
        self.left = left
        self.right = right
        self.split = split
        self.lift = lift
        self.yaw = yaw
        self.pitch = pitch
        self.roll = roll
    }

    static func lerp(_ a: BlobEyePose, _ b: BlobEyePose, t: Double) -> BlobEyePose {
        func mix(_ x: Double, _ y: Double) -> Double { x + (y - x) * t }
        var p = BlobEyePose(
            left: BlobEye.lerp(a.left, b.left, t: t),
            right: BlobEye.lerp(a.right, b.right, t: t),
            split: mix(a.split, b.split), lift: mix(a.lift, b.lift),
            yaw: mix(a.yaw, b.yaw), pitch: mix(a.pitch, b.pitch), roll: mix(a.roll, b.roll)
        )
        p.lid = mix(a.lid, b.lid)
        return p
    }

    /// The same pose with the lids closed to the blink sliver.
    func closed() -> BlobEyePose {
        var p = self
        p.lid = Theme.blobClosedLid
        return p
    }

    /// The same pose with the lids at `lid`.
    func withLid(_ lid: Double) -> BlobEyePose {
        var p = self
        p.lid = lid
        return p
    }

    /// The same pose looking somewhere else (absolute gaze).
    func looking(yaw: Double, pitch: Double) -> BlobEyePose {
        var p = self
        p.yaw = yaw
        p.pitch = pitch
        return p
    }

    /// The pose with a gaze offset added.
    func glancing(yaw: Double, pitch: Double) -> BlobEyePose {
        var p = self
        p.yaw += yaw
        p.pitch += pitch
        return p
    }

    /// The pose with the identity's subtle tilt and spacing deltas applied.
    func varied(tilt: Double, split: Double) -> BlobEyePose {
        var p = self
        p.left.tilt += tilt
        p.right.tilt += tilt
        p.split += split
        return p
    }
}
