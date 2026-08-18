import Foundation

@main
struct FreeFlowTests {
    static func main() {
        AppContextServiceTests.run()
        ModelConfigurationTests.run()
        ShortcutCoreTests.run()
        SemanticVersionTests.run()
        LLMCooldownManagerTests.run()
        TranscriptTextCoreTests.run()
        print("FreeFlowTests passed")
    }
}
