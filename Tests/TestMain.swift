import Foundation

@main
struct FreeFlowTests {
    static func main() async {
        AppContextServiceTests.run()
        await LLMAPITransportTests.run()
        await TemperatureCapabilityCacheTests.run()
        ModelConfigurationTests.run()
        RecordingCaptureTimingTests.run()
        RecordingTimerPreferenceTests.run()
        ShortcutCoreTests.run()
        SemanticVersionTests.run()
        LLMCooldownManagerTests.run()
        TranscriptionErrorPresentationCoreTests.run()
        TranscriptTextCoreTests.run()
        print("FreeFlowTests passed")
    }
}
