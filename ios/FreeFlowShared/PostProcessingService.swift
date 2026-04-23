import Foundation

enum PostProcessingError: LocalizedError {
    case requestFailed(Int, String)
    case invalidResponse(String)
    case invalidInput(String)
    case emptyOutput
    case requestTimedOut(TimeInterval)

    var errorDescription: String? {
        switch self {
        case .requestFailed(let statusCode, let details):
            "Post-processing failed with status \(statusCode): \(details)"
        case .invalidResponse(let details):
            "Invalid post-processing response: \(details)"
        case .invalidInput(let details):
            "Invalid post-processing input: \(details)"
        case .emptyOutput:
            "Post-processing returned empty output"
        case .requestTimedOut(let seconds):
            "Post-processing timed out after \(Int(seconds))s"
        }
    }
}

struct PostProcessingResult {
    let transcript: String
    let prompt: String
    let modelUsed: String
}

final class PostProcessingService {
    private let apiKey: String
    private let baseURL: String
    private let preferredModel: String
    private let preferredFallbackModel: String
    private let defaultModel = "openai/gpt-oss-20b"
    private let defaultFallbackModel = "meta-llama/llama-4-scout-17b-16e-instruct"
    private let defaultModelReasoningEffort = "low"
    private let postProcessingMaxCompletionTokens = 4096
    private let postProcessingTimeoutSeconds: TimeInterval = 20

    init(
        apiKey: String,
        baseURL: String = "https://api.groq.com/openai/v1",
        preferredModel: String = "",
        preferredFallbackModel: String = ""
    ) {
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.preferredModel = preferredModel.trimmingCharacters(in: .whitespacesAndNewlines)
        self.preferredFallbackModel = preferredFallbackModel.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func postProcess(
        transcript: String,
        customVocabulary: String,
        customSystemPrompt: String = ""
    ) async throws -> PostProcessingResult {
        let vocabularyTerms = mergedVocabularyTerms(rawVocabulary: customVocabulary)
        let timeoutSeconds = postProcessingTimeoutSeconds
        return try await withThrowingTaskGroup(of: PostProcessingResult.self) { group in
            group.addTask { [weak self] in
                guard let self else {
                    throw PostProcessingError.invalidResponse("Post-processing service deallocated")
                }
                return try await self.processWithFallback(
                    transcript: transcript,
                    customVocabulary: vocabularyTerms,
                    customSystemPrompt: customSystemPrompt
                )
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeoutSeconds * 1_000_000_000))
                throw PostProcessingError.requestTimedOut(timeoutSeconds)
            }
            do {
                guard let result = try await group.next() else {
                    throw PostProcessingError.invalidResponse("No post-processing result")
                }
                group.cancelAll()
                return result
            } catch {
                group.cancelAll()
                throw error
            }
        }
    }

    private func processWithFallback(
        transcript: String,
        customVocabulary: [String],
        customSystemPrompt: String
    ) async throws -> PostProcessingResult {
        let primaryModel = resolvedPrimaryModel()
        let retryModel = resolvedRetryModel(for: primaryModel)
        do {
            return try await process(
                transcript: transcript,
                model: primaryModel,
                customVocabulary: customVocabulary,
                customSystemPrompt: customSystemPrompt
            )
        } catch let error as PostProcessingError {
            let shouldFallback: Bool
            switch error {
            case .requestFailed(let statusCode, _):
                shouldFallback = statusCode == 429
            case .emptyOutput:
                shouldFallback = true
            default:
                shouldFallback = false
            }
            guard shouldFallback, let retryModel else { throw error }
            return try await process(
                transcript: transcript,
                model: retryModel,
                customVocabulary: customVocabulary,
                customSystemPrompt: customSystemPrompt
            )
        }
    }

    private func resolvedPrimaryModel() -> String {
        preferredModel.isEmpty ? defaultModel : preferredModel
    }

    private func resolvedRetryModel(for primaryModel: String) -> String? {
        if !preferredFallbackModel.isEmpty {
            return preferredFallbackModel == primaryModel ? nil : preferredFallbackModel
        }
        if primaryModel == defaultModel { return defaultFallbackModel }
        if primaryModel == defaultFallbackModel { return defaultModel }
        return nil
    }

    private func process(
        transcript: String,
        model: String,
        customVocabulary: [String],
        customSystemPrompt: String
    ) async throws -> PostProcessingResult {
        guard let url = URL(string: "\(baseURL)/chat/completions") else {
            throw PostProcessingError.invalidResponse("Invalid base URL")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = postProcessingTimeoutSeconds

        let normalizedVocabulary = normalizedVocabularyText(customVocabulary)
        let vocabularyPrompt = normalizedVocabulary.isEmpty ? "" : """
The following vocabulary must be treated as high-priority terms while rewriting.
Use these spellings exactly in the output when relevant:
\(normalizedVocabulary)
"""

        var systemPrompt = customSystemPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? Prompts.defaultSystemPrompt
            : customSystemPrompt
        if !vocabularyPrompt.isEmpty {
            systemPrompt += "\n\n" + vocabularyPrompt
        }

        let userMessage = """
Instructions: Clean up RAW_TRANSCRIPTION and return only the cleaned transcript text without surrounding quotes. Return EMPTY if there should be no result.

RAW_TRANSCRIPTION: "\(transcript)"
"""

        let promptForDisplay = """
Model: \(model)

[System]
\(systemPrompt)

[User]
\(userMessage)
"""

        var payload: [String: Any] = [
            "model": model,
            "temperature": 0.0,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userMessage]
            ]
        ]
        if model == defaultModel {
            payload["max_completion_tokens"] = postProcessingMaxCompletionTokens
            payload["reasoning_effort"] = defaultModelReasoningEffort
            payload["include_reasoning"] = false
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])

        let (data, response) = try await LLMAPITransport.data(for: request)
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
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw PostProcessingError.emptyOutput
        }
        return PostProcessingResult(
            transcript: sanitizePostProcessedTranscript(content),
            prompt: promptForDisplay,
            modelUsed: model
        )
    }

    private func sanitizePostProcessedTranscript(_ value: String) -> String {
        var result = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !result.isEmpty else { return "" }
        if result.hasPrefix("\"") && result.hasSuffix("\"") && result.count > 1 {
            result.removeFirst()
            result.removeLast()
            result = result.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if result == "EMPTY" { return "" }
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
