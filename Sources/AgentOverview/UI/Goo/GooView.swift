import SwiftUI

/// Draws ONLY the black goo shape, with the renderer chosen by `PanelModel.gooRenderer`
/// (`Theme.gooRenderer` or `--goo`). Faces and text are layered on top by `CapsuleView`.
///
/// Two springs drive it: `state` (bulge width and centre, body size) animates with the open or
/// close spring in the renderer, and this view's own `animatableData`, the droplets' lagging
/// centre, animates with `Theme.dropletSpring` (applied by `CapsuleView`), so the droplets trail
/// the blob and snap after it.
///
/// Reduce Motion: no goo at all. The capsule is drawn plainly and the bulge (or the widened body)
/// fades in and out over `Theme.reduceMotionBulgeFade` without travelling.
struct GooView: View, Animatable {
    let renderer: Theme.GooRenderer
    let expandMode: Theme.ExpandMode
    var state: GooState
    /// Target of the droplet centre (the hovered row's centre); interpolated by SwiftUI.
    var dropletY: CGFloat
    let capsuleHeight: CGFloat
    /// Open or close spring for `state`, or the slot curve while rows arrive or leave (nil: at once), picked by the model.
    let animation: Animation?
    let reduceMotion: Bool
    let isExpanded: Bool
    /// The screen edge the capsule meets: both renderers draw the right edge's goo mirrored on the left.
    var side: PanelSide = .default

    nonisolated var animatableData: CGFloat {
        get { dropletY }
        set { dropletY = newValue }
    }

    var body: some View {
        if reduceMotion {
            reducedMotionBody
        } else {
            switch renderer {
            case .blurThreshold:
                GooCanvasView(state: state, dropletY: dropletY, capsuleHeight: capsuleHeight, side: side)
                    .animation(animation, value: state)
            case .path, .sdfShader:
                // `.sdfShader` (signed-distance metaball as a Metal `.layerEffect`) needs Xcode to
                // compile the shader; until then it draws with the path renderer.
                GooPathShape(state: state, capsuleHeight: capsuleHeight, side: side)
                    .fill(Theme.capsuleColor)
                    .frame(width: Theme.contentWidth, height: capsuleHeight)
                    .animation(animation, value: state)
            }
        }
    }

    /// Plain capsule plus a fading bulge overlay at the row, nothing travels.
    private var reducedMotionBody: some View {
        let restState = GooState(bodyHeight: state.bodyHeight, bodyExtraWidth: 0, bulgeWidth: 0, bulgeCenterY: 0, bulgeHeight: 0)
        // Canonical (right-edge) geometry; the overlay and the capsule's place are mirrored below.
        let capsuleRect = GooLayout.capsuleRect(state: restState, height: capsuleHeight)
        let edgeFillet = GooLayout.edgeFilletRadius(bodyHeight: state.bodyHeight)
        // Separate shapes filled one by one, not united: a path boolean with a coincident edge (the
        // flush corner square on the blob's edge) is unreliable on macOS 26 (`GooLayout.capsuleTips`).
        var overlays: [Path]
        switch expandMode {
        case .row:
            let open = GooState(
                bodyHeight: state.bodyHeight, bodyExtraWidth: 0, bulgeWidth: Theme.bulgeWidth,
                bulgeCenterY: state.bulgeCenterY, bulgeHeight: state.bulgeHeight,
                bulgeTopFlush: state.bulgeTopFlush, bulgeBottomFlush: state.bulgeBottomFlush
            )
            // On a flush side the overlay also squares off the plain capsule's corner below it.
            overlays = [GooLayout.bulgeBlob(state: open, height: capsuleHeight)]
            let body = GooLayout.bodySpan(height: capsuleHeight, bodyHeight: state.bodyHeight)
            let flush = GooLayout.flushWeights(state: open)
            let r = Theme.capsuleCornerRadius
            if flush.top > 0.5 {
                overlays.append(Path(CGRect(x: capsuleRect.minX, y: body.lowerBound, width: r, height: r)))
            }
            if flush.bottom > 0.5 {
                overlays.append(Path(CGRect(x: capsuleRect.minX, y: body.upperBound - r, width: r, height: r)))
            }
        case .all:
            let wide = GooState(bodyHeight: state.bodyHeight, bodyExtraWidth: Theme.bulgeWidth, bulgeWidth: 0, bulgeCenterY: 0, bulgeHeight: 0)
            overlays = [CapsuleShape(cornerRadius: Theme.capsuleCornerRadius, filletRadius: edgeFillet, bodyHeight: state.bodyHeight)
                .path(in: GooLayout.capsuleRect(state: wide, height: capsuleHeight))]
        }
        return ZStack(alignment: .topLeading) {
            CapsuleShape(cornerRadius: Theme.capsuleCornerRadius, filletRadius: edgeFillet, bodyHeight: state.bodyHeight, side: side)
                .fill(Theme.capsuleColor)
                .frame(width: capsuleRect.width, height: capsuleHeight)
                .offset(x: side.mirror(capsuleRect, in: Theme.contentWidth).minX)
                .animation(animation, value: state.bodyHeight)
            ZStack(alignment: .topLeading) {
                ForEach(overlays.indices, id: \.self) { index in
                    side.mirror(overlays[index], in: Theme.contentWidth)
                        .fill(Theme.capsuleColor)
                }
            }
            // One group, so the overlapping pieces fade as one shape.
            .compositingGroup()
            .opacity(isExpanded ? 1 : 0)
                .animation(.easeInOut(duration: Theme.reduceMotionBulgeFade), value: isExpanded)
        }
        .frame(width: Theme.contentWidth, height: capsuleHeight, alignment: .topLeading)
    }
}
