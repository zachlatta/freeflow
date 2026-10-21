import Foundation

/// Safe diagnostics for the existing local run history. Never include provider
/// response bodies, request URLs, keys, or captured user content.
enum ContextInferenceFailure: Error {
    case httpStatus(Int)
    case invalidResponse
    case emptySummary
    case timeout
    case network
    case missingAPIKey

    var summary: String {
        let reason: String
        switch self {
        case .httpStatus(let status):
            switch status {
            case 401, 403: reason = "Provider rejected authentication (HTTP \(status)). Check your API key and permissions in Settings."
            case 404: reason = "The context model or endpoint is unavailable (HTTP 404). Check the Context Model and API Base URL in Settings."
            case 429: reason = "Provider rate limit reached (HTTP 429). Wait before retrying or reduce context usage."
            case 500...599: reason = "Provider service error (HTTP \(status)). Try again later."
            default: reason = "Provider rejected the context request (HTTP \(status)). Check your context model and provider settings."
            }
        case .invalidResponse: reason = "Provider returned an invalid response. Try again or select another context model."
        case .emptySummary: reason = "Provider returned no usable summary. Try again or select another context model."
        case .timeout: reason = "Provider request timed out. Try again or select a faster context model."
        case .network: reason = "Could not reach the context provider. Check your connection and API Base URL."
        case .missingAPIKey: reason = "No API key is configured. Add an API key in Settings."
        }
        return "Context summary failed: \(reason)"
    }

    static func isFailureSummary(_ summary: String) -> Bool {
        // Include legacy messages so retrying older history entries also
        // omits diagnostic text from post-processing.
        let value = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.hasPrefix("Context summary failed:")
            || value.hasPrefix("Could not reliably infer a two-sentence summary")
            || value.hasPrefix("Could not refresh app context at stop time;")
            || value == "You are dictating in an unrecognized context."
    }

    static func promptSection(for summary: String) -> String {
        let usable = usableSummary(summary).trimmingCharacters(in: .whitespacesAndNewlines)
        return usable.isEmpty ? "" : "CONTEXT: \"\(usable)\"\n"
    }

    static func usableSummary(_ summary: String) -> String {
        isFailureSummary(summary) ? "" : summary
    }
}
