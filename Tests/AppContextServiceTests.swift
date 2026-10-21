import Foundation

@main
struct AppContextServiceTests {
    static func main() {
        testQwenRawOutputIsSummarized()
        testQwenReasoningOutputIsStripped()
        testNonStrippingModelPreservesExistingBehavior()
        testDeprecatedGroqModelsAreNotPredefined()
        testQwenCleanupDisablesReasoning()
        testMiniMaxModelsArePredefinedAndStripThinkTags()
        print("AppContextServiceTests passed")
    }

    private static func testQwenRawOutputIsSummarized() {
        let output = """
        The user is replying to an email about the product launch. They likely intend to confirm the next steps. This third sentence should be dropped.
        """

        let summary = AppContextService.activitySummary(from: output, model: "qwen/qwen3.6-27b")

        expectEqual(
            summary,
            "The user is replying to an email about the product launch. They likely intend to confirm the next steps."
        )
    }

    private static func testQwenReasoningOutputIsStripped() {
        let output = """
        <think>
        Hidden chain of thought should never appear in context.
        It contains misleading details.
        </think>
        The user is editing a project note in FreeFlow. They likely intend to tighten the release wording.
        """

        let summary = AppContextService.activitySummary(from: output, model: "qwen/qwen3.6-27b")

        expectEqual(
            summary,
            "The user is editing a project note in FreeFlow. They likely intend to tighten the release wording."
        )
        expect(summary?.contains("Hidden chain of thought") == false, "Qwen reasoning leaked into summary")
    }

    private static func testNonStrippingModelPreservesExistingBehavior() {
        let output = "<think>Visible for non-stripping models.</think> The user is writing a status update."

        let summary = AppContextService.activitySummary(
            from: output,
            model: "meta-llama/llama-4-scout-17b-16e-instruct"
        )

        expectEqual(summary, output)
    }

    private static func testDeprecatedGroqModelsAreNotPredefined() {
        let deprecatedModels = [
            "qwen/qwen3-32b",
            "meta-llama/llama-4-scout-17b-16e-instruct",
            "llama-3.1-8b-instant",
            "llama-3.3-70b-versatile"
        ]

        for model in deprecatedModels {
            expect(!ModelConfiguration.llmModels.contains(model), "Deprecated model remains in picker: \(model)")
        }
        expect(ModelConfiguration.llmModels.contains("qwen/qwen3.6-27b"), "New fallback is missing from picker")
    }

    private static func testQwenCleanupDisablesReasoning() {
        let config = ModelConfiguration.config(for: "qwen/qwen3.6-27b")

        expect(config.reasoningEffort == "none", "Qwen cleanup should disable reasoning")
        expect(config.includeReasoning == false, "Qwen cleanup should exclude reasoning output")
    }

    private static func testMiniMaxModelsArePredefinedAndStripThinkTags() {
        guard let flashIndex = ModelConfiguration.llmModels.firstIndex(of: "MiniMax-M3.1-Flash"),
              let m3Index = ModelConfiguration.llmModels.firstIndex(of: "MiniMax-M3") else {
            expect(false, "MiniMax models are missing from the picker")
            return
        }
        expect(m3Index == flashIndex + 1, "MiniMax-M3 should follow MiniMax-M3.1-Flash")
        expect(ModelConfiguration.llmModels.contains("MiniMax-M3.1-Flash"), "MiniMax-M3.1-Flash is missing from the picker")
        expect(ModelConfiguration.llmModels.contains("MiniMax-M3"), "MiniMax-M3 is missing from the picker")
        expect(!ModelConfiguration.llmModels.contains("MiniMax-M2.7"), "Retired MiniMax-M2.7 remains in the picker")

        let miniMaxModels = ModelConfiguration.llmModels.filter { $0.hasPrefix("MiniMax-") }
        expect(miniMaxModels == ["MiniMax-M3.1-Flash", "MiniMax-M3"], "Unexpected ordinary MiniMax choices")
        for model in ["MiniMax-M3.1-Flash", "MiniMax-M3", "MiniMax-M2.7", "  minimax-m3.1-flash  "] {
            let config = ModelConfiguration.config(for: model)
            expect(config.shouldStripThinkTags, "MiniMax model should strip think tags: \(model)")
            expect(config.reasoningEffort == nil, "MiniMax should retain provider reasoning defaults")
            expect(config.includeReasoning == nil, "MiniMax should not disable adaptive thinking")
            expect(config.maxCompletionTokens == nil, "MiniMax should retain provider token defaults")
        }
        expect(!ModelConfiguration.config(for: "custom-model").shouldStripThinkTags, "Custom model behavior changed")

        let reasoningOutput = """
        <think>
        Hidden reasoning should never reach the transcript.
        </think>
        Cleaned transcript text.
        """
        for model in ["MiniMax-M3.1-Flash", "MiniMax-M3", "MiniMax-M2.7"] {
            let summary = AppContextService.activitySummary(from: reasoningOutput, model: model)
            expect(summary?.contains("Hidden reasoning") == false, "MiniMax reasoning leaked into summary: \(model)")
            expect(summary?.contains("Cleaned transcript text.") == true, "MiniMax summary dropped the transcript text: \(model)")
        }
    }

    private static func expectEqual(_ actual: String?, _ expected: String, file: StaticString = #file, line: UInt = #line) {
        expect(actual == expected, "Expected \(expected.debugDescription), got \((actual ?? "nil").debugDescription)", file: file, line: line)
    }

    private static func expect(_ condition: Bool, _ message: String, file: StaticString = #file, line: UInt = #line) {
        if !condition {
            fatalError("\(file):\(line): \(message)")
        }
    }
}
