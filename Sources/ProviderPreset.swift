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

    /// Forms may contain raw whitespace or a blank URL that means the default.
    /// Normalize before pinning inherited values into explicit overrides.
    public var normalizedDraft: ProviderSettingsSnapshot {
        let url = apiBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        return ProviderSettingsSnapshot(
            apiBaseURL: url.isEmpty ? APIConfigurationSaveFlow.defaultBaseURL : url,
            apiKey: apiKey.trimmingCharacters(in: .whitespacesAndNewlines),
            transcriptionAPIURL: transcriptionAPIURL.trimmingCharacters(in: .whitespacesAndNewlines),
            transcriptionAPIKey: transcriptionAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        )
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

    /// Why the preset cannot be applied to the current settings.
    public enum Blocker: Equatable {
        /// Transcription would end up sending a key that is not its own: with
        /// no transcription key set, the transcription key falls back to the
        /// LLM key, so once the Atlas Cloud key is entered it would be sent to
        /// the transcription host.
        case transcriptionKeyRequired
        /// Transcription would resolve to Atlas Cloud, which has no
        /// transcription endpoint.
        case separateTranscriptionRequired

        public var message: String {
            switch self {
            case .transcriptionKeyRequired:
                return "Enter a Transcription API Key first. Without one, your Atlas Cloud key would be sent to the transcription provider."
            case .separateTranscriptionRequired:
                return "Atlas Cloud has no transcription endpoint. Set a separate Transcription API URL and Transcription API Key first."
            }
        }
    }

    /// Returns why the preset cannot be applied yet, or nil when it can.
    ///
    /// The transcription URL/key pair must be explicit and must not be Atlas
    /// Cloud, because an empty transcription override resolves to the LLM URL
    /// or key, and those are exactly what the preset changes.
    public static func blocker(for current: ProviderSettingsSnapshot) -> Blocker? {
        let urlOverride = current.transcriptionAPIURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let keyOverride = current.transcriptionAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)

        if isAtlasCloud(baseURL: current.apiBaseURL) {
            // Already on Atlas Cloud: nothing is being pinned, so both halves
            // must already be set by the user and point somewhere else.
            if urlOverride.isEmpty || isAtlasCloud(baseURL: urlOverride) {
                return .separateTranscriptionRequired
            }
            return keyOverride.isEmpty ? .transcriptionKeyRequired : nil
        }

        if isAtlasCloud(baseURL: current.effectiveTranscriptionBaseURL) {
            return .separateTranscriptionRequired
        }
        // The key we would pin must be a real one; an empty value cannot be
        // pinned because empty means "inherit the LLM key".
        return current.effectiveTranscriptionAPIKey.isEmpty ? .transcriptionKeyRequired : nil
    }

    /// Applies the preset to saved settings and the unsaved key field together.
    /// A blocked or already-selected preset preserves the user's draft; crossing
    /// to Atlas clears it even when the saved key was empty before the change.
    public static func applyingAtlasCloud(
        to current: ProviderSettingsSnapshot,
        apiKeyDraft: String
    ) -> (settings: ProviderSettingsSnapshot, apiKeyDraft: String) {
        let next = applyingAtlasCloud(to: current)
        let changedEndpoint = next.apiBaseURL != current.apiBaseURL
        return (next, changedEndpoint ? "" : apiKeyDraft)
    }

    /// Settings after choosing the Atlas Cloud preset.
    ///
    /// Returns `current` unchanged when `blocker(for:)` is non-nil.
    ///
    /// When the LLM endpoint changes, the key saved for the previous provider
    /// is cleared so it can never be sent to Atlas Cloud; the user has to enter
    /// an Atlas Cloud key. Transcription is not moved: any empty transcription
    /// override is pinned to the URL / key it was already resolving to, and an
    /// override that is already set is left as it is, so the transcription
    /// URL/key pair is exactly the one in use before the preset.
    public static func applyingAtlasCloud(to current: ProviderSettingsSnapshot) -> ProviderSettingsSnapshot {
        guard blocker(for: current) == nil else { return current }
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

/// Lets an in-flight API key validation be discarded when the provider changes
/// underneath it. A validation captures a token before it starts; changing the
/// provider (for example choosing a preset) invalidates every earlier token,
/// and a result is only applied while its token is still current.
public final class KeyValidationGate: @unchecked Sendable {
    private let lock = NSLock()
    private var generation = 0

    public init() {}

    public func begin() -> Int {
        lock.lock()
        defer { lock.unlock() }
        generation += 1
        return generation
    }

    public func invalidate() {
        lock.lock()
        defer { lock.unlock() }
        generation += 1
    }

    /// A field commit that only loses focus must not cancel a current validation.
    /// An actual endpoint edit or reset must discard the previous result.
    public func invalidateIfEndpointChanged(from previous: String, to next: String) {
        if previous != next { invalidate() }
    }

    /// Runs `apply` and returns true only if no provider change happened since
    /// `token` was issued. Must be called where `apply` is allowed to run.
    @discardableResult
    public func applyIfCurrent(_ token: Int, _ apply: () -> Void) -> Bool {
        lock.lock()
        let isCurrent = token == generation
        lock.unlock()
        guard isCurrent else { return false }
        apply()
        return true
    }
}
