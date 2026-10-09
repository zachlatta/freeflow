import Foundation

@main
struct FreeFlowTests {
    static func main() async throws {
        AppContextServiceTests.run()
        ModelConfigurationTests.run()
        RecordingCaptureTimingTests.run()
        RecordingTimerPreferenceTests.run()
        ShortcutCoreTests.run()
        SemanticVersionTests.run()
        LLMCooldownManagerTests.run()
        TranscriptionErrorPresentationCoreTests.run()
        TranscriptTextCoreTests.run()
        TranscriptionConfigurationTests.run()
        try await TranscriptionServiceTests.run()
        try await ElevenLabsRealtimeTranscriptionTests.run()
        try await TranscriptionFallbackTests.run()
        try await TranscriptionPipelineTests.run()
        print("FreeFlowTests passed")
    }
}
