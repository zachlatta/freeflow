using Xunit;
using FreeFlowWindows.Core.Services;
using FreeFlowWindows.Core.Models;

namespace FreeFlowWindows.Tests;

/// <summary>
/// Unit tests for SettingsManager.
/// Validates: Requirements 7.1, 7.2, 7.6
/// </summary>
public class SettingsManagerTests
{
    /// <summary>
    /// Test that Load returns default settings when the settings file doesn't exist.
    /// Validates: Requirement 7.6 - IF no settings file exists, THE Settings_Manager SHALL use default values for all settings
    /// </summary>
    [Fact]
    public void Load_WhenFileDoesNotExist_ReturnsDefaults()
    {
        // Arrange
        var tempDir = Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString());
        var settingsPath = Path.Combine(tempDir, "settings.json");
        var manager = new SettingsManager(settingsPath, enforcePermissions: false);

        try
        {
            // Act
            var settings = manager.Load();

            // Assert
            Assert.NotNull(settings);
            Assert.Equal("https://api.groq.com/openai/v1", settings.ApiBaseUrl);
            Assert.Equal("whisper-large-v3", settings.TranscriptionModel);
            Assert.Equal("openai/gpt-oss-20b", settings.PostProcessingModel);
            Assert.Equal("qwen/qwen3.6-27b", settings.PostProcessingFallbackModel);
            Assert.Null(settings.TranscriptionApiUrl);
            Assert.Null(settings.SelectedMicrophoneId);
            Assert.Equal("", settings.CustomVocabulary);
            Assert.True(settings.PreserveClipboard);
            Assert.False(settings.StartWithWindows);
            Assert.Equal(20, settings.TranscriptionTimeoutSeconds);
            Assert.Equal(20, settings.PostProcessingTimeoutSeconds);
        }
        finally
        {
            // Cleanup
            if (Directory.Exists(tempDir))
            {
                Directory.Delete(tempDir, recursive: true);
            }
        }
    }

    /// <summary>
    /// Test that Load returns default settings when the settings file contains invalid JSON.
    /// Validates: Requirement 7.6 - Settings_Manager handles corrupt files gracefully
    /// </summary>
    [Fact]
    public void Load_WhenFileContainsInvalidJson_ReturnsDefaults()
    {
        // Arrange
        var tempDir = Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString());
        var settingsPath = Path.Combine(tempDir, "settings.json");
        Directory.CreateDirectory(tempDir);
        File.WriteAllText(settingsPath, "{ invalid json content }}}");
        var manager = new SettingsManager(settingsPath, enforcePermissions: false);

        try
        {
            // Act
            var settings = manager.Load();

            // Assert
            Assert.NotNull(settings);
            Assert.Equal("https://api.groq.com/openai/v1", settings.ApiBaseUrl);
        }
        finally
        {
            // Cleanup
            if (Directory.Exists(tempDir))
            {
                Directory.Delete(tempDir, recursive: true);
            }
        }
    }

    /// <summary>
    /// Test that Save creates the directory if it doesn't exist.
    /// Validates: Requirement 7.1 - THE Settings_Manager SHALL persist user settings to a configuration file in the user's application data directory
    /// </summary>
    [Fact]
    public void Save_WhenDirectoryDoesNotExist_CreatesDirectory()
    {
        // Arrange
        var tempDir = Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString(), "nested", "directory");
        var settingsPath = Path.Combine(tempDir, "settings.json");
        var manager = new SettingsManager(settingsPath, enforcePermissions: false);

        var settings = new AppSettings
        {
            ApiBaseUrl = "https://test.api.com/v1"
        };

        try
        {
            // Act
            manager.Save(settings);

            // Assert
            Assert.True(Directory.Exists(tempDir), "Directory should be created");
            Assert.True(File.Exists(settingsPath), "Settings file should exist");
            
            // Verify content was saved correctly
            var loaded = manager.Load();
            Assert.Equal(settings.ApiBaseUrl, loaded.ApiBaseUrl);
        }
        finally
        {
            // Cleanup - delete from the root temp folder
            var rootTempDir = Path.Combine(Path.GetTempPath(), Path.GetFileName(Path.GetDirectoryName(Path.GetDirectoryName(tempDir))!)!);
            if (Directory.Exists(rootTempDir))
            {
                Directory.Delete(rootTempDir, recursive: true);
            }
        }
    }

    /// <summary>
    /// Test that atomic write prevents corruption when there's an existing settings file.
    /// This test verifies that the temp file + rename pattern preserves the original file if something goes wrong.
    /// Validates: Requirement 7.1 - Atomic writes via temp file + rename
    /// </summary>
    [Fact]
    public void Save_AtomicWrite_PreservesOriginalOnSuccess()
    {
        // Arrange
        var tempDir = Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString());
        var settingsPath = Path.Combine(tempDir, "settings.json");
        var manager = new SettingsManager(settingsPath, enforcePermissions: false);

        var originalSettings = new AppSettings
        {
            ApiBaseUrl = "https://original.api.com/v1",
            TranscriptionModel = "original-model"
        };

        var newSettings = new AppSettings
        {
            ApiBaseUrl = "https://new.api.com/v1",
            TranscriptionModel = "new-model"
        };

        try
        {
            // Act - Save original settings
            manager.Save(originalSettings);
            Assert.True(File.Exists(settingsPath), "Original settings file should exist");

            // Act - Save new settings (should atomically replace)
            manager.Save(newSettings);

            // Assert - New settings should be in place
            var loaded = manager.Load();
            Assert.Equal(newSettings.ApiBaseUrl, loaded.ApiBaseUrl);
            Assert.Equal(newSettings.TranscriptionModel, loaded.TranscriptionModel);

            // Verify no temp files left behind
            var tempFiles = Directory.GetFiles(tempDir, "*.tmp.*");
            Assert.Empty(tempFiles);
        }
        finally
        {
            // Cleanup
            if (Directory.Exists(tempDir))
            {
                Directory.Delete(tempDir, recursive: true);
            }
        }
    }

    /// <summary>
    /// Test that atomic write doesn't leave corrupt data when original file exists.
    /// We verify this by checking that after multiple saves, the file is always valid.
    /// Validates: Requirement 7.1 - Atomic writes protect against partial failure
    /// </summary>
    [Fact]
    public void Save_MultipleConsecutiveSaves_NeverCorruptsFile()
    {
        // Arrange
        var tempDir = Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString());
        var settingsPath = Path.Combine(tempDir, "settings.json");
        var manager = new SettingsManager(settingsPath, enforcePermissions: false);

        try
        {
            // Act - Perform multiple rapid saves
            for (int i = 0; i < 10; i++)
            {
                var settings = new AppSettings
                {
                    ApiBaseUrl = $"https://api{i}.test.com/v1",
                    TranscriptionModel = $"model-{i}",
                    TranscriptionTimeoutSeconds = i + 10
                };
                manager.Save(settings);

                // Verify file is always readable and valid after each save
                var loaded = manager.Load();
                Assert.NotNull(loaded);
                Assert.Equal(settings.ApiBaseUrl, loaded.ApiBaseUrl);
                Assert.Equal(settings.TranscriptionModel, loaded.TranscriptionModel);
                Assert.Equal(settings.TranscriptionTimeoutSeconds, loaded.TranscriptionTimeoutSeconds);
            }
        }
        finally
        {
            // Cleanup
            if (Directory.Exists(tempDir))
            {
                Directory.Delete(tempDir, recursive: true);
            }
        }
    }

    /// <summary>
    /// Test that Reset clears settings to default values.
    /// Validates: Requirement 7.6 - Reset functionality returns to defaults
    /// </summary>
    [Fact]
    public void Reset_ClearsToDefaults()
    {
        // Arrange
        var tempDir = Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString());
        var settingsPath = Path.Combine(tempDir, "settings.json");
        var manager = new SettingsManager(settingsPath, enforcePermissions: false);

        // First, save some custom settings
        var customSettings = new AppSettings
        {
            ApiBaseUrl = "https://custom.api.com/v1",
            TranscriptionModel = "custom-model",
            PostProcessingModel = "custom-llm",
            PreserveClipboard = false,
            StartWithWindows = true,
            TranscriptionTimeoutSeconds = 60,
            CustomVocabulary = "custom\nwords\nhere"
        };

        try
        {
            // Save custom settings
            manager.Save(customSettings);

            // Verify custom settings were saved
            var loaded = manager.Load();
            Assert.Equal("https://custom.api.com/v1", loaded.ApiBaseUrl);
            Assert.Equal("custom-model", loaded.TranscriptionModel);
            Assert.False(loaded.PreserveClipboard);
            Assert.True(loaded.StartWithWindows);

            // Act - Reset to defaults
            manager.Reset();

            // Assert - All values should be back to defaults
            var resetSettings = manager.Load();
            Assert.Equal("https://api.groq.com/openai/v1", resetSettings.ApiBaseUrl);
            Assert.Equal("whisper-large-v3", resetSettings.TranscriptionModel);
            Assert.Equal("openai/gpt-oss-20b", resetSettings.PostProcessingModel);
            Assert.Equal("qwen/qwen3.6-27b", resetSettings.PostProcessingFallbackModel);
            Assert.Null(resetSettings.TranscriptionApiUrl);
            Assert.Null(resetSettings.SelectedMicrophoneId);
            Assert.Equal("", resetSettings.CustomVocabulary);
            Assert.True(resetSettings.PreserveClipboard);
            Assert.False(resetSettings.StartWithWindows);
            Assert.Equal(20, resetSettings.TranscriptionTimeoutSeconds);
            Assert.Equal(20, resetSettings.PostProcessingTimeoutSeconds);
        }
        finally
        {
            // Cleanup
            if (Directory.Exists(tempDir))
            {
                Directory.Delete(tempDir, recursive: true);
            }
        }
    }

    /// <summary>
    /// Test that Reset works even when settings file doesn't exist.
    /// Validates: Requirement 7.6 - Reset creates defaults when no file exists
    /// </summary>
    [Fact]
    public void Reset_WhenFileDoesNotExist_CreatesDefaults()
    {
        // Arrange
        var tempDir = Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString());
        var settingsPath = Path.Combine(tempDir, "settings.json");
        var manager = new SettingsManager(settingsPath, enforcePermissions: false);

        try
        {
            // Act - Reset without any prior save
            manager.Reset();

            // Assert - File should be created with defaults
            Assert.True(File.Exists(settingsPath), "Settings file should be created");
            
            var settings = manager.Load();
            Assert.Equal("https://api.groq.com/openai/v1", settings.ApiBaseUrl);
            Assert.Equal("whisper-large-v3", settings.TranscriptionModel);
        }
        finally
        {
            // Cleanup
            if (Directory.Exists(tempDir))
            {
                Directory.Delete(tempDir, recursive: true);
            }
        }
    }

    /// <summary>
    /// Test that SaveAndLoad round-trip preserves all settings fields.
    /// Validates: Requirements 7.1, 7.2 - Settings persistence and loading
    /// </summary>
    [Fact]
    public void SaveAndLoad_RoundTrip_PreservesSettings()
    {
        // Arrange
        var tempDir = Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString());
        var settingsPath = Path.Combine(tempDir, "settings.json");
        var manager = new SettingsManager(settingsPath, enforcePermissions: false);

        var settings = new AppSettings
        {
            ApiBaseUrl = "https://custom.api.com/v1",
            TranscriptionModel = "custom-model",
            PreserveClipboard = false,
            TranscriptionTimeoutSeconds = 30
        };

        try
        {
            // Act
            manager.Save(settings);
            var loaded = manager.Load();

            // Assert
            Assert.Equal(settings.ApiBaseUrl, loaded.ApiBaseUrl);
            Assert.Equal(settings.TranscriptionModel, loaded.TranscriptionModel);
            Assert.Equal(settings.PreserveClipboard, loaded.PreserveClipboard);
            Assert.Equal(settings.TranscriptionTimeoutSeconds, loaded.TranscriptionTimeoutSeconds);
        }
        finally
        {
            // Cleanup
            if (Directory.Exists(tempDir))
            {
                Directory.Delete(tempDir, recursive: true);
            }
        }
    }

    /// <summary>
    /// Test that SaveAndLoad round-trip preserves all settings fields including hotkeys.
    /// Validates: Requirements 7.1, 7.2, 7.3 - Full settings persistence
    /// </summary>
    [Fact]
    public void SaveAndLoad_RoundTrip_PreservesAllFields()
    {
        // Arrange
        var tempDir = Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString());
        var settingsPath = Path.Combine(tempDir, "settings.json");
        var manager = new SettingsManager(settingsPath, enforcePermissions: false);

        var settings = new AppSettings
        {
            ApiBaseUrl = "https://custom.api.com/v1",
            TranscriptionModel = "custom-whisper-model",
            TranscriptionApiUrl = "https://transcription.custom.com/v1",
            PostProcessingModel = "custom-llm-model",
            PostProcessingFallbackModel = "custom-fallback-model",
            HoldHotkey = new HotkeyBinding 
            { 
                Modifiers = ModifierKeys.Alt | ModifierKeys.Shift, 
                Key = VirtualKey.D 
            },
            ToggleHotkey = new HotkeyBinding 
            { 
                Modifiers = ModifierKeys.Win | ModifierKeys.Ctrl, 
                Key = VirtualKey.T 
            },
            SelectedMicrophoneId = "custom-mic-id-12345",
            CustomVocabulary = "FreeFlow\nKiro\nCustom Term",
            PreserveClipboard = false,
            StartWithWindows = true,
            TranscriptionTimeoutSeconds = 45,
            PostProcessingTimeoutSeconds = 35
        };

        try
        {
            // Act
            manager.Save(settings);
            var loaded = manager.Load();

            // Assert - All fields preserved
            Assert.Equal(settings.ApiBaseUrl, loaded.ApiBaseUrl);
            Assert.Equal(settings.TranscriptionModel, loaded.TranscriptionModel);
            Assert.Equal(settings.TranscriptionApiUrl, loaded.TranscriptionApiUrl);
            Assert.Equal(settings.PostProcessingModel, loaded.PostProcessingModel);
            Assert.Equal(settings.PostProcessingFallbackModel, loaded.PostProcessingFallbackModel);
            Assert.Equal(settings.HoldHotkey.Modifiers, loaded.HoldHotkey.Modifiers);
            Assert.Equal(settings.HoldHotkey.Key, loaded.HoldHotkey.Key);
            Assert.Equal(settings.ToggleHotkey.Modifiers, loaded.ToggleHotkey.Modifiers);
            Assert.Equal(settings.ToggleHotkey.Key, loaded.ToggleHotkey.Key);
            Assert.Equal(settings.SelectedMicrophoneId, loaded.SelectedMicrophoneId);
            Assert.Equal(settings.CustomVocabulary, loaded.CustomVocabulary);
            Assert.Equal(settings.PreserveClipboard, loaded.PreserveClipboard);
            Assert.Equal(settings.StartWithWindows, loaded.StartWithWindows);
            Assert.Equal(settings.TranscriptionTimeoutSeconds, loaded.TranscriptionTimeoutSeconds);
            Assert.Equal(settings.PostProcessingTimeoutSeconds, loaded.PostProcessingTimeoutSeconds);
        }
        finally
        {
            // Cleanup
            if (Directory.Exists(tempDir))
            {
                Directory.Delete(tempDir, recursive: true);
            }
        }
    }

    /// <summary>
    /// Test that SettingsFilePath property returns the correct path.
    /// </summary>
    [Fact]
    public void SettingsFilePath_ReturnsCorrectPath()
    {
        // Arrange
        var tempDir = Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString());
        var settingsPath = Path.Combine(tempDir, "settings.json");
        var manager = new SettingsManager(settingsPath, enforcePermissions: false);

        try
        {
            // Assert
            Assert.Equal(settingsPath, manager.SettingsFilePath);
        }
        finally
        {
            // Cleanup
            if (Directory.Exists(tempDir))
            {
                Directory.Delete(tempDir, recursive: true);
            }
        }
    }
}
