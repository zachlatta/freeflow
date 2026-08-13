namespace FreeFlowWindows.Core.Models;

/// <summary>
/// Event arguments for recording errors.
/// </summary>
public class RecordingErrorEventArgs : EventArgs
{
    /// <summary>
    /// The type of recording error that occurred.
    /// </summary>
    public RecordingErrorType ErrorType { get; }

    /// <summary>
    /// A human-readable error message.
    /// </summary>
    public string Message { get; }

    /// <summary>
    /// The underlying exception, if any.
    /// </summary>
    public Exception? Exception { get; }

    /// <summary>
    /// Creates a new RecordingErrorEventArgs with the specified values.
    /// </summary>
    /// <param name="errorType">The type of error.</param>
    /// <param name="message">The error message.</param>
    /// <param name="exception">The underlying exception, if any.</param>
    public RecordingErrorEventArgs(RecordingErrorType errorType, string message, Exception? exception = null)
    {
        ErrorType = errorType;
        Message = message ?? throw new ArgumentNullException(nameof(message));
        Exception = exception;
    }
}

/// <summary>
/// Types of recording errors.
/// </summary>
public enum RecordingErrorType
{
    /// <summary>
    /// No microphone or audio input device is available.
    /// </summary>
    NoDevice,

    /// <summary>
    /// The selected device is unavailable (disconnected or in use).
    /// </summary>
    DeviceUnavailable,

    /// <summary>
    /// The microphone failed during recording (watchdog timeout).
    /// </summary>
    MicrophoneFailure,

    /// <summary>
    /// Failed to write audio data to the output file.
    /// </summary>
    WriteError,

    /// <summary>
    /// An unknown error occurred during recording.
    /// </summary>
    Unknown
}
