import SwiftUI

/// SwiftUI bridge to the Core Animation blob face. SwiftUI only hands over a value; every
/// animation and loop lives in the layer tree and runs in the render server.
struct BlobLayerView: NSViewRepresentable {
    let configuration: FaceConfiguration

    func makeNSView(context: Context) -> BlobHostView {
        let view = BlobHostView(frame: CGRect(x: 0, y: 0, width: configuration.size, height: configuration.size))
        view.apply(configuration)
        return view
    }

    func updateNSView(_ view: BlobHostView, context: Context) {
        view.apply(configuration)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: BlobHostView, context: Context) -> CGSize? {
        CGSize(width: configuration.size, height: configuration.size)
    }
}
