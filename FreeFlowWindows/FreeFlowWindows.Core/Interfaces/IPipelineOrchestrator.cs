using FreeFlowWindows.Core.Models;

namespace FreeFlowWindows.Core.Interfaces;

/// <summary>
/// Event arguments for pipeline state changes.
/// </summary>
public class PipelineStateChangedEventArgs : EventArgs
{
    /// <summary>
    /// The previous pipeline state.
    /// </summary>
    public PipelineState PreviousState { get; }

    /// <summary>
    /// The new pipeline state.
    /// </summary>
    public PipelineState NewState { get; }

    /// <summary>
    /// Creates a new state changed event args.
    /// </summary>
    public PipelineStateChangedEventArgs(PipelineState previousState, PipelineState newState)
    {
        PreviousState = previousState;
        NewState = newState;
    }
}

/// <summary>
/// Event arguments for pipeline completion.
/// </summary>
public class PipelineCompletedEventArgs : EventArgs
{
    /// <summary>
    /// The final transcript that was pasted (may be empty if cancelled or no speech detected).
    /// </summary>
    public string Transcript { get; }

    /// <summary>
    /// Whether the pipeline was cancelled before completion.
    /// </summary>
    public bool WasCancelled { get; }

    /// <summary>
    /// The raw transcript before post-processing (for debugging/history).
    /// </summary>
    public string? RawTranscript { get; }

    /// <summary>
    /// Creates a new completion event args.
    /// </summary>
    public PipelineCompletedEventArgs(string transcript, bool wasCancelled, string? rawTranscript = null)
    {
        Transcript = transcript;
        WasCancelled = wasCancelled;
        RawTranscript = rawTranscript;
    }
}

/// <summary>
/// Event arguments for pipeline errors.
/// </summary>
public class PipelineErrorEventArgs : EventArgs
{
    /// <summary>
    /// The state the pipeline was in when the error occurred.
    /// </summary>
    public PipelineState StateAtError { get; }

    /// <summary>
    /// A user-friendly error message.
    /// </summary>
    public string Message { get; }

    /// <summary>
    /// The underlying exception, if any.
    /// </summary>
    public Exception? Exception { get; }

    /// <summary>
    /// Creates a new error event args.
    /// </summary>
    public PipelineErrorEventArgs(PipelineState stateAtError, string message, Exception? exception = null)
    {
        StateAtError = stateAtError;
        Message = message;
        Exception = exception;
    }
}

/// <summary>
/// Orchestrates the dictation pipeline: recording → transcription → post-processing → pasting.
/// Manages state transitions and coordinates between all pipeline services.
/// </summary>
public interface IPipelineOrchestrator
{
    /// <summary>
    /// Raised when the pipeline state changes.
    /// </summary>
    event EventHandler<PipelineStateChangedEventArgs>? StateChanged;

    /// <summary>
    /// Raised when the pipeline completes (successfully or cancelled).
    /// </summary>
    event EventHandler<PipelineCompletedEventArgs>? Completed;

    /// <summary>
    /// Raised when an error occurs in the pipeline.
    /// </summary>
    event EventHandler<PipelineErrorEventArgs>? Error;

    /// <summary>
    /// Raised when audio level changes during recording.
    /// Provides normalized levels (0.0 to 1.0) for visual feedback.
    /// </summary>
    event EventHandler<AudioLevelEventArgs>? AudioLevelChanged;

    /// <summary>
    /// Gets the current pipeline state.
    /// </summary>
    PipelineState CurrentState { get; }

    /// <summary>
    /// Gets whether the pipeline is currently active (not Idle).
    /// </summary>
    bool IsActive { get; }

    /// <summary>
    /// Gets the current recording mode (Hold or Toggle), or null if not recording.
    /// </summary>
    RecordingMode? ActiveRecordingMode { get; }

    /// <summary>
    /// Starts the dictation pipeline with the specified recording mode.
    /// </summary>
    /// <param name="mode">The recording mode (Hold or Toggle).</param>
    /// <param name="deviceId">The microphone device ID to use, or null for default.</param>
    /// <returns>A task that completes when recording has started.</returns>
    /// <exception cref="InvalidOperationException">Thrown if the pipeline is already active.</exception>
    Task StartAsync(RecordingMode mode, string? deviceId = null);

    /// <summary>
    /// Stops recording and processes the audio through the pipeline.
    /// </summary>
    /// <returns>A task that completes when the pipeline has finished processing.</returns>
    Task StopAsync();

    /// <summary>
    /// Cancels the current pipeline operation and returns to Idle state.
    /// Safe to call at any state - will be ignored if already Idle.
    /// </summary>
    void Cancel();

    /// <summary>
    /// Gets the last transcript that was successfully pasted.
    /// Used for "Paste Again" functionality.
    /// </summary>
    string? LastTranscript { get; }
}
