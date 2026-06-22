import AppKit
import Foundation
import os.log

// MARK: - Transcribe Again Errors

enum TranscribeAgainError: LocalizedError {
    case noRawTranscriptAndNoAudio
    case audioFileNotFound
    case emptyTranscript
    
    var errorDescription: String? {
        switch self {
        case .noRawTranscriptAndNoAudio:
            return "No raw transcript and no audio file available."
        case .audioFileNotFound:
            return "Audio file not found for retry."
        case .emptyTranscript:
            return "Transcribed text is empty."
        }
    }
}

// MARK: - Transcribe Again (Retry with Model Selection)

extension AppState {

    /// Logger for transcription retry events
    internal static let retryLog = OSLog(subsystem: "com.zachlatta.freeflow", category: "Recording")

    /// Destination behavior for a transcription retry
    enum RetryAction: Sendable {
        case pasteAtCursor
        case copyToClipboard
    }

    /// Retries post-processing for a history item, optionally using a different LLM model.
    /// Safely resolves configuration state on the `@MainActor` and delegates execution to a background context.
    @MainActor
    func retryTranscription(item: PipelineHistoryItem, overrideModel: String? = nil, action: RetryAction = .copyToClipboard) {
        guard !retryingItemIDs.contains(item.id) else { return }
        retryingItemIDs.insert(item.id)

        let targetModel = overrideModel ?? postProcessingModel
        let postService = PostProcessingService(
            apiKey: apiKey,
            baseURL: apiBaseURL,
            preferredModel: targetModel,
            preferredFallbackModel: postProcessingFallbackModel
        )

        let transService: TranscriptionService
        do {
            transService = try makeTranscriptionService()
        } catch {
            errorMessage = "Failed to initialize transcription service: \(error.localizedDescription)"
            retryingItemIDs.remove(item.id)
            return
        }

        // Capture properties safely on MainActor before entering the async cooperative background context
        let isPressEnter = isPressEnterVoiceCommandEnabled
        let vocab = customVocabulary
        let sysPrompt = customSystemPrompt
        let outLanguage = outputLanguage

        Task {
            do {
                let result = try await executeRetry(
                    item: item,
                    model: targetModel,
                    service: postService,
                    transcriptionService: transService,
                    isPressEnterVoiceCommandEnabled: isPressEnter,
                    customVocabulary: vocab,
                    customSystemPrompt: sysPrompt,
                    outputLanguage: outLanguage
                )
                finalizeRetrySuccess(item: item, result: result, action: action)
            } catch {
                finalizeRetryFailure(item: item, error: error)
            }
        }
    }
}

// MARK: - Private Retry Helpers

private extension AppState {

    /// Holds the computed results of a successful retry execution
    struct RetryResult {
        let transcript: String
        let prompt: String
        let status: String
        let rawTranscript: String
    }

