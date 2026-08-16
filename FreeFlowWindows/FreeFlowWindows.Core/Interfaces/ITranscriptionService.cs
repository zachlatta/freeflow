namespace FreeFlowWindows.Core.Interfaces;

/// <summary>
/// Service for transcribing audio files using the Whisper API.
/// </summary>
public interface ITranscriptionService
{
    /// <summary>
    /// Transcribes an audio file and returns the transcript text.
    /// </summary>
    /// <param name="audioFilePath">Path to the audio file to transcribe.</param>
    /// <param name="cancellationToken">Cancellation token.</param>
    /// <returns>The transcription result containing the transcript or error information.</returns>
    Task<TranscriptionResult> TranscribeAsync(
        string audioFilePath,
        CancellationToken cancellationToken = default);
}

/// <summary>
/// Result of a transcription operation.
/// </summary>
public class TranscriptionResult
{
    /// <summary>
    /// Gets whether the transcription succeeded.
    /// </summary>
    public bool Success { get; }

    /// <summary>
    /// Gets the transcript text (only valid when Success is true).
    /// May be empty if the audio was silence/noise or a hallucination was detected.
    /// </summary>
    public string? Transcript { get; }

    /// <summary>
    /// Gets the error information (only valid when Success is false).
    /// </summary>
    public TranscriptionError? Error { get; }

    private TranscriptionResult(bool success, string? transcript, TranscriptionError? error)
    {
        Success = success;
        Transcript = transcript;
        Error = error;
    }

    /// <summary>
    /// Creates a successful transcription result.
    /// </summary>
    public static TranscriptionResult Ok(string transcript) => new(true, transcript, null);

    /// <summary>
    /// Creates a failed transcription result.
    /// </summary>
    public static TranscriptionResult Fail(TranscriptionError error) => new(false, null, error);
}

/// <summary>
/// Error information for a failed transcription.
/// </summary>
public class TranscriptionError
{
    /// <summary>
    /// Gets the error type category.
    /// </summary>
    public TranscriptionErrorType Type { get; }

    /// <summary>
    /// Gets the user-friendly error message.
    /// </summary>
    public string Message { get; }

    /// <summary>
    /// Creates a new transcription error.
    /// </summary>
    public TranscriptionError(TranscriptionErrorType type, string message)
    {
        Type = type;
        Message = message;
    }

    /// <summary>
    /// Creates a network error.
    /// </summary>
    public static TranscriptionError NetworkError(string message) => 
        new(TranscriptionErrorType.NetworkError, message);

    /// <summary>
    /// Creates an authentication error.
    /// </summary>
    public static TranscriptionError AuthenticationError(string message) => 
        new(TranscriptionErrorType.AuthenticationError, message);

    /// <summary>
    /// Creates a timeout error.
    /// </summary>
    public static TranscriptionError Timeout(double timeoutSeconds) => 
        new(TranscriptionErrorType.Timeout, $"Transcription timed out after {timeoutSeconds:F0}s. Check your connection and try again.");

    /// <summary>
    /// Creates an invalid response error.
    /// </summary>
    public static TranscriptionError InvalidResponse(string message) => 
        new(TranscriptionErrorType.InvalidResponse, message);

    /// <summary>
    /// Creates a server error.
    /// </summary>
    public static TranscriptionError ServerError(string message) => 
        new(TranscriptionErrorType.ServerError, message);
}

/// <summary>
/// Types of transcription errors.
/// </summary>
public enum TranscriptionErrorType
{
    /// <summary>
    /// Network connectivity issues.
    /// </summary>
    NetworkError,

    /// <summary>
    /// Authentication failure (invalid API key).
    /// </summary>
    AuthenticationError,

    /// <summary>
    /// Request timed out.
    /// </summary>
    Timeout,

    /// <summary>
    /// Invalid or unparseable response from the API.
    /// </summary>
    InvalidResponse,

    /// <summary>
    /// Server-side error (HTTP 5xx).
    /// </summary>
    ServerError
}
