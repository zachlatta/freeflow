import Foundation

enum ProviderURLPolicy {
    static let secureHTTPProviderMessage = "Provider URL must use https unless it points to localhost or a loopback address."
    static let secureWebSocketProviderMessage = "Realtime provider URL must use wss unless it points to localhost or a loopback address."

    static func normalizedHTTPBaseURL(from baseURL: String) throws -> URL {
        let trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ProviderURLPolicyError.empty
        }

        guard var components = URLComponents(string: trimmed) else {
            throw ProviderURLPolicyError.malformed
        }

        guard let scheme = components.scheme?.lowercased(),
              let host = components.host,
              !host.isEmpty else {
            throw ProviderURLPolicyError.malformed
        }

        guard scheme == "https" || (scheme == "http" && isLoopbackHost(host)) else {
            throw ProviderURLPolicyError.insecureScheme
        }

        components.scheme = scheme
        components.path = normalizedPath(components.path)

        guard let normalizedURL = components.url else {
            throw ProviderURLPolicyError.malformed
        }

        return normalizedURL
    }

    static func normalizedRealtimeWebSocketURL(
        from baseURL: String,
        model: String,
        language: String?
    ) -> URL? {
        let trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              let host = components.host,
              !host.isEmpty else {
            return nil
        }

        switch scheme {
        case "https":
            components.scheme = "wss"
        case "wss":
            components.scheme = "wss"
        case "http" where isLoopbackHost(host):
            components.scheme = "ws"
        case "ws" where isLoopbackHost(host):
            components.scheme = "ws"
        default:
            return nil
        }

        var path = normalizedPath(components.path)
        if path.hasSuffix("/v1") {
            path += "/realtime"
        } else {
            path += "/v1/realtime"
        }
        components.path = path

        var queryItems = components.queryItems ?? []
        if !queryItems.contains(where: { $0.name == "intent" }) {
            queryItems.append(URLQueryItem(name: "intent", value: "transcription"))
        }
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        return components.url
    }

    static func isLoopbackHost(_ host: String) -> Bool {
        let normalized = host.trimmingCharacters(in: CharacterSet(charactersIn: "[]")).lowercased()
        return normalized == "localhost"
            || normalized == "::1"
            || normalized == "0:0:0:0:0:0:0:1"
            || normalized == "127.0.0.1"
            || normalized.hasPrefix("127.")
    }

    private static func normalizedPath(_ path: String) -> String {
        if path == "/" {
            return ""
        }
        return path.replacingOccurrences(
            of: "/+$",
            with: "",
            options: .regularExpression
        )
    }
}

enum ProviderURLPolicyError: LocalizedError {
    case empty
    case malformed
    case insecureScheme

    var errorDescription: String? {
        switch self {
        case .empty:
            return "Provider URL is empty."
        case .malformed:
            return "Provider URL is malformed."
        case .insecureScheme:
            return ProviderURLPolicy.secureHTTPProviderMessage
        }
    }
}
