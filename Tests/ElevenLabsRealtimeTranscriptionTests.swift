import Foundation

// These fixtures are synthetic. The transport never opens a network connection.
enum ElevenLabsRealtimeTranscriptionTests {
    static func run() async throws {
        let watchdog = DispatchWorkItem { fatalError("Realtime fixtures exceeded their 15-second deadline") }
        DispatchQueue.global().asyncAfter(deadline: .now() + 15, execute: watchdog)
        defer { watchdog.cancel() }
        try testRequestConfiguration()
        try await testPartialAndCommittedEvents()
        try await testAudioAndCommitRemainOrdered()
        try await testCancellationBeforeFinalization()
        try await testCancellationDuringFinalization()
        try await testCallerTaskCancellation()
        try await testStalledFinalizationTimesOut()
        try await testEarlyClose()
        try await testSendFailure()
        try await testServerErrorIsSanitized()
    }

    private static func configuration(
        baseURL: String = "https://elevenlabs.invalid/v1",
        apiKey: String = "synthetic-key",
        model: String = "scribe_v2_realtime",
        language: String? = nil
    ) -> ElevenLabsRealtimeTranscriptionService.Configuration {
        .init(baseURL: baseURL, apiKey: apiKey, model: model, language: language)
    }

    private static func service(
        _ socket: FakeRealtimeWebSocket,
        timer: ManualRealtimeTimeout = ManualRealtimeTimeout(),
        config: ElevenLabsRealtimeTranscriptionService.Configuration = configuration()
    ) -> ElevenLabsRealtimeTranscriptionService {
        ElevenLabsRealtimeTranscriptionService(
            config: config,
            transportFactory: { request in
                socket.recordRequest(request)
                return socket
            },
            finalizationTimeout: 10,
            timeoutScheduler: timer.schedule
        )
    }

    private static func testRequestConfiguration() throws {
        let socket = FakeRealtimeWebSocket()
        let client = service(socket, config: configuration(
            baseURL: " https://elevenlabs.invalid/prefix/v1/?model_id=stale&commit_strategy=vad&audio_format=other&language_code=old&custom=synthetic ",
            apiKey: " synthetic-key ",
            model: " custom-synthetic-model ",
            language: " da "
        ))
        try client.start()
        defer { client.cancel() }
        let request = socket.request!
        let components = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!
        TestSupport.expectEqual(components.scheme, "wss")
        TestSupport.expectEqual(components.path, "/prefix/v1/speech-to-text/realtime")
        let query = Dictionary(uniqueKeysWithValues: components.queryItems!.map { ($0.name, $0.value ?? "") })
        TestSupport.expectEqual(query["model_id"], "custom-synthetic-model")
        TestSupport.expectEqual(query["commit_strategy"], "manual")
        TestSupport.expectEqual(query["audio_format"], "pcm_16000")
        TestSupport.expectEqual(query["language_code"], "da")
        TestSupport.expectEqual(query["custom"], "synthetic")
        TestSupport.expectEqual(request.value(forHTTPHeaderField: "xi-api-key"), "synthetic-key")
        TestSupport.expectEqual(request.value(forHTTPHeaderField: "Authorization"), nil)
        TestSupport.expectEqual(client.pcmSampleRate, 16_000)
        TestSupport.expectEqual(socket.resumeCount, 1)
        TestSupport.expectEqual(socket.sentCount, 0)

        let defaultURL = ElevenLabsRealtimeTranscriptionService.deriveWebSocketURL(
            baseURL: "http://elevenlabs.invalid/v1/speech-to-text/realtime?language_code=stale",
            model: " \n ", language: " "
        )!
        let defaultComponents = URLComponents(url: defaultURL, resolvingAgainstBaseURL: false)!
        TestSupport.expectEqual(defaultComponents.scheme, "ws")
        TestSupport.expectEqual(defaultComponents.path, "/v1/speech-to-text/realtime")
        TestSupport.expectEqual(defaultComponents.queryItems?.first { $0.name == "model_id" }?.value, "scribe_v2_realtime")
        TestSupport.expect(!defaultComponents.queryItems!.contains { $0.name == "language_code" }, "Empty language must not reuse a stale URL value")
        TestSupport.expectEqual(ElevenLabsRealtimeTranscriptionService.deriveWebSocketURL(baseURL: "file:///synthetic", model: "", language: nil), nil)
        TestSupport.expectEqual(ElevenLabsRealtimeTranscriptionService.deriveWebSocketURL(baseURL: "https:///synthetic", model: "", language: nil), nil)

        let missingKey = service(FakeRealtimeWebSocket(), config: configuration(apiKey: " \n "))
        do {
            try missingKey.start()
            TestSupport.expect(false, "Missing API key must fail before creating a connection")
        } catch let error as RealtimeTranscriptionError {
            guard case .missingAPIKey = error else { throw error }
        }

        // The original provider's request shape and sample rate stay unchanged.
        let originalURL = RealtimeTranscriptionService.deriveWebSocketURL(baseURL: "https://openai.invalid/v1", model: "synthetic", language: nil)!
        TestSupport.expectEqual(originalURL.path, "/v1/realtime")
        TestSupport.expectEqual(URLComponents(url: originalURL, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "intent" }?.value, "transcription")
        let original = RealtimeTranscriptionService(config: .init(baseURL: "https://openai.invalid/v1", apiKey: "", model: "synthetic", language: nil))
        TestSupport.expectEqual(original.pcmSampleRate, 24_000)
    }

