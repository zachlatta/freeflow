using FreeFlowWindows.Core.Http;

namespace FreeFlowWindows.Core.Interfaces;

/// <summary>
/// Interface for displaying toast notifications for errors and status updates.
/// Provides modern Windows 10+ toast notification support with action buttons.
/// </summary>
public interface IToastNotificationService : IDisposable
{
    /// <summary>
    /// Raised when the user clicks the "Retry" action on a notification.
    /// </summary>
    event EventHandler? RetryRequested;

    /// <summary>
    /// Raised when the user clicks the "Open Settings" action on a notification.
    /// </summary>
    event EventHandler? OpenSettingsRequested;

    /// <summary>
    /// Gets whether the toast notification service has been initialized.
    /// </summary>
    bool IsInitialized { get; }

    /// <summary>
    /// Initializes the toast notification service.
    /// Must be called before showing notifications.
    /// </summary>
    void Initialize();

    /// <summary>
    /// Shows a toast notification for a transcription error.
    /// </summary>
    /// <param name="error">The HTTP error that occurred during transcription.</param>
    void ShowTranscriptionError(HttpError error);

    /// <summary>
    /// Shows a toast notification for a post-processing (LLM) error.
    /// </summary>
    /// <param name="error">The HTTP error that occurred during post-processing.</param>
    void ShowPostProcessingError(HttpError error);

    /// <summary>
    /// Shows a toast notification for an API authentication error.
    /// Includes an action to open settings for API key configuration.
    /// </summary>
    /// <param name="host">The API host that returned the auth error.</param>
    void ShowAuthenticationError(string? host);

    /// <summary>
    /// Shows a toast notification for a rate limit error.
    /// </summary>
    /// <param name="host">The API host that returned the rate limit error.</param>
    /// <param name="retryAfterSeconds">Optional retry-after value from the API response.</param>
    void ShowRateLimitError(string? host, int? retryAfterSeconds = null);

    /// <summary>
    /// Shows a toast notification for a network/connectivity error.
    /// Includes a retry action.
    /// </summary>
    /// <param name="message">The error message to display.</param>
    void ShowNetworkError(string message);

    /// <summary>
    /// Shows a toast notification for a timeout error.
    /// Includes a retry action.
    /// </summary>
    /// <param name="operationName">The name of the operation that timed out (e.g., "Transcription", "Processing").</param>
    /// <param name="timeoutSeconds">The timeout value that was exceeded.</param>
    void ShowTimeoutError(string operationName, double timeoutSeconds);

    /// <summary>
    /// Shows a toast notification for a microphone/audio error.
    /// </summary>
    /// <param name="message">The error message to display.</param>
    void ShowAudioError(string message);

    /// <summary>
    /// Shows a toast notification for a configuration error.
    /// Includes an action to open settings.
    /// </summary>
    /// <param name="message">The error message to display.</param>
    void ShowConfigurationError(string message);

    /// <summary>
    /// Shows a general error toast notification.
    /// </summary>
    /// <param name="title">The notification title.</param>
    /// <param name="message">The notification message.</param>
    /// <param name="allowRetry">Whether to show a retry action button.</param>
    void ShowError(string title, string message, bool allowRetry = false);

    /// <summary>
    /// Shows an informational toast notification.
    /// </summary>
    /// <param name="title">The notification title.</param>
    /// <param name="message">The notification message.</param>
    void ShowInfo(string title, string message);

    /// <summary>
    /// Clears all pending toast notifications from this application.
    /// </summary>
    void ClearAllNotifications();
}
