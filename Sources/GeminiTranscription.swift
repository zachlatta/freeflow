import Foundation

/// Google's Gemini 3.5 Transcribe models do not speak the OpenAI-compatible
/// `/audio/transcriptions` protocol the Groq path uses. They run on the
/// Interactions API, authenticate with `x-goog-api-key` instead of a bearer
/// token, and take audio inline as base64 rather than as multipart form data.
///
/// The payoff is that smart mode folds cleanup into transcription: fillers and
/// false starts are dropped and punctuation is repaired inside the same request,
/// so a Gemini dictation needs one API round trip where Groq needs two.
enum GeminiTranscription {
    /// Interactions lives under the Gemini base path, not the Groq provider URL.
    static let defaultBaseURL = "https://generativelanguage.googleapis.com/v1beta"

    /// Smart mode cannot be combined with word timestamps or diarization, and
    /// FreeFlow needs neither — it wants clean prose to paste at the cursor.
    private static let smartMode = "smart"

    /// The API caps biasing terms; send the first ones and drop the rest rather
    /// than letting the whole request fail on an oversized vocabulary.
    private static let customVocabularyLimit = 1000

    /// True for models that transcribe over the Interactions API. The `-live`
    /// variant streams over a bidirectional socket instead, so it is excluded:
    /// routing it here would build a request the endpoint cannot answer.
    static func handlesModel(_ model: String) -> Bool {
        let normalized = model.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard normalized.hasPrefix("gemini-"), normalized.contains("transcribe") else { return false }
        return !normalized.hasSuffix("-live")
    }

    /// Gemini requests must reach Google even when the surrounding settings
    /// still hold a Groq provider URL, which is the default for every existing
    /// install. Keep an explicitly configured Gemini host, replace anything else.
    static func resolvedBaseURL(from configuredBaseURL: String) -> String {
        let trimmed = configuredBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let host = URLComponents(string: trimmed)?.host?.lowercased() else {
            return defaultBaseURL
        }
        let isGoogleHost = host == "generativelanguage.googleapis.com"
            || host.hasSuffix(".googleapis.com")
        return isGoogleHost ? trimmed : defaultBaseURL
    }

    static func endpoint(baseURL: URL) -> URL {
        baseURL.appendingPathComponent("interactions")
    }

    static func requestBody(
        model: String,
        audioData: Data,
        mimeType: String,
        customVocabulary: String
    ) throws -> Data {
        let terms = vocabularyTerms(from: customVocabulary)
        let request = InteractionRequest(
            model: model.trimmingCharacters(in: .whitespacesAndNewlines),
            input: [
                AudioInput(
                    type: "audio",
                    data: audioData.base64EncodedString(),
                    mimeType: mimeType
                )
            ],
            generationConfig: GenerationConfig(
                transcriptionConfig: TranscriptionConfig(
                    mode: Mode(type: smartMode),
                    // Language is deliberately omitted. Auto-detection handles
                    // the dictated language and code-switching, and pinning
                    // `language_codes` was observed to drop smart mode back to
                    // verbatim output — which would undo the cleanup pass.
                    customVocabulary: terms.isEmpty ? nil : terms
                )
            )
        )
        return try JSONEncoder().encode(request)
    }

    /// Splits the free-text vocabulary setting the same way the post-processing
    /// prompt does, so both stages bias on an identical list of terms.
    static func vocabularyTerms(from rawVocabulary: String) -> [String] {
        let terms = rawVocabulary
            .split(whereSeparator: { $0 == "\n" || $0 == "," || $0 == ";" })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var seen = Set<String>()
        let deduplicated = terms.filter { seen.insert($0.lowercased()).inserted }
        return Array(deduplicated.prefix(customVocabularyLimit))
    }

    /// Quota, validation and billing problems come back in a JSON envelope whose
    /// message is far more actionable than the bare status line, so prefer it.
    static func failureMessage(fromResponse data: Data, fallback: String) -> String {
        guard let message = errorMessage(fromResponse: data), !message.isEmpty else {
            return fallback
        }
        return message
    }

    /// Google is inconsistent here: parameter and quota failures arrive as a
    /// bare object, while auth failures arrive wrapped in an array. Read both,
    /// otherwise an invalid key degrades to a generic status line.
    private static func errorMessage(fromResponse data: Data) -> String? {
        let decoder = JSONDecoder()
        if let failure = try? decoder.decode(InteractionErrorEnvelope.self, from: data) {
            return failure.error.message
        }
        if let failures = try? decoder.decode([InteractionErrorEnvelope].self, from: data) {
            return failures.compactMap { $0.error.message }.first
        }
        return nil
    }

    /// Pulls the transcript out of the interaction's model output. Errors are
    /// reported in the body with HTTP 200 in some cases, so the payload is
    /// checked for a failure before its text is trusted.
    static func transcript(fromResponse data: Data) throws -> String {
        let decoder = JSONDecoder()

        if let message = errorMessage(fromResponse: data) {
            throw TranscriptionError.transcriptionFailed(message)
        }

        guard let response = try? decoder.decode(InteractionResponse.self, from: data) else {
            throw TranscriptionError.transcriptionFailed("Unreadable Gemini transcription response.")
        }

        if let status = response.status, status != "completed" {
            throw TranscriptionError.transcriptionFailed("Gemini transcription \(status).")
        }

        let transcript = (response.steps ?? [])
            .filter { $0.type == nil || $0.type == "model_output" }
            .flatMap { $0.content ?? [] }
            .compactMap { $0.text }
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !transcript.isEmpty else {
            throw TranscriptionError.transcriptionFailed("Gemini returned an empty transcript.")
        }
        return transcript
    }

    // MARK: - Wire format

    private struct InteractionRequest: Encodable {
        let model: String
        let input: [AudioInput]
        let generationConfig: GenerationConfig

        enum CodingKeys: String, CodingKey {
            case model
            case input
            case generationConfig = "generation_config"
        }
    }

    private struct AudioInput: Encodable {
        let type: String
        let data: String
        let mimeType: String

        enum CodingKeys: String, CodingKey {
            case type
            case data
            case mimeType = "mime_type"
        }
    }

    private struct GenerationConfig: Encodable {
        let transcriptionConfig: TranscriptionConfig

        enum CodingKeys: String, CodingKey {
            case transcriptionConfig = "transcription_config"
        }
    }

    private struct TranscriptionConfig: Encodable {
        let mode: Mode
        let customVocabulary: [String]?

        enum CodingKeys: String, CodingKey {
            case mode
            case customVocabulary = "custom_vocabulary"
        }
    }

    private struct Mode: Encodable {
        let type: String
    }

    private struct InteractionResponse: Decodable {
        let status: String?
        let steps: [Step]?
    }

    private struct Step: Decodable {
        let type: String?
        let content: [Content]?
    }

    private struct Content: Decodable {
        let text: String?
    }

    private struct InteractionErrorEnvelope: Decodable {
        let error: InteractionError
    }

    private struct InteractionError: Decodable {
        let message: String?
    }
}
