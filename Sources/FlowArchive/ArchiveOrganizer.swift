import Foundation

enum ArchivePipelineError: LocalizedError {
    case missingAPIKey
    case destinationMissing(String)
    case chunkingFailed(String)
    case organizerFailed(String)
    case writeFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Add an API key in Settings before archiving recordings."
        case .destinationMissing(let message):
            return message
        case .chunkingFailed(let message):
            return message
        case .organizerFailed(let message):
            return message
        case .writeFailed(let message):
            return message
        }
    }
}

struct OrganizerResult: Equatable {
    var filename: String
    var summary: [String]
    var tags: [String]
}

enum ArchiveOrganizer {
    static func organize(
        transcript: String,
        apiKey: String,
        baseURL: String,
        model: String,
        prompt: String,
        timeoutSeconds: TimeInterval = 120
    ) async throws -> OrganizerResult {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else { throw ArchivePipelineError.missingAPIKey }

        var request = URLRequest(url: URL(string: "\(normalizedBase(baseURL))/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(trimmedKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = timeoutSeconds

        let systemPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? ArchiveSettings.defaultOrganizerPrompt
            : prompt
        let userMessage = """
        TRANSCRIPT:
        <<<TRANSCRIPT
        \(transcript)
        TRANSCRIPT
        """

        var payload: [String: Any] = [
            "model": model,
            "temperature": 0.2,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userMessage]
            ]
        ]
        let config = ModelConfiguration.config(for: model)
        if let maxTokens = config.maxCompletionTokens {
            payload["max_completion_tokens"] = maxTokens
        }
        if let effort = config.reasoningEffort {
            payload["reasoning_effort"] = effort
        }
        if let include = config.includeReasoning {
            payload["include_reasoning"] = include
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await LLMAPITransport.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw ArchivePipelineError.organizerFailed("Organizer request failed: \(body)")
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              var content = message["content"] as? String
        else {
            throw ArchivePipelineError.organizerFailed("Organizer returned no content.")
        }

        if config.shouldStripThinkTags {
            content = ModelConfiguration.stripThinkTags(content)
        }
        return try parse(content)
    }

    static func parse(_ raw: String) throws -> OrganizerResult {
        let jsonText = extractJSONObject(from: raw)
        guard let data = jsonText.data(using: .utf8),
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            throw ArchivePipelineError.organizerFailed("Organizer output was not JSON.")
        }
        let filename = ArchiveMarkdownWriter.kebabCase((object["filename"] as? String) ?? "untitled-recording")
        let summary = (object["summary"] as? [String])?.map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty } ?? []
        let tags = (object["tags"] as? [String])?.map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "#"))
                .lowercased()
        }.filter { !$0.isEmpty } ?? []
        return OrganizerResult(filename: filename, summary: summary, tags: tags)
    }

    static func fallback(from transcript: String) -> OrganizerResult {
        let words = transcript
            .split { !$0.isLetter && !$0.isNumber }
            .prefix(5)
            .map(String.init)
        let filename = ArchiveMarkdownWriter.kebabCase(words.joined(separator: " "))
        let snippet = transcript.replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let summary = snippet.isEmpty ? ["Recording archived."] : [String(snippet.prefix(180))]
        return OrganizerResult(filename: filename, summary: summary, tags: [])
    }

    private static func extractJSONObject(from raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("```") {
            text = text.replacingOccurrences(of: "```json", with: "")
            text = text.replacingOccurrences(of: "```", with: "")
            text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}") {
            return String(text[start...end])
        }
        return text
    }

    private static func normalizedBase(_ baseURL: String) -> String {
        var value = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while value.hasSuffix("/") { value.removeLast() }
        return value.isEmpty ? "https://api.groq.com/openai/v1" : value
    }
}
