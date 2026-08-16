namespace FreeFlowWindows.Core.Models;

/// <summary>
/// Event arguments for audio level change events during recording.
/// </summary>
public class AudioLevelEventArgs : EventArgs
{
    /// <summary>
    /// The normalized audio level (0.0 to 1.0).
    /// </summary>
    public float Level { get; }

    /// <summary>
    /// Creates a new AudioLevelEventArgs with the specified level.
    /// </summary>
    /// <param name="level">The normalized audio level (0.0 to 1.0).</param>
    public AudioLevelEventArgs(float level)
    {
        Level = Math.Clamp(level, 0f, 1f);
    }
}
