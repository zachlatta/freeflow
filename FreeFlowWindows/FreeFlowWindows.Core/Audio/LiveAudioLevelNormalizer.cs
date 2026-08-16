namespace FreeFlowWindows.Core.Audio;

/// <summary>
/// Normalizes raw RMS audio levels into a visually meaningful [0.0, 1.0] range
/// with adaptive noise floor and peak ceiling tracking.
/// Ported from the macOS Swift implementation.
/// </summary>
public class LiveAudioLevelNormalizer
{
    #region Constants

    /// <summary>
    /// Minimum RMS value to prevent log(0) when converting to dB.
    /// </summary>
    private const float MinimumRMS = 0.00001f;

    /// <summary>
    /// Minimum dynamic range in dB between floor and ceiling.
    /// </summary>
    private const float MinSpanDB = 18f;

    /// <summary>
    /// Headroom above peak ceiling for display scaling.
    /// </summary>
    private const float PeakHeadroomDB = 8f;

    /// <summary>
    /// Margin above noise floor for speech gating in dB.
    /// </summary>
    private const float SpeechGateMarginDB = 3f;

    /// <summary>
    /// Minimum visible level for active speech to ensure visibility.
    /// </summary>
    private const float MinimumVisibleActiveLevel = 0.12f;

    /// <summary>
    /// Threshold below which normalized level is gated to zero.
    /// </summary>
    private const float NoiseGateNormalizedThreshold = 0.06f;

    /// <summary>
    /// Window above noise floor where floor can rise in dB.
    /// </summary>
    private const float FloorRiseWindowDB = 4f;

    /// <summary>
    /// Blend factor for noise floor falling (fast adaptation).
    /// </summary>
    private const float FloorFallBlend = 0.12f;

    /// <summary>
    /// Blend factor for noise floor rising (slow adaptation).
    /// </summary>
    private const float FloorRiseBlend = 0.02f;

    /// <summary>
    /// Blend factor for peak ceiling attack (fast rise).
    /// </summary>
    private const float PeakAttackBlend = 0.55f;

    /// <summary>
    /// Blend factor for peak ceiling release (slow fall).
    /// </summary>
    private const float PeakReleaseBlend = 0.04f;

    /// <summary>
    /// Blend factor for display level attack (fast rise).
    /// </summary>
    private const float DisplayAttackBlend = 0.45f;

    /// <summary>
    /// Blend factor for display level release (slow fall).
    /// </summary>
    private const float DisplayReleaseBlend = 0.12f;

    /// <summary>
    /// Default noise floor value in dB.
    /// </summary>
    private const float DefaultNoiseFloorDB = -55f;

    /// <summary>
    /// Default peak ceiling value in dB.
    /// </summary>
    private const float DefaultPeakCeilingDB = -37f;

    #endregion

    #region State

    /// <summary>
    /// Current estimated noise floor level in dB.
    /// </summary>
    private float _noiseFloorDB = DefaultNoiseFloorDB;

    /// <summary>
    /// Current estimated peak ceiling level in dB.
    /// </summary>
    private float _peakCeilingDB = DefaultPeakCeilingDB;

    /// <summary>
    /// Smoothed display level output [0.0, 1.0].
    /// </summary>
    private float _displayLevel = 0f;

    #endregion

    #region Properties

    /// <summary>
    /// Gets the current noise floor level in dB.
    /// </summary>
    public float NoiseFloorDB => _noiseFloorDB;

    /// <summary>
    /// Gets the current peak ceiling level in dB.
    /// </summary>
    public float PeakCeilingDB => _peakCeilingDB;

    /// <summary>
    /// Gets the current smoothed display level [0.0, 1.0].
    /// </summary>
    public float DisplayLevel => _displayLevel;

    #endregion

    #region Public Methods

    /// <summary>
    /// Resets the normalizer state for a new recording session.
    /// </summary>
    public void Reset()
    {
        _noiseFloorDB = DefaultNoiseFloorDB;
        _peakCeilingDB = DefaultPeakCeilingDB;
        _displayLevel = 0f;
    }

