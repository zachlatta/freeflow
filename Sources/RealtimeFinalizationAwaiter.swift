import Foundation

enum RealtimeFinalizationError: LocalizedError, Equatable {
    case timedOut

    var errorDescription: String? {
        switch self {
        case .timedOut:
            return "Realtime transcription timed out while waiting for the final transcript"
        }
    }
}

final class RealtimeFinalizationAwaiter {
    private let timeoutNanoseconds: UInt64
    private let lock = NSLock()
    private var continuation: CheckedContinuation<String, Error>?
    private var completedResult: Result<String, Error>?
    private var deadlineTask: Task<Void, Never>?
    private let onContinuationRegistered: (() -> Void)?

    /// - Parameter onContinuationRegistered: Test seam invoked (outside the
    ///   lock) after a waiter's continuation and deadline are installed, so
    ///   tests can cancel or resolve a registered wait without racing sleeps.
    init(timeoutNanoseconds: UInt64, onContinuationRegistered: (() -> Void)? = nil) {
        self.timeoutNanoseconds = timeoutNanoseconds
        self.onContinuationRegistered = onContinuationRegistered
    }

    func wait() async throws -> String {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                var immediateResult: Result<String, Error>?
                var registered = false

                lock.lock()
                if let completedResult {
                    immediateResult = completedResult
                } else {
                    self.continuation = continuation
                    registered = true
                    deadlineTask = Task { [weak self] in
                        do {
                            try await Task.sleep(nanoseconds: self?.timeoutNanoseconds ?? 0)
                        } catch {
                            return
                        }
                        self?.resolve(.failure(RealtimeFinalizationError.timedOut))
                    }
                }
                lock.unlock()

                if let immediateResult {
                    continuation.resume(with: immediateResult)
                } else if registered {
                    onContinuationRegistered?()
                }
            }
        } onCancel: {
            resolve(.failure(CancellationError()))
        }
    }

    func resolve(_ result: Result<String, Error>) {
        let pendingContinuation: CheckedContinuation<String, Error>?
        let pendingDeadline: Task<Void, Never>?

        lock.lock()
        guard completedResult == nil else {
            lock.unlock()
            return
        }
        completedResult = result
        pendingContinuation = continuation
        continuation = nil
        pendingDeadline = deadlineTask
        deadlineTask = nil
        lock.unlock()

        pendingDeadline?.cancel()
        pendingContinuation?.resume(with: result)
    }
}
