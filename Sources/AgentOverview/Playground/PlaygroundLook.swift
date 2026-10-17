import SwiftUI

/// The playground's runtime overrides, applied to every face it shows.
struct PlaygroundLook: Equatable {
    var style: FaceStyle
    var filter: FaceFilter
    var shapeMode: Theme.BlobShapeMode
    var colorMode: Theme.ColorMode
    var blinkToken: Int
    var replayToken: Int
    /// Working hero: its substate and satellites.
    var activity: SessionActivity = .thinking
    var satellites: Int = 0
    /// Needs-input hero: bump to hop.
    var attentionToken: Int = 0
    /// Every status hero: bump for the excited reaction (only the working hero's program has it).
    var excitedToken: Int = 0
    /// Needs-input hero: what it waits for (question or permission: pulse and grow tempo).
    var waitingKind: WaitingKind = .question
    /// Every hero: as if the row were under the pointer (the genie under `.stretch`).
    var hovered: Bool = false
    /// What a hover does to the faces.
    var hoverEffect: Theme.HoverEffect = Theme.hoverEffect

    /// The columns of the preset row and the grid: one per eye preset (dot matrix), per status
    /// shape (blob, `.status` mode) or per silhouette (blob, `.identity` mode).
    var columns: [PlaygroundColumn] {
        switch (style, shapeMode) {
        case (.dotMatrix, _):
            return EyePreset.allCases.map { PlaygroundColumn(label: $0.label, preset: $0, body: nil) }
        case (.blob, .status):
            return BlobBody.statusPresets.map { PlaygroundColumn(label: $0.label, preset: nil, body: $0.body) }
        case (.blob, .identity):
            return BlobShape.allCases.map { PlaygroundColumn(label: $0.label, preset: nil, body: BlobBody(shape: $0)) }
        }
    }

    /// Sample project keys for `.project` colour mode: one distinct hue per column.
    var projectKeys: [String] {
        ProjectColor.sampleKeys(count: Theme.projectPalette.count)
    }

    /// The project key column `index` shows in `.project` colour mode (nil in the other modes).
    func projectKey(column index: Int) -> String? {
        guard colorMode == .project else { return nil }
        let keys = projectKeys
        return keys.isEmpty ? nil : keys[index % keys.count]
    }

    /// A face with every override applied.
    @MainActor
    func styled(_ face: FaceView) -> FaceView {
        face.faceStyle(style).faceFilter(filter).blobShapeMode(shapeMode).colorMode(colorMode).hoverEffect(hoverEffect)
            .triggers(blink: blinkToken, replay: replayToken)
    }
}
