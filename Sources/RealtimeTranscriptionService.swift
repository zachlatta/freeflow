import Foundation
import os.log

private let realtimeLog = OSLog(subsystem: "com.zachlatta.freeflow", category: "RealtimeTranscription")

enum RealtimeTranscriptionError: LocalizedError {
    case invalidBaseURL(String)
    case notConnected
    case serverError
    case missingAPIKey
    case sendFailed
    case finalizationTimedOut
    case alreadyFinalizing
    case closedBeforeFinal

    var errorDescription: String? {
        switch self {
        case .invalidBaseURL: return "Cannot derive a WebSocket URL from the configured base URL"
        case .notConnected: return "Realtime transcription socket is not connected"
        case .serverError: return "Realtime transcription server rejected the request"
        case .missingAPIKey: return "Enter an ElevenLabs API key in Settings."
        case .sendFailed: return "Realtime transcription could not send audio"
        case .finalizationTimedOut: return "Realtime transcription timed out waiting for the final transcript"
        case .alreadyFinalizing: return "Realtime transcription is already waiting for the final transcript"
        case .closedBeforeFinal: return "Realtime socket closed before emitting the final transcript"
        }
    }
}

protocol RealtimeTranscriptionClient: AnyObject {
    var pcmSampleRate: Double { get }
    func start() throws
    func cancel()
    func appendPCM16(_ data: Data)
    func commitAndAwaitFinal() async throws -> String
}

final class RealtimeTranscriptionService: RealtimeTranscriptionClient {
    struct Configuration {
        let baseURL: String
        let apiKey: String
        let model: String
        let language: String?
    }

    private let config: Configuration
    private let session: URLSession
    private var task: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?

    private let stateQueue = DispatchQueue(label: "com.zachlatta.freeflow.realtime.state")
    private var finalText: String = ""
    private var partialText: String = ""
    private var finalContinuation: CheckedContinuation<String, Error>?
    private var commitSent: Bool = false
    private var closed: Bool = false
    private var terminalError: Error?
    private var serverEventCount: Int = 0
    private var commitEventCount: Int?
    private var postCommitCompleted: Bool = false
    private var currentItemID: String?

    /// Published on the main queue as partial transcript updates. The service
    /// concatenates all `completed` events and currently-streaming `delta`
    /// events — useful for a live overlay readout.
    var onPartialUpdate: ((String) -> Void)?
    let pcmSampleRate: Double = 24_000

    init(config: Configuration, session: URLSession = .shared) {
        self.config = config
        self.session = session
    }

    // MARK: Lifecycle

    func start() throws {
        guard let wsURL = Self.deriveWebSocketURL(
            baseURL: config.baseURL,
            model: config.model,
            language: config.language
        ) else {
            throw RealtimeTranscriptionError.invalidBaseURL(config.baseURL)
        }

        var request = URLRequest(url: wsURL)
        if !config.apiKey.isEmpty {
            request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        }

        let task = session.webSocketTask(with: request)
        stateQueue.sync {
            self.task = task
        }
        task.resume()

        receiveTask = Task { [weak self] in
            await self?.receiveLoop()
        }

        sendSessionUpdate()
    }

    /// Cancel the socket and any in-flight receive. Safe to call multiple times.
    func cancel() {
        let currentTask: URLSessionWebSocketTask? = stateQueue.sync {
            let currentTask = task
            task = nil
            return currentTask
        }
        stateQueue.sync {
            guard !closed else { return }
            closed = true
            if let cont = finalContinuation {
                finalContinuation = nil
                cont.resume(throwing: CancellationError())
            }
        }
        receiveTask?.cancel()
        currentTask?.cancel(with: .normalClosure, reason: nil)
    }

    // MARK: Producer

