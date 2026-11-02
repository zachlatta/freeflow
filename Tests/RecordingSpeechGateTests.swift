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

        // Boundaries: thresholds are inclusive keeps.
        TestSupport.expectEqual(RecordingSpeechGate.evaluate(durationSeconds: 0.1, peakAmplitude: 0.01), .keep)
        TestSupport.expectEqual(RecordingSpeechGate.evaluate(durationSeconds: 0.0999, peakAmplitude: 0.5), .skip(.tooShort))
        TestSupport.expectEqual(RecordingSpeechGate.evaluate(durationSeconds: 0.5, peakAmplitude: 0.0099), .skip(.silent))
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

        // Messages name the mic and fall back when the name is unknown.
        TestSupport.expect(
            RecordingSpeechGate.userMessage(deviceName: "Test Headset").contains("Test Headset"),
            "User message must name the microphone"
        )
        TestSupport.expect(
            RecordingSpeechGate.userMessage(deviceName: "Test Headset").contains("Bluetooth"),
            "User message must include the Bluetooth wake-up hint"
        )
        TestSupport.expect(
            RecordingSpeechGate.overlayMessage(deviceName: nil).contains("the microphone"),
            "Missing device name must fall back to a generic label"
        )
        TestSupport.expect(
            RecordingSpeechGate.overlayMessage(deviceName: "Test Headset").count <= 90,
            "Overlay message must fit the toast length cap for typical mic names"
        )

        TestSupport.expectEqual(
            RecordingSpeechGate.historyStatus(reason: .silent, summary: summary),
            "Skipped transcription: no speech-level audio (duration 0.78s, peak -60.0 dBFS, mic Test Headset)"
        )
        TestSupport.expectEqual(
            RecordingSpeechGate.historyStatus(
                reason: .tooShort,
                summary: RecordingAudioSummary(durationSeconds: 0.04, peakAmplitude: 0, bufferCount: 1, deviceName: nil)
            ),
            "Skipped transcription: recording shorter than 0.1s (duration 0.04s, peak -inf dBFS, mic the microphone)"
        )
    }
}
