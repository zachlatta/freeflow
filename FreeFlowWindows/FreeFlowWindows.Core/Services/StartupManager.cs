using Microsoft.Win32;
using FreeFlowWindows.Core.Interfaces;

namespace FreeFlowWindows.Core.Services;

/// <summary>
/// Manages Windows startup registration for the FreeFlow application.
/// Uses the Windows Registry (HKCU\Software\Microsoft\Windows\CurrentVersion\Run)
/// to enable or disable automatic startup at user login.
/// </summary>
public class StartupManager : IStartupManager
{
    /// <summary>
    /// Registry path for Windows startup applications under current user.
    /// </summary>
    private const string StartupRegistryPath = @"Software\Microsoft\Windows\CurrentVersion\Run";

    /// <summary>
    /// Default application name used for the registry key.
    /// </summary>
    private const string DefaultApplicationName = "FreeFlow";

    private readonly string _applicationName;
    private readonly string _executablePath;

    /// <inheritdoc/>
    public string ApplicationName => _applicationName;

    /// <inheritdoc/>
    public string ExecutablePath => _executablePath;

    /// <summary>
    /// Initializes a new instance of the StartupManager with default settings.
    /// Uses the current executable path and default application name.
    /// </summary>
    public StartupManager() : this(DefaultApplicationName, GetCurrentExecutablePath())
    {
    }

    /// <summary>
    /// Initializes a new instance of the StartupManager with specified settings.
    /// Useful for testing or custom configurations.
    /// </summary>
    /// <param name="applicationName">The name to use for the registry key.</param>
    /// <param name="executablePath">The full path to the application executable.</param>
    public StartupManager(string applicationName, string executablePath)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(applicationName);
        ArgumentException.ThrowIfNullOrWhiteSpace(executablePath);

        _applicationName = applicationName;
        _executablePath = executablePath;
    }

    /// <inheritdoc/>
    public bool IsRegisteredForStartup()
    {
        if (!OperatingSystem.IsWindows())
        {
            return false;
        }

        try
        {
            using var key = Registry.CurrentUser.OpenSubKey(StartupRegistryPath, writable: false);
            if (key == null)
            {
                return false;
            }

            var value = key.GetValue(_applicationName);
            if (value == null)
            {
                return false;
            }

            // Verify the registered path matches our executable
            var registeredPath = value.ToString();
            return string.Equals(registeredPath, _executablePath, StringComparison.OrdinalIgnoreCase) ||
                   string.Equals(registeredPath, $"\"{_executablePath}\"", StringComparison.OrdinalIgnoreCase);
        }
        catch (Exception)
        {
            // If we can't read the registry, assume not registered
            return false;
        }
    }

    /// <inheritdoc/>
    public bool RegisterForStartup()
    {
        if (!OperatingSystem.IsWindows())
        {
            return false;
        }

        try
        {
            using var key = Registry.CurrentUser.OpenSubKey(StartupRegistryPath, writable: true);
            if (key == null)
            {
                // Try to create the key if it doesn't exist
                using var createdKey = Registry.CurrentUser.CreateSubKey(StartupRegistryPath);
                if (createdKey == null)
                {
                    return false;
                }
                
                // Quote the path to handle spaces in the path
                createdKey.SetValue(_applicationName, $"\"{_executablePath}\"");
                return true;
            }

            // Quote the path to handle spaces in the path
            key.SetValue(_applicationName, $"\"{_executablePath}\"");
            return true;
        }
        catch (Exception)
        {
            // Registration failed (e.g., permission denied, registry access blocked)
            return false;
        }
    }

    /// <inheritdoc/>
    public bool UnregisterFromStartup()
    {
        if (!OperatingSystem.IsWindows())
        {
            return false;
        }

        try
        {
            using var key = Registry.CurrentUser.OpenSubKey(StartupRegistryPath, writable: true);
            if (key == null)
            {
                // Key doesn't exist, nothing to unregister
                return true;
            }

            // Check if our value exists
            if (key.GetValue(_applicationName) == null)
            {
                // Value doesn't exist, already unregistered
                return true;
            }

            key.DeleteValue(_applicationName, throwOnMissingValue: false);
            return true;
        }
        catch (Exception)
        {
            // Unregistration failed (e.g., permission denied)
            return false;
        }
    }

    /// <inheritdoc/>
    public bool SetStartupEnabled(bool enabled)
    {
        return enabled ? RegisterForStartup() : UnregisterFromStartup();
    }

    /// <summary>
    /// Gets the full path to the currently executing application.
    /// </summary>
    /// <returns>The full path to the executable.</returns>
    private static string GetCurrentExecutablePath()
    {
        // Environment.ProcessPath returns the path to the process executable
        // This works correctly for both .NET Framework and .NET Core/5+
        var processPath = Environment.ProcessPath;
        
        if (!string.IsNullOrEmpty(processPath))
        {
            return processPath;
        }

        // Fallback: use the entry assembly location
        var entryAssembly = System.Reflection.Assembly.GetEntryAssembly();
        if (entryAssembly != null)
        {
            var location = entryAssembly.Location;
            if (!string.IsNullOrEmpty(location))
            {
                return location;
            }
        }

        // Final fallback: use AppContext.BaseDirectory with expected exe name
        return Path.Combine(AppContext.BaseDirectory, "FreeFlowWindows.exe");
    }
}
