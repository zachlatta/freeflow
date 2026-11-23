import Foundation

/// Decides which run-history entries represent failed runs and can be retried
/// from their locally saved audio.
enum PipelineHistoryRetryPolicy {
    static let failureStatusPrefix = "Error:"
    static let cancelledTranscriptionStatus = "\(failureStatusPrefix) Transcription cancelled"
    static let cancelledScreenshotStatus = "Not captured (transcription cancelled)"

    static func isFailure(status: String) -> Bool {
        status.hasPrefix(failureStatusPrefix)
    }

    static func canRetry(status: String, audioFileName: String?) -> Bool {
        guard let audioFileName, !audioFileName.isEmpty else { return false }
        return isFailure(status: status)
    }

    static func canRetry(_ item: PipelineHistoryItem) -> Bool {
        canRetry(status: item.postProcessingStatus, audioFileName: item.audioFileName)
    }
}
