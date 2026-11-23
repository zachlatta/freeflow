import Foundation

/// The realtime operations the transcript pipeline depends on.
protocol RealtimeTranscriptFinalizing: AnyObject {
    func commitAndAwaitFinal() async throws -> String
    func cancel()
}

enum RealtimeTranscriptFallback {
    /// Await the realtime final transcript. If realtime fails or times out
    /// (or was never started), fall back to the file upload so the user still
    /// gets a transcript. The realtime commit and file upload run in strict
    /// order so a successful realtime result never also pays for the upload.
    /// Cancellation never starts the upload.
    static func resolve(
        realtime: RealtimeTranscriptFinalizing?,
        transcribeFile: () async throws -> String
    ) async throws -> String {
        if let realtime {
            do {
                try Task.checkCancellation()
                return try await withTaskCancellationHandler {
                    try await realtime.commitAndAwaitFinal()
                } onCancel: {
                    realtime.cancel()
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                try Task.checkCancellation()
                return try await transcribeFile()
            }
        }
        return try await transcribeFile()
    }
}
