import Foundation

private actor ValidationRequestRecorder {
    private(set) var requests: [URLRequest] = []

    func append(_ request: URLRequest) {
        requests.append(request)
    }
}

enum TranscriptionServiceTests {
    @MainActor
    static func run() async {
        let recorder = ValidationRequestRecorder()
        let savedCredential = "saved-main-credential"
        let savedBaseURL = "https://saved-provider.invalid/v1"
        let savedTranscriptionCredential = "saved-transcription-credential"
        let savedTranscriptionURL = "https://saved-transcription.invalid/v1"
        let draftTranscriptionCredential = "draft-transcription-credential"
        let draftTranscriptionURL = "https://draft-transcription.invalid/v1"
        var persistedCredential = savedCredential
        var persistedBaseURL = savedBaseURL
        var persistedTranscriptionCredential = savedTranscriptionCredential
        var persistedTranscriptionURL = savedTranscriptionURL
        var applyCount = 0
        let valid = await APIConfigurationSaveFlow.validateAndApply(
            apiKey: savedCredential,
            baseURL: savedBaseURL,
            transcriptionAPIURL: draftTranscriptionURL,
            transcriptionAPIKey: draftTranscriptionCredential,
            validator: { key, baseURL in
                await TranscriptionService.validateAPIKey(key, baseURL: baseURL) { request in
                    await recorder.append(request)
                    let status = request.url?.host == "saved-provider.invalid" ? 200 : 401
                    let response = HTTPURLResponse(
                        url: request.url!,
                        statusCode: status,
                        httpVersion: nil,
                        headerFields: nil
                    )!
                    return (Data(), response)
                }
            }
        ) { configuration in
            applyCount += 1
            persistedCredential = configuration.apiKey
            persistedBaseURL = configuration.baseURL
            persistedTranscriptionCredential = configuration.transcriptionAPIKey
            persistedTranscriptionURL = configuration.transcriptionAPIURL
        }
        let requests = await recorder.requests
        TestSupport.expect(!valid && requests.count == 2, "Main and effective transcription pairs are validated before persistence")
        let draftRequest = requests.first { $0.url?.host == "draft-transcription.invalid" }
        TestSupport.expect(draftRequest?.url?.absoluteString == "https://draft-transcription.invalid/v1/models", "Draft transcription endpoint is validated before it is saved")
        let authorization = draftRequest?.value(forHTTPHeaderField: "Authorization")
        TestSupport.expect(authorization == "Bearer \(draftTranscriptionCredential)", "Draft transcription endpoint receives only its paired draft credential")
        TestSupport.expect(authorization != "Bearer \(savedTranscriptionCredential)", "Saved transcription credential never reaches the draft endpoint")
        TestSupport.expect(applyCount == 0, "Failed validation does not cross the shared draft-to-persisted boundary")
        TestSupport.expect(persistedCredential == savedCredential && persistedBaseURL == savedBaseURL, "Failed transcription validation preserves the existing main API configuration")
        TestSupport.expect(persistedTranscriptionCredential == savedTranscriptionCredential && persistedTranscriptionURL == savedTranscriptionURL, "Failed transcription validation preserves the existing transcription override pair")

        var fallbackApplied: ValidatedAPIConfiguration?
        let fallbackValid = await APIConfigurationSaveFlow.validateAndApply(
            apiKey: savedCredential,
            baseURL: savedBaseURL,
            transcriptionAPIURL: "",
            transcriptionAPIKey: "",
            validator: { _, _ in true }
        ) { fallbackApplied = $0 }
        TestSupport.expect(fallbackValid && fallbackApplied?.transcriptionAPIURL.isEmpty == true && fallbackApplied?.transcriptionAPIKey.isEmpty == true, "Empty transcription overrides preserve fallback semantics without a partial override")

        testVocabularyPromptDeduplicatesInOrder()
        testVocabularyPromptIsNilWhenVocabularyIsEmpty()
        testVocabularyPromptStopsBeforeByteLimit()
        testVocabularyPromptBoundsNonLatinTermsByBytes()
        testPromptIsOnlyBuiltForModelsThatSupportIt()
        testMultipartBodyIncludesPromptForSupportedModel()
        testMultipartBodyOmitsPromptForUnsupportedModel()
        testMultipartBodyOmitsPromptForEmptyVocabulary()
    }

    // Synthetic vocabulary only; these strings are invented for tests.
    private static let syntheticVocabulary = "Zephyrion, Quillbrook;zephyrion\n Marlowe Vex , ,Tandrel"

    private static func testVocabularyPromptDeduplicatesInOrder() {
        TestSupport.expectEqual(
            TranscriptionService.vocabularyPrompt(fromVocabulary: syntheticVocabulary),
            "Zephyrion, Quillbrook, Marlowe Vex, Tandrel."
        )
    }

    private static func testVocabularyPromptIsNilWhenVocabularyIsEmpty() {
        TestSupport.expectEqual(TranscriptionService.vocabularyPrompt(fromVocabulary: nil), nil)
        TestSupport.expectEqual(TranscriptionService.vocabularyPrompt(fromVocabulary: ""), nil)
        TestSupport.expectEqual(TranscriptionService.vocabularyPrompt(fromVocabulary: " , ;\n"), nil)
    }

