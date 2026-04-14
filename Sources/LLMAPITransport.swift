import Foundation

enum LLMAPITransport {
    static let defaultMaxAttempts = 2

    private static let transientRetryableErrorCodes: Set<URLError.Code> = [
        .networkConnectionLost,
        .timedOut,
        .cannotConnectToHost,
        .notConnectedToInternet
    ]

    private static let requestSession: URLSession = {
        makeEphemeralSession()
    }()

    private static func makeEphemeralSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 30
        return URLSession(configuration: configuration)
    }

    static func data(
        for request: URLRequest,
        maxAttempts: Int = defaultMaxAttempts
    ) async throws -> (Data, URLResponse) {
        try await perform(maxAttempts: maxAttempts) {
            try await requestSession.data(for: request)
        }
    }

    static func upload(
        for request: URLRequest,
        from bodyData: Data,
        maxAttempts: Int = defaultMaxAttempts
    ) async throws -> (Data, URLResponse) {
        try await perform(maxAttempts: maxAttempts) {
            // Use a fresh session for each upload attempt so a bad reused connection
            // cannot poison subsequent transcription uploads.
            let session = makeEphemeralSession()
            defer { session.finishTasksAndInvalidate() }
            return try await session.upload(for: request, from: bodyData)
        }
    }

    private static func perform<T>(
        maxAttempts: Int,
        operation: () async throws -> T
    ) async throws -> T {
        precondition(maxAttempts > 0, "maxAttempts must be positive")

        var lastError: Error?
        for attempt in 1...maxAttempts {
            do {
                return try await operation()
            } catch {
                lastError = error
                guard shouldRetry(error: error, attempt: attempt, maxAttempts: maxAttempts) else {
                    throw error
                }
                try await Task.sleep(nanoseconds: retryDelayNanoseconds(forAttempt: attempt))
            }
        }

        throw lastError ?? URLError(.unknown)
    }

    private static func shouldRetry(error: Error, attempt: Int, maxAttempts: Int) -> Bool {
        guard attempt < maxAttempts else { return false }
        guard !(error is CancellationError) else { return false }
        guard let urlError = error as? URLError else { return false }
        return transientRetryableErrorCodes.contains(urlError.code)
    }

    private static func retryDelayNanoseconds(forAttempt attempt: Int) -> UInt64 {
        let delaySeconds = min(pow(2.0, Double(attempt - 1)), 2.0)
        return UInt64(delaySeconds * 1_000_000_000)
    }
}
