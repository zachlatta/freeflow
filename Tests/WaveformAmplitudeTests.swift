import CoreGraphics
import Foundation

enum WaveformAmplitudeTests {
    static func run() {
        let fullMultipliers: [CGFloat] = [0.35, 0.55, 0.75, 0.9, 1.0, 0.9, 0.75, 0.55, 0.35]
        let compactMultipliers: [CGFloat] = [0.5, 0.75, 1.0, 0.75, 0.5]
        let times = stride(from: 0.0, through: 4.0, by: 1.0 / 60.0).map { $0 }

        for multipliers in [fullMultipliers, compactMultipliers] {
            for (index, multiplier) in multipliers.enumerated() {
                for time in times {
                    let silent = WaveformAmplitude.barAmplitude(
                        level: 0, multiplier: multiplier, index: index, pulseTime: time
                    )
                    TestSupport.expect(silent <= 0.001, "Silence must stay flat, got \(silent) at t=\(time)")

                    let invalid = WaveformAmplitude.barAmplitude(
                        level: -.infinity, multiplier: multiplier, index: index, pulseTime: time
                    )
                    TestSupport.expect(invalid <= 0.001, "Invalid levels must render as silence")

                    let quietSpeech = WaveformAmplitude.barAmplitude(
                        level: 0.12, multiplier: multiplier, index: index, pulseTime: time
                    )
                    TestSupport.expect(quietSpeech >= 0.06, "Quiet speech must stay visible, got \(quietSpeech)")

                    let speech = WaveformAmplitude.barAmplitude(
                        level: 0.6, multiplier: multiplier, index: index, pulseTime: time
                    )
                    TestSupport.expect(speech > quietSpeech, "Louder input must draw taller bars")
                    TestSupport.expect(speech <= 1.0, "Amplitude must stay within range")
                }
            }
        }

        // Without the pulse, amplitude is the plain scaled level.
        TestSupport.expectApproximatelyEqual(
            Double(WaveformAmplitude.barAmplitude(level: 0.5, multiplier: 0.5, index: 0, pulseTime: nil)),
            0.25
        )
        TestSupport.expect(
            WaveformAmplitude.barAmplitude(level: 3, multiplier: 1, index: 0, pulseTime: 1.5) <= 1.0,
            "Out-of-range levels must stay clamped"
        )
    }
}
