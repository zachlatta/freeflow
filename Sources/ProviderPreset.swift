import Foundation

/// The provider-related settings that a one-click provider preset can change.
///
/// Kept free of SwiftUI so the credential handling can be tested with
/// synthetic values. `effectiveTranscriptionBaseURL` and
/// `effectiveTranscriptionAPIKey` are the same resolution `AppState` uses when
/// it builds the transcription service: an empty override falls back to the
/// LLM provider's URL / key.
public struct ProviderSettingsSnapshot: Equatable {
    public var apiBaseURL: String
    public var apiKey: String
    public var transcriptionAPIURL: String
    public var transcriptionAPIKey: String

    public init(apiBaseURL: String, apiKey: String, transcriptionAPIURL: String, transcriptionAPIKey: String) {
        self.apiBaseURL = apiBaseURL
        self.apiKey = apiKey
        self.transcriptionAPIURL = transcriptionAPIURL
        self.transcriptionAPIKey = transcriptionAPIKey
    }

    public var effectiveTranscriptionBaseURL: String {
        let trimmed = transcriptionAPIURL.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? apiBaseURL : trimmed
    }

    public var effectiveTranscriptionAPIKey: String {
        let trimmed = transcriptionAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? apiKey : trimmed
    }
}

public enum ProviderPreset {
    public static let atlasCloudAPIBaseURL = "https://api.atlascloud.ai/v1"
    private static let atlasCloudHost = "api.atlascloud.ai"

    /// Atlas Cloud serves this model with image input, and it is already the
    /// model FreeFlow uses for screenshot context, so one ID covers cleanup,
    /// fallback and context without adding a model configuration.
    public static let atlasCloudModel = "qwen/qwen3.8-27b"

    public static func isAtlasCloud(baseURL: String) -> Bool {
        guard let url = URL(string: baseURL.trimmingCharacters(in: .whitespacesAndNewlines)),
              url.scheme?.lowercased() == "https" else { return false }
        return url.host?.lowercased() == atlasCloudHost
    }

    /// Settings after choosing the Atlas Cloud preset.
    ///
    /// When the LLM endpoint changes, the key saved for the previous provider
    /// is cleared so it can never be sent to Atlas Cloud; the user has to enter
    /// an Atlas Cloud key. Transcription is not moved: any empty transcription
    /// override is pinned to the URL / key it was already resolving to, and an
    /// override that is already set is left as it is, so the transcription
    /// URL/key pair is exactly the one in use before the preset.
    public static func applyingAtlasCloud(to current: ProviderSettingsSnapshot) -> ProviderSettingsSnapshot {
        var result = current
        guard !isAtlasCloud(baseURL: current.apiBaseURL) else {
            return result
        }

        let previous = current
        if previous.transcriptionAPIURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            result.transcriptionAPIURL = previous.effectiveTranscriptionBaseURL
        }
        if previous.transcriptionAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            result.transcriptionAPIKey = previous.effectiveTranscriptionAPIKey
        }
        result.apiBaseURL = atlasCloudAPIBaseURL
        result.apiKey = ""
        return result
    }
}
