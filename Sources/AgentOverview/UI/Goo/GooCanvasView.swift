import SwiftUI

/// The `.blurThreshold` goo renderer: a `Canvas` that draws the capsule, the bulge blob and the
/// trailing droplets as separate solid shapes into one layer, blurs the layer and cuts it at an
/// alpha threshold. Where shapes are close, the blurred alpha stays above the threshold between
/// them, which is what joins the bulge to the capsule with concave fillets, for free.
///
/// Filter order, verified visually (13-10-26, 1x display): filters added to a `GraphicsContext`
/// apply in REVERSE order of adding. Adding `alphaThreshold` first and `blur` second gives crisp
/// edges with fillets (blur runs first, threshold second). Adding them the other way round gives a
/// blurry black blob with no fillets. So the order here is: edge soften (runs last), threshold,
/// blur (runs first). All three must wrap one `drawLayer`, otherwise each fill is filtered on its own
/// and nothing merges.
///
/// Cost rules: the view is `Animatable` on `GooState`, so SwiftUI re-evaluates the body (and the
/// Canvas redraws) only while a spring is moving one of its values, or while the droplet centre
/// lags. At rest nothing redraws. The canvas is the capsule plus the widest bulge plus
/// `Theme.gooBleed` on the top, bottom and right, which lie outside the window so the blur never
/// sees a clipped edge. The blurred capsule has no edge fillets: its body continues into the right
/// bleed as a solid block between the body's top and bottom (`GooLayout.capsuleCore`), and the two
/// fillets are drawn crisp on top, outside the filters (`GooLayout.capsuleTips`). Blurred, the
/// fillets filled in (the blur is as wide as they are), the arc ended about 3 pt short of the screen
/// edge and the window edge cut it flat.
///
/// Flush edges: at the first and last slot the blob's top (or bottom) edge lies on the body's, and
/// the capsule core's corner on that side and the blob's corner inside the capsule are square
/// (`GooLayout.capsuleCornerRadii`, `GooLayout.bulgeBlob`), so the blurred layer has one straight
/// edge from the blob's rounded outer corner to past the screen edge. A straight edge with solid
/// below it thresholds at 0.5 exactly on itself, so the drawn edge stays where the shapes have it
/// (a test blurs and thresholds the shapes numerically and checks the junction).
///
/// Left side: the canvas draws the same canonical shapes through `drawingTransform(side:)`, a mirror
/// across the canvas width, and the bleed overflows to the left (`bleedOffset(side:)`). The blur and
/// the threshold are symmetric, so the mirrored layer is the right side's, mirrored.
struct GooCanvasView: View, Animatable {
    var state: GooState
    /// Lagging centre of the droplets (its own, slower spring in `GooView`).
    var dropletY: CGFloat
    /// Final capsule height (the window height); the body is centred in it while it springs.
    let capsuleHeight: CGFloat
    /// The screen edge the capsule meets.
    var side: PanelSide = .default

    /// The drawing transform of the canvas (`Theme.contentWidth + bleed` wide): canonical content
    /// x maps to canvas x as is on the right, mirrored across the canvas on the left, so the screen
    /// edge (canonical `Theme.contentWidth`) lands `bleed` in from the canvas's left edge.
    static func drawingTransform(side: PanelSide, bleed: CGFloat = Theme.gooBleed) -> CGAffineTransform {
        side.transform(in: Theme.contentWidth + bleed)
    }

    /// How far the canvas is moved so its bleed lies outside the content: half the bleed toward the
    /// screen edge (right, or left on the left side).
    static func bleedOffset(side: PanelSide, bleed: CGFloat = Theme.gooBleed) -> CGFloat {
        side.mirror(dx: bleed / 2)
    }

    nonisolated var animatableData: GooState {
        get { state }
        set { state = newValue }
    }

    var body: some View {
        let bleed = Theme.gooBleed
        Canvas(opaque: false, colorMode: .nonLinear, rendersAsynchronously: false) { context, size in
            let shading = GraphicsContext.Shading.color(Theme.capsuleColor)
            // While rows arrive or leave, SwiftUI animates this view's frame from the old height
            // to `capsuleHeight` (around the same centre), but the drawing already uses the final
            // height: drawn from the frame's top it would sit off centre until that spring settled
            // (measured: the body's top lagged the opening slot by about 10 pt). Centring the
            // drawing in the actual size keeps the body on the anchor, in step with the rows.
            let drift = (size.height - bleed * 2 - capsuleHeight) / 2
            let mirror = Self.drawingTransform(side: side, bleed: bleed)
            var goo = context
            if Theme.gooEdgeSoften > 0 {
                goo.addFilter(.blur(radius: Theme.gooEdgeSoften))
            }
            goo.addFilter(.alphaThreshold(min: Theme.gooThreshold, color: Theme.capsuleColor))
            goo.addFilter(.blur(radius: Theme.gooBlur))
            goo.drawLayer { layer in
                layer.concatenate(mirror)
                layer.translateBy(x: 0, y: bleed + drift)
                // The capsule without its edge fillets, continued past the screen edge (`GooLayout.capsuleCore`).
                layer.fill(GooLayout.capsuleCore(state: state, height: capsuleHeight, bleed: bleed), with: shading)
                // At the first or last slot the blob's edge is the body's edge (flush): the blob's
                // inner corner and the capsule's corner square off there, so the two are one straight
                // edge under the blur and the threshold keeps it straight, with no dip at the junction.
                layer.fill(GooLayout.bulgeBlob(state: state, height: capsuleHeight), with: shading)
                for droplet in GooLayout.droplets(state: state, dropletY: dropletY) {
                    let rect = CGRect(
                        x: droplet.center.x - droplet.radius,
                        y: droplet.center.y - droplet.radius,
                        width: droplet.radius * 2,
                        height: droplet.radius * 2
                    )
                    layer.fill(Path(ellipseIn: rect), with: shading)
                }
            }
            // Crisp pass, outside the blur and the threshold: the edge fillets, so the tips meet the
            // screen edge as clean points. Only the edge soften, so its arcs are as soft as the
            // thresholded edges they continue.
            var tips = context
            if Theme.gooEdgeSoften > 0 {
                tips.addFilter(.blur(radius: Theme.gooEdgeSoften))
            }
            tips.drawLayer { layer in
                layer.concatenate(mirror)
                layer.translateBy(x: 0, y: bleed + drift)
                layer.fill(GooLayout.capsuleTips(state: state, height: capsuleHeight, overhang: bleed), with: shading)
            }
        }
        .frame(width: Theme.contentWidth + bleed, height: capsuleHeight + bleed * 2)
        .drawingGroup()
        // Layout size is the content size; the bleed overflows it (frames do not clip) and the
        // offset pushes the overflow outside the window: the screen-edge side and both vertical sides.
        .frame(width: Theme.contentWidth, height: capsuleHeight)
        .offset(x: Self.bleedOffset(side: side, bleed: bleed))
    }
}
