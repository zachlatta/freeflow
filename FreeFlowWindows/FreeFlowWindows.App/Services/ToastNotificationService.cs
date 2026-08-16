using System.Runtime.InteropServices;
using Windows.Data.Xml.Dom;
using Windows.UI.Notifications;
using FreeFlowWindows.Core.Http;
using FreeFlowWindows.Core.Interfaces;

namespace FreeFlowWindows.App.Services;

/// <summary>
/// Provides Windows 10+ toast notification support for error handling and status updates.
/// Uses the native Windows ToastNotificationManager API for modern toast notifications.
/// </summary>
public class ToastNotificationService : IToastNotificationService
{
    private const string AppUserModelId = "FreeFlow.Dictation";
    private const string ToastGroup = "FreeFlowErrors";
    
    // Default auto-dismiss timeout in seconds
    private const int DefaultTimeoutSeconds = 10;
    
    private ToastNotifier? _toastNotifier;
    private bool _disposed;
    private readonly object _lock = new();

    /// <summary>
    /// Raised when the user clicks the "Retry" action on a notification.
    /// </summary>
    public event EventHandler? RetryRequested;

    /// <summary>
    /// Raised when the user clicks the "Open Settings" action on a notification.
    /// </summary>
    public event EventHandler? OpenSettingsRequested;

    /// <inheritdoc/>
    public bool IsInitialized { get; private set; }

    /// <inheritdoc/>
    public void Initialize()
    {
        if (IsInitialized)
            return;

        lock (_lock)
        {
            if (IsInitialized)
                return;

            try
            {
                // Create toast notifier - use the app's AUMID if available, otherwise default
                // For unpackaged apps, we need to create a notifier without AUMID or use a compat method
                _toastNotifier = ToastNotificationManager.CreateToastNotifier(AppUserModelId);
                IsInitialized = true;
            }
            catch (Exception ex) when (ex is COMException || ex is InvalidOperationException)
            {
                // Fall back to creating notifier without AUMID for unpackaged apps
                try
                {
                    // For unpackaged desktop apps, use the History approach
                    _toastNotifier = ToastNotificationManager.CreateToastNotifier();
                    IsInitialized = true;
                }
                catch
                {
                    // Toast notifications not available - will use fallback balloon notifications
                    IsInitialized = false;
                }
            }
        }
    }

    /// <inheritdoc/>
    public void ShowTranscriptionError(HttpError error)
    {
        var title = "Transcription Failed";
        var message = GetUserFriendlyMessage(error, "transcription");
        var allowRetry = IsRetryableError(error);
        var showSettings = error.Type == HttpErrorType.AuthenticationError;

        ShowToast(title, message, allowRetry, showSettings);
    }

    /// <inheritdoc/>
    public void ShowPostProcessingError(HttpError error)
    {
        var title = "Processing Failed";
        var message = GetUserFriendlyMessage(error, "processing");
        
        // Post-processing failures are less critical - the raw transcript is still usable
        var allowRetry = false;
        var showSettings = error.Type == HttpErrorType.AuthenticationError;

        ShowToast(title, message, allowRetry, showSettings);
    }

    /// <inheritdoc/>
    public void ShowAuthenticationError(string? host)
    {
        var title = "API Key Invalid";
        var hostText = string.IsNullOrEmpty(host) ? "the API" : host;
        var message = $"Invalid API key for {hostText}. Please update your API key in settings.";

        ShowToast(title, message, allowRetry: false, showSettings: true);
    }

    /// <inheritdoc/>
    public void ShowRateLimitError(string? host, int? retryAfterSeconds = null)
    {
        var title = "Rate Limit Reached";
        string message;

        if (retryAfterSeconds.HasValue && retryAfterSeconds.Value > 0)
        {
            var waitTime = retryAfterSeconds.Value > 60 
                ? $"{retryAfterSeconds.Value / 60} minutes" 
                : $"{retryAfterSeconds.Value} seconds";
            message = $"API rate limit reached. Please wait {waitTime} before trying again.";
        }
        else
        {
            message = "API rate limit reached. Please wait a moment and try again.";
        }

        ShowToast(title, message, allowRetry: true, showSettings: false);
    }

