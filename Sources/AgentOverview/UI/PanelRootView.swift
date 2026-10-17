import SwiftUI

/// Root of the panel's hosting view. It is exactly the hosting view's size (so `NSHostingView`
/// never has to place a root that is larger than itself) and attaches the capsule content as a
/// overlay on the screen-edge side (trailing on the right edge, leading on the left). The hosting
/// view is always the full content width plus the window padding
/// (`PanelWindow.install`), whatever the window's width: nothing here moves when the window
/// grows or shrinks. The window padding on the inner side stays transparent.
///
/// The content takes its identity from the model: a rebuild (a settings change, a new model) builds
/// every view and face afresh. The faces read the look from `FaceLook`, which SwiftUI does not track,
/// so a face whose own inputs did not change would otherwise keep the old look.
struct PanelRootView: View {
    let model: PanelModel

    var body: some View {
        Color.clear
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: model.side.edgeAlignment) {
                CapsuleView(model: model)
            }
            .id(ObjectIdentifier(model))
    }
}
