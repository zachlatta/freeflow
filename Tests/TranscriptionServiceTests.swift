import Foundation

@main
struct TranscriptionServiceTests {
    static func main() throws {
        let service = try TranscriptionService(apiKey: "test-key")

        // Silent audio: whisper's subtitle-credit hallucinations get dropped in any language.
        for text in [
            "Undertekster av Ai-Media",
            "Untertitel von ZDF, 2021",
            "Sous-titres réalisés para la communauté d'Amara.org",
            "Subtítulos realizados por la comunidad de Amara.org",
            "字幕by索兰娅",
            "Thank you.",
        ] {
            assert(service.isHallucination(text: text, json: response(text, noSpeechProb: 0.9)),
                   "expected '\(text)' to be filtered on silent audio")
        }

        // Real speech: same phrases survive when whisper is confident there is speech.
        for text in ["Undertekster av Ai-Media", "Thank you."] {
            assert(!service.isHallucination(text: text, json: response(text, noSpeechProb: 0.01)),
                   "expected '\(text)' to survive when no_speech_prob is low")
        }

        // A real sentence that merely mentions subtitles is not a credit line.
        let sentence = "Can you add subtitles by tomorrow so the team can review the launch video?"
        assert(!service.isHallucination(text: sentence, json: response(sentence, noSpeechProb: 0.9)),
               "expected a long sentence mentioning subtitles to survive")

        print("TranscriptionServiceTests passed")
    }

    private static func response(_ text: String, noSpeechProb: Double) -> [String: Any] {
        ["text": text, "segments": [["no_speech_prob": noSpeechProb]]]
    }
}
