import SwiftUI

/// A face with the model's magnification for its slot. Its body is the only SwiftUI work a pointer
/// move causes: it reads `PanelModel.pointer` through `magnify(slot:)`, so the rows and the capsule
/// are untouched by a move; the face's layer tree does the smoothing. The model knows every slot's
/// reach (rest scale, grow, silhouette), so the clamps need nothing from the row.
struct MagnifiedFaceView: View {
    let model: PanelModel
    let slot: Int
    /// The session the face shows (nil for an action face, which cannot be thrown).
    var key: SessionKey? = nil
    let face: FaceView

    var body: some View {
        let face = face.magnify(model.magnify(slot: slot))
        if let key {
            face.thrown(model.throwPose(for: key))
        } else {
            face
        }
    }
}
