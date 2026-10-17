import SwiftUI

/// The dark glossy rounded square behind one face: a vertical gradient, a soft top highlight
/// and an inner shadow at the rim, so it reads as a tiny recessed 3D screen rather than a flat icon.
/// `FaceView` draws the eyes on top of this.
struct FaceDisc: View {
    var size: CGFloat = Theme.faceSize

    var body: some View {
        shape
            .fill(
                LinearGradient(
                    colors: [Theme.discTopColor, Theme.discBottomColor],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .overlay(innerShadow)
            .overlay(highlight)
            .overlay(shape.strokeBorder(Theme.discRimColor, lineWidth: 1))
            .frame(width: size, height: size)
    }

    /// Continuous-corner rounded square; the radius scales with the face.
    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: size * Theme.faceCornerRadiusFraction, style: .continuous)
    }

    /// Soft sheen across the upper third of the face.
    private var highlight: some View {
        Ellipse()
            .fill(
                LinearGradient(
                    colors: [Theme.discHighlightColor, .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(width: size * 0.7, height: size * 0.4)
            .offset(y: -size * 0.24)
    }

    /// Dark blurred ring just inside the rim; clipped to the shape so it reads as depth.
    private var innerShadow: some View {
        shape
            .strokeBorder(Theme.discInnerShadowColor, lineWidth: Theme.discInnerShadowWidth * size / Theme.faceSize)
            .blur(radius: Theme.discInnerShadowWidth * 0.7 * size / Theme.faceSize)
            .clipShape(shape)
    }
}