    /// Append 16-bit little-endian PCM samples. The caller owns rate matching
    /// (the service declares 24 kHz mono in `session.update`, matching the
    /// OpenAI Realtime default).
    func appendPCM16(_ data: Data) {
        let currentTask: URLSessionWebSocketTask? = stateQueue.sync {
            task
        }
        guard let currentTask, !data.isEmpty else { return }
        let audioB64 = data.base64EncodedString()
        let message: [String: Any] = [
            "type": "input_audio_buffer.append",
            "audio": audioB64,
        ]
        send(message, over: currentTask)
    }

    /// Signal end-of-input, wait for the final transcript, return it.
    func commitAndAwaitFinal() async throws -> String {
        let currentTask: URLSessionWebSocketTask? = stateQueue.sync {
            task
        }
        guard let currentTask else {
            throw RealtimeTranscriptionError.notConnected
        }
        let alreadyCommitted: Bool = stateQueue.sync {
            if commitSent { return true }
            commitSent = true
            commitEventCount = serverEventCount
            postCommitCompleted = false
            return false
        }
        if !alreadyCommitted {
            send(["type": "input_audio_buffer.commit"], over: currentTask)
        }

        return try await withCheckedThrowingContinuation { continuation in
            var immediateResult: Result<String, Error>?
            stateQueue.sync {
                if let terminalError {
                    immediateResult = .failure(terminalError)
                    return
                }
                if closed {
                    immediateResult = .failure(RealtimeTranscriptionError.closedBeforeFinal)
                    return
                }
                if let finalText = readyCommittedTranscriptLocked() {
                    closed = true
                    immediateResult = .success(finalText)
                    return
                }
                finalContinuation = continuation
            }
            if let immediateResult {
                currentTask.cancel(with: .normalClosure, reason: nil)
                continuation.resume(with: immediateResult)
            }
        }
    }

    // MARK: Receive loop

    private func receiveLoop() async {
        while !Task.isCancelled {
            let currentTask: URLSessionWebSocketTask? = stateQueue.sync {
                task
            }
            guard let currentTask else { break }
            do {
                let message = try await currentTask.receive()
                switch message {
                case .string(let text):
                    handleServerEvent(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        handleServerEvent(text)
                    }
                @unknown default:
                    break
                }
            } catch {
                finishWithClose()
                return
            }
        }
        finishWithClose()
    }

    private func finishWithClose() {
        stateQueue.sync {
            closed = true
            if let cont = finalContinuation {
                finalContinuation = nil
                if postCommitCompleted {
                    cont.resume(returning: finalText)
                } else {
                    cont.resume(throwing: RealtimeTranscriptionError.closedBeforeFinal)
                }
            }
        }
    }

    private func handleServerEvent(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let eventType = json["type"] as? String else {
            return
        }

        stateQueue.sync {
            serverEventCount += 1
        }

        switch eventType {
        case "conversation.item.input_audio_transcription.delta":
            if let itemID = json["item_id"] as? String {
                stateQueue.sync {
                    currentItemID = itemID
                }
            }
            if let delta = json["delta"] as? String, !delta.isEmpty {
                appendDelta(delta)
            }
            resumeIfReadyAfterCommit()
        case "conversation.item.input_audio_transcription.completed":
            stateQueue.sync {
                if let commitEventCount, serverEventCount > commitEventCount {
                    postCommitCompleted = true
                }
            }
            if let itemID = json["item_id"] as? String {
                stateQueue.sync {
                    currentItemID = itemID
                }
            }
            if let transcript = json["transcript"] as? String {
                commitSegment(transcript)
            } else {
                resumeIfReadyAfterCommit()
            }
        case "input_audio_buffer.committed":
            if let itemID = json["item_id"] as? String {
                stateQueue.sync {
                    currentItemID = itemID
                }
            }
            resumeIfReadyAfterCommit()
        case "error":
            os_log(.error, log: realtimeLog, "server rejected realtime transcription request")
            let error = RealtimeTranscriptionError.serverError
            stateQueue.sync {
                terminalError = error
                closed = true
                if let cont = finalContinuation {
                    finalContinuation = nil
                    cont.resume(throwing: error)
                }
            }
        default:
            resumeIfReadyAfterCommit()
            break
        }
    }

