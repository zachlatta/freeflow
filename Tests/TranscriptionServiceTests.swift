import Foundation

enum TranscriptionServiceTests {
    static func run() {
        testWhisperPromptDeduplicatesAndCapsTerms()
        testWhisperPromptIsNilWhenVocabularyIsEmpty()
        testWhisperPromptStopsBeforeCharacterLimit()
    }

    private static func testWhisperPromptStopsBeforeCharacterLimit() {
        let longTerm = String(repeating: "x", count: 50)
        TestSupport.expectEqual(
            TranscriptionService.whisperPrompt(fromVocabulary: "short, \(longTerm), tail", maxCharacters: 20),
            "short."
        )
        TestSupport.expectEqual(
            TranscriptionService.whisperPrompt(fromVocabulary: longTerm, maxCharacters: 20),
            nil
        )
    }

    private static func testWhisperPromptDeduplicatesAndCapsTerms() {
        TestSupport.expectEqual(
            TranscriptionService.whisperPrompt(fromVocabulary: "Alpha, beta;alpha\n Gamma , ,delta", maxTerms: 3),
            "Alpha, beta, Gamma."
        )
    }

    private static func testWhisperPromptIsNilWhenVocabularyIsEmpty() {
        TestSupport.expectEqual(TranscriptionService.whisperPrompt(fromVocabulary: nil), nil)
        TestSupport.expectEqual(TranscriptionService.whisperPrompt(fromVocabulary: " , ;\n"), nil)
    }
}
