import Foundation
import Testing
@testable import AgentOverview

@Suite("Action setup prompt")
struct ActionSetupPromptTests {
    private let text = ActionSetupPrompt.text(filePath: "~/Library/Application Support/Wallflower/actions.json")

    /// Every key `ActionItem` writes, read from an item with every field set.
    private var fileKeys: Set<String> {
        get throws {
            let item = ActionItem(
                id: "a", name: "b", cwd: "~", prompt: "c", seed: "d", symbol: "e", shape: "star", color: "#FFFFFF",
                days: ["mon"], model: "sonnet", effort: "low"
            )
            let data = try ActionItem.encode([item])
            let objects = try #require(try JSONSerialization.jsonObject(with: data) as? [[String: Any]])
            return Set(try #require(objects.first).keys)
        }
    }

    @Test("Names every field the file format has, so the two cannot drift apart")
    func mentionsEveryField() throws {
        let keys = try fileKeys
        #expect(keys.count == 11)
        for key in keys {
            #expect(text.contains("- `\(key)`:"), "\(key) is not described")
        }
    }

    @Test("Lists the allowed values from the decoding code")
    func allowedValues() {
        for value in ActionSchedule.weekdayKeys + BlobShape.allCases.map(\.rawValue) + ClaudeEffort.allCases.map(\.rawValue)
            + ActionEditorModel.ModelChoice.aliases.map(\.rawValue) {
            #expect(text.contains("`\(value)`"), "\(value) is missing")
        }
    }

    @Test("The examples are a valid actions file")
    func examplesDecode() throws {
        let items = try ActionItem.decode(Data(ActionSetupPrompt.examples.utf8))
        #expect(items.count == 3)
        #expect(Set(items.map(\.id)).count == items.count)
        #expect(text.contains(ActionSetupPrompt.examples))
    }

    @Test("Names the file with the home folder as ~, including an --actions-file path")
    func filePath() {
        let home = "/Users/demo"
        let standard = ActionSetupPrompt.text(
            fileURL: URL(filePath: "/Users/demo/Library/Application Support/Wallflower/actions.json"), home: home
        )
        #expect(standard.contains("`~/Library/Application Support/Wallflower/actions.json`"))
        let custom = ActionSetupPrompt.text(fileURL: URL(filePath: "/tmp/fixture/actions.json"), home: home)
        #expect(custom.contains("`/tmp/fixture/actions.json`"))
    }

    @Test("Carries the safety rules and the check, and no em-dash")
    func rulesAndStyle() {
        for phrase in ["Read the file first", "Back up the file", "Write valid JSON only", "Wait for my answers",
                       "Never invent a folder", "Settings > General > Actions lists them"] {
            #expect(text.contains(phrase), "\(phrase) is missing")
        }
        #expect(!text.contains("\u{2014}"))
        #expect(!text.replacingOccurrences(of: ActionSetupPrompt.examples, with: "").contains("  "), "a line continuation left a double space")
    }

    @Test("Copy confirms for a moment, then clears by itself", .timeLimit(.minutes(1)))
    @MainActor
    func copyFeedback() async throws {
        var written: [String] = []
        let feedback = CopyFeedback(duration: .milliseconds(50)) { written.append($0) }
        #expect(!feedback.copied)
        feedback.copy("one")
        feedback.copy("two")
        #expect(feedback.copied && written == ["one", "two"])
        for _ in 0..<100 where feedback.copied {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(!feedback.copied)
    }
}