    private static func testPartialAndCommittedEvents() async throws {
        let socket = FakeRealtimeWebSocket()
        let client = service(socket)
        let updates = RealtimeTestEvents<String>()
        client.onPartialUpdate = { updates.push($0) }
        try client.start()
        socket.emit(["message_type": "partial_transcript", "text": "Syn"])
        let update1 = await updates.next()
        TestSupport.expectEqual(update1, "Syn")
        socket.emit(["message_type": "partial_transcript", "partial_transcript": "Synthetic"])
        let update2 = await updates.next()
        TestSupport.expectEqual(update2, "Synthetic")
        socket.emit(["message_type": "committed_transcript", "text": " First segment. "])
        let update3 = await updates.next()
        TestSupport.expectEqual(update3, "First segment.")
        socket.emit(["message_type": "partial_transcript", "text": "Second"])
        let update4 = await updates.next()
        TestSupport.expectEqual(update4, "First segment. Second")
        client.appendPCM16(Data([1, 0, 2, 0]))
        let final = Task { try await client.commitAndAwaitFinal() }
        let chunk = await socket.nextSent()
        TestSupport.expectEqual(chunk["commit"] as? Bool, true)
        TestSupport.expectEqual(chunk["sample_rate"] as? Int, 16_000)
        TestSupport.expectEqual(Data(base64Encoded: chunk["audio_base_64"] as! String), Data([1, 0, 2, 0]))
        TestSupport.expectEqual(chunk["message_type"] as? String, "input_audio_chunk")
        socket.emit(["message_type": "committed_transcript_with_timestamps", "transcript": "Second segment.", "words": []])
        let finalValue5 = try await final.value
        TestSupport.expectEqual(finalValue5, "First segment. Second segment.")
        let update6 = await updates.next()
        TestSupport.expectEqual(update6, "First segment. Second segment.")
        TestSupport.expectEqual(socket.cancelCount, 1)
        client.cancel()
        TestSupport.expectEqual(socket.cancelCount, 1)
    }

    private static func testAudioAndCommitRemainOrdered() async throws {
        let socket = FakeRealtimeWebSocket(automaticallyCompleteSends: false)
        let timer = ManualRealtimeTimeout()
        let client = service(socket, timer: timer)
        let updates = RealtimeTestEvents<String>()
        client.onPartialUpdate = { updates.push($0) }
        try client.start()
        let first = Data(repeating: 1, count: 16_000)
        let second = Data(repeating: 2, count: 16_000)
        let held = Data(repeating: 3, count: 3_200)
        client.appendPCM16(first + second + held)
        let firstMessage = await socket.nextSent()
        let final = Task { try await client.commitAndAwaitFinal() }
        await timer.waitUntilScheduled()
        TestSupport.expectEqual(socket.sentCount, 1)
        TestSupport.expectEqual(firstMessage["commit"] as? Bool, false)
        TestSupport.expectEqual(Data(base64Encoded: firstMessage["audio_base_64"] as! String), first)

        // A preceding segment can complete while the commit is still queued.
        socket.emit(["message_type": "committed_transcript", "text": "Earlier segment."])
        let update7 = await updates.next()
        TestSupport.expectEqual(update7, "Earlier segment.")
        TestSupport.expectEqual(socket.cancelCount, 0)
        socket.completeNextSend()
        let secondMessage = await socket.nextSent()
        TestSupport.expectEqual(secondMessage["commit"] as? Bool, false)
        TestSupport.expectEqual(Data(base64Encoded: secondMessage["audio_base_64"] as! String), second)
        socket.completeNextSend()
        let commitMessage = await socket.nextSent()
        TestSupport.expectEqual(commitMessage["commit"] as? Bool, true)
        TestSupport.expectEqual(Data(base64Encoded: commitMessage["audio_base_64"] as! String), held)
        client.appendPCM16(Data(repeating: 4, count: 20_000))
        socket.completeNextSend()
        socket.emit(["message_type": "committed_transcript", "text": "Final segment."])
        let finalValue8 = try await final.value
        TestSupport.expectEqual(finalValue8, "Earlier segment. Final segment.")
        TestSupport.expectEqual(socket.sentCount, 3)
        TestSupport.expectEqual(timer.cancelCount, 1)
    }

