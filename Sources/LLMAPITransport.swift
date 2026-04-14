import Foundation

enum LLMAPITransport {
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
        for request: URLRequest
    ) async throws -> (Data, URLResponse) {
        try await requestSession.data(for: request)
    }

    static func upload(
        for request: URLRequest,
        from bodyData: Data
    ) async throws -> (Data, URLResponse) {
        // Use a fresh session for each upload so a bad reused connection cannot
        // poison subsequent transcription uploads.
        let session = makeEphemeralSession()
        defer { session.finishTasksAndInvalidate() }
        return try await session.upload(for: request, from: bodyData)
    }
}
