import AppKit
import Observation
import SwiftUI

/// "Copy Setup Prompt", in Settings > General > Actions and on the welcome's "Action faces": puts
/// `ActionSetupPrompt` for `fileURL` on the pasteboard and reads "Copied" for a moment
/// (`CopyFeedback`). The look comes from the surrounding button style. Both labels are laid out on
/// top of each other, so the button keeps its width when the label changes.
struct CopySetupPromptButton: View {
    let fileURL: URL
    /// Owned by the window's model: the Command Line Tools have no `@State`.
    let feedback: CopyFeedback

    static let title = "Copy Setup Prompt"
    static let copiedTitle = "Copied"

    var body: some View {
        Button {
            feedback.copy(ActionSetupPrompt.text(fileURL: fileURL))
        } label: {
            ZStack {
                Label(Self.title, systemImage: "doc.on.doc")
                    .opacity(feedback.copied ? 0 : 1)
                    .accessibilityHidden(feedback.copied)
                Label(Self.copiedTitle, systemImage: "checkmark")
                    .opacity(feedback.copied ? 1 : 0)
                    .accessibilityHidden(!feedback.copied)
            }
        }
        .help("Copy a prompt that helps a coding agent set up your actions")
    }
}

/// A copy to the pasteboard with brief confirmation: `copied` is true for `duration` after `copy`,
/// cleared by one one-shot task (a second copy starts it over). Nothing keeps running afterwards.
@Observable @MainActor
final class CopyFeedback {
    private(set) var copied = false
    @ObservationIgnored let duration: Duration
    /// Writes the text (tests inject one).
    @ObservationIgnored private let write: @MainActor (String) -> Void
    @ObservationIgnored private var reset: Task<Void, Never>?

    init(duration: Duration = ActionSetupPrompt.copiedDuration, write: @escaping @MainActor (String) -> Void = CopyFeedback.writeToPasteboard) {
        self.duration = duration
        self.write = write
    }

    func copy(_ text: String) {
        write(text)
        copied = true
        reset?.cancel()
        reset = Task { [weak self, duration] in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled else { return }
            self?.copied = false
        }
    }

    static func writeToPasteboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}
