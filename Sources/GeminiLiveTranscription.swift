import Foundation

/// Wire format for `gemini-3.5-transcribe-live`, which streams over the Live
/// API's bidirectional socket rather than the Interactions API used by
/// ``GeminiTranscription``.
///
/// The live model matters for dictation because its free-tier quota is orders
/// of magnitude larger: the batch model allows a couple of dozen requests a
/// day, while the live model is limited by tokens per minute, which a single
/// speaker cannot realistically exhaust.
enum GeminiLiveTranscription {
    static let defaultBaseURL = "wss://generativelanguage.googleapis.com"

    private static let servicePath =
        "/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent"

    /// Smart mode is spelled in upper case here, unlike the Interactions API.
    private static let smartMode = "SMART"

    static func handlesModel(_ model: String) -> Bool {
        let normalized = model.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized.hasPrefix("gemini-") && normalized.hasSuffix("-transcribe-live")
    }

    static func socketURL(baseURL: String) -> URL? {
        let trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let source = trimmed.isEmpty ? defaultBaseURL : trimmed
        guard var components = URLComponents(string: source) else { return nil }

        // Accept an https base and upgrade it, so a Gemini provider URL copied
        // from the REST docs still works here.
        switch components.scheme?.lowercased() {
        case "https", "wss": components.scheme = "wss"
        case "http", "ws": components.scheme = "ws"
        default: return nil
        }
        guard let host = components.host, !host.isEmpty else { return nil }

        // Anything other than a Google host cannot serve this protocol, so fall
        // back rather than opening a socket that will never speak it.
        let isGoogleHost = host.lowercased().hasSuffix("googleapis.com")
        if !isGoogleHost {
            return URL(string: defaultBaseURL + servicePath)
        }

        components.path = servicePath
        components.query = nil
        return components.url
    }

    static func setupMessage(model: String, customVocabulary: String) throws -> String {
        var transcription: [String: Any] = ["mode": smartMode]
        let terms = GeminiTranscription.vocabularyTerms(from: customVocabulary)
        if !terms.isEmpty {
            transcription["custom_vocabulary"] = terms
        }
        // Language is deliberately left to auto-detection, matching the batch
        // path: pinning it drops the model out of smart mode.
        let payload: [String: Any] = [
            "setup": [
                "model": normalizedModelPath(model),
                "generationConfig": ["responseModalities": ["TEXT"]],
                "inputAudioTranscription": transcription
            ]
        ]
        return try encode(payload)
    }

    static func audioMessage(pcm16: Data, sampleRate: Int) throws -> String {
        try encode([
            "realtimeInput": [
                "audio": [
                    "mimeType": "audio/pcm;rate=\(sampleRate)",
                    "data": pcm16.base64EncodedString()
                ]
            ]
        ])
    }

    static func audioStreamEndMessage() throws -> String {
        try encode(["realtimeInput": ["audioStreamEnd": true]])
    }

    /// The Live API namespaces models under `models/`; accept either spelling.
    static func normalizedModelPath(_ model: String) -> String {
        let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasPrefix("models/") ? trimmed : "models/\(trimmed)"
    }

    // MARK: - Server frames

    struct ServerFrame {
        var transcript: String?
        var isComplete: Bool
        var errorMessage: String?
        var isSetupComplete: Bool
    }

    static func parseServerFrame(_ text: String) -> ServerFrame {
        guard let data = text.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return ServerFrame(transcript: nil, isComplete: false, errorMessage: nil, isSetupComplete: false)
        }

        if let error = root["error"] as? [String: Any] {
            let message = error["message"] as? String ?? "Gemini live transcription failed."
            return ServerFrame(transcript: nil, isComplete: true, errorMessage: message, isSetupComplete: false)
        }

        if root["setupComplete"] != nil {
            return ServerFrame(transcript: nil, isComplete: false, errorMessage: nil, isSetupComplete: true)
        }

        guard let server = root["serverContent"] as? [String: Any] else {
            return ServerFrame(transcript: nil, isComplete: false, errorMessage: nil, isSetupComplete: false)
        }

        var transcript: String?
        if let text = (server["inputTranscription"] as? [String: Any])?["text"] as? String {
            transcript = text
        } else if let turn = server["modelTurn"] as? [String: Any],
                  let parts = turn["parts"] as? [[String: Any]] {
            let joined = parts.compactMap { $0["text"] as? String }.joined()
            transcript = joined.isEmpty ? nil : joined
        }

        let complete = (server["turnComplete"] as? Bool ?? false)
            || (server["generationComplete"] as? Bool ?? false)

        return ServerFrame(
            transcript: transcript,
            isComplete: complete,
            errorMessage: nil,
            isSetupComplete: false
        )
    }

    private static func encode(_ payload: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: payload)
        guard let text = String(data: data, encoding: .utf8) else {
            throw TranscriptionError.transcriptionFailed("Could not encode Gemini live message.")
        }
        return text
    }
}
