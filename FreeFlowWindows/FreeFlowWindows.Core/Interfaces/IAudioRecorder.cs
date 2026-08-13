using FreeFlowWindows.Core.Models;

namespace FreeFlowWindows.Core.Interfaces;

/// <summary>
/// Interface for audio recording from microphone devices.
/// </summary>
public interface IAudioRecorder : IDisposable
{
    /// <summary>
    /// Raised when the audio level changes during recording.
    /// Provides normalized levels (0.0 to 1.0) for visual feedback.
    /// </summary>
    event EventHandler<AudioLevelEventArgs>? AudioLevelChanged;

    /// <summary>
    /// Raised when a recording is ready (stopped and file saved).
    /// </summary>
    event EventHandler<RecordingReadyEventArgs>? RecordingReady;

    /// <summary>
    /// Raised when a recording error occurs.
    /// </summary>
    event EventHandler<RecordingErrorEventArgs>? RecordingFailed;

    /// <summary>
    /// Gets the list of available audio input devices.
    /// </summary>
    /// <returns>A read-only list of available audio devices.</returns>
    IReadOnlyList<AudioDevice> GetAvailableDevices();

    /// <summary>
    /// Starts recording audio from the specified device.
    /// </summary>
    /// <param name="deviceId">The device ID to record from. If null, uses the default device or falls back if the selected device is unavailable.</param>
    /// <returns>A task that completes when recording has started.</returns>
    /// <exception cref="InvalidOperationException">Thrown if recording is already in progress.</exception>
    Task StartRecordingAsync(string? deviceId = null);

    /// <summary>
    /// Stops the current recording and returns the path to the recorded file.
    /// </summary>
    /// <returns>The path to the recorded WAV file, or null if no recording was active or an error occurred.</returns>
    Task<string?> StopRecordingAsync();

    /// <summary>
    /// Cancels the current recording and cleans up any temporary files.
    /// </summary>
    void CancelRecording();

    /// <summary>
    /// Gets whether recording is currently in progress.
    /// </summary>
    bool IsRecording { get; }
}