    /// <inheritdoc/>
    public void ShowNetworkError(string message)
    {
        var title = "Network Error";
        var displayMessage = string.IsNullOrWhiteSpace(message) 
            ? "Unable to connect to the server. Please check your internet connection." 
            : message;

        ShowToast(title, displayMessage, allowRetry: true, showSettings: false);
    }

    /// <inheritdoc/>
    public void ShowTimeoutError(string operationName, double timeoutSeconds)
    {
        var title = $"{operationName} Timed Out";
        var message = $"The {operationName.ToLowerInvariant()} took longer than {timeoutSeconds:F0} seconds. Please check your connection and try again.";

        ShowToast(title, message, allowRetry: true, showSettings: false);
    }

    /// <inheritdoc/>
    public void ShowAudioError(string message)
    {
        var title = "Microphone Error";
        var displayMessage = string.IsNullOrWhiteSpace(message) 
            ? "No microphone available. Please connect a microphone and try again." 
            : message;

        ShowToast(title, displayMessage, allowRetry: false, showSettings: false);
    }

    /// <inheritdoc/>
    public void ShowConfigurationError(string message)
    {
        var title = "Configuration Error";
        var displayMessage = string.IsNullOrWhiteSpace(message) 
            ? "Please configure your settings before using FreeFlow." 
            : message;

        ShowToast(title, displayMessage, allowRetry: false, showSettings: true);
    }

    /// <inheritdoc/>
    public void ShowError(string title, string message, bool allowRetry = false)
    {
        ShowToast(title, message, allowRetry, showSettings: false);
    }

    /// <inheritdoc/>
    public void ShowInfo(string title, string message)
    {
        ShowToast(title, message, allowRetry: false, showSettings: false, isError: false);
    }

    /// <inheritdoc/>
    public void ClearAllNotifications()
    {
        if (!IsInitialized)
            return;

        try
        {
            var history = ToastNotificationManager.History;
            history.Clear();
        }
        catch
        {
            // Ignore errors when clearing notifications
        }
    }

    /// <summary>
    /// Shows a toast notification with the specified parameters.
    /// </summary>
    private void ShowToast(
        string title, 
        string message, 
        bool allowRetry, 
        bool showSettings, 
        bool isError = true)
    {
        if (!IsInitialized || _toastNotifier == null)
        {
            // Fall back to invoking events directly if toast not available
            // The caller should handle this by using balloon notifications
            return;
        }

        try
        {
            var toastXml = CreateToastXml(title, message, allowRetry, showSettings, isError);
            var toast = new ToastNotification(toastXml)
            {
                Tag = Guid.NewGuid().ToString("N")[..8],
                Group = ToastGroup,
                ExpirationTime = DateTimeOffset.Now.AddSeconds(DefaultTimeoutSeconds)
            };

            // Handle activation (button clicks)
            toast.Activated += OnToastActivated;
            toast.Dismissed += OnToastDismissed;
            toast.Failed += OnToastFailed;

            _toastNotifier.Show(toast);
        }
        catch (Exception)
        {
            // Toast notification failed - the application should fall back to balloon notifications
            // This is expected on older Windows versions or when toast notifications are disabled
        }
    }

    /// <summary>
    /// Creates the XML content for a toast notification.
    /// </summary>
    private static XmlDocument CreateToastXml(
        string title, 
        string message, 
        bool allowRetry, 
        bool showSettings,
        bool isError)
    {
        // Build the toast XML according to Windows toast schema
        // https://docs.microsoft.com/en-us/windows/apps/design/shell/tiles-and-notifications/adaptive-interactive-toasts
        
        var actionsXml = "";
        
        if (allowRetry || showSettings)
        {
            var buttons = new List<string>();
            
            if (allowRetry)
            {
                buttons.Add(@"<action content=""Retry"" arguments=""action=retry"" activationType=""foreground"" />");
            }
            
            if (showSettings)
            {
                buttons.Add(@"<action content=""Open Settings"" arguments=""action=settings"" activationType=""foreground"" />");
            }
            
            actionsXml = $@"<actions>{string.Join("", buttons)}</actions>";
        }

        // Use the reminder scenario for errors to make them more prominent
        var scenarioAttr = isError ? @"scenario=""reminder""" : "";
        
        var xml = $@"
<toast {scenarioAttr} duration=""short"">
    <visual>
        <binding template=""ToastGeneric"">
            <text>{EscapeXml(title)}</text>
            <text>{EscapeXml(message)}</text>
            <text placement=""attribution"">FreeFlow</text>
        </binding>
    </visual>
    {actionsXml}
    <audio silent=""false"" />
</toast>";

        var doc = new XmlDocument();
        doc.LoadXml(xml.Trim());
        return doc;
    }

