import Foundation

enum LLMAPITransport {
    /// Floor for the whole-transfer budget so requests that never set an
    /// explicit timeout still fail within a reasonable window.
    private static let minimumResourceTimeout: TimeInterval = 30

    /// Reusable sessions keyed by resource timeout, so connection reuse is
    /// preserved while each request still gets a whole-transfer budget that
    /// honors the caller's configured timeout. Only a handful of distinct
    /// timeout values ever exist (one per timeout setting).
    private static var sessionsByResourceTimeout: [TimeInterval: URLSession] = [:]
    private static let sessionsLock = NSLock()

    private static func makeEphemeralSession(resourceTimeout: TimeInterval) -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = resourceTimeout
        return URLSession(configuration: configuration)
    }

    /// timeoutIntervalForResource caps the entire transfer and has no
    /// per-request override, so derive it from the caller's configured
    /// timeout (e.g. post_processing_timeout_seconds) instead of a fixed cap.
    private static func resourceTimeout(for request: URLRequest) -> TimeInterval {
        max(request.timeoutInterval, minimumResourceTimeout)
    }

    private static func sharedSession(for request: URLRequest) -> URLSession {
        let timeout = resourceTimeout(for: request)
        sessionsLock.lock()
        defer { sessionsLock.unlock() }
        if let existing = sessionsByResourceTimeout[timeout] {
            return existing
        }
        let session = makeEphemeralSession(resourceTimeout: timeout)
        sessionsByResourceTimeout[timeout] = session
        return session
    }

    static func data(
        for request: URLRequest
    ) async throws -> (Data, URLResponse) {
        try await sharedSession(for: request).data(for: request)
    }

    static func upload(
        for request: URLRequest,
        from bodyData: Data
    ) async throws -> (Data, URLResponse) {
        // Use a fresh session for each upload so a bad reused connection cannot
        // poison subsequent transcription uploads.
        let session = makeEphemeralSession(resourceTimeout: resourceTimeout(for: request))
        defer { session.finishTasksAndInvalidate() }
        return try await session.upload(for: request, from: bodyData)
    }
}
