import Foundation
import os.log

private let transcriptionLog = OSLog(subsystem: "com.zachlatta.freeflow", category: "Transcription")

enum TranscriptionProvider: String, CaseIterable, Identifiable {
    case openAICompatible = "openai_compatible"
    case elevenLabs = "elevenlabs"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .openAICompatible: return "OpenAI-compatible"
        case .elevenLabs: return "ElevenLabs Scribe"
        }
    }
}

private protocol BatchTranscriptionClient {
    func transcribe(fileURL: URL) async throws -> String
}

class TranscriptionService {
    static let defaultOpenAICompatibleBaseURL = "https://api.groq.com/openai/v1"
    static let defaultElevenLabsBaseURL = "https://api.elevenlabs.io/v1"
    static let defaultElevenLabsModel = "scribe_v2"
    static let defaultElevenLabsRealtimeModel = "scribe_v2_realtime"

    private let client: BatchTranscriptionClient
    private var transcriptionTimeoutSeconds: TimeInterval {
        let override = UserDefaults.standard.double(forKey: "transcription_timeout_seconds")
        return override > 0 ? override : 20
    }

    init(
        provider: TranscriptionProvider = .openAICompatible,
        apiKey: String,
        baseURL: String = TranscriptionService.defaultOpenAICompatibleBaseURL,
        transcriptionModel: String = "whisper-large-v3",
        language: String? = nil
    ) throws {
        switch provider {
        case .openAICompatible:
            self.client = try OpenAICompatibleTranscriptionClient(
                apiKey: apiKey,
                baseURL: baseURL,
                transcriptionModel: transcriptionModel,
                language: language
            )
        case .elevenLabs:
            self.client = try ElevenLabsTranscriptionClient(
                apiKey: apiKey,
                baseURL: baseURL,
                language: language
            )
        }
    }

    static func validateAPIKey(
        _ key: String,
        baseURL: String = TranscriptionService.defaultOpenAICompatibleBaseURL,
        provider: TranscriptionProvider = .openAICompatible
    ) async -> Bool {
        switch provider {
        case .openAICompatible:
            return await OpenAICompatibleTranscriptionClient.validateAPIKey(key, baseURL: baseURL)
        case .elevenLabs:
            return await ElevenLabsTranscriptionClient.validateAPIKey(key, baseURL: baseURL)
        }
    }

    func transcribe(fileURL: URL) async throws -> String {
        guard !Task.isCancelled else {
            throw CancellationError()
        }

        let timeoutSeconds = transcriptionTimeoutSeconds
        let raceState = TranscriptionTimeoutRaceState()

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                raceState.setContinuation(continuation)

                let transcriptionTask = Task { [weak self] in
                    do {
                        guard let self else {
                            throw TranscriptionError.transcriptionFailed("Transcription service deallocated")
                        }
                        let result = try await self.client.transcribe(fileURL: fileURL)
                        raceState.finish(.success(result))
                    } catch {
                        raceState.finish(.failure(Self.transcriptionTimeoutErrorIfNeeded(
                            error,
                            timeoutSeconds: timeoutSeconds
                        )))
                    }
                }

                let timeoutTask = Task {
                    do {
                        try await Task.sleep(nanoseconds: UInt64(timeoutSeconds * 1_000_000_000))
                        raceState.finish(.failure(TranscriptionError.transcriptionTimedOut(timeoutSeconds)))
                    } catch is CancellationError {
                    } catch {
                        raceState.finish(.failure(error))
                    }
                }

                raceState.setTasks([transcriptionTask, timeoutTask])
            }
        } onCancel: {
            raceState.cancel()
        }
    }

    static func friendlyHTTPMessage(status: Int, host: String?) -> String {
        let provider = host ?? "the provider"
        switch status {
        case 400:
            return "Request rejected by \(provider) (HTTP 400). Check provider settings."
        case 401:
            return "Invalid API key for \(provider). Open Settings to fix it."
        case 403:
            return "Key lacks permission for this endpoint at \(provider) (HTTP 403). Check the key's scopes."
        case 404:
            return "Endpoint not found at \(provider) (HTTP 404). Base URL is likely wrong for this provider."
        case 413:
            return "Audio file too large for \(provider) (HTTP 413). Try a shorter recording."
        case 422:
            return "Audio request rejected by \(provider) (HTTP 422). Try again with a shorter recording."
        case 429:
            return "Rate limit reached at \(provider) (HTTP 429). Wait a moment and try again."
        case 500..<600:
            return "Provider error at \(provider) (HTTP \(status)). Try again in a moment."
        default:
            return "Request failed at \(provider) (HTTP \(status))."
        }
    }

    private static func transcriptionTimeoutErrorIfNeeded(
        _ error: Error,
        timeoutSeconds: TimeInterval
    ) -> Error {
        if let urlError = error as? URLError, urlError.code == .timedOut {
            return TranscriptionError.transcriptionTimedOut(timeoutSeconds)
        }
        return error
    }
}

