import Foundation

enum RecordingSpeechGateTests {
    static func run() {
        // Synthetic measurements modeled on the reported failures and successes.
        TestSupport.expectEqual(
            RecordingSpeechGate.evaluate(durationSeconds: 0.04, peakAmplitude: 0.5),
            .skip(.tooShort)
        )
        TestSupport.expectEqual(
            RecordingSpeechGate.evaluate(durationSeconds: 0.78, peakAmplitude: 0.001),
            .skip(.silent)
        )
        TestSupport.expectEqual(
            RecordingSpeechGate.evaluate(durationSeconds: 1.3, peakAmplitude: 0.041),
            .keep
        )
        TestSupport.expectEqual(
            RecordingSpeechGate.evaluate(durationSeconds: 0.04, peakAmplitude: 0.0),
            .skip(.tooShort)
        )

        // Threshold is -45 dBFS.
        TestSupport.expectEqual(RecordingSpeechGate.minimumPeakDBFS, -45.0)
        TestSupport.expectApproximatelyEqual(RecordingSpeechGate.minimumPeakAmplitude, 0.005623, accuracy: 0.000_001)

        // Boundaries: thresholds are inclusive keeps.
        let threshold = RecordingSpeechGate.minimumPeakAmplitude
        TestSupport.expectEqual(RecordingSpeechGate.evaluate(durationSeconds: 0.1, peakAmplitude: threshold), .keep)
        TestSupport.expectEqual(RecordingSpeechGate.evaluate(durationSeconds: 0.5, peakAmplitude: threshold * 0.999), .skip(.silent))
        TestSupport.expectEqual(RecordingSpeechGate.evaluate(durationSeconds: 0.5, peakAmplitude: 0.006), .keep)
        TestSupport.expectEqual(RecordingSpeechGate.evaluate(durationSeconds: 0.5, peakAmplitude: 0.003), .skip(.silent))
        TestSupport.expectEqual(RecordingSpeechGate.evaluate(durationSeconds: 0.0999, peakAmplitude: 0.5), .skip(.tooShort))
        TestSupport.expectEqual(RecordingSpeechGate.evaluate(durationSeconds: 0.0, peakAmplitude: 0.0), .skip(.tooShort))
        TestSupport.expectEqual(RecordingSpeechGate.evaluate(durationSeconds: 0.5, peakAmplitude: 1.0), .keep)
        TestSupport.expectEqual(RecordingSpeechGate.evaluate(durationSeconds: .nan, peakAmplitude: 0.5), .skip(.tooShort))
        TestSupport.expectEqual(RecordingSpeechGate.evaluate(durationSeconds: 0.5, peakAmplitude: .nan), .skip(.silent))

        let summary = RecordingAudioSummary(durationSeconds: 0.78, peakAmplitude: 0.001, bufferCount: 12, deviceName: "Test Headset")
        TestSupport.expectEqual(RecordingSpeechGate.evaluate(summary), .skip(.silent))

        // dBFS formatting.
        TestSupport.expectEqual(RecordingSpeechGate.formatDBFS(1.0), "0.0 dBFS")
        TestSupport.expectEqual(RecordingSpeechGate.formatDBFS(0.01), "-40.0 dBFS")
        TestSupport.expectEqual(RecordingSpeechGate.formatDBFS(0.001), "-60.0 dBFS")
        TestSupport.expectEqual(RecordingSpeechGate.formatDBFS(0.0), "-inf dBFS")
        TestSupport.expectEqual(RecordingSpeechGate.formatDBFS(.nan), "-inf dBFS")

        // User-facing copy differs per reason.
        TestSupport.expectEqual(
            RecordingSpeechGate.userMessage(reason: .silent, deviceName: "Test Headset"),
            "No speech detected from Test Headset. Bluetooth mics can take a moment to wake up — try again."
        )
        TestSupport.expectEqual(
            RecordingSpeechGate.userMessage(reason: .silent, deviceName: "  "),
            "No speech detected from the microphone. Bluetooth mics can take a moment to wake up — try again."
        )
        TestSupport.expectEqual(
            RecordingSpeechGate.userMessage(reason: .tooShort, deviceName: "Test Headset"),
            "Recording was too short. Hold the shortcut while you speak."
        )
        TestSupport.expectEqual(RecordingSpeechGate.overlayMessage(reason: .silent), "No speech detected. Try again.")
        // RecordingOverlay truncates toasts at 90 characters (private UI constant).
        for reason in [RecordingSpeechGate.SkipReason.silent, .tooShort] {
            TestSupport.expect(
                RecordingSpeechGate.overlayMessage(reason: reason).count <= 90,
                "Overlay message must fit the toast length cap"
            )
            for text in [
                RecordingSpeechGate.userMessage(reason: reason, deviceName: "Test Headset"),
                RecordingSpeechGate.overlayMessage(reason: reason),
            ] {
                TestSupport.expect(!text.lowercased().contains("tick"), "Copy must not mention a tick")
            }
        }

        // History status must start with "Error:" so the history row offers Retry.
        TestSupport.expectEqual(
            RecordingSpeechGate.historyStatus(reason: .silent, summary: summary),
            "Error: No speech detected (0.78s, peak -60.0 dBFS, mic: Test Headset). Transcription skipped."
        )
        let shortStatus = RecordingSpeechGate.historyStatus(
            reason: .tooShort,
            summary: RecordingAudioSummary(durationSeconds: 0.04, peakAmplitude: 0, bufferCount: 1, deviceName: nil)
        )
        TestSupport.expectEqual(
            shortStatus,
            "Error: Recording too short (0.04s, peak -inf dBFS, mic: the microphone). Transcription skipped."
        )
        TestSupport.expect(shortStatus.hasPrefix("Error:"), "Skip status must enable history Retry")
    }
}
