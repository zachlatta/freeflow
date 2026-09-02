import SwiftUI

/// A scrolling level meter: every bar is a moment in time and its height is how
/// loud the microphone actually was then, newest on the right. This is what an
/// ordinary voice recorder shows, and what the decorative waveform cannot: the
/// existing `WaveformView` mixes the level with a traveling sine and a shimmer,
/// so the bars keep moving in silence and barely change when you get louder.
/// Mid-sentence you want to know the microphone is hearing you, not that an
/// animation is running.
struct LoudnessMeterView: View {
    let levels: [Float]
    var barCount: Int = 13
    var height: CGFloat = 24
    var barWidth: CGFloat = 2.5
    var spacing: CGFloat = 2.5

    /// Bars below this are drawn dimmed, so "the microphone is picking up
    /// almost nothing" is visible at a glance rather than inferred.
    private static let quietThreshold: Float = 0.08

    private var window: [Float] {
        let tail = levels.suffix(barCount)
        if tail.count == barCount { return Array(tail) }
        return Array(repeating: 0, count: barCount - tail.count) + Array(tail)
    }

    var body: some View {
        HStack(alignment: .center, spacing: spacing) {
            ForEach(Array(window.enumerated()), id: \.offset) { index, level in
                LoudnessBar(
                    level: level,
                    isNewest: index == barCount - 1,
                    isQuiet: level < Self.quietThreshold,
                    maxHeight: height,
                    width: barWidth
                )
            }
        }
        .frame(height: height)
        .animation(.linear(duration: 0.05), value: levels.count)
    }
}

private struct LoudnessBar: View {
    let level: Float
    let isNewest: Bool
    let isQuiet: Bool
    let maxHeight: CGFloat
    let width: CGFloat

    private var barHeight: CGFloat {
        // A gentle curve, so ordinary speech uses the middle of the range
        // instead of pinning the meter at the top.
        let shaped = pow(CGFloat(max(0, min(level, 1))), 0.65)
        return max(width, shaped * maxHeight)
    }

    var body: some View {
        Capsule()
            .fill(.white)
            .frame(width: width, height: barHeight)
            .opacity(isQuiet ? 0.28 : (isNewest ? 1.0 : 0.85))
    }
}
