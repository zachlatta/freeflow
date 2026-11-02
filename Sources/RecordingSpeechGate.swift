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
    static let minimumPeakDBFS = -45.0
    /// `minimumPeakDBFS` as a linear amplitude (about 0.005623 of full scale).
    static let minimumPeakAmplitude = pow(10.0, minimumPeakDBFS / 20.0)

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
    static func userMessage(reason: SkipReason, deviceName: String?) -> String {
        switch reason {
        case .silent:
            return "No speech detected from \(displayDeviceName(deviceName)). Bluetooth mics can take a moment to wake up — try again."
        case .tooShort:
            return "Recording was too short. Hold the shortcut while you speak."
        }
    }

    /// Short message for the overlay toast; never includes the mic name so it
    /// always fits the toast length cap.
    static func overlayMessage(reason: SkipReason) -> String {
        switch reason {
        case .silent:
            return "No speech detected. Try again."
        case .tooShort:
            return "Recording was too short. Hold the shortcut while you speak."
        }
    }

    /// Pipeline-history status. Starts with `Error:` so the history row offers Retry.
    static func historyStatus(reason: SkipReason, summary: RecordingAudioSummary) -> String {
        let headline: String
        switch reason {
        case .tooShort:
            headline = "Recording too short"
        case .silent:
            headline = "No speech detected"
        }
        let duration = String(format: "%.2f", summary.durationSeconds)
        return "Error: \(headline) (\(duration)s, peak \(formatDBFS(summary.peakAmplitude)), "
            + "mic: \(displayDeviceName(summary.deviceName))). Transcription skipped."
    }
}
