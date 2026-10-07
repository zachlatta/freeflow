import Foundation
import os.log

private let geminiLiveLog = OSLog(subsystem: "com.zachlatta.freeflow", category: "GeminiLiveTranscription")

/// Streams microphone audio to `gemini-3.5-transcribe-live` over the Live API
/// socket and returns the transcript when the dictation ends.
///
/// This is a sibling of ``RealtimeTranscriptionService`` rather than a variant
/// of it: that service speaks the OpenAI realtime protocol, while the Live API
/// exchanges `setup` / `realtimeInput` / `serverContent` frames. The surface is
/// kept identical so ``AppState`` can hold either behind
/// ``RealtimeTranscriptBackend``.
final class GeminiLiveTranscriptionService: RealtimeTranscriptBackend {
    struct Configuration {
        let baseURL: String
        let apiKey: String
        let model: String
        let customVocabulary: String
        /// Matches what ``AudioRecorder`` streams. The model accepts rates
        /// other than 16 kHz as long as the frames declare the real one.
        let sampleRate: Int
    }

    private let config: Configuration
    private let session: URLSession
    private var task: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?

    private let stateQueue = DispatchQueue(label: "com.zachlatta.freeflow.geminilive.state")
    private var transcript: String = ""
    private var finalContinuation: CheckedContinuation<String, Error>?
    private var streamEnded: Bool = false
    private var closed: Bool = false
    private var setupCompleted: Bool = false
    private var terminalError: Error?

    var onPartialUpdate: ((String) -> Void)?

    init(config: Configuration, session: URLSession = .shared) {
        self.config = config
        self.session = session
    }

    // MARK: Lifecycle

    func start() throws {
        guard let url = GeminiLiveTranscription.socketURL(baseURL: config.baseURL) else {
            throw RealtimeTranscriptionError.invalidBaseURL(config.baseURL)
        }

        var request = URLRequest(url: url)
        // The key rides in a header so it never lands in a URL or a log line.
        request.setValue(config.apiKey, forHTTPHeaderField: "x-goog-api-key")

        let socket = session.webSocketTask(with: request)
        stateQueue.sync { task = socket }
        socket.resume()

        let setup = try GeminiLiveTranscription.setupMessage(
            model: config.model,
            customVocabulary: config.customVocabulary
        )
        send(setup, over: socket)

        receiveTask = Task { [weak self] in
            await self?.receiveLoop()
        }
    }

    func cancel() {
        let socket: URLSessionWebSocketTask? = stateQueue.sync {
            closed = true
            let current = task
            task = nil
            return current
        }
        receiveTask?.cancel()
        receiveTask = nil
        socket?.cancel(with: .goingAway, reason: nil)
        resume(with: .failure(CancellationError()))
    }

    func appendPCM16(_ data: Data) {
        let socket: URLSessionWebSocketTask? = stateQueue.sync { closed ? nil : task }
        guard let socket else { return }
        guard let message = try? GeminiLiveTranscription.audioMessage(
            pcm16: data,
            sampleRate: config.sampleRate
        ) else { return }
        send(message, over: socket)
    }

    /// Close the audio stream and wait for the model to finish the turn.
    func commitAndAwaitFinal() async throws -> String {
        let socket: URLSessionWebSocketTask? = stateQueue.sync { closed ? nil : task }
        guard let socket else {
            throw RealtimeTranscriptionError.notConnected
        }

        if let error = stateQueue.sync(execute: { terminalError }) {
            throw error
        }

        return try await withCheckedThrowingContinuation { continuation in
            let alreadyDone: String? = stateQueue.sync {
                if let error = terminalError {
                    continuation.resume(throwing: error)
                    return nil
                }
                guard !streamEnded else { return transcript }
                streamEnded = true
                finalContinuation = continuation
                return nil
            }
            if let alreadyDone {
                continuation.resume(returning: alreadyDone)
                return
            }
            guard stateQueue.sync(execute: { finalContinuation != nil }) else { return }
            guard let end = try? GeminiLiveTranscription.audioStreamEndMessage() else {
                resume(with: .failure(RealtimeTranscriptionError.notConnected))
                return
            }
            send(end, over: socket)
        }
    }

    // MARK: Socket plumbing

    private func send(_ text: String, over socket: URLSessionWebSocketTask) {
        socket.send(.string(text)) { error in
            if let error {
                os_log(.error, log: geminiLiveLog, "send failed: %{public}@", error.localizedDescription)
            }
        }
    }

    private func receiveLoop() async {
        while !Task.isCancelled {
            let socket: URLSessionWebSocketTask? = stateQueue.sync { closed ? nil : task }
            guard let socket else { return }

            do {
                let message = try await socket.receive()
                guard let text = Self.text(from: message) else { continue }
                handle(frame: GeminiLiveTranscription.parseServerFrame(text))
            } catch {
                if Task.isCancelled { return }
                let resolved = Self.describe(error, setupCompleted: stateQueue.sync { setupCompleted })
                let pending: Bool = stateQueue.sync { finalContinuation != nil }
                if pending {
                    resume(with: .failure(resolved))
                } else {
                    stateQueue.sync { terminalError = resolved }
                }
                return
            }
        }
    }

    private func handle(frame: GeminiLiveTranscription.ServerFrame) {
        if frame.isSetupComplete {
            stateQueue.sync { setupCompleted = true }
            return
        }

        if let message = frame.errorMessage {
            os_log(.error, log: geminiLiveLog, "server error: %{public}@", message)
            let error = RealtimeTranscriptionError.serverError(code: "live", message: message)
            let pending: Bool = stateQueue.sync { finalContinuation != nil }
            if pending {
                resume(with: .failure(error))
            } else {
                stateQueue.sync { terminalError = error }
            }
            return
        }

        if let text = frame.transcript, !text.isEmpty {
            let snapshot: String = stateQueue.sync {
                transcript += text
                return transcript
            }
            if let onPartialUpdate {
                DispatchQueue.main.async { onPartialUpdate(snapshot) }
            }
        }

        guard frame.isComplete else { return }
        let snapshot: String = stateQueue.sync { transcript }
        let trimmed = snapshot.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            resume(with: .failure(RealtimeTranscriptionError.closedBeforeFinal))
            return
        }
        resume(with: .success(trimmed))
    }

    private func resume(with result: Result<String, Error>) {
        let continuation: CheckedContinuation<String, Error>? = stateQueue.sync {
            let pending = finalContinuation
            finalContinuation = nil
            return pending
        }
        guard let continuation else { return }
        switch result {
        case .success(let text): continuation.resume(returning: text)
        case .failure(let error): continuation.resume(throwing: error)
        }
    }

    /// The Live API rejects a bad key during the HTTP upgrade, so the socket
    /// simply fails to connect and no error frame ever arrives. Turn that into
    /// something a user can act on instead of "Socket is not connected".
    private static func describe(_ error: Error, setupCompleted: Bool) -> Error {
        // Any failure before the handshake means the session never established,
        // whether it surfaces as a URLError or a raw POSIX socket error.
        guard !setupCompleted else { return error }
        return RealtimeTranscriptionError.serverError(
            code: "live",
            message: "Could not connect to Gemini live transcription. Check the transcription API key."
        )
    }

    private static func text(from message: URLSessionWebSocketTask.Message) -> String? {
        switch message {
        case .string(let text): return text
        case .data(let data): return String(data: data, encoding: .utf8)
        @unknown default: return nil
        }
    }
}
