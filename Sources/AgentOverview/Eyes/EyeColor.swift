import AppKit
import SwiftUI

/// A glowing eye tint. Plain components so it is Sendable; converted to CGColor at the layer.
struct EyeColor: Equatable, Hashable, Sendable {
    let name: String
    let red: Double
    let green: Double
    let blue: Double

    init(name: String, red: Double, green: Double, blue: Double) {
        self.name = name
        self.red = red
        self.green = green
        self.blue = blue
    }

    /// `#RRGGBB` (the hash is optional); nil for anything else.
    init?(hex: String, name: String) {
        var text = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("#") { text.removeFirst() }
        guard text.count == 6, let value = UInt32(text, radix: 16) else { return nil }
        self.init(
            name: name,
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }

    var cgColor: CGColor {
        CGColor(srgbRed: red, green: green, blue: blue, alpha: 1)
    }

    var color: Color {
        Color(.sRGB, red: red, green: green, blue: blue, opacity: 1)
    }

    /// The colour mixed toward white by `amount` (0 = unchanged, 1 = white): the excited brighten.
    func brightened(_ amount: Double) -> EyeColor {
        let mix = min(max(amount, 0), 1)
        return EyeColor(name: "\(name) bright", red: red + (1 - red) * mix, green: green + (1 - green) * mix, blue: blue + (1 - blue) * mix)
    }

    /// The colour mixed toward black by `amount` (0 = unchanged, 1 = black). On the black capsule
    /// this is what an opacity would look like, without a translucent body.
    func dimmed(_ amount: Double) -> EyeColor {
        let keep = 1 - min(max(amount, 0), 1)
        return EyeColor(name: "\(name) dim", red: red * keep, green: green * keep, blue: blue * keep)
    }
}
