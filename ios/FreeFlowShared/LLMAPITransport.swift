import Foundation

enum LLMAPITransport {
    private static func makeEphemeralSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 30
        return URLSession(configuration: configuration)
    }

    static func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let session = makeEphemeralSession()
        defer { session.finishTasksAndInvalidate() }
        return try await session.data(for: request)
    }

    static func upload(for request: URLRequest, from bodyData: Data) async throws -> (Data, URLResponse) {
        let session = makeEphemeralSession()
        defer { session.finishTasksAndInvalidate() }
        return try await session.upload(for: request, from: bodyData)
    }
}