private final class OpenAICompatibleTranscriptionClient: BatchTranscriptionClient {
    private let apiKey: String
    private let baseURL: URL
    private let transcriptionModel: String
    private let language: String?
    private let transcriptionResponseFormat = "verbose_json"
    private var transcriptionTimeoutSeconds: TimeInterval {
        let override = UserDefaults.standard.double(forKey: "transcription_timeout_seconds")
        return override > 0 ? override : 20
    }

    init(
        apiKey: String,
        baseURL: String,
        transcriptionModel: String,
        language: String?
    ) throws {
        self.apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        self.baseURL = try normalizedBaseURL(from: baseURL)
        let trimmedModel = transcriptionModel.trimmingCharacters(in: .whitespacesAndNewlines)
        self.transcriptionModel = trimmedModel.isEmpty ? "whisper-large-v3" : trimmedModel
        let trimmedLanguage = language?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.language = (trimmedLanguage?.isEmpty == false) ? trimmedLanguage : nil
    }

    static func validateAPIKey(_ key: String, baseURL: String) async -> Bool {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        guard let baseURL = try? normalizedBaseURL(from: baseURL) else { return false }

        var request = URLRequest(url: baseURL.appendingPathComponent("models"))
        request.timeoutInterval = 10
        request.setValue("Bearer \(trimmed)", forHTTPHeaderField: "Authorization")

        do {
            let (_, response) = try await LLMAPITransport.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            return status == 200
        } catch {
            return false
        }
    }

    func transcribe(fileURL: URL) async throws -> String {
        guard !apiKey.isEmpty else {
            throw TranscriptionError.submissionFailed("Enter an API key in Settings.")
        }

        let url = baseURL
            .appendingPathComponent("audio")
            .appendingPathComponent("transcriptions")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = transcriptionTimeoutSeconds
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        let audioData = try Data(contentsOf: fileURL)
        var fields: [(String, String)] = [
            ("model", transcriptionModel),
            ("response_format", transcriptionResponseFormat)
        ]
        if let language {
            fields.append(("language", language))
        }

        let body = makeMultipartBody(
            fields: fields,
            audioData: audioData,
            fileFieldName: "file",
            fileName: fileURL.lastPathComponent,
            boundary: boundary
        )

        do {
            let (data, response) = try await LLMAPITransport.upload(for: request, from: body)
            return try validateTranscriptionResponse(data: data, response: response, fileURL: fileURL)
        } catch {
            logUploadFailure(error, fileURL: fileURL)
            throw error
        }
    }

    private func validateTranscriptionResponse(data: Data, response: URLResponse, fileURL: URL) throws -> String {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw TranscriptionError.submissionFailed("No response from server")
        }

        guard httpResponse.statusCode == 200 else {
            os_log(
                .error,
                log: transcriptionLog,
                "OpenAI-compatible upload returned HTTP %ld for %{public}@ (bytes=%{public}lld)",
                httpResponse.statusCode,
                fileURL.lastPathComponent,
                fileSizeBytes(for: fileURL)
            )
            throw TranscriptionError.submissionFailed(TranscriptionService.friendlyHTTPMessage(
                status: httpResponse.statusCode,
                host: baseURL.host
            ))
        }

