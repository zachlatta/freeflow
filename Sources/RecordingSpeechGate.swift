import Foundation

/// Per-recording measurements reported by `AudioRecorder` when a recording stops.
struct RecordingAudioSummary: Equatable {
    /// Written 16 kHz frames divided by the sample rate.
    let durationSeconds: Double
    /// Largest absolute sample written to the file, linear 0...1 of full scale.
    let peakAmplitude: Double
    let bufferCount: Int
    let deviceName: String?
}

/// Decides whether a finished recording contains speech-level signal before
/// it is sent to a transcription provider. Recordings that are too short or
/// digitally silent (for example a Bluetooth mic still waking up) are skipped.
enum RecordingSpeechGate {
    /// OpenAI rejects audio shorter than 0.1 seconds.
    static let minimumDurationSeconds = 0.1
    /// Successful dictations peak well above this; silent failures sit below it.
    static let minimumPeakAmplitude = 0.01

    enum SkipReason: Equatable {
        case tooShort
        case silent
    }

    enum Decision: Equatable {
        case keep
        case skip(SkipReason)
    }

    static func evaluate(durationSeconds: Double, peakAmplitude: Double) -> Decision {
        // Negated comparisons also reject NaN measurements.
        if !(durationSeconds >= minimumDurationSeconds) {
            return .skip(.tooShort)
        }
        if !(peakAmplitude >= minimumPeakAmplitude) {
            return .skip(.silent)
        }
        return .keep
    }

    static func evaluate(_ summary: RecordingAudioSummary) -> Decision {
        evaluate(durationSeconds: summary.durationSeconds, peakAmplitude: summary.peakAmplitude)
    }

    /// Formats a linear peak (0...1) as dBFS, e.g. `-44.4 dBFS`.
    static func formatDBFS(_ peakAmplitude: Double) -> String {
        guard peakAmplitude.isFinite, peakAmplitude > 0 else { return "-inf dBFS" }
        let dbfs = 20 * log10(min(peakAmplitude, 1))
        return String(format: "%.1f dBFS", dbfs)
    }

    static func displayDeviceName(_ deviceName: String?) -> String {
        let trimmed = deviceName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "the microphone" : trimmed
    }

    /// Full message for the menu-bar error surface.
    static func userMessage(deviceName: String?) -> String {
        "No speech detected from \(displayDeviceName(deviceName)). Bluetooth mics can take a second to wake up — wait for the tick, then speak."
    }

    /// Shorter message that fits the overlay toast.
    static func overlayMessage(deviceName: String?) -> String {
        "No speech detected from \(displayDeviceName(deviceName)). Wait for the tick, then speak."
    }

    /// Pipeline-history status explaining why transcription was skipped.
    static func historyStatus(reason: SkipReason, summary: RecordingAudioSummary) -> String {
        let reasonText: String
        switch reason {
        case .tooShort:
            reasonText = "recording shorter than \(String(format: "%.1f", minimumDurationSeconds))s"
        case .silent:
            reasonText = "no speech-level audio"
        }
        let duration = String(format: "%.2f", summary.durationSeconds)
        return "Skipped transcription: \(reasonText) (duration \(duration)s, "
            + "peak \(formatDBFS(summary.peakAmplitude)), mic \(displayDeviceName(summary.deviceName)))"
    }
}
