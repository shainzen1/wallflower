import Foundation

/// Window geometry states of the panel. `expanded` takes the visible capsule width including the bulge.
/// `PanelModel` decides the state (animation rule 4); `PanelWindow` applies it in one resize.
enum PanelWindowState: Equatable, Sendable {
    case collapsed
    case expanded(width: CGFloat)
}
