import SwiftUI

/// The one label style of the playground: 11 pt SF Pro in quiet grey.
struct PlaygroundLabel: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(Color(white: 0.6))
            .lineLimit(1)
    }
}
