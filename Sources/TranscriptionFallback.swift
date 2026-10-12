import Foundation

enum TranscriptionFallback {
    /// Upload only when realtime is unavailable or fails. An empty successful
    /// transcript represents silence and must not trigger a second request.
    static func resolve(
        realtimeService: RealtimeTranscriptionClient?,
        transcribeFile: () async throws -> String
    ) async throws -> String {
        try Task.checkCancellation()
        if let realtimeService {
            do {
                let transcript = try await withTaskCancellationHandler {
                    try await realtimeService.commitAndAwaitFinal()
                } onCancel: {
                    realtimeService.cancel()
                }
                try Task.checkCancellation()
                return transcript
            } catch is CancellationError {
                realtimeService.cancel()
                throw CancellationError()
            } catch {
                realtimeService.cancel()
                try Task.checkCancellation()
            }
        }
        return try await transcribeFile()
    }
}
