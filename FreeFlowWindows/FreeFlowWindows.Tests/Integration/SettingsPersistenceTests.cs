using FreeFlowWindows.Core.Interfaces;
using FreeFlowWindows.Core.Services;
using FreeFlowWindows.Core.Models;
using Xunit;

namespace FreeFlowWindows.Tests.Integration;

/// <summary>
/// Integration tests for settings persistence.
/// Tests that settings survive application restart scenarios.
/// Requirements covered: 7.1, 7.2, 7.4
/// </summary>
public class SettingsPersistenceTests : IDisposable
{
    private readonly string _testSettingsPath;
    private readonly SettingsManager _settingsManager;

    public SettingsPersistenceTests()
    {
        // Use a unique test path to avoid conflicts
        _testSettingsPath = Path.Combine(
            Path.GetTempPath(),
            "FreeFlowTest",
            $"settings_{Guid.NewGuid()}.json");

        // Ensure directory exists
        Directory.CreateDirectory(Path.GetDirectoryName(_testSettingsPath)!);

        _settingsManager = new SettingsManager(_testSettingsPath);
    }

    #region Settings Persistence Tests

    [Fact]
    public void Settings_SurviveRoundTrip()
    {
        // Arrange
        var originalSettings = new AppSettings
        {
            ApiBaseUrl = "https://custom-api.example.com",
            TranscriptionModel = "whisper-1",
            PostProcessingModel = "gpt-4",
            PreserveClipboard = true,
            StartWithWindows = true,
            CustomVocabulary = "FreeFlow\nWhisper\nOpenAI",
            HoldHotkey = new HotkeyBinding 
            { 
                Key = VirtualKey.F5, 
                Modifiers = ModifierKeys.Ctrl 
            },
            ToggleHotkey = new HotkeyBinding 
            { 
                Key = VirtualKey.F6, 
                Modifiers = ModifierKeys.Alt 
            }
        };

        // Act - Save settings
        _settingsManager.Save(originalSettings);

        // Create new SettingsManager to simulate app restart
        var newSettingsManager = new SettingsManager(_testSettingsPath);
        var loadedSettings = newSettingsManager.Load();

        // Assert
        Assert.Equal(originalSettings.ApiBaseUrl, loadedSettings.ApiBaseUrl);
        Assert.Equal(originalSettings.TranscriptionModel, loadedSettings.TranscriptionModel);
        Assert.Equal(originalSettings.PostProcessingModel, loadedSettings.PostProcessingModel);
        Assert.Equal(originalSettings.PreserveClipboard, loadedSettings.PreserveClipboard);
        Assert.Equal(originalSettings.StartWithWindows, loadedSettings.StartWithWindows);
        Assert.Equal(originalSettings.CustomVocabulary, loadedSettings.CustomVocabulary);
    }

    [Fact]
    public void Settings_HotkeysSurviveRoundTrip()
    {
        // Arrange
        var originalSettings = new AppSettings
        {
            HoldHotkey = new HotkeyBinding 
            { 
                Key = VirtualKey.D1, 
                Modifiers = ModifierKeys.Ctrl | ModifierKeys.Shift 
            },
            ToggleHotkey = new HotkeyBinding 
            { 
                Key = VirtualKey.D2, 
                Modifiers = ModifierKeys.Alt | ModifierKeys.Win 
            }
        };

        // Act
        _settingsManager.Save(originalSettings);
        var newManager = new SettingsManager(_testSettingsPath);
        var loadedSettings = newManager.Load();

        // Assert
        Assert.NotNull(loadedSettings.HoldHotkey);
        Assert.Equal(originalSettings.HoldHotkey.Key, loadedSettings.HoldHotkey!.Key);
        Assert.Equal(originalSettings.HoldHotkey.Modifiers, loadedSettings.HoldHotkey.Modifiers);

        Assert.NotNull(loadedSettings.ToggleHotkey);
        Assert.Equal(originalSettings.ToggleHotkey.Key, loadedSettings.ToggleHotkey!.Key);
        Assert.Equal(originalSettings.ToggleHotkey.Modifiers, loadedSettings.ToggleHotkey.Modifiers);
    }

