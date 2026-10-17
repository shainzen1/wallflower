import Foundation

/// The colour of a project: one of `Theme.projectPalette`, picked by a deterministic hash of the
/// project key, so two sessions in the same repo share it across launches. The dot in the bulge
/// always; in `.project` colour mode the body too, with the status folded in by `color(for:projectKey:)`.
enum ProjectColor {
    static func color(for projectKey: String) -> EyeColor {
        let palette = Theme.projectPalette
        return palette[SeedHash(projectKey).index(0, count: palette.count)]
    }

    /// `.project` colour mode: the body colour of a status. Needs input is amber whatever the project,
    /// working, just finished and your turn show the project colour (the builder adds the mint flash
    /// and the your-turn halo), idle the project colour dimmed by `Theme.projectIdleDim`, ended the grey of every mode.
    static func color(for status: FaceStatus, projectKey: String) -> EyeColor {
        let project = color(for: projectKey)
        switch status {
        case .needsInput: return Theme.needsInputColor
        case .working, .justFinished, .yourTurn: return project
        case .idle: return project.dimmed(Theme.projectIdleDim)
        case .ended: return Theme.endedColor
        }
    }

    /// `count` keys that hash to pairwise different palette colours (the playground's sample projects).
    static func sampleKeys(count: Int) -> [String] {
        var keys: [String] = []
        var seen: Set<EyeColor> = []
        var index = 0
        while keys.count < min(count, Theme.projectPalette.count), index < 10_000 {
            let key = "project-\(index)"
            index += 1
            let color = color(for: key)
            if seen.insert(color).inserted { keys.append(key) }
        }
        return keys
    }
}
