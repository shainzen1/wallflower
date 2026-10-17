import Foundation

/// Everything a face layer tree renders, as a value so SwiftUI updates can be diffed and
/// loops are only rebuilt when something relevant changed. Shared by both face styles.
struct FaceConfiguration: Equatable {
    var identity: FaceIdentity
    var mode: FaceMode
    var size: CGFloat
    /// Screen filter over the face (the playground overrides `Theme.faceFilter`).
    var filter: FaceFilter
    /// Blob style: what the silhouette means (status or identity).
    var blobShapeMode: Theme.BlobShapeMode = Theme.blobShapeMode
    /// What the body colour means (status, identity or project).
    var colorMode: Theme.ColorMode = Theme.colorMode
    /// `.project` colour mode: the key the body colour is hashed from (nil falls back to the status colour).
    var projectKey: String? = nil
    /// Blob style: a forced body (the playground's preset row and grid columns).
    var blobBody: BlobBody? = nil
    /// Bump to blink once.
    var blinkToken: Int = 0
    /// Bump to replay the finished bounce.
    var replayToken: Int = 0
    /// Bump for one quick happy squint (an action face was clicked).
    var squintToken: Int = 0
    /// Blob style: what a working session is doing (picks the working substate loop).
    var activity: SessionActivity = .thinking
    /// Blob style: subagents running for the session (small blobs orbit the face while working).
    var satellites: Int = 0
    /// Bump to hop once (a session started waiting for the person).
    var attentionToken: Int = 0
    /// Bump for the excited reaction (a resting or waiting session started working). Blob style, and
    /// only where the program has it (`BlobProgram.excited`).
    var excitedToken: Int = 0
    /// The row is under the pointer. With `hoverEffect == .stretch` the blob stretches toward the
    /// bulge (the genie) and the dot-matrix face scales up; the other effects ignore it.
    var hovered: Bool = false
    /// What a hover does to the face (the playground overrides `FaceLook.hoverEffect`).
    var hoverEffect: Theme.HoverEffect = Theme.hoverEffect
    /// Dock-style magnification: scale and drift toward the pointer, computed by the model per pointer event.
    var magnify: MagnifyState = .identity
    /// Seconds from the face's first appearance to its pop (`RowEntrance.faceDelay`): the slot opens
    /// first, several new rows stagger. Read once, when the layer tree is first configured.
    var enterDelay: TimeInterval = 0
    /// How far the face has left (a departing row, `RowDeparture`): applied to the host layer each frame.
    var leave: FaceLeave = .none
    /// Where a held or thrown face is drawn (`FaceThrowPose`): applied to the host layer with the leave.
    var throwPose: FaceThrowPose = .rest
    /// The panel's screen edge. The faces are designed for the right edge (the gaze toward the screen
    /// is leftward, the genie stretches left); on the left edge the trees draw the face mirrored about
    /// its centre (`PanelSide.faceTransform`), below the magnification, the throw and the screen filter,
    /// so those stay in screen coordinates and the filter lattice is never mirrored.
    var side: PanelSide = .default

    /// Whether the genie stretch is on: hovered under the `.stretch` effect.
    var stretched: Bool { hovered && hoverEffect == .stretch }
}
