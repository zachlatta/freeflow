import Foundation

enum ProviderPresetTests {
    static func run() {
        testPresetModelSupportsScreenshotContext()
        testAtlasCloudHostDetection()
        testPreviousKeyIsNeverSentToAtlasCloud()
        testEmptyTranscriptionOverridesStayOnPreviousProvider()
        testExistingTranscriptionOverridesArePreserved()
        testPartialTranscriptionOverridesKeepTheirPair()
        testRepeatingThePresetDoesNotClearTheAtlasCloudKey()
    }

    private static let groqURL = "https://api.groq.com/openai/v1"

    private static func snapshot(
        baseURL: String = groqURL,
        key: String = "synthetic-groq-key",
        transcriptionURL: String = "",
        transcriptionKey: String = ""
    ) -> ProviderSettingsSnapshot {
        ProviderSettingsSnapshot(
            apiBaseURL: baseURL,
            apiKey: key,
            transcriptionAPIURL: transcriptionURL,
            transcriptionAPIKey: transcriptionKey
        )
    }

    private static func testPresetModelSupportsScreenshotContext() {
        TestSupport.expect(
            ModelConfiguration.visionModels.contains(ProviderPreset.atlasCloudModel),
            "The preset's context model must accept image input"
        )
        TestSupport.expect(
            ModelConfiguration.llmModels.contains(ProviderPreset.atlasCloudModel),
            "The preset's model must be offered in the model pickers"
        )
    }

    private static func testAtlasCloudHostDetection() {
        TestSupport.expect(ProviderPreset.isAtlasCloud(baseURL: ProviderPreset.atlasCloudAPIBaseURL), "Preset URL should be detected")
        TestSupport.expect(ProviderPreset.isAtlasCloud(baseURL: " https://API.atlascloud.ai/v1/ "), "Host match ignores case, spaces and a trailing slash")
        TestSupport.expect(!ProviderPreset.isAtlasCloud(baseURL: groqURL), "Groq is not Atlas Cloud")
        TestSupport.expect(!ProviderPreset.isAtlasCloud(baseURL: "http://api.atlascloud.ai/v1"), "Plain http is not accepted")
        TestSupport.expect(!ProviderPreset.isAtlasCloud(baseURL: "https://api.atlascloud.ai.example.test/v1"), "Look-alike host is not Atlas Cloud")
    }

    /// No (URL, key) pair that reaches Atlas Cloud may carry the previous provider's key.
    private static func testPreviousKeyIsNeverSentToAtlasCloud() {
        let before = snapshot()
        let after = ProviderPreset.applyingAtlasCloud(to: before)

        TestSupport.expectEqual(after.apiBaseURL, ProviderPreset.atlasCloudAPIBaseURL)
        TestSupport.expectEqual(after.apiKey, "")

        let pairs = [
            (url: after.apiBaseURL, key: after.apiKey),
            (url: after.effectiveTranscriptionBaseURL, key: after.effectiveTranscriptionAPIKey),
        ]
        for pair in pairs where ProviderPreset.isAtlasCloud(baseURL: pair.url) {
            TestSupport.expect(pair.key != "synthetic-groq-key", "Previous provider key would be sent to Atlas Cloud")
        }
    }

    private static func testEmptyTranscriptionOverridesStayOnPreviousProvider() {
        let before = snapshot()
        let after = ProviderPreset.applyingAtlasCloud(to: before)

        TestSupport.expectEqual(after.effectiveTranscriptionBaseURL, before.effectiveTranscriptionBaseURL)
        TestSupport.expectEqual(after.effectiveTranscriptionAPIKey, before.effectiveTranscriptionAPIKey)
        TestSupport.expectEqual(after.transcriptionAPIURL, groqURL)
        TestSupport.expectEqual(after.transcriptionAPIKey, "synthetic-groq-key")
    }

    private static func testExistingTranscriptionOverridesArePreserved() {
        let before = snapshot(
            transcriptionURL: "https://asr.example.test/v1",
            transcriptionKey: "synthetic-asr-key"
        )
        let after = ProviderPreset.applyingAtlasCloud(to: before)

        TestSupport.expectEqual(after.transcriptionAPIURL, "https://asr.example.test/v1")
        TestSupport.expectEqual(after.transcriptionAPIKey, "synthetic-asr-key")
        TestSupport.expectEqual(after.effectiveTranscriptionBaseURL, "https://asr.example.test/v1")
        TestSupport.expectEqual(after.effectiveTranscriptionAPIKey, "synthetic-asr-key")
    }

    /// With only one override set, the other half keeps resolving to what it
    /// resolved to before, so no unintended URL/key pair is assembled.
    private static func testPartialTranscriptionOverridesKeepTheirPair() {
        let urlOnly = snapshot(transcriptionURL: "https://asr.example.test/v1")
        let afterURLOnly = ProviderPreset.applyingAtlasCloud(to: urlOnly)
        TestSupport.expectEqual(afterURLOnly.effectiveTranscriptionBaseURL, "https://asr.example.test/v1")
        TestSupport.expectEqual(afterURLOnly.effectiveTranscriptionAPIKey, urlOnly.effectiveTranscriptionAPIKey)

        let keyOnly = snapshot(transcriptionKey: "synthetic-asr-key")
        let afterKeyOnly = ProviderPreset.applyingAtlasCloud(to: keyOnly)
        TestSupport.expectEqual(afterKeyOnly.effectiveTranscriptionBaseURL, groqURL)
        TestSupport.expectEqual(afterKeyOnly.effectiveTranscriptionAPIKey, "synthetic-asr-key")
    }

    private static func testRepeatingThePresetDoesNotClearTheAtlasCloudKey() {
        let onAtlas = snapshot(baseURL: ProviderPreset.atlasCloudAPIBaseURL, key: "synthetic-atlas-key")
        TestSupport.expectEqual(ProviderPreset.applyingAtlasCloud(to: onAtlas), onAtlas)

        let once = ProviderPreset.applyingAtlasCloud(to: snapshot())
        TestSupport.expectEqual(ProviderPreset.applyingAtlasCloud(to: once), once)
    }
}
