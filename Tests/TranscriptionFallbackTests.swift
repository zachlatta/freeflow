import Foundation

enum TranscriptionFallbackTests {
    static func run() async throws {
        try await testUnavailableRealtimeUsesFile()
        try await testSuccessfulRealtimeSkipsFile()
        try await testSilentRealtimeSkipsFile()
        try await testRealtimeErrorFallsBackInOrder()
        try await testRealtimeFinalizationTimeoutFallsBack()
        try await testFileFailurePropagates()
        try await testRealtimeCancellationSkipsFile()
        try await testTaskCancellationCancelsRealtime()
        try await testCancelledTaskNeverStartsRequest()
    }

    private static func testUnavailableRealtimeUsesFile() async throws {
        var uploadCount = 0
        let result = try await TranscriptionFallback.resolve(realtimeService: nil) {
            uploadCount += 1
            return "Invented batch result."
        }
        TestSupport.expectEqual(result, "Invented batch result.")
        TestSupport.expectEqual(uploadCount, 1)
    }

    private static func testSuccessfulRealtimeSkipsFile() async throws {
        let realtime = SyntheticRealtimeClient { "Invented realtime result." }
        var uploadCount = 0
        let result = try await TranscriptionFallback.resolve(realtimeService: realtime) {
            uploadCount += 1
            return "Unexpected upload."
        }
        TestSupport.expectEqual(result, "Invented realtime result.")
        TestSupport.expectEqual(realtime.commitCount, 1)
        TestSupport.expectEqual(uploadCount, 0)
    }

    private static func testSilentRealtimeSkipsFile() async throws {
        for silence in ["", " \n "] {
            let realtime = SyntheticRealtimeClient { silence }
            var uploadCount = 0
            let result = try await TranscriptionFallback.resolve(realtimeService: realtime) {
                uploadCount += 1
                return "Unexpected upload."
            }
            TestSupport.expectEqual(result, silence)
            TestSupport.expectEqual(uploadCount, 0)
        }
    }

    private static func testRealtimeErrorFallsBackInOrder() async throws {
        let events = SyntheticFallbackEvents()
        let realtime = SyntheticRealtimeClient {
            events.append("realtime")
            throw SyntheticFallbackError.realtime
        }
        let result = try await TranscriptionFallback.resolve(realtimeService: realtime) {
            events.append("upload")
            TestSupport.expectEqual(realtime.cancelCount, 1)
            return "Invented recovered result."
        }
        TestSupport.expectEqual(result, "Invented recovered result.")
        TestSupport.expectEqual(events.values, ["realtime", "upload"])
    }

    private static func testRealtimeFinalizationTimeoutFallsBack() async throws {
        // The realtime service owns its deadline. A stalled finalization
        // reports an error through the same seam as other realtime failures.
        let realtime = SyntheticRealtimeClient {
            await Task.yield()
            throw RealtimeTranscriptionError.finalizationTimedOut
        }
        var uploadCount = 0
        let result = try await TranscriptionFallback.resolve(realtimeService: realtime) {
            uploadCount += 1
            return "Invented timeout recovery."
        }
        TestSupport.expectEqual(result, "Invented timeout recovery.")
        TestSupport.expectEqual(uploadCount, 1)
        TestSupport.expectEqual(realtime.cancelCount, 1)
    }

    private static func testFileFailurePropagates() async throws {
        let realtime = SyntheticRealtimeClient { throw SyntheticFallbackError.realtime }
        do {
            _ = try await TranscriptionFallback.resolve(realtimeService: realtime) {
                throw SyntheticFallbackError.upload
            }
            TestSupport.expect(false, "Upload failure must propagate")
        } catch SyntheticFallbackError.upload {
        }
    }

    private static func testRealtimeCancellationSkipsFile() async throws {
        let realtime = SyntheticRealtimeClient { throw CancellationError() }
        var uploadCount = 0
        do {
            _ = try await TranscriptionFallback.resolve(realtimeService: realtime) {
                uploadCount += 1
                return "Unexpected upload."
            }
            TestSupport.expect(false, "Realtime cancellation must propagate")
        } catch is CancellationError {
        }
        TestSupport.expectEqual(uploadCount, 0)
    }

    private static func testTaskCancellationCancelsRealtime() async throws {
        let realtime = SuspendedSyntheticRealtimeClient()
        let uploadCount = SyntheticFallbackCounter()
        let task = Task {
            try await TranscriptionFallback.resolve(realtimeService: realtime) {
                uploadCount.increment()
                return "Unexpected upload."
            }
        }
        await realtime.waitUntilCommitting()
        task.cancel()
        do {
            _ = try await task.value
            TestSupport.expect(false, "Cancelled task must not produce a transcript")
        } catch is CancellationError {
        }
        TestSupport.expectEqual(realtime.cancelCount, 1)
        TestSupport.expectEqual(uploadCount.value, 0)
    }

    private static func testCancelledTaskNeverStartsRequest() async throws {
        let requestCount = SyntheticFallbackCounter()
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await TranscriptionFallback.resolve(realtimeService: nil) {
                requestCount.increment()
                return "Unexpected upload."
            }
        }
        do {
            _ = try await task.value
            TestSupport.expect(false, "Already-cancelled task must not start an upload")
        } catch is CancellationError {
        }
        TestSupport.expectEqual(requestCount.value, 0)
    }
}

private enum SyntheticFallbackError: Error {
    case realtime
    case upload
}

private final class SyntheticRealtimeClient: RealtimeTranscriptionClient {
    private let commit: () async throws -> String
    private(set) var commitCount = 0
    private(set) var cancelCount = 0
    let pcmSampleRate: Double = 16_000

    init(commit: @escaping () async throws -> String) {
        self.commit = commit
    }

    func start() throws {}
    func appendPCM16(_ data: Data) {}
    func cancel() { cancelCount += 1 }
    func commitAndAwaitFinal() async throws -> String {
        commitCount += 1
        return try await commit()
    }
}

private final class SuspendedSyntheticRealtimeClient: RealtimeTranscriptionClient {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<String, Error>?
    private var isCommitting = false
    private var closed = false
    private var cancellations = 0
    let pcmSampleRate: Double = 16_000

    var cancelCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return cancellations
    }

    func start() throws {}
    func appendPCM16(_ data: Data) {}

    func cancel() {
        lock.lock()
        guard !closed else {
            lock.unlock()
            return
        }
        closed = true
        cancellations += 1
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(throwing: CancellationError())
    }

    func commitAndAwaitFinal() async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            self.continuation = continuation
            isCommitting = true
            lock.unlock()
        }
    }

    func waitUntilCommitting() async {
        while !committingSnapshot() {
            await Task.yield()
        }
    }

    private func committingSnapshot() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return isCommitting
    }
}

private final class SyntheticFallbackEvents {
    private(set) var values: [String] = []
    func append(_ value: String) { values.append(value) }
}

private final class SyntheticFallbackCounter {
    private let lock = NSLock()
    private var count = 0

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    func increment() {
        lock.lock()
        count += 1
        lock.unlock()
    }
}
