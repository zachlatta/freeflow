import Foundation

enum LLMAPITransport {
    private static func makeEphemeralSession(timeout: TimeInterval) -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        // URLSession's resource timeout is session-scoped, while each caller
        // already puts its configured timeout on the URLRequest. Keep both
        // session timers aligned with that request instead of applying one
        // global timeout to every provider and operation.
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout
        return URLSession(configuration: configuration)
    }

    private static func timeout(for request: URLRequest) -> TimeInterval {
        let requestTimeout = request.timeoutInterval
        guard requestTimeout.isFinite, requestTimeout > 0 else {
            return 60
        }
        return requestTimeout
    }

    static func data(
        for request: URLRequest
    ) async throws -> (Data, URLResponse) {
        let session = makeEphemeralSession(timeout: timeout(for: request))
        defer { session.finishTasksAndInvalidate() }
        return try await session.data(for: request)
    }

    static func upload(
        for request: URLRequest,
        from bodyData: Data
    ) async throws -> (Data, URLResponse) {
        // Fresh session per upload — no poisoned connection re-use.
        let session = makeEphemeralSession(timeout: timeout(for: request))
        defer { session.finishTasksAndInvalidate() }
        return try await session.upload(for: request, from: bodyData)
    }
}
