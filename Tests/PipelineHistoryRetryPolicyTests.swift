import Foundation

enum PipelineHistoryRetryPolicyTests {
    static func run() {
        let syntheticAudioFileName = "00000000-0000-0000-0000-000000000317.wav"

        let cancelled = makeItem(
            status: PipelineHistoryRetryPolicy.cancelledTranscriptionStatus,
            audioFileName: syntheticAudioFileName
        )
        TestSupport.expect(
            PipelineHistoryRetryPolicy.isFailure(status: cancelled.postProcessingStatus),
            "A cancelled transcription must be shown as a failed run"
        )
        TestSupport.expect(
            PipelineHistoryRetryPolicy.canRetry(cancelled),
            "A cancelled transcription with saved audio must offer Retry"
        )

        let failed = makeItem(status: "Error: synthetic provider failure", audioFileName: syntheticAudioFileName)
        TestSupport.expect(PipelineHistoryRetryPolicy.canRetry(failed), "A failed transcription with saved audio must offer Retry")

        let cancelledWithoutAudio = makeItem(
            status: PipelineHistoryRetryPolicy.cancelledTranscriptionStatus,
            audioFileName: nil
        )
        TestSupport.expect(
            !PipelineHistoryRetryPolicy.canRetry(cancelledWithoutAudio),
            "Retry must not be offered without a saved audio file"
        )
        TestSupport.expect(
            !PipelineHistoryRetryPolicy.canRetry(status: PipelineHistoryRetryPolicy.cancelledTranscriptionStatus, audioFileName: ""),
            "Retry must not be offered for an empty audio file name"
        )

        let succeeded = makeItem(status: "Post-processing succeeded", audioFileName: syntheticAudioFileName)
        TestSupport.expect(
            !PipelineHistoryRetryPolicy.isFailure(status: succeeded.postProcessingStatus),
            "A successful run must not be shown as failed"
        )
        TestSupport.expect(!PipelineHistoryRetryPolicy.canRetry(succeeded), "A successful run must not offer Retry")
    }

    private static func makeItem(status: String, audioFileName: String?) -> PipelineHistoryItem {
        PipelineHistoryItem(
            timestamp: Date(timeIntervalSince1970: 0),
            rawTranscript: "",
            postProcessedTranscript: "",
            postProcessingPrompt: "",
            contextSummary: "",
            contextScreenshotDataURL: nil,
            contextScreenshotStatus: PipelineHistoryRetryPolicy.cancelledScreenshotStatus,
            postProcessingStatus: status,
            debugStatus: "Cancelled",
            customVocabulary: "",
            audioFileName: audioFileName
        )
    }
}
