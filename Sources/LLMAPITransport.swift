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

    // MARK: - Connection Pre-warming

    /// One-shot session opened while the user is still speaking so the
    /// transcription upload does not pay DNS + TCP + TLS setup on the
    /// critical stop-to-paste path. Guarded by sessionsLock.
    private static var prewarmedUploadSession: (session: URLSession, host: String, resourceTimeout: TimeInterval)?

    /// Opens a connection to `baseURL`'s host on a fresh session and holds
    /// that session for the next upload to the same host. Safe to call on
    /// every recording start; failures are ignored — the response is
    /// irrelevant (401/404 are fine), only the handshake matters.
    static func prewarmUploadConnection(to baseURL: URL, expectedRequestTimeout: TimeInterval) {
        let timeout = max(expectedRequestTimeout, minimumResourceTimeout)
        let session = makeEphemeralSession(resourceTimeout: timeout)

        sessionsLock.lock()
        let previous = prewarmedUploadSession?.session
        prewarmedUploadSession = (session, baseURL.host ?? "", timeout)
        sessionsLock.unlock()
        previous?.finishTasksAndInvalidate()

        var request = URLRequest(url: baseURL)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 10
        Task {
            _ = try? await session.data(for: request)
        }
    }

    /// Warms the shared data session for `baseURL`'s host so the first
    /// post-processing call after idle reuses an open connection. The
    /// timeout must match the real requests' so the same session is used.
    static func prewarmSharedConnection(to baseURL: URL, expectedRequestTimeout: TimeInterval) {
        var request = URLRequest(url: baseURL)
        request.httpMethod = "HEAD"
        request.timeoutInterval = expectedRequestTimeout
        Task {
            _ = try? await data(for: request)
        }
    }

    private static func takePrewarmedUploadSession(for request: URLRequest) -> URLSession? {
        sessionsLock.lock()
        defer { sessionsLock.unlock() }
        guard let candidate = prewarmedUploadSession,
              candidate.host == request.url?.host,
              candidate.resourceTimeout == resourceTimeout(for: request) else {
            return nil
        }
        prewarmedUploadSession = nil
        return candidate.session
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
        // Prefer the session prewarmed at recording start (skips the TLS
        // handshake); otherwise use a fresh session. Either way the session
        // serves exactly one upload, so a bad reused connection cannot
        // poison subsequent transcription uploads.
        let session = takePrewarmedUploadSession(for: request)
            ?? makeEphemeralSession(resourceTimeout: resourceTimeout(for: request))
        defer { session.finishTasksAndInvalidate() }
        return try await session.upload(for: request, from: bodyData)
    }
}
