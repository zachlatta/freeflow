using System.Security.AccessControl;
using System.Security.Principal;
using System.Text.Json;
using FreeFlowWindows.Core.Interfaces;
using FreeFlowWindows.Core.Models;

namespace FreeFlowWindows.Core.Services;

/// <summary>
/// Manages persistence and retrieval of application settings.
/// Settings are stored in %APPDATA%\FreeFlow\settings.json with user-only permissions.
/// </summary>
public class SettingsManager : ISettingsManager
{
    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        WriteIndented = true,
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase
    };

    private readonly string _settingsDirectory;
    private readonly string _settingsFilePath;
    private readonly bool _enforcePermissions;

    public string SettingsFilePath => _settingsFilePath;

    public SettingsManager() : this(enforcePermissions: true)
    {
    }

    /// <summary>
    /// Constructor with permission enforcement option.
    /// </summary>
    /// <param name="enforcePermissions">Whether to set user-only file permissions (can be disabled for testing).</param>
    public SettingsManager(bool enforcePermissions)
    {
        _settingsDirectory = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
            "FreeFlow");
        _settingsFilePath = Path.Combine(_settingsDirectory, "settings.json");
        _enforcePermissions = enforcePermissions;
    }

    /// <summary>
    /// Constructor for testing with custom path.
    /// </summary>
    /// <param name="settingsFilePath">Custom path for the settings file.</param>
    /// <param name="enforcePermissions">Whether to set user-only file permissions.</param>
    internal SettingsManager(string settingsFilePath, bool enforcePermissions = false)
    {
        _settingsFilePath = settingsFilePath;
        _settingsDirectory = Path.GetDirectoryName(settingsFilePath) 
            ?? throw new ArgumentException("Invalid path", nameof(settingsFilePath));
        _enforcePermissions = enforcePermissions;
    }

    public AppSettings Load()
    {
        try
        {
            if (!File.Exists(_settingsFilePath))
            {
                return CreateDefaultSettings();
            }

            // Validate file permissions before reading
            if (_enforcePermissions && !ValidateFilePermissions(_settingsFilePath))
            {
                // File has insecure permissions, fix them
                SetUserOnlyPermissions(_settingsFilePath);
            }

            var json = File.ReadAllText(_settingsFilePath);
            var settings = JsonSerializer.Deserialize<AppSettings>(json, JsonOptions);
            
            return settings ?? CreateDefaultSettings();
        }
        catch (JsonException)
        {
            // If JSON is malformed, return defaults
            return CreateDefaultSettings();
        }
        catch (Exception)
        {
            // For any other error (IO, permissions), return defaults
            return CreateDefaultSettings();
        }
    }

    public void Save(AppSettings settings)
    {
        ArgumentNullException.ThrowIfNull(settings);

        // Ensure directory exists with proper permissions
        EnsureDirectoryExists();

        // Atomic write: write to temp file, then rename
        var tempPath = _settingsFilePath + ".tmp." + Guid.NewGuid().ToString("N");
        
        try
        {
            var json = JsonSerializer.Serialize(settings, JsonOptions);

            // Write to temp file
            File.WriteAllText(tempPath, json);

            // Set permissions on temp file before moving
            if (_enforcePermissions)
            {
                SetUserOnlyPermissions(tempPath);
            }

            // Atomic rename (overwrites existing file)
            File.Move(tempPath, _settingsFilePath, overwrite: true);
        }
        catch
        {
            // Clean up temp file if something goes wrong
            TryDeleteFile(tempPath);
            throw;
        }
    }

    public void Reset()
    {
        Save(CreateDefaultSettings());
    }

    /// <summary>
    /// Creates a new AppSettings instance with all default values.
    /// </summary>
    private static AppSettings CreateDefaultSettings()
    {
        return new AppSettings();
    }

    /// <summary>
    /// Ensures the settings directory exists and has proper permissions.
    /// </summary>
    private void EnsureDirectoryExists()
    {
        if (!Directory.Exists(_settingsDirectory))
        {
            Directory.CreateDirectory(_settingsDirectory);
            
            if (_enforcePermissions)
            {
                SetUserOnlyDirectoryPermissions(_settingsDirectory);
            }
        }
    }

    /// <summary>
    /// Sets file permissions to allow only the current user to read/write.
    /// This matches macOS 0600 permissions for secure settings storage.
    /// </summary>
    private static void SetUserOnlyPermissions(string filePath)
    {
        if (!OperatingSystem.IsWindows())
        {
            return;
        }

        try
        {
            var fileInfo = new FileInfo(filePath);
            var security = fileInfo.GetAccessControl();

            // Get current user identity
            var currentUser = WindowsIdentity.GetCurrent();
            var userSid = currentUser.User;

            if (userSid == null)
            {
                return;
            }

            // Remove inherited permissions
            security.SetAccessRuleProtection(isProtected: true, preserveInheritance: false);

            // Clear existing access rules
            var existingRules = security.GetAccessRules(
                includeExplicit: true, 
                includeInherited: true, 
                typeof(SecurityIdentifier));
            
            foreach (FileSystemAccessRule rule in existingRules)
            {
                security.RemoveAccessRule(rule);
            }

            // Add full control for current user only
            var userRule = new FileSystemAccessRule(
                userSid,
                FileSystemRights.FullControl,
                AccessControlType.Allow);
            
            security.AddAccessRule(userRule);

            // Apply the new security settings
            fileInfo.SetAccessControl(security);
        }
        catch (Exception)
        {
            // If we can't set permissions (e.g., on network drives), continue without them
            // The file is still in the user's AppData which has some inherent protection
        }
    }

    /// <summary>
    /// Sets directory permissions to allow only the current user to access.
    /// </summary>
    private static void SetUserOnlyDirectoryPermissions(string directoryPath)
    {
        if (!OperatingSystem.IsWindows())
        {
            return;
        }

        try
        {
            var directoryInfo = new DirectoryInfo(directoryPath);
            var security = directoryInfo.GetAccessControl();

            // Get current user identity
            var currentUser = WindowsIdentity.GetCurrent();
            var userSid = currentUser.User;

            if (userSid == null)
            {
                return;
            }

            // Remove inherited permissions
            security.SetAccessRuleProtection(isProtected: true, preserveInheritance: false);

            // Clear existing access rules
            var existingRules = security.GetAccessRules(
                includeExplicit: true, 
                includeInherited: true, 
                typeof(SecurityIdentifier));
            
            foreach (FileSystemAccessRule rule in existingRules)
            {
                security.RemoveAccessRule(rule);
            }

            // Add full control for current user only
            var userRule = new FileSystemAccessRule(
                userSid,
                FileSystemRights.FullControl,
                InheritanceFlags.ContainerInherit | InheritanceFlags.ObjectInherit,
                PropagationFlags.None,
                AccessControlType.Allow);
            
            security.AddAccessRule(userRule);

            // Apply the new security settings
            directoryInfo.SetAccessControl(security);
        }
        catch (Exception)
        {
            // If we can't set permissions, continue without them
        }
    }

    /// <summary>
    /// Validates that the file has secure permissions (only current user can access).
    /// </summary>
    /// <returns>True if permissions are secure, false if they need to be fixed.</returns>
    private static bool ValidateFilePermissions(string filePath)
    {
        if (!OperatingSystem.IsWindows())
        {
            return true;
        }

        try
        {
            var fileInfo = new FileInfo(filePath);
            var security = fileInfo.GetAccessControl();
            var currentUser = WindowsIdentity.GetCurrent();
            var userSid = currentUser.User;

            if (userSid == null)
            {
                return true;
            }

            var rules = security.GetAccessRules(
                includeExplicit: true, 
                includeInherited: true, 
                typeof(SecurityIdentifier));

            // Check if any rule grants access to someone other than current user
            foreach (FileSystemAccessRule rule in rules)
            {
                if (rule.AccessControlType == AccessControlType.Allow)
                {
                    var ruleSid = rule.IdentityReference as SecurityIdentifier;
                    
                    // Allow SYSTEM account (SID S-1-5-18) for Windows services
                    if (ruleSid != null && 
                        !ruleSid.Equals(userSid) && 
                        !ruleSid.IsWellKnown(WellKnownSidType.LocalSystemSid))
                    {
                        // Someone other than current user or SYSTEM has access
                        return false;
                    }
                }
            }

            return true;
        }
        catch (Exception)
        {
            // If we can't check permissions, assume they're OK
            return true;
        }
    }

    /// <summary>
    /// Attempts to delete a file, ignoring any errors.
    /// </summary>
    private static void TryDeleteFile(string filePath)
    {
        try
        {
            if (File.Exists(filePath))
            {
                File.Delete(filePath);
            }
        }
        catch
        {
            // Ignore cleanup errors
        }
    }
}
