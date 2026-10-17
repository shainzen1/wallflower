import Foundation

/// What makes one face look like itself: shape preset, palette colour (used in `.identity`
/// colour mode) and the timing phases of its loops. Derived from a seed (the session id) with a
/// deterministic hash, so it is stable for the seed's lifetime and differs between seeds.
struct FaceIdentity: Equatable, Hashable, Sendable {
    let color: EyeColor
    let preset: EyePreset
    let hash: SeedHash
    /// Blob style: the silhouette (`.identity` shape mode) and the body colour (`.identity` colour mode).
    let shape: BlobShape
    let blobColor: EyeColor

    /// Full identity from a seed.
    init(seed: String) {
        let hash = SeedHash(seed)
        self.hash = hash
        self.color = Theme.eyePalette[hash.index(0, count: Theme.eyePalette.count)]
        self.preset = EyePreset.allCases[hash.index(1, count: EyePreset.allCases.count)]
        self.shape = Self.seededShape(hash)
        self.blobColor = Self.seededBlobColor(hash)
    }

    /// Identity from a seed with the preset forced (playground columns).
    init(seed: String, preset: EyePreset) {
        let hash = SeedHash(seed)
        self.hash = hash
        self.color = Theme.eyePalette[hash.index(0, count: Theme.eyePalette.count)]
        self.preset = preset
        self.shape = Self.seededShape(hash)
        self.blobColor = Self.seededBlobColor(hash)
    }

    /// Identity from a seed with the blob silhouette forced (playground columns in `.identity` shape mode).
    init(seed: String, shape: BlobShape) {
        let hash = SeedHash(seed)
        self.hash = hash
        self.color = Theme.eyePalette[hash.index(0, count: Theme.eyePalette.count)]
        self.preset = EyePreset.allCases[hash.index(1, count: EyePreset.allCases.count)]
        self.shape = shape
        self.blobColor = Self.seededBlobColor(hash)
    }

    /// Explicit identity (the blob fields still come from the hash).
    init(color: EyeColor, preset: EyePreset, hash: SeedHash) {
        self.color = color
        self.preset = preset
        self.hash = hash
        self.shape = Self.seededShape(hash)
        self.blobColor = Self.seededBlobColor(hash)
    }

    private static func seededShape(_ hash: SeedHash) -> BlobShape {
        BlobShape.identityShapes[hash.index(2, count: BlobShape.identityShapes.count)]
    }

    private static func seededBlobColor(_ hash: SeedHash) -> EyeColor {
        Theme.blobPalette[hash.index(3, count: Theme.blobPalette.count)]
    }

    // MARK: Blob variation (`.status` shape mode shows identity only through these)

    /// Small eye tilt delta in degrees, so two faces with the same status are not clones.
    var blobTiltDelta: Double { hash.value(in: Theme.blobIdentityTiltRange, slot: 50) }
    /// Small eye spacing delta in degrees.
    var blobSplitDelta: Double { hash.value(in: Theme.blobIdentitySplitRange, slot: 51) }

    // MARK: Loop personality (slots are arbitrary but fixed, so values stay stable)

    /// Phase in [0, 1) that offsets the blink loop so faces never blink in sync.
    var blinkPhase: Double { hash.unit(10) }
    /// Phase for the dart loop.
    var dartPhase: Double { hash.unit(11) }
    /// Phase for the pulse loop.
    var pulsePhase: Double { hash.unit(12) }
    /// Phase for the working variety loop.
    var varietyPhase: Double { hash.unit(13) }
    /// Phase for the working reading scan.
    var scanPhase: Double { hash.unit(14) }
    /// Phase for the idle gaze wander.
    var wanderPhase: Double { hash.unit(15) }
    /// Phase for the scale breath.
    var breathPhase: Double { hash.unit(16) }
    /// Phase for the your-turn shape swap and its hop.
    var swapPhase: Double { hash.unit(17) }

    /// Blink interval for a status, from its Theme range, picked per face.
    func blinkInterval(in range: ClosedRange<Double>) -> Double {
        hash.value(in: range, slot: 20)
    }

    /// Time between two working glances.
    var dartInterval: Double { hash.value(in: Theme.dartInterval, slot: 21) }
    /// How long focused holds between two alternative working poses.
    var workingPoseInterval: Double { hash.value(in: Theme.workingPoseInterval, slot: 22) }
    /// Time between two idle mood flickers.
    var idleMoodInterval: Double { hash.value(in: Theme.idleMoodInterval, slot: 23) }

    /// Picks one of two expressions for a status (surprised or awe, happy or glee).
    func pick(_ a: Expression, _ b: Expression, slot: UInt64) -> Expression {
        hash.unit(slot) < 0.5 ? a : b
    }

    /// Order of the alternative working expressions (squint first or skeptic first).
    var workingAlternatives: [Expression] {
        hash.unit(31) < 0.5 ? [.squint, .skeptic] : [.skeptic, .squint]
    }

    /// The idle mood flicker: a quick happy or a curious skeptic look.
    var idleMood: Expression {
        hash.unit(32) < 0.5 ? .happy : .skeptic
    }
}
