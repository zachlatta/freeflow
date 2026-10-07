import Foundation

enum GeminiTranscriptionTests {
    static func run() {
        testOnlyInteractionsCapableModelsAreRouted()
        testGroqProviderURLIsReplacedWithGoogleHost()
        testRequestAsksForSmartModeWithInlineAudio()
        testVocabularyIsSplitDeduplicatedAndCapped()
        testTranscriptIsReadFromModelOutput()
        testFailuresSurfaceGoogleMessage()
    }

    private static func testOnlyInteractionsCapableModelsAreRouted() {
        TestSupport.expect(GeminiTranscription.handlesModel("gemini-3.5-transcribe"), "Should route the transcribe model")
        TestSupport.expect(GeminiTranscription.handlesModel(" GEMINI-3.5-TRANSCRIBE "), "Should tolerate spacing and case")

        // The live model streams over a socket, so it must not be routed here.
        TestSupport.expect(!GeminiTranscription.handlesModel("gemini-3.5-transcribe-live"), "Should not route the live model")
        TestSupport.expect(!GeminiTranscription.handlesModel("whisper-large-v3"), "Should leave Whisper on the Groq path")
        TestSupport.expect(!GeminiTranscription.handlesModel("gemini-3.5-flash"), "Should not route non-transcribe Gemini models")
    }

    private static func testGroqProviderURLIsReplacedWithGoogleHost() {
        TestSupport.expectEqual(
            GeminiTranscription.resolvedBaseURL(from: "https://api.groq.com/openai/v1"),
            GeminiTranscription.defaultBaseURL
        )
        TestSupport.expectEqual(GeminiTranscription.resolvedBaseURL(from: ""), GeminiTranscription.defaultBaseURL)
        TestSupport.expectEqual(
            GeminiTranscription.resolvedBaseURL(from: "https://generativelanguage.googleapis.com/v1beta"),
            "https://generativelanguage.googleapis.com/v1beta"
        )

        TestSupport.expectEqual(
            GeminiTranscription.endpoint(baseURL: URL(string: "https://generativelanguage.googleapis.com/v1beta")!)
                .absoluteString,
            "https://generativelanguage.googleapis.com/v1beta/interactions"
        )
    }

    private static func testRequestAsksForSmartModeWithInlineAudio() {
        let audio = Data([0x01, 0x02, 0x03])
        let body = try! GeminiTranscription.requestBody(
            model: "gemini-3.5-transcribe",
            audioData: audio,
            mimeType: "audio/wav",
            customVocabulary: "FreeFlow, Groq"
        )
        let json = try! JSONSerialization.jsonObject(with: body) as! [String: Any]

        TestSupport.expectEqual(json["model"] as? String, "gemini-3.5-transcribe")

        let input = (json["input"] as? [[String: Any]]) ?? []
        TestSupport.expectEqual(input.count, 1)
        TestSupport.expectEqual(input.first?["type"] as? String, "audio")
        TestSupport.expectEqual(input.first?["mime_type"] as? String, "audio/wav")
        TestSupport.expectEqual(input.first?["data"] as? String, audio.base64EncodedString())

        let config = ((json["generation_config"] as? [String: Any])?["transcription_config"]) as? [String: Any]
        TestSupport.expectEqual((config?["mode"] as? [String: Any])?["type"] as? String, "smart")
        TestSupport.expectEqual(config?["custom_vocabulary"] as? [String], ["FreeFlow", "Groq"])

        // Pinning a language was observed to drop smart mode back to verbatim
        // output, which would silently undo the cleanup this model is used for.
        TestSupport.expect(config?["language_codes"] == nil, "Should let Gemini auto-detect the language")

        // Smart mode rejects these, so they must never be sent.
        TestSupport.expect((config?["mode"] as? [String: Any])?["timestamp_granularities"] == nil, "No timestamps in smart mode")
        TestSupport.expect((config?["mode"] as? [String: Any])?["diarization_mode"] == nil, "No diarization in smart mode")
    }

    private static func testVocabularyIsSplitDeduplicatedAndCapped() {
        TestSupport.expectEqual(
            GeminiTranscription.vocabularyTerms(from: "Kubernetes\nBigQuery; Groq , Groq"),
            ["Kubernetes", "BigQuery", "Groq"]
        )
        TestSupport.expectEqual(GeminiTranscription.vocabularyTerms(from: "  ,  ;  \n "), [])

        let oversized = (1...1200).map { "term\($0)" }.joined(separator: ",")
        TestSupport.expectEqual(GeminiTranscription.vocabularyTerms(from: oversized).count, 1000)

        // An empty vocabulary must be omitted rather than sent as an empty list.
        let body = try! GeminiTranscription.requestBody(
            model: "gemini-3.5-transcribe",
            audioData: Data([0x00]),
            mimeType: "audio/wav",
            customVocabulary: ""
        )
        let json = try! JSONSerialization.jsonObject(with: body) as! [String: Any]
        let config = ((json["generation_config"] as? [String: Any])?["transcription_config"]) as? [String: Any]
        TestSupport.expect(config?["custom_vocabulary"] == nil, "Should omit an empty vocabulary")
    }

    private static func testTranscriptIsReadFromModelOutput() {
        let payload = """
        {"status":"completed","steps":[{"type":"model_output","content":[{"text":"  Hello there. ","type":"text"}]}]}
        """
        TestSupport.expectEqual(try! GeminiTranscription.transcript(fromResponse: Data(payload.utf8)), "Hello there.")

        let empty = """
        {"status":"completed","steps":[{"type":"model_output","content":[{"text":"   ","type":"text"}]}]}
        """
        expectThrows(Data(empty.utf8), "Empty transcripts should be rejected")

        let unfinished = """
        {"status":"failed","steps":[{"type":"model_output","content":[{"text":"partial","type":"text"}]}]}
        """
        expectThrows(Data(unfinished.utf8), "Non-completed interactions should be rejected")

        expectThrows(Data("not json".utf8), "Unreadable payloads should be rejected")
    }

    private static func testFailuresSurfaceGoogleMessage() {
        let quota = """
        {"error":{"code":"resource_exhausted","message":"You exceeded your current quota."}}
        """
        TestSupport.expectEqual(
            GeminiTranscription.failureMessage(fromResponse: Data(quota.utf8), fallback: "HTTP 429"),
            "You exceeded your current quota."
        )
        TestSupport.expectEqual(
            GeminiTranscription.failureMessage(fromResponse: Data("not json".utf8), fallback: "HTTP 500"),
            "HTTP 500"
        )

        // Auth failures arrive wrapped in an array rather than as a bare object.
        let badKey = "[{\"error\":{\"code\":400,\"message\":\"API key not valid. Please pass a valid API key.\",\"status\":\"INVALID_ARGUMENT\"}}]"
        TestSupport.expectEqual(
            GeminiTranscription.failureMessage(fromResponse: Data(badKey.utf8), fallback: "HTTP 400"),
            "API key not valid. Please pass a valid API key."
        )

        // An error body carrying HTTP 200 must not be mistaken for a transcript.
        expectThrows(Data(quota.utf8), "Error envelopes should not parse as transcripts")
    }

    private static func expectThrows(_ data: Data, _ message: String) {
        do {
            _ = try GeminiTranscription.transcript(fromResponse: data)
            TestSupport.expect(false, message)
        } catch {
        }
    }
}