    /// Executes the full pipeline retry: recovers raw transcript (prioritizing audio re-transcription),
    /// checks for empty transcripts/macros, restores the context, and runs post-processing.
    func executeRetry(
        item: PipelineHistoryItem,
        model: String,
        service: PostProcessingService,
        transcriptionService: TranscriptionService,
        isPressEnterVoiceCommandEnabled: Bool,
        customVocabulary: String,
        customSystemPrompt: String,
        outputLanguage: String
    ) async throws -> RetryResult {
        try Task.checkCancellation()

        let rawTranscript = try await resolveRawTranscript(for: item, transcriptionService: transcriptionService)
        try Task.checkCancellation()

        let parsedTranscript = Self.parseTranscriptCommands(
            from: rawTranscript,
            pressEnterCommandEnabled: isPressEnterVoiceCommandEnabled
        )

        let trimmedTranscript = parsedTranscript.transcript.trimmingCharacters(in: .whitespacesAndNewlines)

        // Edge Case 1: Empty Transcript (skip LLM post-processing entirely)
        guard !trimmedTranscript.isEmpty else {
            return RetryResult(
                transcript: "",
                prompt: "",
                status: Self.statusMessage(for: .skippedEmptyRawTranscript, parsedTranscript: parsedTranscript, isRetry: true),
                rawTranscript: rawTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }

        // Edge Case 2: Voice Macro trigger (skip LLM, resolve macro directly)
        if let macro = findMatchingMacro(for: trimmedTranscript) {
            return RetryResult(
                transcript: macro.payload,
                prompt: "",
                status: Self.statusMessage(for: .voiceMacro(command: macro.command), parsedTranscript: parsedTranscript, isRetry: true),
                rawTranscript: rawTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }

        let restoredIntent = SessionIntent.fromPersisted(
            intent: item.intent,
            selectedText: item.selectedText
        )


        let restoredContext = AppContext(
            appName: item.contextAppName,
            bundleIdentifier: item.contextBundleIdentifier,
            windowTitle: item.contextWindowTitle,
            selectedText: item.selectedText,
            precedingText: item.precedingText,
            followingText: item.followingText,
            cursorPosition: nil,
            currentActivity: item.contextSummary,
            contextSystemPrompt: item.contextSystemPrompt,
            contextPrompt: item.contextPrompt,
            screenshotDataURL: item.contextScreenshotDataURL,
            screenshotMimeType: item.contextScreenshotDataURL != nil ? "image/jpeg" : nil,
            screenshotError: nil
        )

        let result: PostProcessingResult
        let outcome: TranscriptProcessingOutcome

        if restoredIntent.isCommandMode {
            result = try await service.commandTransform(
                selectedText: item.selectedText ?? "",
                voiceCommand: parsedTranscript.transcript,
                context: restoredContext,
                customVocabulary: customVocabulary,
                outputLanguage: outputLanguage
            )
            switch restoredIntent {
            case .command(let invocation, _):
                outcome = .commandModeSucceeded(invocation: invocation)
            default:
                outcome = .commandModeSucceeded(invocation: .manual)
            }
        } else {
            result = try await service.postProcess(
                transcript: parsedTranscript.transcript,
                context: restoredContext,
                customVocabulary: customVocabulary,
                customSystemPrompt: customSystemPrompt,
                outputLanguage: outputLanguage
            )
            outcome = .postProcessingSucceeded
        }

        try Task.checkCancellation()

        return RetryResult(
            transcript: result.transcript,
            prompt: result.prompt,
            status: Self.statusMessage(for: outcome, parsedTranscript: parsedTranscript, isRetry: true),
            rawTranscript: rawTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    /// Resolves the raw transcript, prioritizing re-transcription from audio if the file exists.
    func resolveRawTranscript(
        for item: PipelineHistoryItem,
        transcriptionService: TranscriptionService
    ) async throws -> String {
        // 1. Try to re-transcribe from the audio file first if it is available on disk
        if let audioFileName = item.audioFileName {
            let audioURL = Self.audioStorageDirectory().appendingPathComponent(audioFileName)
            if FileManager.default.fileExists(atPath: audioURL.path) {
                try Task.checkCancellation()
                return try await transcriptionService.transcribe(fileURL: audioURL)
            }
        }

        // 2. Fall back to the saved raw transcript if no audio file exists/is found
        let saved = item.rawTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        if !saved.isEmpty {
            return item.rawTranscript
        }

        // 3. Neither is available, throw localized error
        if item.audioFileName != nil {
            throw TranscribeAgainError.audioFileNotFound
        } else {
            throw TranscribeAgainError.noRawTranscriptAndNoAudio
        }
    }


    /// Persists updated history and dispatches the retry action on success
    @MainActor
    func finalizeRetrySuccess(item: PipelineHistoryItem, result: RetryResult, action: RetryAction) {
        let updatedItem = PipelineHistoryItem(
            intent: item.intent,
            selectedText: item.selectedText,
            capturedSelection: item.capturedSelection,
            id: item.id,
            timestamp: item.timestamp,
            rawTranscript: result.rawTranscript,
            postProcessedTranscript: result.transcript.trimmingCharacters(in: .whitespacesAndNewlines),
            postProcessingPrompt: result.prompt,
            systemPrompt: item.systemPrompt,
            contextSummary: item.contextSummary,
            contextSystemPrompt: item.contextSystemPrompt,
            contextPrompt: item.contextPrompt,
            contextScreenshotDataURL: item.contextScreenshotDataURL,
            contextScreenshotStatus: item.contextScreenshotStatus,
            postProcessingStatus: result.status,
            debugStatus: "Retried",
            customVocabulary: item.customVocabulary,
            audioFileName: item.audioFileName,
            contextAppName: item.contextAppName,
            contextBundleIdentifier: item.contextBundleIdentifier,
            contextWindowTitle: item.contextWindowTitle,
            precedingText: item.precedingText,
            followingText: item.followingText
        )
        do {
            try pipelineHistoryStore.update(updatedItem)
            pipelineHistory = pipelineHistoryStore.loadAllHistory()
            let trimmed = result.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                lastTranscript = trimmed
                dispatchRetryAction(action, transcript: trimmed)
            }
        } catch {
            errorMessage = "Failed to save retry result: \(error.localizedDescription)"
        }
        retryingItemIDs.remove(item.id)
    }

    /// Persists error status and cleans up on retry failure
    @MainActor
    func finalizeRetryFailure(item: PipelineHistoryItem, error: Error) {
        let updatedItem = PipelineHistoryItem(
            intent: item.intent,
            selectedText: item.selectedText,
            capturedSelection: item.capturedSelection,
            id: item.id,
            timestamp: item.timestamp,
            rawTranscript: item.rawTranscript,
            postProcessedTranscript: item.postProcessedTranscript,
            postProcessingPrompt: item.postProcessingPrompt,
            systemPrompt: item.systemPrompt,
            contextSummary: item.contextSummary,
            contextSystemPrompt: item.contextSystemPrompt,
            contextPrompt: item.contextPrompt,
            contextScreenshotDataURL: item.contextScreenshotDataURL,
            contextScreenshotStatus: item.contextScreenshotStatus,
            postProcessingStatus: "Error: \(error.localizedDescription)",
            debugStatus: "Retry failed",
            customVocabulary: item.customVocabulary,
            audioFileName: item.audioFileName,
            contextAppName: item.contextAppName,
            contextBundleIdentifier: item.contextBundleIdentifier,
            contextWindowTitle: item.contextWindowTitle,
            precedingText: item.precedingText,
            followingText: item.followingText
        )
        do {
            try pipelineHistoryStore.update(updatedItem)
            pipelineHistory = pipelineHistoryStore.loadAllHistory()
        } catch {
            os_log(.error, log: AppState.retryLog, "Failed to update pipeline history store during retry failure: %{public}@", error.localizedDescription)
        }
        errorMessage = "Retry failed: \(error.localizedDescription)"
        retryingItemIDs.remove(item.id)
    }

    /// Routes the finished transcript to the appropriate output via the AppState hook
    @MainActor
    func dispatchRetryAction(_ action: RetryAction, transcript: String) {
        applyRetryOutput(transcript, action: action)
    }
}
