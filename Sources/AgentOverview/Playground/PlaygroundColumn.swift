import Foundation

/// One column of the preset row and the expression grid: a label and what it forces on the face.
struct PlaygroundColumn: Equatable, Identifiable {
    var label: String
    /// Dot-matrix style: the eye preset.
    var preset: EyePreset?
    /// Blob style: the body.
    var body: BlobBody?

    var id: String { label }

    /// The identity for this column from a seed (preset forced for the dot-matrix style).
    func identity(seed: String) -> FaceIdentity {
        if let preset { return FaceIdentity(seed: seed, preset: preset) }
        return FaceIdentity(seed: seed)
    }
}
