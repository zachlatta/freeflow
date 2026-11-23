import CoreGraphics
import Foundation

/// Pure bar-height math for the recording waveform overlays.
///
/// The decorative activity pulse is scaled by the input level so a silent or
/// muted microphone draws flat bars, while quiet speech still animates.
enum WaveformAmplitude {
    /// Input level at and above which the activity pulse runs at full strength.
    /// `LiveAudioLevelNormalizer` lifts detected speech to at least 0.12.
    static let fullPulseLevel: CGFloat = 0.1

    /// Returns a normalized bar amplitude in `0...1`.
    static func barAmplitude(
        level rawLevel: Float,
        multiplier: CGFloat,
        index: Int,
        pulseTime: TimeInterval?
    ) -> CGFloat {
        let level = rawLevel.isFinite ? CGFloat(max(rawLevel, 0)) : 0
        let base = min(level * multiplier, 1.0)

        guard let pulseTime else { return base }

        let travelingWave = CGFloat(0.5 + 0.5 * sin((pulseTime * 6.2) - Double(index) * 0.78))
        let shimmer = CGFloat(0.5 + 0.5 * sin((pulseTime * 3.1) + Double(index) * 0.5))
        let pulse = travelingWave * 0.22 + shimmer * 0.06

        let saturationRelief = base * (0.74 + pulse)
        let activity = min(level / fullPulseLevel, 1.0)
        let quietPulse = (1.0 - base) * (0.04 + pulse * 0.28) * activity
        return min(saturationRelief + quietPulse, 1.0)
    }
}