    private static func testVocabularyPromptStopsBeforeByteLimit() {
        let longTerm = String(repeating: "x", count: 50)
        // "short, " + 50 bytes exceeds 20; later terms are dropped, not skipped over.
        TestSupport.expectEqual(
            TranscriptionService.vocabularyPrompt(fromVocabulary: "short, \(longTerm), tail", maxUTF8Bytes: 20),
            "short."
        )
        TestSupport.expectEqual(
            TranscriptionService.vocabularyPrompt(fromVocabulary: longTerm, maxUTF8Bytes: 20),
            nil
        )
        // Exactly at the limit is allowed: "abcd." is 5 bytes.
        TestSupport.expectEqual(TranscriptionService.vocabularyPrompt(fromVocabulary: "abcd", maxUTF8Bytes: 5), "abcd.")
        TestSupport.expectEqual(TranscriptionService.vocabularyPrompt(fromVocabulary: "abcde", maxUTF8Bytes: 5), nil)

        let manyTerms = (1...200).map { "Term\($0)" }.joined(separator: ", ")
        let prompt = TranscriptionService.vocabularyPrompt(fromVocabulary: manyTerms) ?? ""
        TestSupport.expect(!prompt.isEmpty, "A long vocabulary still yields a prompt")
        TestSupport.expect(prompt.utf8.count <= TranscriptionService.maxPromptUTF8Bytes, "Default prompt stays within the 224-byte token bound")
        TestSupport.expect(prompt.hasPrefix("Term1, Term2, "), "Earlier vocabulary terms take priority")
    }

    private static func testVocabularyPromptBoundsNonLatinTermsByBytes() {
        // Each CJK character is 3 UTF-8 bytes, so 80 characters is 240 bytes.
        let cjkTerm = String(repeating: "\u{6F22}", count: 80)
        TestSupport.expectEqual(TranscriptionService.vocabularyPrompt(fromVocabulary: cjkTerm), nil)

        let cjkTerms = (0..<40).map { _ in String(repeating: "\u{5B57}", count: 2) }
            .enumerated().map { "\($1)\($0)" }.joined(separator: "\n")
        let prompt = TranscriptionService.vocabularyPrompt(fromVocabulary: cjkTerms) ?? ""
        TestSupport.expect(!prompt.isEmpty, "Non-Latin vocabulary yields a prompt")
        TestSupport.expect(prompt.utf8.count <= TranscriptionService.maxPromptUTF8Bytes, "Non-Latin prompt is bounded by bytes, not characters")
        TestSupport.expect(prompt.count < cjkTerms.count, "Non-Latin vocabulary over the limit is truncated")
    }

    private static func testPromptIsOnlyBuiltForModelsThatSupportIt() {
        for model in ["whisper-1", "gpt-4o-transcribe", "gpt-4o-mini-transcribe", "whisper-large-v3", " Whisper-Large-V3-Turbo "] {
            TestSupport.expectEqual(
                TranscriptionService.transcriptionPrompt(forModel: model, customVocabulary: "Zephyrion"),
                "Zephyrion."
            )
        }
        for model in ["", "custom-asr-model", "gpt-4o-transcribe-diarize", "distil-whisper-large-v3-en", "nova-3"] {
            TestSupport.expectEqual(
                TranscriptionService.transcriptionPrompt(forModel: model, customVocabulary: "Zephyrion"),
                nil
            )
        }
        TestSupport.expectEqual(TranscriptionService.transcriptionPrompt(forModel: "whisper-1", customVocabulary: "  "), nil)
    }

    private static func multipartBody(model: String, vocabulary: String?) -> String {
        let body = TranscriptionService.makeMultipartBody(
            audioData: Data([0x00, 0x01, 0x02]),
            fileName: "synthetic.wav",
            model: model,
            responseFormat: TranscriptionService.responseFormat(forModel: model),
            language: "en",
            prompt: TranscriptionService.transcriptionPrompt(forModel: model, customVocabulary: vocabulary),
            boundary: "TEST-BOUNDARY"
        )
        return String(decoding: body, as: UTF8.self)
    }

    private static func testMultipartBodyIncludesPromptForSupportedModel() {
        let body = multipartBody(model: "whisper-large-v3", vocabulary: "Zephyrion, Quillbrook")
        TestSupport.expect(
            body.contains("--TEST-BOUNDARY\r\nContent-Disposition: form-data; name=\"prompt\"\r\n\r\nZephyrion, Quillbrook.\r\n"),
            "Supported model receives the vocabulary prompt field"
        )
        TestSupport.expect(body.contains("name=\"language\"\r\n\r\nen\r\n"), "Language field is preserved")
        TestSupport.expect(body.hasSuffix("--TEST-BOUNDARY--\r\n"), "Multipart body is terminated")
    }

    private static func testMultipartBodyOmitsPromptForUnsupportedModel() {
        let body = multipartBody(model: "custom-asr-model", vocabulary: "Zephyrion, Quillbrook")
        TestSupport.expect(!body.contains("name=\"prompt\""), "Unsupported model never receives a prompt field")
        TestSupport.expect(!body.contains("Zephyrion"), "Vocabulary is not sent to unsupported models")
        TestSupport.expect(body.contains("name=\"model\"\r\n\r\ncustom-asr-model\r\n"), "Model field is still sent")
    }

    private static func testMultipartBodyOmitsPromptForEmptyVocabulary() {
        for vocabulary in [nil, "", " ;\n,"] as [String?] {
            let body = multipartBody(model: "whisper-1", vocabulary: vocabulary)
            TestSupport.expect(!body.contains("name=\"prompt\""), "Empty vocabulary sends no prompt field")
        }
    }
}
