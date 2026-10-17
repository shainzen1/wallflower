import Foundation

/// One action face below the divider, as a value derived from an `ActionItem` plus the model's
/// transient state (launching feedback, click token). The face look is decided here.
struct ActionRow: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let cwd: String
    let prompt: String
    /// Seed of the face identity.
    let seed: String
    /// Silhouette and body colour (the item's overrides, else the `Theme` action look).
    let shape: BlobShape
    let color: EyeColor
    /// The working cloud shows for `Theme.actionLaunchFeedback` after a click.
    let launching: Bool
    /// Bumped per click: the face squints once.
    let squintToken: Int
    /// Replaces the prompt on the bulge's second line for a while (`Theme.actionSendHint`).
    let hint: String?

    init(item: ActionItem, launching: Bool = false, squintToken: Int = 0, hint: String? = nil) {
        id = item.id
        name = item.name
        cwd = item.cwd
        prompt = item.prompt
        seed = item.faceSeed
        shape = item.blobShape ?? Theme.actionShape
        color = item.bodyColor ?? Theme.actionColor
        self.launching = launching
        self.squintToken = squintToken
        self.hint = hint
    }

    /// The face look for a hover state.
    func face(hovered: Bool) -> ActionFace {
        ActionFace(phase: launching ? .launching : (hovered ? .hovered : .resting), shape: shape, color: color)
    }
}
