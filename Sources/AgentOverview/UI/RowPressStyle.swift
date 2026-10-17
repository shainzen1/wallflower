import SwiftUI

/// Press feedback for a face: scales to `Theme.pressScale` while the mouse is down.
/// Reduce Motion keeps the face still.
struct RowPressStyle: ButtonStyle {
    var reduceMotion = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? Theme.pressScale : 1)
            .animation(.easeOut(duration: Theme.pressDuration), value: configuration.isPressed)
    }
}