    private func appendDelta(_ delta: String) {
        let snapshot: String = stateQueue.sync {
            partialText += delta
            return finalText + partialText
        }
        reportPartial(snapshot)
    }

    private func commitSegment(_ transcript: String) {
        let snapshot: String = stateQueue.sync {
            let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                if !finalText.isEmpty { finalText += " " }
                finalText += trimmed
            }
            partialText = ""
            return finalText
        }
        reportPartial(snapshot)
        resumeIfReadyAfterCommit()
    }

    private func reportPartial(_ text: String) {
        guard let handler = onPartialUpdate else { return }
        DispatchQueue.main.async {
            handler(text)
        }
    }

    // MARK: Send helpers

    private func send(_ payload: [String: Any], over task: URLSessionWebSocketTask) {
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let text = String(data: data, encoding: .utf8) else {
            return
        }
        task.send(.string(text)) { error in
            if error != nil {
                os_log(.error, log: realtimeLog, "realtime audio send failed")
            }
        }
    }

    private func sendSessionUpdate() {
        let currentTask: URLSessionWebSocketTask? = stateQueue.sync {
            task
        }
        guard let currentTask else { return }
        var transcription: [String: Any] = [:]
        let model = config.model.trimmingCharacters(in: .whitespacesAndNewlines)
        if !model.isEmpty {
            transcription["model"] = model
        }
        if let language = config.language, !language.isEmpty {
            transcription["language"] = language
        }
        let session: [String: Any] = [
            "type": "transcription",
            "audio": [
                "input": [
                    "format": [
                        "type": "audio/pcm",
                        "rate": 24_000,
                    ],
                    "transcription": transcription,
                    "turn_detection": NSNull(),
                ],
            ],
        ]
        send(["type": "session.update", "session": session], over: currentTask)
    }

    // MARK: URL derivation

    /// Turn `https://host[/prefix]` or `http://host[/prefix]` into
    /// `wss://host[/prefix]/realtime`, reusing a trailing `/v1` prefix when
    /// the configured base URL already includes it.
    static func deriveWebSocketURL(
        baseURL: String,
        model: String,
        language: String?
    ) -> URL? {
        let trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: trimmed) else { return nil }

        switch components.scheme?.lowercased() {
        case "http": components.scheme = "ws"
        case "https": components.scheme = "wss"
        case "ws", "wss": break
        default: return nil
        }

        var path = components.path
        if path.hasSuffix("/") { path.removeLast() }
        if path.hasSuffix("/v1") {
            path += "/realtime"
        } else {
            path += "/v1/realtime"
        }
        components.path = path

        var queryItems = components.queryItems ?? []
        if !queryItems.contains(where: { $0.name == "intent" }) {
            queryItems.append(URLQueryItem(name: "intent", value: "transcription"))
        }
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        return components.url
    }

    private func resumeIfReadyAfterCommit() {
        var pendingResume: (CheckedContinuation<String, Error>, String)?
        stateQueue.sync {
            guard let cont = finalContinuation,
                  let finalText = readyCommittedTranscriptLocked() else {
                return
            }
            finalContinuation = nil
            closed = true
            pendingResume = (cont, finalText)
        }
        if let (cont, text) = pendingResume {
            let currentTask: URLSessionWebSocketTask? = stateQueue.sync {
                task
            }
            currentTask?.cancel(with: .normalClosure, reason: nil)
            cont.resume(returning: text)
        }
    }

    private func readyCommittedTranscriptLocked() -> String? {
        guard commitSent,
              partialText.isEmpty,
              postCommitCompleted else {
            return nil
        }
        return finalText
    }
}

