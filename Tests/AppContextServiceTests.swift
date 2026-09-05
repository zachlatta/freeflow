import Foundation

enum AppContextServiceTests {
    static func run() {
        testQwenRawOutputIsSummarized()
        testQwenReasoningOutputIsStripped()
        testNonStrippingModelPreservesExistingBehavior()
        testDeprecatedGroqModelsAreNotPredefined()
        testQwenCleanupDisablesReasoning()
        testAtlasCloudModelsArePredefined()
        testAtlasCloudAliasesUseAtlasModelConfig()
        testAtlasCloudQwenOutputIsStripped()
    }

    private static func testQwenRawOutputIsSummarized() {
        let output = """
        The user is replying to an email about the product launch. They likely intend to confirm the next steps. This third sentence should be dropped.
        """

        let summary = AppContextService.activitySummary(from: output, model: "qwen/qwen3.6-27b")

        TestSupport.expectEqual(
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

        TestSupport.expectEqual(
            summary,
            "The user is editing a project note in FreeFlow. They likely intend to tighten the release wording."
        )
        TestSupport.expect(summary?.contains("Hidden chain of thought") == false, "Qwen reasoning leaked into summary")
    }

    private static func testNonStrippingModelPreservesExistingBehavior() {
        let output = "<think>Visible for non-stripping models.</think> The user is writing a status update."

        let summary = AppContextService.activitySummary(
            from: output,
            model: "meta-llama/llama-4-scout-17b-16e-instruct"
        )

        TestSupport.expectEqual(summary, output)
    }

    private static func testDeprecatedGroqModelsAreNotPredefined() {
        let deprecatedModels = [
            "qwen/qwen3-32b",
            "meta-llama/llama-4-scout-17b-16e-instruct",
            "llama-3.1-8b-instant",
            "llama-3.3-70b-versatile"
        ]

        for model in deprecatedModels {
            TestSupport.expect(!ModelConfiguration.llmModels.contains(model), "Deprecated model remains in picker: \(model)")
        }
        TestSupport.expect(ModelConfiguration.llmModels.contains("qwen/qwen3.6-27b"), "New fallback is missing from picker")
    }

    private static func testQwenCleanupDisablesReasoning() {
        let config = ModelConfiguration.config(for: "qwen/qwen3.6-27b")

        expect(config.reasoningEffort == "none", "Qwen cleanup should disable reasoning")
        expect(config.includeReasoning == false, "Qwen cleanup should exclude reasoning output")
    }

    private static func testAtlasCloudModelsArePredefined() {
        expect(
            ModelConfiguration.llmModels.contains(ModelConfiguration.atlasCloudPrimaryModel),
            "Atlas Cloud primary model is missing from picker"
        )
        expect(
            ModelConfiguration.llmModels.contains(ModelConfiguration.atlasCloudReasoningModel),
            "Atlas Cloud reasoning model is missing from picker"
        )
    }

    private static func testAtlasCloudAliasesUseAtlasModelConfig() {
        let qwenConfig = ModelConfiguration.config(for: "atlascloud/qwen/qwen3.5-flash")
        expect(qwenConfig.shouldStripThinkTags, "Atlas Cloud Qwen output should strip think tags")

        let shortQwenConfig = ModelConfiguration.config(for: "atlas/qwen3.5-flash")
        expect(shortQwenConfig.shouldStripThinkTags, "Atlas Cloud short Qwen alias should strip think tags")

        let reasoningConfig = ModelConfiguration.config(for: "atlas-cloud/deepseek-ai/deepseek-v4-pro")
        expect(reasoningConfig.maxCompletionTokens == 4096, "Atlas Cloud reasoning model should set output budget")
        expect(reasoningConfig.shouldStripThinkTags, "Atlas Cloud reasoning output should strip think tags")
    }

    private static func testAtlasCloudQwenOutputIsStripped() {
        let output = """
        <think>
        Hidden reasoning should not be included.
        </think>
        The user is editing a note in FreeFlow. They likely want a concise rewrite.
        """

        let summary = AppContextService.activitySummary(from: output, model: "atlas/qwen/qwen3.5-flash")

        expectEqual(
            summary,
            "The user is editing a note in FreeFlow. They likely want a concise rewrite."
        )
        expect(summary?.contains("Hidden reasoning") == false, "Atlas Cloud Qwen reasoning leaked into summary")
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
