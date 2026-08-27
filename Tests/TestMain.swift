import Foundation

@main
struct FreeFlowTests {
    static func main() {
        AppContextServiceTests.run()
        GeminiLiveTranscriptionTests.run()
        GeminiTranscriptionTests.run()
        ModelConfigurationTests.run()
        ShortcutCoreTests.run()
        SemanticVersionTests.run()
        LLMCooldownManagerTests.run()
        TranscriptTextCoreTests.run()
        print("FreeFlowTests passed")
    }
}
