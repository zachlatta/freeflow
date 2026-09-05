import Foundation

enum ModelConfigurationTests {
    static func run() {
        testProviderlessAliasesMatchCanonicalModels()
        testKnownModelSettingsRemainStable()
        testModelListsAreConsistent()
        testThinkTagStripping()
    }

    private static func testProviderlessAliasesMatchCanonicalModels() {
        assertSameConfig(" GPT-OSS-20B ", "openai/gpt-oss-20b")
        assertSameConfig("gpt-oss-120b", "openai/gpt-oss-120b")
        assertSameConfig("gpt-oss-safeguard-20b", "openai/gpt-oss-safeguard-20b")
        assertSameConfig("qwen3-32b", "qwen/qwen3-32b")
        assertSameConfig(" QWEN3.6-27B ", "qwen/qwen3.6-27b")
    }

    private static func testKnownModelSettingsRemainStable() {
        let gptOSS = ModelConfiguration.config(for: "openai/gpt-oss-20b")
        TestSupport.expectEqual(gptOSS.maxCompletionTokens, 4096)
        TestSupport.expectEqual(gptOSS.reasoningEffort, "low")
        TestSupport.expectEqual(gptOSS.includeReasoning, false)
        TestSupport.expectEqual(gptOSS.shouldStripThinkTags, false)

        let qwen = ModelConfiguration.config(for: "qwen/qwen3.6-27b")
        TestSupport.expectEqual(qwen.reasoningEffort, "none")
        TestSupport.expectEqual(qwen.includeReasoning, false)
        TestSupport.expectEqual(qwen.shouldStripThinkTags, true)

        let unknown = ModelConfiguration.config(for: "example/unknown-model")
        TestSupport.expectEqual(unknown.maxCompletionTokens, nil)
        TestSupport.expectEqual(unknown.reasoningEffort, nil)
        TestSupport.expectEqual(unknown.includeReasoning, nil)
        TestSupport.expectEqual(unknown.shouldStripThinkTags, false)
    }

    private static func testModelListsAreConsistent() {
        TestSupport.expectEqual(Set(ModelConfiguration.llmModels).count, ModelConfiguration.llmModels.count)
        TestSupport.expectEqual(Set(ModelConfiguration.visionModels).count, ModelConfiguration.visionModels.count)
        TestSupport.expectEqual(Set(ModelConfiguration.transcriptionModels).count, ModelConfiguration.transcriptionModels.count)
        TestSupport.expect(
            Set(ModelConfiguration.visionModels).isSubset(of: Set(ModelConfiguration.llmModels)),
            "Every vision model must also be selectable as an LLM"
        )
    }

    private static func testThinkTagStripping() {
        TestSupport.expectEqual(
            ModelConfiguration.stripThinkTags("<think>hidden</think> Visible output"),
            "Visible output"
        )
        TestSupport.expectEqual(
            ModelConfiguration.stripThinkTags("<think>one</think>\n<think>two</think>\nResult"),
            "Result"
        )
        TestSupport.expectEqual(ModelConfiguration.stripThinkTags("<think>unfinished"), "")
        TestSupport.expectEqual(
            ModelConfiguration.stripThinkTags("Ordinary output with a later <think> marker"),
            "Ordinary output with a later <think> marker"
        )
    }

    private static func assertSameConfig(_ alias: String, _ canonical: String) {
        let aliasConfig = ModelConfiguration.config(for: alias)
        let canonicalConfig = ModelConfiguration.config(for: canonical)
        TestSupport.expectEqual(aliasConfig.maxCompletionTokens, canonicalConfig.maxCompletionTokens)
        TestSupport.expectEqual(aliasConfig.reasoningEffort, canonicalConfig.reasoningEffort)
        TestSupport.expectEqual(aliasConfig.includeReasoning, canonicalConfig.includeReasoning)
        TestSupport.expectEqual(aliasConfig.shouldStripThinkTags, canonicalConfig.shouldStripThinkTags)
    }
}
