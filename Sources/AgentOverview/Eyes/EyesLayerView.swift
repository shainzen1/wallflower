import SwiftUI

/// SwiftUI bridge to the Core Animation eyes. SwiftUI only hands over a value; every
/// animation and loop lives in the layer tree and runs in the render server.
struct EyesLayerView: NSViewRepresentable {
    let configuration: FaceConfiguration

    func makeNSView(context: Context) -> EyesHostView {
        let view = EyesHostView(frame: CGRect(x: 0, y: 0, width: configuration.size, height: configuration.size))
        view.apply(configuration)
        return view
    }

    func updateNSView(_ view: EyesHostView, context: Context) {
        view.apply(configuration)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: EyesHostView, context: Context) -> CGSize? {
        CGSize(width: configuration.size, height: configuration.size)
    }
}
