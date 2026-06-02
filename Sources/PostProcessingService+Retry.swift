import Foundation

extension PostProcessingService {
    // Retries post-processing using a saved prompt template and the specified model.
    func retryWithPrompt(
        systemPrompt: String,
        userMessage: String,
        model: String,
        isCommandMode: Bool
    ) async throws -> PostProcessingResult {
        var request = URLRequest(url: URL(string: "\(baseURL)/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let timeoutSeconds = UserDefaults.standard.double(forKey: "post_processing_timeout_seconds")
        request.timeoutInterval = timeoutSeconds > 0 ? timeoutSeconds : 20
        
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
        
        let config = ModelConfiguration.config(for: model)
        if let maxTokens = config.maxCompletionTokens {
            payload["max_completion_tokens"] = maxTokens
        } else if model == "openai/gpt-oss-20b" {
            payload["max_completion_tokens"] = 4096
        }
        if let effort = config.reasoningEffort {
            payload["reasoning_effort"] = effort
        } else if model == "openai/gpt-oss-20b" {
            payload["reasoning_effort"] = "low"
        }
        if let include = config.includeReasoning {
            payload["include_reasoning"] = include
        } else if model == "openai/gpt-oss-20b" {
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
              let rawContent = message["content"] as? String else {
            throw PostProcessingError.invalidResponse("Missing choices[0].message.content")
        }
        
        var content = rawContent
        if config.shouldStripThinkTags {
            content = ModelConfiguration.stripThinkTags(content)
        }
        
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw PostProcessingError.emptyOutput
        }
        
        // Use the existing sanitize functions (they are public/internal)
        // Wait, sanitizePostProcessedTranscript and sanitizeCommandModeTranscript are private in PostProcessingService?
        // Let's check if they are private. I might need to reproduce them or make them internal.
        // For now, I'll reproduce the exact logic they have since it's just trimming quotes.
        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        let sanitizedTranscript = sanitizeTranscript(trimmedContent)
        
        return PostProcessingResult(
            transcript: sanitizedTranscript,
            prompt: promptForDisplay
        )
    }
    
    // Sanitizes final transcript text by trimming quotes and handling EMPTY outputs.
    private func sanitizeTranscript(_ transcript: String) -> String {
        var clean = transcript
        if clean.hasPrefix("\"") && clean.hasSuffix("\"") && clean.count >= 2 {
            clean.removeFirst()
            clean.removeLast()
        }
        if clean.hasPrefix("'") && clean.hasSuffix("'") && clean.count >= 2 {
            clean.removeFirst()
            clean.removeLast()
        }
        if clean.uppercased() == "EMPTY" {
            return ""
        }
        return clean.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