    private static func testCancellationBeforeFinalization() async throws {
        let socket = FakeRealtimeWebSocket()
        let client = service(socket)
        try client.start()
        client.cancel()
        client.cancel()
        await expectCancellation { try await client.commitAndAwaitFinal() }
        TestSupport.expectEqual(socket.sentCount, 0)
        TestSupport.expectEqual(socket.cancelCount, 1)
    }

    private static func testCancellationDuringFinalization() async throws {
        let socket = FakeRealtimeWebSocket(automaticallyCompleteSends: false)
        let timer = ManualRealtimeTimeout()
        let client = service(socket, timer: timer)
        try client.start()
        client.appendPCM16(Data(repeating: 0, count: 19_200))
        _ = await socket.nextSent()
        let final = Task { try await client.commitAndAwaitFinal() }
        await timer.waitUntilScheduled()
        client.cancel()
        await expectCancellation { try await final.value }
        socket.completeNextSend()
        TestSupport.expectEqual(socket.sentCount, 1)
        TestSupport.expectEqual(socket.cancelCount, 1)
        TestSupport.expectEqual(timer.cancelCount, 1)
        timer.fireEvenIfCancelled() // A racing timeout must not overwrite cancellation.
        await expectCancellation { try await client.commitAndAwaitFinal() }
    }

    private static func testCallerTaskCancellation() async throws {
        let socket = FakeRealtimeWebSocket()
        let client = service(socket)
        try client.start()
        let final = Task { try await client.commitAndAwaitFinal() }
        _ = await socket.nextSent()
        final.cancel()
        await expectCancellation { try await final.value }
        TestSupport.expectEqual(socket.cancelCount, 1)
    }

    private static func testStalledFinalizationTimesOut() async throws {
        let socket = FakeRealtimeWebSocket(automaticallyCompleteSends: false)
        let timer = ManualRealtimeTimeout()
        let client = service(socket, timer: timer)
        try client.start()
        let final = Task { try await client.commitAndAwaitFinal() }
        await timer.waitUntilScheduled()
        let commit = await socket.nextSent()
        TestSupport.expectEqual(commit["commit"] as? Bool, true)
        TestSupport.expectEqual(Data(base64Encoded: commit["audio_base_64"] as! String)?.count, 3_200)
        timer.fireEvenIfCancelled()
        await expectError(.finalizationTimedOut) { try await final.value }
        TestSupport.expectEqual(socket.cancelCount, 1)
    }

    private static func testEarlyClose() async throws {
        for closeBeforeCommit in [true, false] {
            let socket = FakeRealtimeWebSocket()
            let timer = ManualRealtimeTimeout()
            let client = service(socket, timer: timer)
            try client.start()
            if closeBeforeCommit { socket.close() }
            let final = Task { try await client.commitAndAwaitFinal() }
            if !closeBeforeCommit {
                _ = await socket.nextSent()
                socket.close()
            }
            await expectError(.closedBeforeFinal) { try await final.value }
            TestSupport.expectEqual(socket.cancelCount, 1)
        }
    }

    private static func testSendFailure() async throws {
        for failCommit in [true, false] {
            let socket = FakeRealtimeWebSocket(automaticallyCompleteSends: false)
            let timer = ManualRealtimeTimeout()
            let client = service(socket, timer: timer)
            try client.start()
            if !failCommit { client.appendPCM16(Data(repeating: 0, count: 19_200)) }
            let final = Task { try await client.commitAndAwaitFinal() }
            _ = await socket.nextSent()
            await timer.waitUntilScheduled()
            socket.completeNextSend(error: SyntheticSocketError())
            await expectError(.sendFailed) { try await final.value }
            TestSupport.expectEqual(socket.sentCount, 1)
            TestSupport.expectEqual(socket.cancelCount, 1)
        }
    }

    private static func testServerErrorIsSanitized() async throws {
        let socket = FakeRealtimeWebSocket()
        let client = service(socket)
        try client.start()
        let final = Task { try await client.commitAndAwaitFinal() }
        _ = await socket.nextSent()
        socket.emit(["message_type": "synthetic-secret-error", "error": "synthetic provider echo containing synthetic-key and synthetic transcript"])
        await expectError(.serverError) { try await final.value }
        TestSupport.expectEqual(RealtimeTranscriptionError.serverError.localizedDescription, "Realtime transcription server rejected the request")
        TestSupport.expect(!RealtimeTranscriptionError.invalidBaseURL("https://private-synthetic.invalid/key").localizedDescription.contains("private-synthetic"), "Errors must not expose configured URLs")
        TestSupport.expect(!RealtimeTranscriptionError.sendFailed.localizedDescription.contains("synthetic"), "Errors must not retain arbitrary network descriptions")
    }

