using FreeFlowWindows.Core.Audio;
using FsCheck;
using FsCheck.Xunit;

namespace FreeFlowWindows.Tests.PropertyTests;

/// <summary>
/// Property-based tests for LiveAudioLevelNormalizer.
/// </summary>
public class AudioLevelNormalizerPropertyTests
{
    /// <summary>
    /// **Validates: Requirements 2.7**
    /// 
    /// Property 3: Audio Level Normalization Bounds
    /// 
    /// For any RMS audio level input (float value), the normalized display level output 
    /// from the LiveAudioLevelNormalizer should always be clamped to the range [0.0, 1.0], 
    /// regardless of whether the input is negative, zero, within normal range, or exceeds 1.0.
    /// </summary>
    [Property(MaxTest = 100, Verbose = true)]
    public Property NormalizedLevel_AlwaysWithinBounds_ForAnyRmsInput()
    {
        return Prop.ForAll(
            AudioLevelArbitrary.GenerateRmsValues(),
            rms =>
            {
                // Arrange
                var normalizer = new LiveAudioLevelNormalizer();

                // Act
                var result = normalizer.NormalizedLevel(rms);

                // Assert: Result must always be in [0.0, 1.0]
                return result >= 0.0f && result <= 1.0f;
            });
    }

    /// <summary>
    /// **Validates: Requirements 2.7**
    /// 
    /// Property 3 extended: Sequential processing should maintain bounds.
    /// 
    /// For any sequence of RMS values, all outputs from NormalizedLevel 
    /// should remain within [0.0, 1.0] bounds, including the adaptive state tracking.
    /// </summary>
    [Property(MaxTest = 100, Verbose = true)]
    public Property NormalizedLevel_AlwaysWithinBounds_ForSequentialInputs()
    {
        return Prop.ForAll(
            AudioLevelArbitrary.GenerateRmsSequence(),
            rmsSequence =>
            {
                // Arrange
                var normalizer = new LiveAudioLevelNormalizer();

                // Act & Assert: All outputs must be in [0.0, 1.0]
                foreach (var rms in rmsSequence)
                {
                    var result = normalizer.NormalizedLevel(rms);
                    if (result < 0.0f || result > 1.0f)
                    {
                        return false;
                    }
                }

                return true;
            });
    }

    /// <summary>
    /// **Validates: Requirements 2.7**
    /// 
    /// Property 3 extended: After reset, bounds should still be maintained.
    /// 
    /// For any RMS value processed after a reset, the output should 
    /// still be within [0.0, 1.0] bounds.
    /// </summary>
    [Property(MaxTest = 100, Verbose = true)]
    public Property NormalizedLevel_AlwaysWithinBounds_AfterReset()
    {
        return Prop.ForAll(
            AudioLevelArbitrary.GenerateRmsSequence(),
            AudioLevelArbitrary.GenerateRmsValues(),
            (initialSequence, postResetRms) =>
            {
                // Arrange
                var normalizer = new LiveAudioLevelNormalizer();

                // Process initial sequence to build up state
                foreach (var rms in initialSequence)
                {
                    normalizer.NormalizedLevel(rms);
                }

                // Reset the normalizer
                normalizer.Reset();

                // Act: Process a value after reset
                var result = normalizer.NormalizedLevel(postResetRms);

                // Assert: Result must still be in [0.0, 1.0]
                return result >= 0.0f && result <= 1.0f;
            });
    }

    /// <summary>
    /// **Validates: Requirements 2.7**
    /// 
    /// Property 3 extended: Edge cases must maintain bounds.
    /// 
    /// For extreme edge case values (float min/max, infinity, very small values),
    /// the normalizer should not produce values outside [0.0, 1.0].
    /// </summary>
    [Property(MaxTest = 100, Verbose = true)]
    public Property NormalizedLevel_AlwaysWithinBounds_ForEdgeCases()
    {
        return Prop.ForAll(
            AudioLevelArbitrary.GenerateEdgeCaseRmsValues(),
            rms =>
            {
                // Skip NaN inputs as they have undefined behavior
                if (float.IsNaN(rms))
                {
                    return true; // Skip this case
                }

                // Arrange
                var normalizer = new LiveAudioLevelNormalizer();

                // Act
                var result = normalizer.NormalizedLevel(rms);

                // Assert: Result must always be in [0.0, 1.0] (or NaN for NaN inputs)
                return (result >= 0.0f && result <= 1.0f) || float.IsNaN(result);
            });
    }
}

/// <summary>
/// Custom FsCheck arbitrary generators for audio level values.
/// </summary>
public static class AudioLevelArbitrary
{
    /// <summary>
    /// Generates arbitrary float RMS values including negative, zero, normal, and >1.0 values.
    /// </summary>
    public static Arbitrary<float> GenerateRmsValues()
    {
        return Arb.From(
            Gen.Frequency(
                // Negative values (invalid but should be handled)
                Tuple.Create(1, Gen.Choose(-1000, -1).Select(x => x / 100.0f)),
                // Zero
                Tuple.Create(1, Gen.Constant(0.0f)),
                // Very small positive values (near minimum RMS)
                Tuple.Create(2, Gen.Choose(1, 100).Select(x => x / 10000000.0f)),
                // Normal range [0.0, 1.0]
                Tuple.Create(4, Gen.Choose(0, 1000).Select(x => x / 1000.0f)),
                // Values exceeding 1.0 (clipping/loud signals)
                Tuple.Create(2, Gen.Choose(1001, 10000).Select(x => x / 1000.0f)),
                // Very large values
                Tuple.Create(1, Gen.Choose(10001, 1000000).Select(x => x / 1000.0f))
            ));
    }

    /// <summary>
    /// Generates a sequence of RMS values to test adaptive behavior.
    /// </summary>
    public static Arbitrary<float[]> GenerateRmsSequence()
    {
        return Arb.From(
            from length in Gen.Choose(1, 50)
            from values in Gen.ArrayOf(length, GenerateRmsValues().Generator)
            select values);
    }

    /// <summary>
    /// Generates edge case RMS values including infinity and extreme floats.
    /// </summary>
    public static Arbitrary<float> GenerateEdgeCaseRmsValues()
    {
        return Arb.From(
            Gen.Frequency(
                // Negative infinity
                Tuple.Create(1, Gen.Constant(float.NegativeInfinity)),
                // Positive infinity
                Tuple.Create(1, Gen.Constant(float.PositiveInfinity)),
                // Very small negative
                Tuple.Create(1, Gen.Constant(-float.Epsilon)),
                // Zero
                Tuple.Create(1, Gen.Constant(0.0f)),
                // Very small positive
                Tuple.Create(1, Gen.Constant(float.Epsilon)),
                // Minimum positive normal float
                Tuple.Create(1, Gen.Constant(float.MinValue)),
                // Maximum float
                Tuple.Create(1, Gen.Constant(float.MaxValue)),
                // Normal small values
                Tuple.Create(2, Gen.Choose(1, 100).Select(x => x / 10000000.0f)),
                // Normal range
                Tuple.Create(3, Gen.Choose(0, 1000).Select(x => x / 1000.0f)),
                // Above 1.0
                Tuple.Create(2, Gen.Choose(1001, 10000).Select(x => x / 1000.0f))
            ));
    }
}
