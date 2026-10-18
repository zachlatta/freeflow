import Foundation

@main
struct FreeFlowTests {
    static func main() async {
        AppContextServiceTests.run()
        await LLMAPITransportTests.run()
        TemperatureCapabilityCacheTests.run()
        ModelConfigurationTests.run()
        RecordingCaptureTimingTests.run()
        RecordingTimerPreferenceTests.run()
        ShortcutCoreTests.run()
        SemanticVersionTests.run()
        LLMCooldownManagerTests.run()
        PostProcessingServiceTests.run()
        TranscriptionErrorPresentationCoreTests.run()
        TranscriptTextCoreTests.run()
        CredentialRecipeTests.run()
        JSONPreferencesTests.run()
        await TranscriptionServiceTests.run()
        await APIConfigurationDraftTests.run()
        print("FreeFlowTests passed")
    }
}