    /// <summary>
    /// Processes a raw RMS audio level and returns a normalized display level.
    /// </summary>
    /// <param name="rms">The raw RMS audio level (typically 0.0 to 1.0, but can exceed).</param>
    /// <returns>A normalized display level clamped to [0.0, 1.0].</returns>
    public float NormalizedLevel(float rms)
    {
        // Convert RMS to dB, clamping to minimum to avoid log(0)
        float levelDB = 20f * MathF.Log10(MathF.Max(rms, MinimumRMS));

        // Update adaptive tracking
        UpdateNoiseFloor(levelDB);
        UpdatePeakCeiling(levelDB);

        // Calculate normalized level within dynamic range
        float displayCeilingDB = _peakCeilingDB + PeakHeadroomDB;
        float dynamicSpan = MathF.Max(displayCeilingDB - _noiseFloorDB, MinSpanDB + PeakHeadroomDB);
        float normalized = Clamp((levelDB - _noiseFloorDB) / dynamicSpan);

        // Determine if this is active speech
        bool isActiveSpeech = levelDB >= _noiseFloorDB + SpeechGateMarginDB;

        // Apply noise gate
        if (normalized < NoiseGateNormalizedThreshold && levelDB <= _noiseFloorDB + SpeechGateMarginDB)
        {
            normalized = 0f;
        }
        else if (isActiveSpeech)
        {
            // Ensure minimum visibility for active speech
            normalized = MathF.Max(normalized, MinimumVisibleActiveLevel);
        }

        // Apply smoothing blend
        float blend = normalized > _displayLevel ? DisplayAttackBlend : DisplayReleaseBlend;
        _displayLevel = Mix(_displayLevel, normalized, blend);

        return _displayLevel;
    }

    #endregion

    #region Private Methods

    /// <summary>
    /// Updates the noise floor estimate based on the current level.
    /// </summary>
    /// <param name="levelDB">The current audio level in dB.</param>
    private void UpdateNoiseFloor(float levelDB)
    {
        // Limit the level to prevent noise floor from rising above (peak - minSpan)
        float ceilingLimitedLevel = MathF.Min(levelDB, _peakCeilingDB - MinSpanDB);

        if (ceilingLimitedLevel <= _noiseFloorDB)
        {
            // Level is below floor - floor falls quickly to follow
            _noiseFloorDB = Mix(_noiseFloorDB, ceilingLimitedLevel, FloorFallBlend);
        }
        else if (ceilingLimitedLevel <= _noiseFloorDB + FloorRiseWindowDB)
        {
            // Level is within rise window - floor rises slowly
            _noiseFloorDB = Mix(_noiseFloorDB, ceilingLimitedLevel, FloorRiseBlend);
        }
        // If level is above rise window, floor stays put
    }

    /// <summary>
    /// Updates the peak ceiling estimate based on the current level.
    /// </summary>
    /// <param name="levelDB">The current audio level in dB.</param>
    private void UpdatePeakCeiling(float levelDB)
    {
        float minimumCeiling = _noiseFloorDB + MinSpanDB;

        if (levelDB >= _peakCeilingDB)
        {
            // Level exceeds ceiling - ceiling rises quickly
            _peakCeilingDB = Mix(_peakCeilingDB, levelDB, PeakAttackBlend);
        }
        else
        {
            // Level below ceiling - ceiling falls slowly toward level or minimum
            _peakCeilingDB = Mix(_peakCeilingDB, MathF.Max(levelDB, minimumCeiling), PeakReleaseBlend);
        }

        // Ensure minimum span is maintained
        _peakCeilingDB = MathF.Max(_peakCeilingDB, minimumCeiling);
    }

    /// <summary>
    /// Linear interpolation between two values.
    /// </summary>
    /// <param name="current">The current value.</param>
    /// <param name="target">The target value.</param>
    /// <param name="blend">The blend factor [0.0, 1.0].</param>
    /// <returns>The interpolated value.</returns>
    private static float Mix(float current, float target, float blend)
    {
        return current + (target - current) * blend;
    }

    /// <summary>
    /// Clamps a value to the range [0.0, 1.0].
    /// </summary>
    /// <param name="value">The value to clamp.</param>
    /// <returns>The clamped value.</returns>
    private static float Clamp(float value)
    {
        return MathF.Min(MathF.Max(value, 0f), 1f);
    }

    #endregion
}