        return try parseTranscript(from: data)
    }

    private let hallucinationPhrases = [
        "thank you",
        "thank you for watching",
        "thank you very much",
        "thank you so much",
        "thanks for watching",
        "please subscribe",
        "like and subscribe",
        "subtitles by",
        "subtitles by the amara.org community",
        "you"
    ]

    private let hallucinationNoSpeechThreshold = 0.1

    private func parseTranscript(from data: Data) throws -> String {
        if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
           let text = json["text"] as? String {
            if isHallucination(text: text, json: json) {
                return ""
            }
            return text
        }

        let plainText = String(data: data, encoding: .utf8) ?? ""
        let text = plainText
            .components(separatedBy: .newlines)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            throw TranscriptionError.pollFailed("Invalid response")
        }

        return text
    }

    private func isHallucination(text: String, json: [String: Any]) -> Bool {
        let normalized = text
            .lowercased()
            .trimmingCharacters(in: CharacterSet.punctuationCharacters.union(.whitespacesAndNewlines))
        guard hallucinationPhrases.contains(normalized) else {
            return false
        }

        guard let segments = json["segments"] as? [[String: Any]] else {
            os_log(
                .info,
                log: transcriptionLog,
                "Skipping hallucination filter for '%{public}@': provider response has no segments/no_speech metadata",
                normalized
            )
            return false
        }

        guard let noSpeechProb = segments.first?["no_speech_prob"] as? Double else {
            os_log(
                .info,
                log: transcriptionLog,
                "Skipping hallucination filter for '%{public}@': provider response omitted no_speech_prob",
                normalized
            )
            return false
        }
        return noSpeechProb >= hallucinationNoSpeechThreshold
    }
}

private final class ElevenLabsTranscriptionClient: BatchTranscriptionClient {
    private let apiKey: String
    private let baseURL: URL
    private let language: String?
    private var transcriptionTimeoutSeconds: TimeInterval {
        let override = UserDefaults.standard.double(forKey: "transcription_timeout_seconds")
        return override > 0 ? override : 20
    }

    init(apiKey: String, baseURL: String, language: String?) throws {
        self.apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        self.baseURL = try normalizedBaseURL(from: baseURL)
        let trimmedLanguage = language?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.language = (trimmedLanguage?.isEmpty == false) ? trimmedLanguage : nil
    }

    static func validateAPIKey(_ key: String, baseURL: String) async -> Bool {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        guard let baseURL = try? normalizedBaseURL(from: baseURL) else { return false }

        var request = URLRequest(url: baseURL.appendingPathComponent("models"))
        request.timeoutInterval = 10
        request.setValue(trimmed, forHTTPHeaderField: "xi-api-key")

        do {
            let (_, response) = try await LLMAPITransport.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            return status == 200
        } catch {
            return false
        }
    }

    func transcribe(fileURL: URL) async throws -> String {
        guard !apiKey.isEmpty else {
            throw TranscriptionError.submissionFailed("Enter an ElevenLabs API key in Settings.")
        }

        let url = baseURL.appendingPathComponent("speech-to-text")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = transcriptionTimeoutSeconds
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var fields: [(String, String)] = [
            ("model_id", TranscriptionService.defaultElevenLabsModel),
            ("tag_audio_events", "false"),
            ("timestamps_granularity", "none")
        ]
        if let language {
            fields.append(("language_code", language))
        }

        let audioData = try Data(contentsOf: fileURL)
        let body = makeMultipartBody(
            fields: fields,
            audioData: audioData,
            fileFieldName: "file",
            fileName: fileURL.lastPathComponent,
            boundary: boundary
        )

        do {
            let (data, response) = try await LLMAPITransport.upload(for: request, from: body)
            return try validateTranscriptionResponse(data: data, response: response, fileURL: fileURL)
        } catch {
            logUploadFailure(error, fileURL: fileURL)
            throw error
        }
    }

    private func validateTranscriptionResponse(data: Data, response: URLResponse, fileURL: URL) throws -> String {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw TranscriptionError.submissionFailed("No response from server")
        }

        guard httpResponse.statusCode == 200 else {
            os_log(
                .error,
                log: transcriptionLog,
                "ElevenLabs upload returned HTTP %ld for %{public}@ (bytes=%{public}lld)",
                httpResponse.statusCode,
                fileURL.lastPathComponent,
                fileSizeBytes(for: fileURL)
            )
            throw TranscriptionError.submissionFailed(TranscriptionService.friendlyHTTPMessage(
                status: httpResponse.statusCode,
                host: baseURL.host
            ))
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let text = json["text"] as? String else {
            throw TranscriptionError.pollFailed("Invalid ElevenLabs response")
        }
        return text
    }
}

