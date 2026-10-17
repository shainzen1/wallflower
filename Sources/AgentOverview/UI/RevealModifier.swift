import SwiftUI

/// Fade in of one text line inside the bulge (plain ease-out opacity, `Theme.revealDuration`,
/// after `delay`) and a fast fade out (`Theme.revealExitDuration`, no delay). Nothing moves:
/// the text is anchored to the face slot, so the goo's overshoot never drags it along.
struct RevealModifier: ViewModifier {
    let visible: Bool
    let delay: TimeInterval

    func body(content: Content) -> some View {
        content
            .opacity(visible ? 1 : 0)
            .animation(
                visible
                    ? .easeOut(duration: Theme.revealDuration).delay(delay)
                    : .easeOut(duration: Theme.revealExitDuration),
                value: visible
            )
    }
}
