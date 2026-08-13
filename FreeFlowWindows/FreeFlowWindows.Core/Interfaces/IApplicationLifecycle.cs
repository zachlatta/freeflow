namespace FreeFlowWindows.Core.Interfaces;

/// <summary>
/// Manages application lifecycle including startup initialization and graceful shutdown.
/// Coordinates cleanup of all services and resources when the application exits.
/// </summary>
public interface IApplicationLifecycle : IDisposable
{
    /// <summary>
    /// Raised when shutdown is initiated but before cleanup begins.
    /// Handlers can perform any last-minute operations.
    /// </summary>
    event EventHandler? ShutdownInitiated;

    /// <summary>
    /// Raised after all resources have been cleaned up and shutdown is complete.
    /// </summary>
    event EventHandler? ShutdownCompleted;

    /// <summary>
    /// Gets whether the application is currently in the process of shutting down.
    /// </summary>
    bool IsShuttingDown { get; }

    /// <summary>
    /// Gets whether the application has been fully initialized.
    /// </summary>
    bool IsInitialized { get; }

    /// <summary>
    /// Initializes all application components on startup.
    /// Sets up services, registers hotkeys, and initializes the system tray.
    /// </summary>
    /// <returns>A task that completes when initialization is finished.</returns>
    Task InitializeAsync();

    /// <summary>
    /// Performs graceful shutdown of all application resources.
    /// Stops any active recording, unregisters hotkeys, disposes services.
    /// </summary>
    /// <param name="cancellationToken">Optional cancellation token for timeout scenarios.</param>
    /// <returns>A task that completes when shutdown is finished.</returns>
    Task ShutdownAsync(CancellationToken cancellationToken = default);

    /// <summary>
    /// Handles Windows session ending events (logout, shutdown, restart).
    /// This is called by the WPF Application.SessionEnding event handler.
    /// </summary>
    /// <param name="isLoggingOff">True if the user is logging off, false if Windows is shutting down.</param>
    void HandleSessionEnding(bool isLoggingOff);

    /// <summary>
    /// Requests application exit. This initiates the shutdown sequence.
    /// </summary>
    void RequestExit();
}
