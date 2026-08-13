namespace FreeFlowWindows.Core.Models;

/// <summary>
/// Event arguments for when a recording is ready (stopped and saved).
/// </summary>
public class RecordingReadyEventArgs : EventArgs
{
    /// <summary>
    /// The path to the recorded audio file.
    /// </summary>
    public string FilePath { get; }

    /// <summary>
    /// The duration of the recording.
    /// </summary>
    public TimeSpan Duration { get; }

    /// <summary>
    /// Creates a new RecordingReadyEventArgs with the specified values.
    /// </summary>
    /// <param name="filePath">The path to the recorded audio file.</param>
    /// <param name="duration">The duration of the recording.</param>
    public RecordingReadyEventArgs(string filePath, TimeSpan duration)
    {
        FilePath = filePath ?? throw new ArgumentNullException(nameof(filePath));
        Duration = duration;
    }
}