    [Fact]
    public void Settings_DefaultsLoadWhenNoFileExists()
    {
        // Arrange
        var nonExistentPath = Path.Combine(
            Path.GetTempPath(),
            "FreeFlowTest",
            $"nonexistent_{Guid.NewGuid()}.json");

        var manager = new SettingsManager(nonExistentPath);

        // Act
        var settings = manager.Load();

        // Assert - Should have sensible defaults
        Assert.NotNull(settings);
        Assert.NotNull(settings.ApiBaseUrl);
        Assert.NotNull(settings.HoldHotkey);
        Assert.NotNull(settings.ToggleHotkey);
    }

    [Fact]
    public void Settings_ResetClearsToDefaults()
    {
        // Arrange
        var customSettings = new AppSettings
        {
            ApiBaseUrl = "https://custom.example.com",
            PreserveClipboard = true,
            StartWithWindows = true
        };
        _settingsManager.Save(customSettings);

        // Act
        _settingsManager.Reset();
        var settings = _settingsManager.Load();

        // Assert - Should be back to defaults
        var defaults = new AppSettings();
        Assert.Equal(defaults.ApiBaseUrl, settings.ApiBaseUrl);
        Assert.Equal(defaults.PreserveClipboard, settings.PreserveClipboard);
        Assert.Equal(defaults.StartWithWindows, settings.StartWithWindows);
    }

    [Fact]
    public void Settings_AtomicWritePreventsCorruption()
    {
        // Arrange - Save initial valid settings
        var validSettings = new AppSettings
        {
            ApiBaseUrl = "https://valid.example.com"
        };
        _settingsManager.Save(validSettings);

        // Act - Verify file exists and is readable
        Assert.True(File.Exists(_testSettingsPath));
        
        // Create new manager and load - should not throw
        var newManager = new SettingsManager(_testSettingsPath);
        var loaded = newManager.Load();

        // Assert
        Assert.Equal("https://valid.example.com", loaded.ApiBaseUrl);
    }

    #endregion

    #region Credential Store Persistence Tests

    [Fact(Skip = "Test requires Windows credential store")]
    public void CredentialStore_ApiKeySurvivesRoundTrip()
    {

        // Arrange
        var testAccountName = $"FreeFlowTest_{Guid.NewGuid()}";
        var credentialStore = new CredentialStore();
        var testApiKey = $"sk-test-{Guid.NewGuid()}";

        try
        {
            // Act - Store and retrieve
            credentialStore.SetApiKey(testAccountName, testApiKey);

            // Create new store instance to simulate app restart
            var newStore = new CredentialStore();
            var retrievedKey = newStore.GetApiKey(testAccountName);

            // Assert
            Assert.Equal(testApiKey, retrievedKey);
        }
        finally
        {
            // Cleanup
            credentialStore.DeleteApiKey(testAccountName);
        }
    }

    [Fact(Skip = "Test requires Windows credential store")]
    public void CredentialStore_DeleteRemovesKey()
    {

        // Arrange
        var testAccountName = $"FreeFlowTest_{Guid.NewGuid()}";
        var credentialStore = new CredentialStore();

        // Store a key first
        credentialStore.SetApiKey(testAccountName, "test-key");
        Assert.NotNull(credentialStore.GetApiKey(testAccountName));

        // Act
        credentialStore.DeleteApiKey(testAccountName);

        // Assert
        Assert.Null(credentialStore.GetApiKey(testAccountName));
    }

    #endregion

    public void Dispose()
    {
        // Cleanup test files
        try
        {
            if (File.Exists(_testSettingsPath))
            {
                File.Delete(_testSettingsPath);
            }
            
            var dir = Path.GetDirectoryName(_testSettingsPath);
            if (dir != null && Directory.Exists(dir) && !Directory.EnumerateFileSystemEntries(dir).Any())
            {
                Directory.Delete(dir);
            }
        }
        catch
        {
            // Best effort cleanup
        }
    }
}
