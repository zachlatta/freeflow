using FreeFlowWindows.Core.Http;
using FreeFlowWindows.Core.Interfaces;
using FreeFlowWindows.Core.Models;

namespace FreeFlowWindows.App.Services;

/// <summary>
/// Helper class that coordinates between ToastNotificationService and SystemTrayManager
/// for comprehensive error notification handling.
/// </summary>
/// <remarks>
/// This helper provides a unified API for showing notifications, automatically using
/// toast notifications when available and falling back to balloon notifications when not.
/// </remarks>
public class NotificationHelper : IDisposable
{
    private readonly IToastNotificationService _toastService;
    private readonly ISystemTrayManager _trayManager;
    private bool _disposed;

    /// <summary>
    /// Creates a new NotificationHelper instance.
    /// </summary>
    /// <param name="toastService">The toast notification service.</param>
    /// <param name="trayManager">The system tray manager for fallback notifications.</param>
    public NotificationHelper(IToastNotificationService toastService, ISystemTrayManager trayManager)
    {
        _toastService = toastService ?? throw new ArgumentNullException(nameof(toastService));
        _trayManager = trayManager ?? throw new ArgumentNullException(nameof(trayManager));

        // Forward events from toast service
        _toastService.RetryRequested += OnRetryRequested;
        _toastService.OpenSettingsRequested += OnOpenSettingsRequested;
    }

    /// <summary>
    /// Raised when the user requests a retry from a notification.
    /// </summary>
    public event EventHandler? RetryRequested;

    /// <summary>
    /// Raised when the user requests to open settings from a notification.
    /// </summary>
    public event EventHandler? OpenSettingsRequested;

    /// <summary>
    /// Shows a notification for a transcription error.
    /// Uses toast notification if available, falls back to balloon.
    /// </summary>
    /// <param name="error">The HTTP error that occurred.</param>
    public void ShowTranscriptionError(HttpError error)
    {
        if (_toastService.IsInitialized)
        {
            _toastService.ShowTranscriptionError(error);
        }
        else
        {
            var message = GetFallbackMessage(error, "Transcription");
            _trayManager.ShowBalloonNotification("Transcription Failed", message, NotificationType.Error);
        }

        _trayManager.UpdateIcon(AppStatus.Error);
    }

    /// <summary>
    /// Shows a notification for a post-processing error.
    /// Uses toast notification if available, falls back to balloon.
    /// </summary>
    /// <param name="error">The HTTP error that occurred.</param>
    public void ShowPostProcessingError(HttpError error)
    {
        if (_toastService.IsInitialized)
        {
            _toastService.ShowPostProcessingError(error);
        }
        else
        {
            var message = GetFallbackMessage(error, "Processing");
            _trayManager.ShowBalloonNotification("Processing Failed", message, NotificationType.Warning);
        }
    }

    /// <summary>
    /// Shows a notification for an authentication error.
    /// </summary>
    /// <param name="host">The API host that returned the auth error.</param>
    public void ShowAuthenticationError(string? host)
    {
        if (_toastService.IsInitialized)
        {
            _toastService.ShowAuthenticationError(host);
        }
        else
        {
            var hostText = string.IsNullOrEmpty(host) ? "the API" : host;
            _trayManager.ShowBalloonNotification(
                "API Key Invalid",
                $"Invalid API key for {hostText}. Please update your API key in settings.",
                NotificationType.Error);
        }

        _trayManager.UpdateIcon(AppStatus.Error);
    }

    /// <summary>
    /// Shows a notification for a rate limit error.
    /// </summary>
    /// <param name="host">The API host that returned the rate limit error.</param>
    /// <param name="retryAfterSeconds">Optional retry-after value.</param>
    public void ShowRateLimitError(string? host, int? retryAfterSeconds = null)
    {
        if (_toastService.IsInitialized)
        {
            _toastService.ShowRateLimitError(host, retryAfterSeconds);
        }
        else
        {
            var message = retryAfterSeconds.HasValue && retryAfterSeconds.Value > 0
                ? $"Rate limit reached. Please wait {retryAfterSeconds.Value} seconds."
                : "Rate limit reached. Please wait a moment and try again.";
            _trayManager.ShowBalloonNotification("Rate Limit", message, NotificationType.Warning);
        }
    }