/// Small transport boundary so realtime sessions can be verified without a
/// provider connection, credentials, or recorded audio.
protocol RealtimeWebSocketTransport: AnyObject {
    func resume()
    func send(_ text: String, completion: @escaping (Error?) -> Void)
    func receive() async throws -> String
    func cancel()
}

private final class URLSessionRealtimeWebSocketTransport: RealtimeWebSocketTransport {
    private let task: URLSessionWebSocketTask

    init(request: URLRequest, session: URLSession) {
        task = session.webSocketTask(with: request)
    }

    func resume() { task.resume() }

    func send(_ text: String, completion: @escaping (Error?) -> Void) {
        task.send(.string(text), completionHandler: completion)
    }

    func receive() async throws -> String {
        switch try await task.receive() {
        case .string(let text): return text
        case .data(let data): return String(data: data, encoding: .utf8) ?? ""
        @unknown default: return ""
        }
    }

    func cancel() { task.cancel(with: .normalClosure, reason: nil) }
}

final class ElevenLabsRealtimeTranscriptionService: RealtimeTranscriptionClient {
    struct Configuration {
        let baseURL: String
        let apiKey: String
        let model: String
        let language: String?
    }

    typealias TransportFactory = (URLRequest) -> RealtimeWebSocketTransport
    /// The scheduler must invoke its action asynchronously and return a
    /// cancellation closure. Production uses a bounded timer; tests fire it manually.
    typealias TimeoutScheduler = (TimeInterval, @escaping () -> Void) -> (() -> Void)

    private struct AudioChunk {
        let data: Data
        let commit: Bool
    }

    private let config: Configuration
    private let makeTransport: TransportFactory
    private let scheduleTimeout: TimeoutScheduler
    private let finalizationTimeout: TimeInterval
    private let stateQueue = DispatchQueue(label: "com.zachlatta.freeflow.realtime.elevenlabs.state")
    // Every field below is read and written on stateQueue.
    private var transport: RealtimeWebSocketTransport?
    private var receiveTask: Task<Void, Never>?
    private var cancelTimeout: (() -> Void)?
    private var finalText = ""
    private var partialText = ""
    private var pendingAudio = Data()
    private var outboundChunks: [AudioChunk] = []
    private var sendInFlight = false
    private var commitRequested = false
    private var commitDispatched = false
    private var finalContinuation: CheckedContinuation<String, Error>?
    private var terminalResult: Result<String, Error>?

    var onPartialUpdate: ((String) -> Void)?
    let pcmSampleRate: Double = 16_000
    private let targetChunkBytes = 16_000 // 500 ms, mono PCM16 at 16 kHz.
    private let heldChunkBytes = 3_200 // Keep 100 ms for the manual commit.

    init(
        config: Configuration,
        session: URLSession = .shared,
        transportFactory: TransportFactory? = nil,
        finalizationTimeout: TimeInterval = 10,
        timeoutScheduler: @escaping TimeoutScheduler = ElevenLabsRealtimeTranscriptionService.scheduleFinalizationTimeout
    ) {
        self.config = config
        self.makeTransport = transportFactory ?? {
            URLSessionRealtimeWebSocketTransport(request: $0, session: session)
        }
        self.finalizationTimeout = finalizationTimeout
        self.scheduleTimeout = timeoutScheduler
    }

    func start() throws {
        let trimmedKey = config.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else { throw RealtimeTranscriptionError.missingAPIKey }
        guard let wsURL = Self.deriveWebSocketURL(
            baseURL: config.baseURL,
            model: config.model,
            language: config.language
        ) else {
            throw RealtimeTranscriptionError.invalidBaseURL(config.baseURL)
        }
        var request = URLRequest(url: wsURL)
        request.setValue(trimmedKey, forHTTPHeaderField: "xi-api-key")

        try stateQueue.sync {
            if let terminalResult {
                _ = try terminalResult.get()
                throw RealtimeTranscriptionError.notConnected
            }
            guard transport == nil else { return }
            let transport = makeTransport(request)
            self.transport = transport
            transport.resume()
            receiveTask = Task { [weak self] in
                await self?.receiveLoop(transport: transport)
            }
        }
    }

