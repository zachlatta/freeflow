import Foundation

enum TranscriptionErrorPresentationCore {
    /// Classifies transcription failures by locale-independent error codes
    /// before falling back to the system's localized description.
    static func message(for error: Error, isOnline: Bool) -> String {
        if let code = urlErrorCode(in: error) {
            switch code {
            case .networkConnectionLost:
                return "Connection lost — retry or try another network"
            case .notConnectedToInternet, .cannotConnectToHost,
                 .cannotFindHost, .dnsLookupFailed:
                return "No internet — check connection"
            case .timedOut:
                return isOnline
                    ? "Request timed out — try again"
                    : "No internet — check connection"
            default:
                break
            }
        }

        let lower = error.localizedDescription.lowercased()
        if lower.contains("timed out") || lower.contains("timeout") {
            return isOnline
                ? "Request timed out — try again"
                : "No internet — check connection"
        }
        if lower.contains("offline") || lower.contains("internet connection")
            || lower.contains("not connected") || lower.contains("network")
            || lower.contains("cannot find host") {
            return "No internet — check connection"
        }
        return error.localizedDescription
    }

    /// Finds a URL error in wrappers used by provider transports.
    private static func urlErrorCode(in error: Error) -> URLError.Code? {
        var current: Error? = error
        var depth = 0
        while let err = current, depth < 8 {
            if let urlError = err as? URLError {
                return urlError.code
            }
            let nsError = err as NSError
            if nsError.domain == NSURLErrorDomain {
                return URLError.Code(rawValue: nsError.code)
            }
            current = nsError.userInfo[NSUnderlyingErrorKey] as? Error
            depth += 1
        }
        return nil
    }
}
