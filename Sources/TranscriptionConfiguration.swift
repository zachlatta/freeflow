import Foundation

/// Resolves transcription settings without reading preferences or credentials.
/// Keeping provider selection here makes the same configuration drive file
/// uploads and realtime sessions, independently of the LLM provider.
struct TranscriptionConfiguration {
    let provider: TranscriptionProvider
    let apiKey: String
    let baseURL: String
    let batchModel: String
    let realtimeModel: String
    let language: String?

    static func resolve(
        provider: TranscriptionProvider,
        apiKey: String,
        apiBaseURL: String,
        transcriptionAPIURL: String,
        transcriptionAPIKey: String,
        elevenLabsAPIKey: String,
        transcriptionModel: String,
        realtimeStreamingModel: String,
        language: String?
    ) -> TranscriptionConfiguration {
        let trimmedLanguage = language?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedLanguage = trimmedLanguage?.isEmpty == false ? trimmedLanguage : nil

        switch provider {
        case .openAICompatible:
            let customKey = transcriptionAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
            let customURL = transcriptionAPIURL.trimmingCharacters(in: .whitespacesAndNewlines)
            let model = transcriptionModel.trimmingCharacters(in: .whitespacesAndNewlines)
            return TranscriptionConfiguration(
                provider: provider,
                apiKey: customKey.isEmpty
                    ? apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
                    : customKey,
                baseURL: customURL.isEmpty
                    ? apiBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
                    : customURL,
                batchModel: model.isEmpty ? "whisper-large-v3" : model,
                realtimeModel: realtimeStreamingModel.trimmingCharacters(in: .whitespacesAndNewlines),
                language: resolvedLanguage
            )
        case .elevenLabs:
            return TranscriptionConfiguration(
                provider: provider,
                apiKey: elevenLabsAPIKey.trimmingCharacters(in: .whitespacesAndNewlines),
                baseURL: TranscriptionService.defaultElevenLabsBaseURL,
                batchModel: TranscriptionService.defaultElevenLabsModel,
                realtimeModel: TranscriptionService.defaultElevenLabsRealtimeModel,
                language: resolvedLanguage
            )
        }
    }
}
