import Foundation

@main
struct FreeFlowTests {
    static func main() async {
        await AppContextServiceTests.run()
        await ContextCaptureTests.run()
        await LLMAPITransportTests.run()
        TemperatureCapabilityCacheTests.run()
        ModelConfigurationTests.run()
        RecordingCaptureTimingTests.run()
        RecordingTimerPreferenceTests.run()
        ShortcutCleanupPreferenceTests.run()
        OriginalFieldInsertionPreferenceTests.run()
        ShortcutCoreTests.run()
        SemanticVersionTests.run()
        LLMCooldownManagerTests.run()
        PostProcessingServiceTests.run()
        TranscriptionErrorPresentationCoreTests.run()
        TranscriptTextCoreTests.run()
        AppTextInsertionCoreTests.run()
        AppTextInsertionDispatchTests.run()
        await TranscriptionServiceTests.run()
        await APIConfigurationDraftTests.run()
        print("FreeFlowTests passed")
    }
}