    /// Cancellation is terminal even when finalization has not started yet.
    func cancel() {
        stateQueue.sync { finishLocked(.failure(CancellationError())) }
    }

    func appendPCM16(_ data: Data) {
        guard !data.isEmpty else { return }
        stateQueue.sync {
            guard transport != nil, !commitRequested, terminalResult == nil else { return }
            pendingAudio.append(data)
            while pendingAudio.count >= targetChunkBytes + heldChunkBytes {
                outboundChunks.append(AudioChunk(data: Data(pendingAudio.prefix(targetChunkBytes)), commit: false))
                pendingAudio.removeFirst(targetChunkBytes)
            }
            sendNextLocked()
        }
    }

    func commitAndAwaitFinal() async throws -> String {
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                stateQueue.sync {
                    if let terminalResult {
                        continuation.resume(with: terminalResult)
                        return
                    }
                    guard transport != nil else {
                        continuation.resume(throwing: RealtimeTranscriptionError.notConnected)
                        return
                    }
                    guard finalContinuation == nil else {
                        continuation.resume(throwing: RealtimeTranscriptionError.alreadyFinalizing)
                        return
                    }
                    finalContinuation = continuation
                    commitRequested = true
                    // No audio still needs a nonempty commit frame. Otherwise
                    // the held audio forms the final chunk, with no added silence.
                    let finalChunk = pendingAudio.isEmpty
                        ? Data(repeating: 0, count: heldChunkBytes)
                        : pendingAudio
                    pendingAudio.removeAll(keepingCapacity: false)
                    outboundChunks.append(AudioChunk(data: finalChunk, commit: true))
                    cancelTimeout = scheduleTimeout(finalizationTimeout) { [weak self] in
                        guard let self else { return }
                        self.stateQueue.sync {
                            self.finishLocked(.failure(RealtimeTranscriptionError.finalizationTimedOut))
                        }
                    }
                    sendNextLocked()
                }
            }
        } onCancel: {
            self.cancel()
        }
    }

    /// Called only on stateQueue. Enqueuing and draining share this queue so
    /// concurrent producers cannot let a commit pass previously accepted audio.
    private func sendNextLocked() {
        guard !sendInFlight, terminalResult == nil,
              let transport, !outboundChunks.isEmpty else { return }
        let chunk = outboundChunks.removeFirst()
        let payload: [String: Any] = [
            "message_type": "input_audio_chunk",
            "audio_base_64": chunk.data.base64EncodedString(),
            "sample_rate": Int(pcmSampleRate),
            "commit": chunk.commit
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let text = String(data: data, encoding: .utf8) else {
            finishLocked(.failure(RealtimeTranscriptionError.sendFailed))
            return
        }
        sendInFlight = true
        commitDispatched = chunk.commit
        transport.send(text) { [weak self] error in
            guard let self else { return }
            // A transport may complete synchronously. Always queue completion
            // to avoid reentering stateQueue while sendNextLocked is running.
            self.stateQueue.async {
                guard self.terminalResult == nil else { return }
                self.sendInFlight = false
                if error != nil {
                    os_log(.error, log: realtimeLog, "ElevenLabs realtime audio send failed")
                    self.finishLocked(.failure(RealtimeTranscriptionError.sendFailed))
                } else {
                    self.sendNextLocked()
                }
            }
        }
    }

    private func receiveLoop(transport: RealtimeWebSocketTransport) async {
        while !Task.isCancelled {
            do {
                let text = try await transport.receive()
                handleServerEvent(text)
            } catch {
                stateQueue.sync {
                    finishLocked(.failure(RealtimeTranscriptionError.closedBeforeFinal))
                }
                return
            }
        }
    }

    private func handleServerEvent(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let eventType = json["message_type"] as? String else { return }
        stateQueue.sync {
            guard terminalResult == nil else { return }
            switch eventType {
            case "partial_transcript":
                partialText = (json["text"] as? String) ?? (json["partial_transcript"] as? String) ?? ""
                reportPartialLocked(joinedTranscriptLocked())
            case "committed_transcript", "committed_transcript_with_timestamps":
                let transcript = (json["text"] as? String) ?? (json["transcript"] as? String) ?? ""
                let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    if !finalText.isEmpty { finalText += " " }
                    finalText += trimmed
                }
                partialText = ""
                reportPartialLocked(finalText)
                // Earlier segments can complete while queued audio is draining.
                // They are not the response to our final manual commit.
                if commitDispatched { finishLocked(.success(finalText)) }
            default:
                if eventType.lowercased().contains("error") {
                    // Provider-controlled messages and codes can contain user
                    // content or credentials. Never retain them in an error or log.
                    os_log(.error, log: realtimeLog, "ElevenLabs server rejected realtime transcription request")
                    finishLocked(.failure(RealtimeTranscriptionError.serverError))
                }
            }
        }
    }

    private func finishLocked(_ result: Result<String, Error>) {
        guard terminalResult == nil else { return }
        terminalResult = result
        let continuation = finalContinuation
        finalContinuation = nil
        let transport = self.transport
        self.transport = nil
        outboundChunks.removeAll(keepingCapacity: false)
        pendingAudio.removeAll(keepingCapacity: false)
        let receiveTask = self.receiveTask
        self.receiveTask = nil
        let cancelTimeout = self.cancelTimeout
        self.cancelTimeout = nil
        cancelTimeout?()
        receiveTask?.cancel()
        transport?.cancel()
        continuation?.resume(with: result)
    }

    private func reportPartialLocked(_ text: String) {
        guard let handler = onPartialUpdate else { return }
        DispatchQueue.main.async { handler(text) }
    }

    private func joinedTranscriptLocked() -> String {
        if finalText.isEmpty { return partialText }
        if partialText.isEmpty { return finalText }
        return finalText + " " + partialText
    }

    private static func scheduleFinalizationTimeout(
        seconds: TimeInterval,
        action: @escaping () -> Void
    ) -> (() -> Void) {
        let workItem = DispatchWorkItem(block: action)
        DispatchQueue.global().asyncAfter(deadline: .now() + seconds, execute: workItem)
        return { workItem.cancel() }
    }

    static func deriveWebSocketURL(
        baseURL: String,
        model: String,
        language: String?
    ) -> URL? {
        let trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: trimmed),
              let host = components.host, !host.isEmpty else { return nil }
        switch components.scheme?.lowercased() {
        case "http": components.scheme = "ws"
        case "https": components.scheme = "wss"
        case "ws", "wss": break
        default: return nil
        }
        var path = components.path
        if path.hasSuffix("/") { path.removeLast() }
        if !path.hasSuffix("/speech-to-text/realtime") { path += "/speech-to-text/realtime" }
        components.path = path
        var queryItems = components.queryItems ?? []
        func setQueryItem(_ name: String, _ value: String?) {
            queryItems.removeAll { $0.name == name }
            if let value { queryItems.append(URLQueryItem(name: name, value: value)) }
        }
        let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        setQueryItem("model_id", trimmedModel.isEmpty ? TranscriptionService.defaultElevenLabsRealtimeModel : trimmedModel)
        setQueryItem("commit_strategy", "manual")
        setQueryItem("audio_format", "pcm_16000")
        let trimmedLanguage = language?.trimmingCharacters(in: .whitespacesAndNewlines)
        setQueryItem("language_code", trimmedLanguage?.isEmpty == false ? trimmedLanguage : nil)
        components.queryItems = queryItems
        return components.url
    }
}
