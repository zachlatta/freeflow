import Foundation

/// One-shot async signal: `wait()` returns once `signal()` has been called,
/// regardless of which happens first. Used as an explicit synchronization
/// point instead of competing sleeps.
final class TestAsyncSignal: @unchecked Sendable {
    private let lock = NSLock()
    private var signaled = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func signal() {
        lock.lock()
        signaled = true
        let pending = waiters
        waiters = []
        lock.unlock()
        pending.forEach { $0.resume() }
    }

    func wait() async {
        await withCheckedContinuation { continuation in
            lock.lock()
            if signaled {
                lock.unlock()
                continuation.resume()
                return
            }
            waiters.append(continuation)
            lock.unlock()
        }
    }
}

/// Local in-memory stand-in for a realtime WebSocket. It never touches the
/// network: server events are injected by the test.
private final class FakeRealtimeSocket: RealtimeWebSocketTask, @unchecked Sendable {
    private let lock = NSLock()
    private var inbox: [URLSessionWebSocketTask.Message] = []
    private var receiver: CheckedContinuation<URLSessionWebSocketTask.Message, Error>?
    private var cancelled = false
    private var sent: [String] = []

    var sentEventTypes: [String] {
        lock.lock()
        defer { lock.unlock() }
        return sent
    }

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    func resume() {}

    func send(
        _ message: URLSessionWebSocketTask.Message,
        completionHandler: @escaping @Sendable (Error?) -> Void
    ) {
        if case .string(let text) = message,
           let data = text.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let type = json["type"] as? String {
            lock.lock()
            sent.append(type)
            lock.unlock()
        }
        completionHandler(nil)
    }

    func receive() async throws -> URLSessionWebSocketTask.Message {
        try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            if cancelled {
                lock.unlock()
                continuation.resume(throwing: URLError(.cancelled))
                return
            }
            if !inbox.isEmpty {
                let message = inbox.removeFirst()
                lock.unlock()
                continuation.resume(returning: message)
                return
            }
            receiver = continuation
            lock.unlock()
        }
    }

    func cancel(with closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        lock.lock()
        cancelled = true
        let pending = receiver
        receiver = nil
        lock.unlock()
        pending?.resume(throwing: URLError(.cancelled))
    }

    func deliver(_ event: [String: Any]) {
        let data = try! JSONSerialization.data(withJSONObject: event)
        let message = URLSessionWebSocketTask.Message.string(String(data: data, encoding: .utf8)!)
        lock.lock()
        if let pending = receiver {
            receiver = nil
            lock.unlock()
            pending.resume(returning: message)
            return
        }
        inbox.append(message)
        lock.unlock()
    }
}

private final class FileUploadSpy: @unchecked Sendable {
    private let lock = NSLock()
    private var calls = 0
    let transcript = "synthetic file transcript"

    var callCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return calls
    }

    func transcribe() async throws -> String {
        recordCall()
        return transcript
    }

    private func recordCall() {
        lock.lock()
        calls += 1
        lock.unlock()
    }
}

enum RealtimeTranscriptFallbackTests {
    private static let longTimeout: UInt64 = 60_000_000_000

    static func run() async {
        await testMissingFinalEventTimesOutInService()
        await testMissingFinalEventStartsFileFallback()
        await testFinalTranscriptAvoidsFileFallback()
        await testServerErrorStartsFileFallback()
        await testCancellationAfterRegistrationNeverStartsUpload()
    }

    private static func makeService(
        socket: FakeRealtimeSocket,
        timeoutNanoseconds: UInt64
    ) -> RealtimeTranscriptionService {
        RealtimeTranscriptionService(
            config: .init(
                baseURL: "https://realtime.invalid/v1",
                apiKey: "",
                model: "synthetic-realtime-model",
                language: nil
            ),
            finalizationTimeoutNanoseconds: timeoutNanoseconds,
            makeWebSocketTask: { _ in socket }
        )
    }

