import Foundation

/// The face style, screen filter, blob shape mode, colour mode and hover effect in force for this
/// process: the `Theme` defaults unless a launch argument replaced them. `AppDelegate` sets these
/// once before any face exists; `FaceView` reads them unless a playground modifier overrides a value.
@MainActor
enum FaceLook {
    static var style: FaceStyle = Theme.faceStyle
    static var filter: FaceFilter = Theme.faceFilter
    static var blobShapeMode: Theme.BlobShapeMode = Theme.blobShapeMode
    static var colorMode: Theme.ColorMode = Theme.colorMode
    static var hoverEffect: Theme.HoverEffect = Theme.hoverEffect

    /// The body colour a session face shows for `status` in `style` and `colorMode`: the same
    /// resolution the program builders use (`BlobProgramBuilder.color`, `FaceProgramBuilder.color`),
    /// so anything drawn beside a face (the edge cue) matches its body.
    static func bodyColor(
        for status: FaceStatus, seed: String, projectKey: String?,
        style: FaceStyle = FaceLook.style, colorMode: Theme.ColorMode = FaceLook.colorMode
    ) -> EyeColor {
        let identity = FaceIdentity(seed: seed)
        return switch style {
        case .blob: BlobProgramBuilder.color(for: status, identity: identity, colorMode: colorMode, projectKey: projectKey)
        case .dotMatrix: FaceProgramBuilder.color(for: status, identity: identity, colorMode: colorMode, projectKey: projectKey)
        }
    }
}
