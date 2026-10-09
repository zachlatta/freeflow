import Foundation

@main
struct FreeFlowTests {
    static func main() {
        AppContextServiceTests.run()
        ModelConfigurationTests.run()
        RecordingCaptureTimingTests.run()
        RecordingTimerPreferenceTests.run()
        ShortcutCoreTests.run()
        SemanticVersionTests.run()
        LLMCooldownManagerTests.run()
        TranscriptionErrorPresentationCoreTests.run()
        TranscriptTextCoreTests.run()
        RecordingOverlayPlacementTests.run()
        CaretAnchorReaderTests.run()
        print("FreeFlowTests passed")
    }
}