    private static func testMissingFinalEventTimesOutInService() async {
        let socket = FakeRealtimeSocket()
        // No competing result is ever delivered, so a zero deadline is the
        // only possible terminal outcome.
        let service = makeService(socket: socket, timeoutNanoseconds: 0)
        do {
            try service.start()
            _ = try await service.commitAndAwaitFinal()
            TestSupport.expect(false, "Expected realtime finalization to time out")
        } catch let error as RealtimeFinalizationError {
            TestSupport.expectEqual(error, .timedOut)
        } catch {
            TestSupport.expect(false, "Expected a realtime finalization timeout, got \(error)")
        }
        TestSupport.expect(socket.isCancelled, "Timed-out realtime socket must be closed")
        TestSupport.expect(
            socket.sentEventTypes.contains("input_audio_buffer.commit"),
            "Expected the realtime commit to be sent before waiting"
        )
    }

    private static func testMissingFinalEventStartsFileFallback() async {
        let socket = FakeRealtimeSocket()
        let service = makeService(socket: socket, timeoutNanoseconds: 0)
        let upload = FileUploadSpy()
        do {
            try service.start()
            let transcript = try await RealtimeTranscriptFallback.resolve(realtime: service) {
                try await upload.transcribe()
            }
            TestSupport.expectEqual(transcript, upload.transcript)
        } catch {
            TestSupport.expect(false, "Expected file fallback after the deadline, got \(error)")
        }
        TestSupport.expectEqual(upload.callCount, 1)
        TestSupport.expect(socket.isCancelled, "Timed-out realtime socket must be closed")
    }

    private static func testFinalTranscriptAvoidsFileFallback() async {
        let socket = FakeRealtimeSocket()
        let service = makeService(socket: socket, timeoutNanoseconds: longTimeout)
        // Deliver the final events only once the wait is registered, so the
        // success path resolves the installed waiter rather than racing it.
        service.onFinalizationWaitRegistered = {
            socket.deliver(["type": "input_audio_buffer.committed", "item_id": "item-1"])
            socket.deliver([
                "type": "conversation.item.input_audio_transcription.completed",
                "item_id": "item-1",
                "transcript": "synthetic realtime transcript",
            ])
        }
        let upload = FileUploadSpy()
        do {
            try service.start()
            let transcript = try await RealtimeTranscriptFallback.resolve(realtime: service) {
                try await upload.transcribe()
            }
            TestSupport.expectEqual(transcript, "synthetic realtime transcript")
        } catch {
            TestSupport.expect(false, "Expected the realtime transcript, got \(error)")
        }
        TestSupport.expectEqual(upload.callCount, 0)
    }

    private static func testServerErrorStartsFileFallback() async {
        let socket = FakeRealtimeSocket()
        let service = makeService(socket: socket, timeoutNanoseconds: longTimeout)
        service.onFinalizationWaitRegistered = {
            socket.deliver([
                "type": "error",
                "error": ["code": "synthetic_code", "message": "synthetic failure"],
            ])
        }
        let upload = FileUploadSpy()
        do {
            try service.start()
            let transcript = try await RealtimeTranscriptFallback.resolve(realtime: service) {
                try await upload.transcribe()
            }
            TestSupport.expectEqual(transcript, upload.transcript)
        } catch {
            TestSupport.expect(false, "Expected file fallback after a server error, got \(error)")
        }
        TestSupport.expectEqual(upload.callCount, 1)
        service.cancel()
    }

    private static func testCancellationAfterRegistrationNeverStartsUpload() async {
        let socket = FakeRealtimeSocket()
        let service = makeService(socket: socket, timeoutNanoseconds: longTimeout)
        let registered = TestAsyncSignal()
        service.onFinalizationWaitRegistered = { registered.signal() }
        let upload = FileUploadSpy()

        do {
            try service.start()
        } catch {
            TestSupport.expect(false, "Expected the fake realtime socket to start, got \(error)")
        }
        let pipeline = Task {
            try await RealtimeTranscriptFallback.resolve(realtime: service) {
                try await upload.transcribe()
            }
        }
        // Explicit synchronization point: cancel only after the finalization
        // continuation is installed. The 60 s deadline cannot win.
        await registered.wait()
        pipeline.cancel()

        do {
            _ = try await pipeline.value
            TestSupport.expect(false, "Expected the cancelled pipeline to throw")
        } catch is CancellationError {
            // Expected.
        } catch {
            TestSupport.expect(false, "Expected CancellationError, got \(error)")
        }
        TestSupport.expectEqual(upload.callCount, 0)
        TestSupport.expect(socket.isCancelled, "Cancelled realtime socket must be closed")
    }
}
