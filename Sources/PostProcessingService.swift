import Foundation

enum PostProcessingError: LocalizedError {
    case requestFailed(Int, String)
    case invalidResponse(String)

    var errorDescription: String? {
        switch self {
        case .requestFailed(let statusCode, let details):
            "Post-processing failed with status \(statusCode): \(details)"
        case .invalidResponse(let details):
            "Invalid post-processing response: \(details)"
        }
    }
}

struct PostProcessingResult {
    let transcript: String
    let prompt: String
}

final class PostProcessingService {
    private let apiKey: String
    private let baseURL = "https://api.groq.com/openai/v1"
    private let defaultModel = "meta-llama/llama-4-scout-17b-16e-instruct"

    init(apiKey: String) {
        self.apiKey = apiKey
    }

    func postProcess(
        transcript: String,
        context: AppContext,
        customVocabulary: String
    ) async throws -> PostProcessingResult {
        let vocabularyTerms = mergedVocabularyTerms(rawVocabulary: customVocabulary)
        return try await process(
            transcript: transcript,
            contextSummary: context.contextSummary,
            model: defaultModel,
            customVocabulary: vocabularyTerms
        )
    }

    private func process(
        transcript: String,
        contextSummary: String,
        model: String,
        customVocabulary: [String]
    ) async throws -> PostProcessingResult {
        var request = URLRequest(url: URL(string: "\(baseURL)/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let normalizedVocabulary = normalizedVocabularyText(customVocabulary)
        let vocabularyPrompt = if !normalizedVocabulary.isEmpty {
            """
The following vocabulary must be treated as high-priority terms while rewriting.
Use these spellings exactly in the output when relevant:
\(normalizedVocabulary)
"""
        } else {
            ""
        }

        var systemPrompt = """
You are a dictation post-processor. You receive raw speech-to-text output and return clean text ready to be typed into an application.

Your job:
- Remove filler words (um, uh, you know, like) unless they carry meaning.
- Fix spelling, grammar, and punctuation errors.
- When the transcript already contains a word that is a close misspelling of a name or term from the context or custom vocabulary, correct the spelling. Never insert names or terms from context that the speaker did not say.
- Preserve the speaker's intent, tone, and meaning exactly.

Output rules:
- Return ONLY the cleaned transcript text, nothing else.
- If the transcription is empty or contains no meaningful speech, return exactly: [EMPTY]
- Do not add words, names, or content that are not in the transcription. The context is only for correcting spelling of words already spoken.
- Do not change the meaning of what was said.
"""
        if !vocabularyPrompt.isEmpty {
            systemPrompt += "\n\n" + vocabularyPrompt
        }

        let userMessage = """
Clean up this transcription. Only use context to fix spelling of words already present.

Transcription:
\(transcript)

Context (for spelling reference only):
\(contextSummary)
"""

        let promptForDisplay = """
Model: \(model)

[System]
\(systemPrompt)

[User]
\(userMessage)
"""

        let payload: [String: Any] = [
            "model": model,
            "temperature": 0.0,
            "messages": [
                [
                    "role": "system",
                    "content": systemPrompt
                ],
                [
                    "role": "user",
                    "content": userMessage
                ]
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw PostProcessingError.invalidResponse("No HTTP response")
        }

        guard httpResponse.statusCode == 200 else {
            let message = String(data: data, encoding: .utf8) ?? ""
            throw PostProcessingError.requestFailed(httpResponse.statusCode, message)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw PostProcessingError.invalidResponse("Missing choices[0].message.content")
        }

        return PostProcessingResult(
            transcript: sanitizePostProcessedTranscript(content),
            prompt: promptForDisplay
        )
    }

    private func sanitizePostProcessedTranscript(_ value: String) -> String {
        var result = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !result.isEmpty else { return "" }

        // Strip outer quotes if the LLM wrapped the entire response
        if result.hasPrefix("\"") && result.hasSuffix("\"") && result.count > 1 {
            result.removeFirst()
            result.removeLast()
            result = result.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // Treat the sentinel value as empty
        if result == "[EMPTY]" {
            return ""
        }

        return result
    }

    private func mergedVocabularyTerms(rawVocabulary: String) -> [String] {
        let terms = rawVocabulary
            .split(whereSeparator: { $0 == "\n" || $0 == "," || $0 == ";" })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var seen = Set<String>()
        return terms.filter { seen.insert($0.lowercased()).inserted }
    }

    private func normalizedVocabularyText(_ vocabularyTerms: [String]) -> String {
        let terms = vocabularyTerms
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !terms.isEmpty else { return "" }
        return terms.joined(separator: ", ")
    }
}
