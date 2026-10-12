import Foundation

enum TranscriptionConfigurationTests {
    static func run() {
        testDefaultProviderAndSharedSettings()
        testCustomOpenAICompatibleSettings()
        testElevenLabsCredentialIsolation()
        testSwitchingProvidersPreservesSelections()
        testEmptyModelsAndLanguage()
    }

    private static func testDefaultProviderAndSharedSettings() {
        let provider = TranscriptionProvider(rawValue: "unknown") ?? .openAICompatible
        TestSupport.expectEqual(provider, .openAICompatible)
        let config = configuration(provider: provider)
        TestSupport.expectEqual(config.provider, .openAICompatible)
        TestSupport.expectEqual(config.apiKey, "synthetic-llm-key")
        TestSupport.expectEqual(config.baseURL, "https://llm.example.invalid/v1")
        TestSupport.expectEqual(config.batchModel, "synthetic-whisper")
        TestSupport.expectEqual(config.realtimeModel, "synthetic-realtime")
        TestSupport.expectEqual(config.language, "en")
    }

    private static func testCustomOpenAICompatibleSettings() {
        let custom = configuration(
            provider: .openAICompatible,
            customURL: " https://transcription.example.invalid/v1/ ",
            customKey: " synthetic-transcription-key "
        )
        TestSupport.expectEqual(custom.apiKey, "synthetic-transcription-key")
        TestSupport.expectEqual(custom.baseURL, "https://transcription.example.invalid/v1/")

        // Each override is independent: a URL alone still uses the shared key,
        // and a key alone still uses the shared provider URL.
        let urlOnly = configuration(
            provider: .openAICompatible,
            customURL: "https://transcription.example.invalid/v1",
            customKey: " \n "
        )
        TestSupport.expectEqual(urlOnly.apiKey, "synthetic-llm-key")
        TestSupport.expectEqual(urlOnly.baseURL, "https://transcription.example.invalid/v1")
        let keyOnly = configuration(provider: .openAICompatible, customKey: "synthetic-transcription-key")
        TestSupport.expectEqual(keyOnly.apiKey, "synthetic-transcription-key")
        TestSupport.expectEqual(keyOnly.baseURL, "https://llm.example.invalid/v1")
    }

    private static func testElevenLabsCredentialIsolation() {
        let config = configuration(
            provider: .elevenLabs,
            customURL: "https://transcription.example.invalid/v1",
            customKey: "synthetic-transcription-key"
        )
        TestSupport.expectEqual(config.apiKey, "synthetic-elevenlabs-key")
        TestSupport.expectEqual(config.baseURL, TranscriptionService.defaultElevenLabsBaseURL)
        TestSupport.expectEqual(config.batchModel, "scribe_v2")
        TestSupport.expectEqual(config.realtimeModel, "scribe_v2_realtime")

        let missingKey = configuration(provider: .elevenLabs, elevenLabsKey: " \n ")
        TestSupport.expectEqual(missingKey.apiKey, "")
        TestSupport.expect(
            missingKey.apiKey != "synthetic-llm-key",
            "ElevenLabs must never fall back to the LLM credential"
        )
        let openAI = configuration(provider: .openAICompatible, sharedKey: "", elevenLabsKey: "synthetic-elevenlabs-key")
        TestSupport.expectEqual(openAI.apiKey, "")
    }

    private static func testSwitchingProvidersPreservesSelections() {
        for provider in [TranscriptionProvider.openAICompatible, .elevenLabs, .openAICompatible] {
            let config = configuration(
                provider: provider,
                customURL: "https://transcription.example.invalid/v1",
                customKey: "synthetic-transcription-key"
            )
            if provider == .openAICompatible {
                TestSupport.expectEqual(config.apiKey, "synthetic-transcription-key")
                TestSupport.expectEqual(config.baseURL, "https://transcription.example.invalid/v1")
                TestSupport.expectEqual(config.batchModel, "synthetic-whisper")
                TestSupport.expectEqual(config.realtimeModel, "synthetic-realtime")
            } else {
                TestSupport.expectEqual(config.apiKey, "synthetic-elevenlabs-key")
                TestSupport.expectEqual(config.baseURL, TranscriptionService.defaultElevenLabsBaseURL)
            }
        }
    }

    private static func testEmptyModelsAndLanguage() {
        let config = configuration(provider: .openAICompatible, model: " \n ", realtimeModel: " ", language: " ")
        TestSupport.expectEqual(config.batchModel, "whisper-large-v3")
        TestSupport.expectEqual(config.realtimeModel, "")
        TestSupport.expectEqual(config.language, nil)
    }

    private static func configuration(
        provider: TranscriptionProvider,
        sharedKey: String = " synthetic-llm-key ",
        customURL: String = "",
        customKey: String = "",
        elevenLabsKey: String = " synthetic-elevenlabs-key ",
        model: String = " synthetic-whisper ",
        realtimeModel: String = " synthetic-realtime ",
        language: String? = " en "
    ) -> TranscriptionConfiguration {
        TranscriptionConfiguration.resolve(
            provider: provider,
            apiKey: sharedKey,
            apiBaseURL: " https://llm.example.invalid/v1 ",
            transcriptionAPIURL: customURL,
            transcriptionAPIKey: customKey,
            elevenLabsAPIKey: elevenLabsKey,
            transcriptionModel: model,
            realtimeStreamingModel: realtimeModel,
            language: language
        )
    }
}
