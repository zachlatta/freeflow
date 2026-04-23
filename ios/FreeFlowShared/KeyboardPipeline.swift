import Foundation

struct PipelineContext {
    let apiKey: String
    let baseURL: String
    let transcriptionModel: String
    let postProcessingModel: String
    let postProcessingFallbackModel: String
    let customSystemPrompt: String
    let customVocabulary: String
    let voiceMacros: [VoiceMacro]

    static func load() -> PipelineContext {
        let storage = SharedStorage.shared
        return PipelineContext(
            apiKey: storage.apiKey.trimmingCharacters(in: .whitespacesAndNewlines),
            baseURL: storage.apiBaseURL,
            transcriptionModel: storage.transcriptionModel,
            postProcessingModel: storage.postProcessingModel,
            postProcessingFallbackModel: storage.postProcessingFallbackModel,
            customSystemPrompt: storage.customSystemPrompt,
            customVocabulary: storage.customVocabulary,
            voiceMacros: storage.voiceMacros
        )
    }
}

enum PipelineOutcome {
    case inserted(String)
    case macro(command: String, payload: String)
    case empty
    case failure(String)
}

final class KeyboardPipeline {
    func run(audioURL: URL, context: PipelineContext) async -> PipelineOutcome {
        defer { try? FileManager.default.removeItem(at: audioURL) }

        guard !context.apiKey.isEmpty else {
            return .failure("No API key. Open FreeFlow and paste your Groq key.")
        }

        let rawTranscript: String
        do {
            let service = try TranscriptionService(
                apiKey: context.apiKey,
                baseURL: context.baseURL,
                transcriptionModel: context.transcriptionModel
            )
            rawTranscript = try await service.transcribe(fileURL: audioURL)
        } catch {
            return .failure(error.localizedDescription)
        }

        let trimmed = rawTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            PipelineHistoryStore.shared.append(PipelineHistoryItem(
                rawTranscript: "",
                finalTranscript: "",
                modelUsed: "n/a",
                transcriptionModel: context.transcriptionModel,
                systemPrompt: "",
                note: "empty transcript"
            ))
            return .empty
        }

        if let macro = VoiceMacroMatcher.findMatch(for: trimmed, in: context.voiceMacros) {
            PipelineHistoryStore.shared.append(PipelineHistoryItem(
                rawTranscript: trimmed,
                finalTranscript: macro.payload,
                modelUsed: "voice-macro",
                transcriptionModel: context.transcriptionModel,
                systemPrompt: "",
                note: "macro: \(macro.command)"
            ))
            return .macro(command: macro.command, payload: macro.payload)
        }

        let service = PostProcessingService(
            apiKey: context.apiKey,
            baseURL: context.baseURL,
            preferredModel: context.postProcessingModel,
            preferredFallbackModel: context.postProcessingFallbackModel
        )

        do {
            let result = try await service.postProcess(
                transcript: trimmed,
                customVocabulary: context.customVocabulary,
                customSystemPrompt: context.customSystemPrompt
            )
            let cleaned = result.transcript
            PipelineHistoryStore.shared.append(PipelineHistoryItem(
                rawTranscript: trimmed,
                finalTranscript: cleaned,
                modelUsed: result.modelUsed,
                transcriptionModel: context.transcriptionModel,
                systemPrompt: context.customSystemPrompt.isEmpty ? "(default)" : "(custom)"
            ))
            if cleaned.isEmpty { return .empty }
            return .inserted(cleaned)
        } catch {
            PipelineHistoryStore.shared.append(PipelineHistoryItem(
                rawTranscript: trimmed,
                finalTranscript: trimmed,
                modelUsed: "raw-fallback",
                transcriptionModel: context.transcriptionModel,
                systemPrompt: "",
                note: "post-processing failed: \(error.localizedDescription)"
            ))
            return .inserted(trimmed)
        }
    }
}
