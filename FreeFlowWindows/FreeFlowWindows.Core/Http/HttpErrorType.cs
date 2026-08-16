namespace FreeFlowWindows.Core.Http;

/// <summary>
/// Categories of HTTP errors for user-friendly messaging.
/// </summary>
public enum HttpErrorType
{
    /// <summary>
    /// Network connectivity issues (DNS failure, connection refused, etc.)
    /// </summary>
    NetworkError,

    /// <summary>
    /// Authentication failure (HTTP 401)
    /// </summary>
    AuthenticationError,

    /// <summary>
    /// Authorization failure (HTTP 403)
    /// </summary>
    AuthorizationError,

    /// <summary>
    /// Resource not found (HTTP 404)
    /// </summary>
    NotFoundError,

    /// <summary>
    /// Request entity too large (HTTP 413)
    /// </summary>
    PayloadTooLarge,

    /// <summary>
    /// Bad request (HTTP 400)
    /// </summary>
    BadRequest,

    /// <summary>
    /// Rate limit exceeded (HTTP 429)
    /// </summary>
    RateLimited,

    /// <summary>
    /// Server-side error (HTTP 5xx)
    /// </summary>
    ServerError,

    /// <summary>
    /// Request timed out
    /// </summary>
    Timeout,

    /// <summary>
    /// Other/unknown HTTP error
    /// </summary>
    Unknown
}

/// <summary>
/// Result type for HTTP operations that may fail.
/// </summary>
/// <typeparam name="T">The success value type.</typeparam>
public class HttpResult<T>
{
    /// <summary>
    /// Gets whether the operation succeeded.
    /// </summary>
    public bool Success { get; }

    /// <summary>
    /// Gets the successful result value (only valid when Success is true).
    /// </summary>
    public T? Value { get; }

    /// <summary>
    /// Gets the error information (only valid when Success is false).
    /// </summary>
    public HttpError? Error { get; }

    private HttpResult(bool success, T? value, HttpError? error)
    {
        Success = success;
        Value = value;
        Error = error;
    }

    /// <summary>
    /// Creates a successful result.
    /// </summary>
    public static HttpResult<T> Ok(T value) => new(true, value, null);

    /// <summary>
    /// Creates a failed result.
    /// </summary>
    public static HttpResult<T> Fail(HttpError error) => new(false, default, error);
}

/// <summary>
/// Represents an HTTP error with type, message, and optional status code.
/// </summary>
public class HttpError
{
    /// <summary>
    /// Gets the error type category.
    /// </summary>
    public HttpErrorType Type { get; }

    /// <summary>
    /// Gets the user-friendly error message.
    /// </summary>
    public string Message { get; }

    /// <summary>
    /// Gets the HTTP status code (if applicable).
    /// </summary>
    public int? StatusCode { get; }

    /// <summary>
    /// Gets the raw response body (for debugging, not shown to users).
    /// </summary>
    public string? ResponseBody { get; }

    /// <summary>
    /// Creates a new HTTP error.
    /// </summary>
    public HttpError(HttpErrorType type, string message, int? statusCode = null, string? responseBody = null)
    {
        Type = type;
        Message = message;
        StatusCode = statusCode;
        ResponseBody = responseBody;
    }

    /// <summary>
    /// Creates an HTTP error from a status code with a friendly message.
    /// </summary>
    public static HttpError FromStatusCode(int statusCode, string? host, string? responseBody = null)
    {
        var type = GetErrorTypeFromStatusCode(statusCode);
        var message = HttpTransport.FriendlyHttpMessage(statusCode, host);
        return new HttpError(type, message, statusCode, responseBody);
    }

    /// <summary>
    /// Creates an HTTP error for a network failure.
    /// </summary>
    public static HttpError NetworkFailure(string message)
    {
        return new HttpError(HttpErrorType.NetworkError, message);
    }

    /// <summary>
    /// Creates an HTTP error for a timeout.
    /// </summary>
    public static HttpError TimeoutFailure(double timeoutSeconds)
    {
        return new HttpError(
            HttpErrorType.Timeout,
            $"Request timed out after {timeoutSeconds:F0}s. Check your connection and try again.");
    }

    private static HttpErrorType GetErrorTypeFromStatusCode(int statusCode)
    {
        return statusCode switch
        {
            401 => HttpErrorType.AuthenticationError,
            403 => HttpErrorType.AuthorizationError,
            404 => HttpErrorType.NotFoundError,
            413 => HttpErrorType.PayloadTooLarge,
            400 => HttpErrorType.BadRequest,
            429 => HttpErrorType.RateLimited,
            >= 500 and < 600 => HttpErrorType.ServerError,
            _ => HttpErrorType.Unknown
        };
    }
}