private func normalizedBaseURL(from baseURL: String) throws -> URL {
    let trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
        throw TranscriptionError.invalidBaseURL("Provider URL is empty.")
    }

    guard var components = URLComponents(string: trimmed) else {
        throw TranscriptionError.invalidBaseURL("Provider URL is malformed.")
    }

    guard let scheme = components.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
        throw TranscriptionError.invalidBaseURL("Provider URL must use http or https.")
    }

    guard let host = components.host, !host.isEmpty else {
        throw TranscriptionError.invalidBaseURL("Provider URL must include a host.")
    }

    components.scheme = scheme
    if components.path == "/" {
        components.path = ""
    } else {
        components.path = components.path.replacingOccurrences(
            of: "/+$",
            with: "",
            options: .regularExpression
        )
    }

    guard let normalizedURL = components.url else {
        throw TranscriptionError.invalidBaseURL("Provider URL is malformed.")
    }

    return normalizedURL
}

private func makeMultipartBody(
    fields: [(String, String)],
    audioData: Data,
    fileFieldName: String,
    fileName: String,
    boundary: String
) -> Data {
    var body = Data()

    func append(_ value: String) {
        body.append(Data(value.utf8))
    }

    for (name, value) in fields {
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
        append("\(value)\r\n")
    }

    append("--\(boundary)\r\n")
    append("Content-Disposition: form-data; name=\"\(fileFieldName)\"; filename=\"\(fileName)\"\r\n")
    append("Content-Type: \(audioContentType(for: fileName))\r\n\r\n")
    body.append(audioData)
    append("\r\n")
    append("--\(boundary)--\r\n")

    return body
}

private func audioContentType(for fileName: String) -> String {
    if fileName.lowercased().hasSuffix(".wav") {
        return "audio/wav"
    }
    if fileName.lowercased().hasSuffix(".mp3") {
        return "audio/mpeg"
    }
    if fileName.lowercased().hasSuffix(".m4a") {
        return "audio/mp4"
    }
    return "audio/mp4"
}

private func fileSizeBytes(for fileURL: URL) -> Int64 {
    let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path)
    return (attributes?[.size] as? NSNumber)?.int64Value ?? -1
}

private func logUploadFailure(_ error: Error, fileURL: URL) {
    let nsError = error as NSError
    os_log(
        .error,
        log: transcriptionLog,
        "Transcription upload failed for %{public}@ (bytes=%{public}lld): domain=%{public}@ code=%ld desc=%{public}@",
        fileURL.lastPathComponent,
        fileSizeBytes(for: fileURL),
        nsError.domain,
        nsError.code,
        error.localizedDescription
    )
}

enum TranscriptionError: LocalizedError {
    case invalidBaseURL(String)
    case uploadFailed(String)
    case submissionFailed(String)
    case transcriptionFailed(String)
    case transcriptionTimedOut(TimeInterval)
    case pollFailed(String)
    case audioPreparationFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidBaseURL(let msg): return "Invalid provider URL: \(msg)"
        case .uploadFailed(let msg): return "Upload failed: \(msg)"
        case .submissionFailed(let msg): return "Submission failed: \(msg)"
        case .transcriptionTimedOut(let seconds): return "Transcription timed out after \(Int(seconds))s"
        case .transcriptionFailed(let msg): return "Transcription failed: \(msg)"
        case .pollFailed(let msg): return "Polling failed: \(msg)"
        case .audioPreparationFailed(let msg): return "Audio preparation failed: \(msg)"
        }
    }
}

private final class TranscriptionTimeoutRaceState {
    private let lock = NSLock()
    private var didFinish = false
    private var continuation: CheckedContinuation<String, Error>?
    private var tasks: [Task<Void, Never>] = []

    func setContinuation(_ continuation: CheckedContinuation<String, Error>) {
        lock.lock()
        if didFinish {
            lock.unlock()
            continuation.resume(throwing: CancellationError())
            return
        }

        self.continuation = continuation
        lock.unlock()
    }

    func setTasks(_ tasks: [Task<Void, Never>]) {
        lock.lock()
        if didFinish {
            lock.unlock()
            tasks.forEach { $0.cancel() }
            return
        }

        self.tasks = tasks
        lock.unlock()
    }

    func finish(_ result: Result<String, Error>) {
        lock.lock()
        guard !didFinish else {
            lock.unlock()
            return
        }

        didFinish = true
        let continuation = self.continuation
        self.continuation = nil
        let tasks = self.tasks
        self.tasks = []
        lock.unlock()

        tasks.forEach { $0.cancel() }

        switch result {
        case .success(let value):
            continuation?.resume(returning: value)
        case .failure(let error):
            continuation?.resume(throwing: error)
        }
    }

    func cancel() {
        finish(.failure(CancellationError()))
    }
}
