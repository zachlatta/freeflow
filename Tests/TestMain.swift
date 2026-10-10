import Foundation

@main
struct FreeFlowTests {
    static func main() {
        AppContextServiceTests.run()
        ModelConfigurationTests.run()
        ProviderPresetTests.run()
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