    /// <summary>
    /// Escapes special XML characters in a string.
    /// </summary>
    private static string EscapeXml(string text)
    {
        if (string.IsNullOrEmpty(text))
            return text;

        return text
            .Replace("&", "&amp;")
            .Replace("<", "&lt;")
            .Replace(">", "&gt;")
            .Replace("\"", "&quot;")
            .Replace("'", "&apos;");
    }

    /// <summary>
    /// Gets a user-friendly error message based on the HTTP error type.
    /// </summary>
    private static string GetUserFriendlyMessage(HttpError error, string operation)
    {
        return error.Type switch
        {
            HttpErrorType.NetworkError => 
                $"Unable to connect to the {operation} service. Please check your internet connection.",
            
            HttpErrorType.AuthenticationError => 
                $"Invalid API key for {operation}. Please check your API key in settings.",
            
            HttpErrorType.AuthorizationError => 
                $"Access denied to {operation} service. Your API key may not have the required permissions.",
            
            HttpErrorType.RateLimited => 
                $"Rate limit exceeded for {operation}. Please wait a moment and try again.",
            
            HttpErrorType.Timeout => 
                $"The {operation} request timed out. Please check your connection and try again.",
            
            HttpErrorType.ServerError => 
                $"The {operation} service is experiencing issues. Please try again later.",
            
            HttpErrorType.PayloadTooLarge => 
                $"The recording is too large for {operation}. Try a shorter recording.",
            
            HttpErrorType.NotFoundError => 
                $"The {operation} endpoint was not found. Please check your API configuration.",
            
            HttpErrorType.BadRequest => 
                $"Invalid request for {operation}. {error.Message}",
            
            _ => error.Message
        };
    }

    /// <summary>
    /// Determines if the error is retryable (transient).
    /// </summary>
    private static bool IsRetryableError(HttpError error)
    {
        return error.Type switch
        {
            HttpErrorType.NetworkError => true,
            HttpErrorType.Timeout => true,
            HttpErrorType.RateLimited => true,
            HttpErrorType.ServerError => true,
            _ => false
        };
    }

    private void OnToastActivated(ToastNotification sender, object args)
    {
        // Parse the arguments to determine which action was clicked
        if (args is ToastActivatedEventArgs activatedArgs)
        {
            var arguments = activatedArgs.Arguments;
            
            if (arguments.Contains("action=retry"))
            {
                RetryRequested?.Invoke(this, EventArgs.Empty);
            }
            else if (arguments.Contains("action=settings"))
            {
                OpenSettingsRequested?.Invoke(this, EventArgs.Empty);
            }
        }

        // Clean up event handlers
        sender.Activated -= OnToastActivated;
        sender.Dismissed -= OnToastDismissed;
        sender.Failed -= OnToastFailed;
    }

    private void OnToastDismissed(ToastNotification sender, ToastDismissedEventArgs args)
    {
        // Clean up event handlers
        sender.Activated -= OnToastActivated;
        sender.Dismissed -= OnToastDismissed;
        sender.Failed -= OnToastFailed;
    }

    private void OnToastFailed(ToastNotification sender, ToastFailedEventArgs args)
    {
        // Clean up event handlers
        sender.Activated -= OnToastActivated;
        sender.Dismissed -= OnToastDismissed;
        sender.Failed -= OnToastFailed;
    }

    /// <inheritdoc/>
    public void Dispose()
    {
        Dispose(true);
        GC.SuppressFinalize(this);
    }

    protected virtual void Dispose(bool disposing)
    {
        if (_disposed)
            return;

        if (disposing)
        {
            lock (_lock)
            {
                try
                {
                    ClearAllNotifications();
                }
                catch
                {
                    // Ignore errors during cleanup
                }

                _toastNotifier = null;
                IsInitialized = false;
            }
        }

        _disposed = true;
    }

    ~ToastNotificationService()
    {
        Dispose(false);
    }
}
