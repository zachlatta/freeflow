import Foundation

enum GeminiLiveTranscriptionTests {
    static func run() {
        testOnlyLiveModelsAreRouted()
        testSocketURLIsDerivedFromAnyGeminiBase()
        testSetupAsksForSmartModeAndVocabulary()
        testAudioFramesDeclareTheRealSampleRate()
        testServerFramesAreClassified()
    }

    private static func testOnlyLiveModelsAreRouted() {
        TestSupport.expect(GeminiLiveTranscription.handlesModel("gemini-3.5-transcribe-live"), "Should route the live model")
        TestSupport.expect(GeminiLiveTranscription.handlesModel(" GEMINI-3.5-TRANSCRIBE-LIVE "), "Should tolerate spacing and case")

        // The batch model goes to the Interactions API instead.
        TestSupport.expect(!GeminiLiveTranscription.handlesModel("gemini-3.5-transcribe"), "Should not route the batch model")
        TestSupport.expect(!GeminiLiveTranscription.handlesModel("gpt-4o-transcribe"), "Should leave other providers alone")

        // The two routers must never both claim a model.
        for model in ["gemini-3.5-transcribe", "gemini-3.5-transcribe-live", "whisper-large-v3"] {
            TestSupport.expect(
                !(GeminiTranscription.handlesModel(model) && GeminiLiveTranscription.handlesModel(model)),
                "Routers must not overlap for \(model)"
            )
        }
    }

    private static func testSocketURLIsDerivedFromAnyGeminiBase() {
        let expected = "wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent"

        // An https REST base upgrades to wss and picks up the service path.
        TestSupport.expectEqual(
            GeminiLiveTranscription.socketURL(baseURL: "https://generativelanguage.googleapis.com/v1beta")?.absoluteString,
            expected
        )
        TestSupport.expectEqual(GeminiLiveTranscription.socketURL(baseURL: "")?.absoluteString, expected)

        // A Groq provider URL cannot serve this protocol, so fall back.
        TestSupport.expectEqual(
            GeminiLiveTranscription.socketURL(baseURL: "https://api.groq.com/openai/v1")?.absoluteString,
            expected
        )

        // Any credentials already on the base URL must not survive.
        TestSupport.expect(
            GeminiLiveTranscription.socketURL(baseURL: "https://generativelanguage.googleapis.com/v1beta?key=secret")?
                .absoluteString.contains("secret") == false,
            "Query parameters must be dropped"
        )
    }

    private static func testSetupAsksForSmartModeAndVocabulary() {
        let setup = try! GeminiLiveTranscription.setupMessage(
            model: "gemini-3.5-transcribe-live",
            customVocabulary: "FreeFlow, Groq, Groq"
        )
        let json = try! JSONSerialization.jsonObject(with: Data(setup.utf8)) as! [String: Any]
        let body = json["setup"] as! [String: Any]

        // The Live API namespaces models under models/.
        TestSupport.expectEqual(body["model"] as? String, "models/gemini-3.5-transcribe-live")
        TestSupport.expectEqual(
            (body["generationConfig"] as? [String: Any])?["responseModalities"] as? [String],
            ["TEXT"]
        )

        let transcription = body["inputAudioTranscription"] as? [String: Any]
        // Smart mode is upper case here, unlike the Interactions API.
        TestSupport.expectEqual(transcription?["mode"] as? String, "SMART")
        TestSupport.expectEqual(transcription?["custom_vocabulary"] as? [String], ["FreeFlow", "Groq"])

        // Pinning a language drops the model out of smart mode.
        TestSupport.expect(transcription?["language_codes"] == nil, "Should let Gemini auto-detect the language")

        let bare = try! GeminiLiveTranscription.setupMessage(model: "models/gemini-3.5-transcribe-live", customVocabulary: "")
        let bareBody = (try! JSONSerialization.jsonObject(with: Data(bare.utf8)) as! [String: Any])["setup"] as! [String: Any]
        TestSupport.expectEqual(bareBody["model"] as? String, "models/gemini-3.5-transcribe-live")
        TestSupport.expect(
            (bareBody["inputAudioTranscription"] as? [String: Any])?["custom_vocabulary"] == nil,
            "Should omit an empty vocabulary"
        )
    }

    private static func testAudioFramesDeclareTheRealSampleRate() {
        let pcm = Data([0x10, 0x20, 0x30, 0x40])
        let frame = try! GeminiLiveTranscription.audioMessage(pcm16: pcm, sampleRate: 24_000)
        let json = try! JSONSerialization.jsonObject(with: Data(frame.utf8)) as! [String: Any]
        let audio = ((json["realtimeInput"] as? [String: Any])?["audio"]) as? [String: Any]

        // The recorder streams 24 kHz; the frame must say so rather than
        // claiming the documented 16 kHz.
        TestSupport.expectEqual(audio?["mimeType"] as? String, "audio/pcm;rate=24000")
        TestSupport.expectEqual(audio?["data"] as? String, pcm.base64EncodedString())

        let end = try! GeminiLiveTranscription.audioStreamEndMessage()
        let endJSON = try! JSONSerialization.jsonObject(with: Data(end.utf8)) as! [String: Any]
        TestSupport.expectEqual(
            (endJSON["realtimeInput"] as? [String: Any])?["audioStreamEnd"] as? Bool,
            true
        )
    }

    private static func testServerFramesAreClassified() {
        let q = "\""
        func frame(_ body: String) -> GeminiLiveTranscription.ServerFrame {
            GeminiLiveTranscription.parseServerFrame(body)
        }

        let partial = frame("{\(q)serverContent\(q):{\(q)inputTranscription\(q):{\(q)text\(q):\(q)Привет\(q)}}}")
        TestSupport.expectEqual(partial.transcript, "Привет")
        TestSupport.expect(!partial.isComplete, "A partial frame is not complete")

        let done = frame("{\(q)serverContent\(q):{\(q)turnComplete\(q):true}}")
        TestSupport.expect(done.isComplete, "turnComplete ends the turn")

        let generated = frame("{\(q)serverContent\(q):{\(q)generationComplete\(q):true}}")
        TestSupport.expect(generated.isComplete, "generationComplete ends the turn")

        let ready = frame("{\(q)setupComplete\(q):{}}")
        TestSupport.expect(ready.isSetupComplete, "setupComplete is recognised")
        TestSupport.expect(!ready.isComplete, "setupComplete does not end the turn")

        let failure = frame("{\(q)error\(q):{\(q)message\(q):\(q)Quota exceeded\(q)}}")
        TestSupport.expectEqual(failure.errorMessage, "Quota exceeded")
        TestSupport.expect(failure.isComplete, "An error ends the turn")

        // Garbage must not crash or be mistaken for a transcript.
        let junk = frame("not json")
        TestSupport.expect(junk.transcript == nil && !junk.isComplete && junk.errorMessage == nil, "Junk is ignored")
    }
}
