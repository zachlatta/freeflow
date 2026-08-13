using FreeFlowWindows.Core.Models;

namespace FreeFlowWindows.Core.Interfaces;

/// <summary>
/// Visual feedback overlay displayed during recording and processing.
/// Shows the current recording state, audio level visualization, and elapsed time.
/// </summary>
public interface IRecordingIndicator
{
    /// <summary>
    /// Shows the indicator in the initializing state.
    /// </summary>
    /// <param name="mode">The recording mode (Hold or Toggle).</param>
    void ShowInitializing(RecordingMode mode);

    /// <summary>
    /// Shows the indicator in the recording state with audio level visualization.
    /// </summary>
    /// <param name="mode">The recording mode (Hold or Toggle).</param>
    void ShowRecording(RecordingMode mode);

    /// <summary>
    /// Shows the indicator in the processing state (transcribing/post-processing).
    /// </summary>
    void ShowProcessing();

    /// <summary>
    /// Shows an error message on the indicator for a specified duration.
    /// </summary>
    /// <param name="message">The error message to display.</param>
    /// <param name="duration">How long to display the error before dismissing.</param>
    void ShowError(string message, TimeSpan duration);

    /// <summary>
    /// Updates the audio level visualization with the current level.
    /// </summary>
    /// <param name="level">The normalized audio level (0.0 to 1.0).</param>
    void UpdateAudioLevel(float level);

    /// <summary>
    /// Updates the elapsed recording time display.
    /// </summary>
    /// <param name="elapsed">The elapsed time since recording started.</param>
    void UpdateElapsedTime(TimeSpan elapsed);

    /// <summary>
    /// Dismisses and hides the indicator.
    /// </summary>
    void Dismiss();

    /// <summary>
    /// Event raised when the user clicks on the indicator to cancel the operation.
    /// </summary>
    event EventHandler? CancelRequested;
}