    /// <summary>
    /// Shows a notification for a network error.
    /// </summary>
    /// <param name="message">The error message.</param>
    public void ShowNetworkError(string message)
    {
        if (_toastService.IsInitialized)
        {
            _toastService.ShowNetworkError(message);
        }
        else
        {
            _trayManager.ShowBalloonNotification(
                "Network Error",
                message ?? "Unable to connect. Please check your internet connection.",
                NotificationType.Error);
        }

        _trayManager.UpdateIcon(AppStatus.Error);
    }

    /// <summary>
    /// Shows a notification for a timeout error.
    /// </summary>
    /// <param name="operationName">The name of the operation that timed out.</param>
    /// <param name="timeoutSeconds">The timeout duration in seconds.</param>
    public void ShowTimeoutError(string operationName, double timeoutSeconds)
    {
        if (_toastService.IsInitialized)
        {
            _toastService.ShowTimeoutError(operationName, timeoutSeconds);
        }
        else
        {
            _trayManager.ShowBalloonNotification(
                $"{operationName} Timed Out",
                $"Request timed out after {timeoutSeconds:F0}s. Please try again.",
                NotificationType.Warning);
        }
    }

    /// <summary>
    /// Shows a notification for an audio/microphone error.
    /// </summary>
    /// <param name="message">The error message.</param>
    public void ShowAudioError(string message)
    {
        if (_toastService.IsInitialized)
        {
            _toastService.ShowAudioError(message);
        }
        else
        {
            _trayManager.ShowBalloonNotification(
                "Microphone Error",
                message ?? "No microphone available.",
                NotificationType.Error);
        }

        _trayManager.UpdateIcon(AppStatus.Error);
    }

    /// <summary>
    /// Shows a notification for a configuration error.
    /// </summary>
    /// <param name="message">The error message.</param>
    public void ShowConfigurationError(string message)
    {
        if (_toastService.IsInitialized)
        {
            _toastService.ShowConfigurationError(message);
        }
        else
        {
            _trayManager.ShowBalloonNotification(
                "Configuration Error",
                message ?? "Please configure FreeFlow in settings.",
                NotificationType.Warning);
        }
    }

    /// <summary>
    /// Shows a general error notification.
    /// </summary>
    /// <param name="title">The notification title.</param>
    /// <param name="message">The notification message.</param>
    /// <param name="allowRetry">Whether to show a retry option (toast only).</param>
    public void ShowError(string title, string message, bool allowRetry = false)
    {
        if (_toastService.IsInitialized)
        {
            _toastService.ShowError(title, message, allowRetry);
        }
        else
        {
            _trayManager.ShowBalloonNotification(title, message, NotificationType.Error);
        }

        _trayManager.UpdateIcon(AppStatus.Error);
    }

    /// <summary>
    /// Shows an informational notification.
    /// </summary>
    /// <param name="title">The notification title.</param>
    /// <param name="message">The notification message.</param>
    public void ShowInfo(string title, string message)
    {
        if (_toastService.IsInitialized)
        {
            _toastService.ShowInfo(title, message);
        }
        else
        {
            _trayManager.ShowBalloonNotification(title, message, NotificationType.Info);
        }
    }

    /// <summary>
    /// Gets a fallback message for balloon notifications.
    /// </summary>
    private static string GetFallbackMessage(HttpError error, string operation)
    {
        return error.Type switch
        {
            HttpErrorType.NetworkError => $"Network error during {operation.ToLowerInvariant()}. Check your connection.",
            HttpErrorType.AuthenticationError => "Invalid API key. Please check your settings.",
            HttpErrorType.RateLimited => "Rate limit reached. Please wait and try again.",
            HttpErrorType.Timeout => $"{operation} timed out. Please try again.",
            HttpErrorType.ServerError => "Server error. Please try again later.",
            _ => error.Message
        };
    }

    private void OnRetryRequested(object? sender, EventArgs e)
    {
        RetryRequested?.Invoke(this, e);
    }

    private void OnOpenSettingsRequested(object? sender, EventArgs e)
    {
        OpenSettingsRequested?.Invoke(this, e);
    }

    /// <inheritdoc/>
    public void Dispose()
    {
        if (_disposed)
            return;

        _toastService.RetryRequested -= OnRetryRequested;
        _toastService.OpenSettingsRequested -= OnOpenSettingsRequested;

        _disposed = true;
    }
}
