import QuartzCore

/// One subagent satellite of a blob face: a small disc (with two ink dots) that orbits the face.
/// Owns its layers and keeps its phase for as long as it exists, so adding or removing another
/// satellite never restarts this one.
@MainActor
final class BlobSatellite {
    let layer = CAShapeLayer()
    let eyes = CAShapeLayer()
    let phase: Double

    init(phase: Double) {
        self.phase = phase
        layer.strokeColor = nil
        layer.opacity = Theme.satelliteOpacity
        eyes.strokeColor = nil
        eyes.fillColor = Theme.blobEyeColor.cgColor
        layer.addSublayer(eyes)
        for sublayer in [layer, eyes] {
            sublayer.masksToBounds = false
            sublayer.actions = ["onOrderIn": NSNull(), "onOrderOut": NSNull(), "sublayers": NSNull(), "bounds": NSNull(), "position": NSNull(), "path": NSNull(), "opacity": NSNull(), "transform": NSNull(), "fillColor": NSNull()]
        }
    }

    /// Sizes the disc and its dots for a face of `size`, rasterised at `scale`, resting at its phase position.
    func layout(size: CGFloat, scale: CGFloat) {
        let diameter = BlobSatelliteLayout.diameter(size: size)
        let bounds = CGRect(x: 0, y: 0, width: diameter, height: diameter)
        for sublayer in [layer, eyes] {
            sublayer.bounds = bounds
            sublayer.contentsScale = scale
        }
        eyes.position = CGPoint(x: diameter / 2, y: diameter / 2)
        layer.path = BlobSatelliteLayout.bodyPath(size: size)
        eyes.path = Theme.satelliteEyes ? BlobSatelliteLayout.eyesPath(size: size) : nil
        layer.position = BlobSatelliteLayout.position(phase: phase, size: size)
    }

    /// Starts (or, under Reduce Motion, stops) the orbit and the bob.
    func installMotion(size: CGFloat, reduceMotion: Bool) {
        layer.removeAnimation(forKey: "loop.orbit")
        layer.removeAnimation(forKey: "loop.bob")
        layer.position = BlobSatelliteLayout.position(phase: phase, size: size)
        guard !reduceMotion else { return }
        layer.add(BlobAnimations.orbit(size: size, phase: phase), forKey: "loop.orbit")
        layer.add(BlobAnimations.bob(size: size, phase: phase), forKey: "loop.bob")
    }
}
