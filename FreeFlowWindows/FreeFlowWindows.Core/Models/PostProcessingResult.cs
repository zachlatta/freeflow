namespace FreeFlowWindows.Core.Models;

/// <summary>
/// Result of a post-processing operation.
/// </summary>
public class PostProcessingResult
{
    /// <summary>
    /// Gets whether the post-processing succeeded.
    /// </summary>
    public bool Success { get; }

    /// <summary>
    /// Gets the cleaned transcript text (only valid when Success is true).
    /// Empty string indicates the transcript was determined to be silence/noise.
    /// </summary>
    public string? CleanedTranscript { get; }

    /// <summary>
    /// Gets the prompt that was used for debugging/display purposes.
    /// </summary>
    public string? PromptUsed { get; }

    /// <summary>
    /// Gets the error information (only valid when Success is false).
    /// </summary>
    public PostProcessingError? Error { get; }

    private PostProcessingResult(bool success, string? cleanedTranscript, string? promptUsed, PostProcessingError? error)
    {
        Success = success;
        CleanedTranscript = cleanedTranscript;
        PromptUsed = promptUsed;
        Error = error;
    }

    /// <summary>
    /// Creates a successful post-processing result.
    /// </summary>
    /// <param name="cleanedTranscript">The cleaned transcript.</param>
    /// <param name="promptUsed">The prompt that was used.</param>
    public static PostProcessingResult Ok(string cleanedTranscript, string promptUsed) => 
        new(true, cleanedTranscript, promptUsed, null);

    /// <summary>
    /// Creates an empty result (transcript was silence/noise only).
    /// </summary>
    public static PostProcessingResult Empty() => 
        new(true, string.Empty, null, null);

    /// <summary>
    /// Creates a failed post-processing result.
    /// </summary>
    /// <param name="error">The error information.</param>
    public static PostProcessingResult Fail(PostProcessingError error) => 
        new(false, null, null, error);

    /// <summary>
    /// Creates a fallback result using the raw transcript when LLM fails.
    /// </summary>
    /// <param name="rawTranscript">The raw transcript to use as fallback.</param>
    public static PostProcessingResult Fallback(string rawTranscript) => 
        new(true, rawTranscript.Trim(), string.Empty, null);
}

/// <summary>
/// Error information for a failed post-processing operation.
/// </summary>
public class PostProcessingError
{
    /// <summary>
    /// Gets the error type category.
    /// </summary>
    public PostProcessingErrorType Type { get; }

    /// <summary>
    /// Gets the user-friendly error message.
    /// </summary>
    public string Message { get; }

    /// <summary>
    /// Gets the model that was being used when the error occurred.
    /// </summary>
    public string? Model { get; }

    /// <summary>
    /// Gets the retry-after duration in seconds for rate limit errors.
    /// </summary>
    public TimeSpan? RetryAfter { get; }

    /// <summary>
    /// Creates a new post-processing error.
    /// </summary>
    public PostProcessingError(PostProcessingErrorType type, string message, string? model = null, TimeSpan? retryAfter = null)
    {
        Type = type;
        Message = message;
        Model = model;
        RetryAfter = retryAfter;
    }

    /// <summary>
    /// Creates a network error.
    /// </summary>
    public static PostProcessingError NetworkError(string message) =>
        new(PostProcessingErrorType.NetworkError, message);

    /// <summary>
    /// Creates an authentication error.
    /// </summary>
    public static PostProcessingError AuthenticationError(string message) =>
        new(PostProcessingErrorType.AuthenticationError, message);

    /// <summary>
    /// Creates a rate limit error.
    /// </summary>
    public static PostProcessingError RateLimited(string model, TimeSpan retryAfter) =>
        new(PostProcessingErrorType.RateLimited, 
            $"Model {model} rate-limited — retry in {(int)retryAfter.TotalSeconds}s",
            model,
            retryAfter);

    /// <summary>
    /// Creates a timeout error.
    /// </summary>
    public static PostProcessingError Timeout(double timeoutSeconds) =>
        new(PostProcessingErrorType.Timeout, 
            $"Post-processing timed out after {(int)timeoutSeconds}s");

    /// <summary>
    /// Creates an empty output error.
    /// </summary>
    public static PostProcessingError EmptyOutput() =>
        new(PostProcessingErrorType.EmptyOutput, "Post-processing returned empty output");

    /// <summary>
    /// Creates an invalid response error.
    /// </summary>
    public static PostProcessingError InvalidResponse(string message) =>
        new(PostProcessingErrorType.InvalidResponse, $"Invalid post-processing response: {message}");

    /// <summary>
    /// Creates a suspected instruction execution error.
    /// </summary>
    public static PostProcessingError SuspectedInstructionExecution() =>
        new(PostProcessingErrorType.SuspectedInstructionExecution, 
            "Post-processing output looked like it answered the transcript instead of cleaning it");
}

/// <summary>
/// Types of post-processing errors.
/// </summary>
public enum PostProcessingErrorType
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
    /// Rate limit exceeded (HTTP 429).
    /// </summary>
    RateLimited,

    /// <summary>
    /// Request timed out.
    /// </summary>
    Timeout,

    /// <summary>
    /// LLM returned empty content.
    /// </summary>
    EmptyOutput,

    /// <summary>
    /// Invalid or unparseable response from the API.
    /// </summary>
    InvalidResponse,

    /// <summary>
    /// LLM appeared to execute instructions in the transcript instead of cleaning it.
    /// </summary>
    SuspectedInstructionExecution
}
