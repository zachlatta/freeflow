using FreeFlowWindows.Core.Models;

namespace FreeFlowWindows.Core.Interfaces;

/// <summary>
/// Manages persistence and retrieval of application settings.
/// </summary>
public interface ISettingsManager
{
    /// <summary>
    /// Loads settings from the configuration file.
    /// Returns default settings if the file doesn't exist.
    /// </summary>
    AppSettings Load();

    /// <summary>
    /// Saves the provided settings to the configuration file.
    /// Uses atomic write (temp file + rename) to prevent corruption.
    /// </summary>
    void Save(AppSettings settings);

    /// <summary>
    /// Resets settings to default values.
    /// </summary>
    void Reset();

    /// <summary>
    /// Gets the path to the settings file.
    /// </summary>
    string SettingsFilePath { get; }
}
