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
        testEmptyKeysAreBlockedUntilTranscriptionKeyIsSet()
        testFullTransitionAfterEnteringTheAtlasKey()
        testExistingAtlasURLNeedsSeparateTranscription()
        testStaleKeyValidationIsDiscarded()
        testPresetClearsUnsavedKeyWithEmptySavedKey()
        testRawDraftNormalizationBeforePreset()
        testEndpointEditsAndResetDiscardValidation()
    }

    private static func testRawDraftNormalizationBeforePreset() {
        let blankURL = snapshot(baseURL: " ", key: " synthetic-old-key ").normalizedDraft
        let applied = ProviderPreset.applyingAtlasCloud(to: blankURL, apiKeyDraft: " synthetic-old-key ")
        TestSupport.expectEqual(applied.settings.transcriptionAPIURL, APIConfigurationSaveFlow.defaultBaseURL)
        TestSupport.expectEqual(applied.settings.transcriptionAPIKey, "synthetic-old-key")
        let whitespaceKeys = snapshot(key: " ", transcriptionKey: " ").normalizedDraft
        TestSupport.expectEqual(ProviderPreset.blocker(for: whitespaceKeys), .transcriptionKeyRequired)
        let blocked = ProviderPreset.applyingAtlasCloud(to: whitespaceKeys)
        TestSupport.expect(!ProviderPreset.isAtlasCloud(baseURL: blocked.apiBaseURL), "Whitespace cannot be pinned as an explicit transcription key")
    }

    private static func testPresetClearsUnsavedKeyWithEmptySavedKey() {
        let before = snapshot(key: "", transcriptionKey: "synthetic-asr-key")
        let applied = ProviderPreset.applyingAtlasCloud(to: before, apiKeyDraft: "synthetic-unsaved-old-key")
        TestSupport.expectEqual(applied.settings.apiBaseURL, ProviderPreset.atlasCloudAPIBaseURL)
        TestSupport.expectEqual(applied.settings.apiKey, before.apiKey)
        TestSupport.expectEqual(applied.apiKeyDraft, "")
        TestSupport.expectEqual(applied.settings.effectiveTranscriptionAPIKey, "synthetic-asr-key")

        let blocked = ProviderPreset.applyingAtlasCloud(to: snapshot(key: ""), apiKeyDraft: "synthetic-draft")
        TestSupport.expectEqual(blocked.apiKeyDraft, "synthetic-draft")
        let alreadySelected = ProviderPreset.applyingAtlasCloud(to: applied.settings, apiKeyDraft: "synthetic-atlas-draft")
        TestSupport.expectEqual(alreadySelected.apiKeyDraft, "synthetic-atlas-draft")
    }

    private static func testEndpointEditsAndResetDiscardValidation() {
        let gate = KeyValidationGate()
        var savedKey = ""
        let unchanged = gate.begin()
        gate.invalidateIfEndpointChanged(from: groqURL, to: groqURL)
        TestSupport.expect(gate.applyIfCurrent(unchanged) { savedKey = "synthetic-current-key" }, "Losing focus without changing the endpoint keeps validation current")

        for (previous, next) in [(groqURL, ProviderPreset.atlasCloudAPIBaseURL), (ProviderPreset.atlasCloudAPIBaseURL, groqURL)] {
            let pending = gate.begin()
            gate.invalidateIfEndpointChanged(from: previous, to: next)
            TestSupport.expect(!gate.applyIfCurrent(pending) { savedKey = "synthetic-stale-key" }, "Editing or resetting the endpoint discards a pending validation")
            TestSupport.expectEqual(savedKey, "synthetic-current-key")
        }
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

    /// Every (URL, key) pair the app would use must keep keys with the host
    /// they were entered for.
    private static func expectNoKeyCrossesHosts(
        _ settings: ProviderSettingsSnapshot,
        atlasKey: String,
        otherKeys: [String],
        _ message: String
    ) {
        let pairs = [
            (url: settings.apiBaseURL, key: settings.apiKey),
            (url: settings.effectiveTranscriptionBaseURL, key: settings.effectiveTranscriptionAPIKey),
        ]
        for pair in pairs {
            if ProviderPreset.isAtlasCloud(baseURL: pair.url) {
                TestSupport.expect(!otherKeys.contains(pair.key), "\(message): another provider's key reaches Atlas Cloud")
            } else if !atlasKey.isEmpty {
                TestSupport.expect(pair.key != atlasKey, "\(message): the Atlas Cloud key reaches \(pair.url)")
            }
        }
    }

    /// With empty LLM and transcription keys, the old transcription URL would
    /// be pinned but its key would stay inherited, so the Atlas key entered
    /// later would be sent to the old transcription host. Apply is refused.
    private static func testEmptyKeysAreBlockedUntilTranscriptionKeyIsSet() {
        let empty = snapshot(key: "")
        TestSupport.expectEqual(ProviderPreset.blocker(for: empty), .transcriptionKeyRequired)
        TestSupport.expectEqual(ProviderPreset.applyingAtlasCloud(to: empty), empty)

        // URL override set, both keys empty: same hole.
        let urlOnly = snapshot(key: "", transcriptionURL: "https://asr.example.test/v1")
        TestSupport.expectEqual(ProviderPreset.blocker(for: urlOnly), .transcriptionKeyRequired)

        // With a transcription key set the preset is allowed.
        let withKey = snapshot(key: "", transcriptionKey: "synthetic-asr-key")
        TestSupport.expectEqual(ProviderPreset.blocker(for: withKey), nil)
    }

    /// Preset, then the user enters an Atlas key: transcription must still
    /// resolve to exactly the pair it used before, and no key crosses hosts.
    private static func testFullTransitionAfterEnteringTheAtlasKey() {
        let starts = [
            snapshot(),
            snapshot(key: "", transcriptionKey: "synthetic-asr-key"),
            snapshot(transcriptionURL: "https://asr.example.test/v1", transcriptionKey: "synthetic-asr-key"),
            snapshot(transcriptionURL: "https://asr.example.test/v1"),
            snapshot(transcriptionKey: "synthetic-asr-key"),
        ]
        for before in starts {
            let applied = ProviderPreset.applyingAtlasCloud(to: before)
            TestSupport.expectEqual(applied.apiBaseURL, ProviderPreset.atlasCloudAPIBaseURL)
            var entered = applied
            entered.apiKey = "synthetic-atlas-key"

            TestSupport.expectEqual(entered.effectiveTranscriptionBaseURL, before.effectiveTranscriptionBaseURL)
            TestSupport.expectEqual(entered.effectiveTranscriptionAPIKey, before.effectiveTranscriptionAPIKey)
            expectNoKeyCrossesHosts(
                entered,
                atlasKey: "synthetic-atlas-key",
                otherKeys: ["synthetic-groq-key"],
                "after entering the Atlas key"
            )
        }
    }

    /// An Atlas URL entered by hand with empty transcription overrides leaves
    /// transcription pointed at Atlas, which has no transcription endpoint.
    private static func testExistingAtlasURLNeedsSeparateTranscription() {
        let onAtlas = snapshot(baseURL: ProviderPreset.atlasCloudAPIBaseURL, key: "synthetic-atlas-key")
        TestSupport.expectEqual(ProviderPreset.blocker(for: onAtlas), .separateTranscriptionRequired)

        let toAtlas = snapshot(
            baseURL: ProviderPreset.atlasCloudAPIBaseURL,
            key: "synthetic-atlas-key",
            transcriptionURL: ProviderPreset.atlasCloudAPIBaseURL,
            transcriptionKey: "synthetic-asr-key"
        )
        TestSupport.expectEqual(ProviderPreset.blocker(for: toAtlas), .separateTranscriptionRequired)

        // URL set but key inherited: the Atlas key would go to the ASR host.
        let urlOnly = snapshot(
            baseURL: ProviderPreset.atlasCloudAPIBaseURL,
            key: "synthetic-atlas-key",
            transcriptionURL: "https://asr.example.test/v1"
        )
        TestSupport.expectEqual(ProviderPreset.blocker(for: urlOnly), .transcriptionKeyRequired)

        let configured = snapshot(
            baseURL: ProviderPreset.atlasCloudAPIBaseURL,
            key: "synthetic-atlas-key",
            transcriptionURL: "https://asr.example.test/v1",
            transcriptionKey: "synthetic-asr-key"
        )
        TestSupport.expectEqual(ProviderPreset.blocker(for: configured), nil)
        TestSupport.expectEqual(ProviderPreset.applyingAtlasCloud(to: configured), configured)
    }

    /// A validation started for the old provider finishes after the preset was
    /// chosen (deferred response): its key must not be saved.
    private static func testStaleKeyValidationIsDiscarded() {
        let gate = KeyValidationGate()
        var savedKey = ""

        // Normal case: nothing changes while validating.
        let first = gate.begin()
        TestSupport.expect(gate.applyIfCurrent(first) { savedKey = "synthetic-groq-key" }, "A current validation is applied")
        TestSupport.expectEqual(savedKey, "synthetic-groq-key")

        // Deferred case: the response is held back until the preset is applied.
        savedKey = ""
        let second = gate.begin()
        let deferredResponse = DispatchSemaphore(value: 0)
        var applied = true
        let finished = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            deferredResponse.wait()
            applied = gate.applyIfCurrent(second) { savedKey = "synthetic-groq-key" }
            finished.signal()
        }
        gate.invalidate() // the preset is chosen while the request is in flight
        deferredResponse.signal()
        finished.wait()
        TestSupport.expect(!applied, "A validation that finishes after the provider changed is rejected")
        TestSupport.expectEqual(savedKey, "")

        // A validation started after the change is current again.
        let third = gate.begin()
        TestSupport.expect(gate.applyIfCurrent(third) { savedKey = "synthetic-atlas-key" }, "A new validation is applied")
        TestSupport.expect(!gate.applyIfCurrent(second) { savedKey = "stale" }, "Older tokens stay invalid")
        TestSupport.expectEqual(savedKey, "synthetic-atlas-key")
    }
}
