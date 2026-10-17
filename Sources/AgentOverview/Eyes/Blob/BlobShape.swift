import Foundation

/// The silhouettes, each written from scratch as a formula around `Theme.blobRadius` (r): a
/// superellipse exponent, lobed sine terms, a Gaussian tip or dent, or a union of circles.
/// All stay inside the cell (max radius about 0.49) and share the same 64 sample angles.
enum BlobShape: String, CaseIterable, Sendable {
    case round
    case squircle
    case pebble
    case bean
    case drop
    case pill
    case softHex
    case cloud
    /// Soft four-point star (points on the axes): the action faces' own silhouette, never a session's.
    case star

    /// The silhouettes a seed can pick in `.identity` shape mode: every session shape, not the star.
    static let identityShapes: [BlobShape] = [.round, .squircle, .pebble, .bean, .drop, .pill, .softHex, .cloud]

    /// Human label for the playground.
    var label: String {
        switch self {
        case .softHex: "soft hex"
        default: rawValue
        }
    }

    /// Where the eyes sit vertically on this silhouette, added to the pose's lift (fraction of
    /// the face size): the cloud carries its mass in the lobes, so the eyes move up into them.
    var eyeLift: Double {
        switch self {
        case .cloud: 0.06
        case .drop: 0.01
        case .bean: -0.01
        default: 0
        }
    }

    /// The radial profile, built once per shape.
    var profile: BlobProfile {
        switch self {
        case .round: Self.roundProfile
        case .squircle: Self.squircleProfile
        case .pebble: Self.pebbleProfile
        case .bean: Self.beanProfile
        case .drop: Self.dropProfile
        case .pill: Self.pillProfile
        case .softHex: Self.softHexProfile
        case .cloud: Self.cloudProfile
        case .star: Self.starProfile
        }
    }

    // MARK: Formulas

    private static let r = Theme.blobRadius

    /// Superellipse radius: (|cos/sx|^n + |sin/sy|^n)^(-1/n). n = 2 is an ellipse, 4 is squarish.
    private static func superellipse(_ angle: Double, n: Double, sx: Double = 1, sy: Double = 1) -> Double {
        pow(pow(abs(cos(angle) / sx), n) + pow(abs(sin(angle) / sy), n), -1 / n)
    }

    /// A Gaussian bump of width `width` (radians) centred on `centre`, wrapping round the circle.
    private static func bump(_ angle: Double, centre: Double, width: Double) -> Double {
        var d = angle - centre
        d = d - (2 * .pi) * (d / (2 * .pi)).rounded()
        return exp(-(d * d) / (width * width))
    }

    private static let roundProfile = BlobProfile { _ in r }

    /// Squarish superellipse (n = 4), a touch smaller on the axes so the corners stay inside the cell.
    private static let squircleProfile = BlobProfile { angle in
        r * 0.96 * superellipse(angle, n: 4)
    }

    /// Lumpy stone: three low-order sine lobes with unrelated phases.
    private static let pebbleProfile = BlobProfile { angle in
        r * (1 + 0.05 * sin(2 * angle + 0.6) + 0.045 * sin(3 * angle - 0.4) + 0.02 * sin(5 * angle + 1.3))
    }

    /// Wide soft ellipse with one dent in the upper edge.
    private static let beanProfile = BlobProfile { angle in
        r * superellipse(angle, n: 2.3, sx: 1.10, sy: 0.90) * (1 - 0.11 * bump(angle, centre: 1.35, width: 0.45))
    }

    /// Teardrop, tip up: a slightly egg shaped base lifted by a soft Gaussian tip at the top.
    private static let dropProfile = BlobProfile { angle in
        r * (0.92 + 0.07 * sin(angle) + 0.13 * bump(angle, centre: .pi / 2, width: 0.55))
    }

    /// Horizontal capsule: a stadium-like superellipse, wider than tall.
    private static let pillProfile = BlobProfile { angle in
        r * superellipse(angle, n: 3.4, sx: 1.12, sy: 0.80)
    }

    /// Flat topped hexagon blended with a circle so the corners soften.
    private static let softHexProfile = BlobProfile { angle in
        let sector = angle - (angle / (.pi / 3)).rounded(.down) * (.pi / 3) - .pi / 6
        let hexagon = 1 / cos(sector)
        return r * 0.97 * (0.5 + 0.5 * hexagon)
    }

    /// Four-point star: a cosine lobe on each axis over a round core, so the points stay soft and the
    /// diagonals keep enough body for the eyes (0.72 r at the diagonals, 1.04 r at the points).
    private static let starProfile = BlobProfile { angle in
        r * 1.04 * (0.845 + 0.155 * cos(4 * angle))
    }

    /// Cloud: a wide flattened base with four rounded lobes along the top, as a union of circles
    /// and one offset superellipse (the inside test picks the farthest rim on every ray).
    private static let cloudProfile = BlobProfile(inside: { x, y in
        let base = pow(abs(x / (1.10 * r)), 3.0) + pow(abs((y + 0.12 * r) / (0.66 * r)), 3.0) <= 1
        let lobes: [(x: Double, y: Double, radius: Double)] = [
            (-0.62 * r, 0.10 * r, 0.44 * r),
            (-0.20 * r, 0.42 * r, 0.50 * r),
            (0.28 * r, 0.36 * r, 0.52 * r),
            (0.68 * r, 0.02 * r, 0.42 * r),
        ]
        let inLobe = lobes.contains { lobe in
            (x - lobe.x) * (x - lobe.x) + (y - lobe.y) * (y - lobe.y) <= lobe.radius * lobe.radius
        }
        return base || inLobe
    })
}
