namespace FreeFlowWindows.Core.Interfaces;

/// <summary>
/// Interface for managing Windows startup registration.
/// Allows the application to register or unregister itself to run automatically at user login.
/// </summary>
public interface IStartupManager
{
    /// <summary>
    /// Checks if the application is currently registered to start at Windows login.
    /// </summary>
    /// <returns>True if the application is registered for startup, false otherwise.</returns>
    bool IsRegisteredForStartup();

    /// <summary>
    /// Registers the application to start automatically at Windows login.
    /// Creates a registry entry in HKCU\Software\Microsoft\Windows\CurrentVersion\Run.
    /// </summary>
    /// <returns>True if registration was successful, false otherwise.</returns>
    bool RegisterForStartup();

    /// <summary>
    /// Unregisters the application from starting automatically at Windows login.
    /// Removes the registry entry from HKCU\Software\Microsoft\Windows\CurrentVersion\Run.
    /// </summary>
    /// <returns>True if unregistration was successful, false otherwise.</returns>
    bool UnregisterFromStartup();

    /// <summary>
    /// Toggles startup registration based on the specified enabled state.
    /// </summary>
    /// <param name="enabled">True to register for startup, false to unregister.</param>
    /// <returns>True if the operation was successful, false otherwise.</returns>
    bool SetStartupEnabled(bool enabled);

    /// <summary>
    /// Gets the application name used for the registry key.
    /// </summary>
    string ApplicationName { get; }

    /// <summary>
    /// Gets the full path to the application executable.
    /// </summary>
    string ExecutablePath { get; }
}