    private static func expectCancellation(_ operation: () async throws -> String) async {
        do {
            _ = try await operation()
            TestSupport.expect(false, "Expected cancellation")
        } catch is CancellationError {
        } catch {
            TestSupport.expect(false, "Expected cancellation, received an unexpected error type")
        }
    }

    private static func expectError(
        _ expected: RealtimeTranscriptionError,
        _ operation: () async throws -> String
    ) async {
        do {
            _ = try await operation()
            TestSupport.expect(false, "Expected realtime failure")
        } catch let error as RealtimeTranscriptionError {
            TestSupport.expectEqual(error.localizedDescription, expected.localizedDescription)
        } catch {
            TestSupport.expect(false, "Expected a realtime error, received an unexpected error type")
        }
    }
}

private struct SyntheticSocketError: LocalizedError {
    var errorDescription: String? { "Synthetic network description containing synthetic-key" }
}

private final class RealtimeTestEvents<Value> {
    private let lock = NSLock()
    private var values: [Value] = []
    private var waiter: CheckedContinuation<Value, Never>?

    func push(_ value: Value) {
        lock.lock()
        let waiter = self.waiter
        self.waiter = nil
        if waiter == nil { values.append(value) }
        lock.unlock()
        waiter?.resume(returning: value)
    }

    func next() async -> Value {
        await withCheckedContinuation { continuation in
            lock.lock()
            if values.isEmpty {
                precondition(waiter == nil, "Fixture has one consumer")
                waiter = continuation
                lock.unlock()
            } else {
                let value = values.removeFirst()
                lock.unlock()
                continuation.resume(returning: value)
            }
        }
    }
}

private final class FakeRealtimeWebSocket: RealtimeWebSocketTransport {
    private let lock = NSLock()
    private let received = RealtimeTestEvents<Result<String, Error>>()
    private let sent = RealtimeTestEvents<[String: Any]>()
    private let automaticallyCompleteSends: Bool
    private var completions: [(Error?) -> Void] = []
    private var recordedRequest: URLRequest?
    private var resumes = 0
    private var sends = 0
    private var cancellations = 0
    private var closed = false

    init(automaticallyCompleteSends: Bool = true) {
        self.automaticallyCompleteSends = automaticallyCompleteSends
    }

    var request: URLRequest? { locked { recordedRequest } }
    var resumeCount: Int { locked { resumes } }
    var sentCount: Int { locked { sends } }
    var cancelCount: Int { locked { cancellations } }

    func recordRequest(_ request: URLRequest) { locked { recordedRequest = request } }
    func resume() { locked { resumes += 1 } }

    func send(_ text: String, completion: @escaping (Error?) -> Void) {
        let json = try! JSONSerialization.jsonObject(with: Data(text.utf8)) as! [String: Any]
        locked {
            sends += 1
            if !automaticallyCompleteSends { completions.append(completion) }
        }
        sent.push(json)
        if automaticallyCompleteSends { completion(nil) }
    }

    func receive() async throws -> String {
        if locked({ closed }) { throw SyntheticSocketError() }
        return try await received.next().get()
    }

    func cancel() {
        locked {
            cancellations += 1
            closed = true
        }
        received.push(.failure(CancellationError()))
    }

    func emit(_ object: [String: Any]) {
        let data = try! JSONSerialization.data(withJSONObject: object)
        received.push(.success(String(data: data, encoding: .utf8)!))
    }

    func close() { received.push(.failure(SyntheticSocketError())) }
    func nextSent() async -> [String: Any] { await sent.next() }

    func completeNextSend(error: Error? = nil) {
        let completion = locked { completions.removeFirst() }
        completion(error)
    }

    private func locked<Value>(_ body: () -> Value) -> Value {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}

private final class ManualRealtimeTimeout {
    private let lock = NSLock()
    private let scheduled = RealtimeTestEvents<Void>()
    private var action: (() -> Void)?
    private var cancellations = 0

    var cancelCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return cancellations
    }

    func schedule(seconds: TimeInterval, action: @escaping () -> Void) -> (() -> Void) {
        TestSupport.expectEqual(seconds, 10)
        lock.lock()
        self.action = action
        lock.unlock()
        scheduled.push(())
        return { [self] in
            lock.lock()
            cancellations += 1
            lock.unlock()
        }
    }

    func waitUntilScheduled() async { await scheduled.next() }

    func fireEvenIfCancelled() {
        lock.lock()
        let action = self.action
        lock.unlock()
        action?()
    }
}
