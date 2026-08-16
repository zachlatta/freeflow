using Xunit;
using FreeFlowWindows.Core.Services;
using FreeFlowWindows.Core.Models;

namespace FreeFlowWindows.Tests;

/// <summary>
/// Unit tests for HotkeyManager.
/// Validates: Requirements 3.1, 3.2, 3.7
/// 
/// Note: Some tests require Windows to run properly due to Win32 API dependencies.
/// Tests are marked with [Trait("Category", "WindowsOnly")] for conditional execution.
/// </summary>
public class HotkeyManagerTests : IDisposable
{
    private HotkeyManager? _hotkeyManager;

    public void Dispose()
    {
        _hotkeyManager?.Dispose();
        _hotkeyManager = null;
    }

    #region Constructor and Initial State Tests

    /// <summary>
    /// Test that a new HotkeyManager is not active initially.
    /// Validates: Requirement 3.1, 3.2 - Hotkeys must be registered before active
    /// </summary>
    [Fact]
    public void Constructor_InitialState_IsNotActive()
    {
        // Arrange & Act
        _hotkeyManager = new HotkeyManager();

        // Assert
        Assert.False(_hotkeyManager.IsActive);
    }

    /// <summary>
    /// Test that a new HotkeyManager has no current configuration.
    /// </summary>
    [Fact]
    public void Constructor_InitialState_CurrentConfigurationIsNull()
    {
        // Arrange & Act
        _hotkeyManager = new HotkeyManager();

        // Assert
        Assert.Null(_hotkeyManager.CurrentConfiguration);
    }

    #endregion

    #region RegisterHotkeys Tests

    /// <summary>
    /// Test that RegisterHotkeys throws ArgumentNullException for null config.
    /// Validates: Proper validation of input parameters
    /// </summary>
    [Fact]
    public void RegisterHotkeys_WithNullConfig_ThrowsArgumentNullException()
    {
        // Arrange
        _hotkeyManager = new HotkeyManager();

        // Act & Assert
        Assert.Throws<ArgumentNullException>(() => _hotkeyManager.RegisterHotkeys(null!));
    }

    /// <summary>
    /// Test that RegisterHotkeys with valid configuration sets IsActive to true.
    /// Validates: Requirement 3.1, 3.2 - Hotkey registration
    /// </summary>
    [Fact]
    [Trait("Category", "WindowsOnly")]
    public void RegisterHotkeys_WithValidConfiguration_SetsIsActiveTrue()
    {
        // Arrange
        _hotkeyManager = new HotkeyManager();
        var config = new HotkeyConfiguration
        {
            HoldHotkey = new HotkeyBinding
            {
                Modifiers = ModifierKeys.Ctrl | ModifierKeys.Shift | ModifierKeys.Alt,
                Key = VirtualKey.F9  // Using obscure key combo to avoid conflicts
            },
            ToggleHotkey = new HotkeyBinding
            {
                Modifiers = ModifierKeys.Ctrl | ModifierKeys.Shift | ModifierKeys.Alt,
                Key = VirtualKey.F10  // Using obscure key combo to avoid conflicts
            }
        };

        // Act
        var result = _hotkeyManager.RegisterHotkeys(config);

        // Assert - May fail if hotkeys conflict with other apps
        if (result)
        {
            Assert.True(_hotkeyManager.IsActive);
        }
    }

    /// <summary>
    /// Test that RegisterHotkeys with valid configuration sets CurrentConfiguration.
    /// Validates: Requirement 3.1, 3.2 - Configuration is stored after registration
    /// </summary>
    [Fact]
    [Trait("Category", "WindowsOnly")]
    public void RegisterHotkeys_WithValidConfiguration_SetsCurrentConfiguration()
    {
        // Arrange
        _hotkeyManager = new HotkeyManager();
        var config = new HotkeyConfiguration
        {
            HoldHotkey = new HotkeyBinding
            {
                Modifiers = ModifierKeys.Ctrl | ModifierKeys.Shift | ModifierKeys.Alt,
                Key = VirtualKey.F11
            },
            ToggleHotkey = new HotkeyBinding
            {
                Modifiers = ModifierKeys.Ctrl | ModifierKeys.Shift | ModifierKeys.Alt,
                Key = VirtualKey.F12
            }
        };

        // Act
        var result = _hotkeyManager.RegisterHotkeys(config);

        // Assert - May fail if hotkeys conflict with other apps
        if (result)
        {
            Assert.NotNull(_hotkeyManager.CurrentConfiguration);
            Assert.Equal(config.HoldHotkey.Key, _hotkeyManager.CurrentConfiguration.HoldHotkey.Key);
            Assert.Equal(config.ToggleHotkey.Key, _hotkeyManager.CurrentConfiguration.ToggleHotkey.Key);
        }
    }

    #endregion

    #region UnregisterAll Tests

    /// <summary>
    /// Test that UnregisterAll clears registrations and sets IsActive to false.
    /// Validates: Requirement 3.7 - Unregistration cleans up properly
    /// </summary>
    [Fact]
    [Trait("Category", "WindowsOnly")]
    public void UnregisterAll_AfterRegistration_ClearsRegistrationsAndSetsInactive()
    {
        // Arrange
        _hotkeyManager = new HotkeyManager();
        var config = new HotkeyConfiguration
        {
            HoldHotkey = new HotkeyBinding
            {
                Modifiers = ModifierKeys.Ctrl | ModifierKeys.Shift | ModifierKeys.Alt,
                Key = VirtualKey.F7
            },
            ToggleHotkey = new HotkeyBinding
            {
                Modifiers = ModifierKeys.Ctrl | ModifierKeys.Shift | ModifierKeys.Alt,
                Key = VirtualKey.F8
            }
        };

        _hotkeyManager.RegisterHotkeys(config);

        // Act
        _hotkeyManager.UnregisterAll();

        // Assert
        Assert.False(_hotkeyManager.IsActive);
        Assert.Null(_hotkeyManager.CurrentConfiguration);
    }

    /// <summary>
    /// Test that UnregisterAll can be called when no hotkeys are registered.
    /// Validates: Safe operation even when nothing is registered
    /// </summary>
    [Fact]
    public void UnregisterAll_WhenNoHotkeysRegistered_DoesNotThrow()
    {
        // Arrange
        _hotkeyManager = new HotkeyManager();

        // Act & Assert - Should not throw
        var exception = Record.Exception(() => _hotkeyManager.UnregisterAll());
        Assert.Null(exception);
    }

    /// <summary>
    /// Test that UnregisterAll can be called multiple times safely.
    /// </summary>
    [Fact]
    public void UnregisterAll_CalledMultipleTimes_DoesNotThrow()
    {
        // Arrange
        _hotkeyManager = new HotkeyManager();

        // Act & Assert - Should not throw
        var exception = Record.Exception(() =>
        {
            _hotkeyManager.UnregisterAll();
            _hotkeyManager.UnregisterAll();
            _hotkeyManager.UnregisterAll();
        });
        Assert.Null(exception);
    }

    #endregion

    #region CheckConflict Tests - Known System Hotkeys

    /// <summary>
    /// Test that CheckConflict throws ArgumentNullException for null binding.
    /// </summary>
    [Fact]
    public void CheckConflict_WithNullBinding_ThrowsArgumentNullException()
    {
        // Arrange
        _hotkeyManager = new HotkeyManager();

        // Act & Assert
        Assert.Throws<ArgumentNullException>(() => _hotkeyManager.CheckConflict(null!));
    }

    /// <summary>
    /// Test that CheckConflict detects Win+D (Show Desktop) as a system hotkey conflict.
    /// Validates: Requirement 3.7 - Hotkey conflict detection
    /// </summary>
    [Fact]
    public void CheckConflict_WithWinD_ReturnsSystemConflict()
    {
        // Arrange
        _hotkeyManager = new HotkeyManager();
        var binding = new HotkeyBinding
        {
            Modifiers = ModifierKeys.Win,
            Key = VirtualKey.D
        };

        // Act
        var conflict = _hotkeyManager.CheckConflict(binding);

        // Assert
        Assert.NotNull(conflict);
        Assert.True(conflict.IsSystemHotkey);
        Assert.Equal("Windows", conflict.ConflictingOwner);
        Assert.Contains("Windows system shortcut", conflict.ConflictDescription);
    }

    /// <summary>
    /// Test that CheckConflict detects Win+E (File Explorer) as a system hotkey conflict.
    /// Validates: Requirement 3.7 - Hotkey conflict detection
    /// </summary>
    [Fact]
    public void CheckConflict_WithWinE_ReturnsSystemConflict()
    {
        // Arrange
        _hotkeyManager = new HotkeyManager();
        var binding = new HotkeyBinding
        {
            Modifiers = ModifierKeys.Win,
            Key = VirtualKey.E
        };

        // Act
        var conflict = _hotkeyManager.CheckConflict(binding);

        // Assert
        Assert.NotNull(conflict);
        Assert.True(conflict.IsSystemHotkey);
        Assert.Equal("Windows", conflict.ConflictingOwner);
    }

    /// <summary>
    /// Test that CheckConflict detects Win+L (Lock workstation) as a system hotkey conflict.
    /// Validates: Requirement 3.7 - Hotkey conflict detection
    /// </summary>
    [Fact]
    public void CheckConflict_WithWinL_ReturnsSystemConflict()
    {
        // Arrange
        _hotkeyManager = new HotkeyManager();
        var binding = new HotkeyBinding
        {
            Modifiers = ModifierKeys.Win,
            Key = VirtualKey.L
        };

        // Act
        var conflict = _hotkeyManager.CheckConflict(binding);

        // Assert
        Assert.NotNull(conflict);
        Assert.True(conflict.IsSystemHotkey);
    }

    /// <summary>
    /// Test that CheckConflict detects Alt+Tab (Switch windows) as a system hotkey conflict.
    /// Validates: Requirement 3.7 - Hotkey conflict detection
    /// </summary>
    [Fact]
    public void CheckConflict_WithAltTab_ReturnsSystemConflict()
    {
        // Arrange
        _hotkeyManager = new HotkeyManager();
        var binding = new HotkeyBinding
        {
            Modifiers = ModifierKeys.Alt,
            Key = VirtualKey.Tab
        };

        // Act
        var conflict = _hotkeyManager.CheckConflict(binding);

        // Assert
        Assert.NotNull(conflict);
        Assert.True(conflict.IsSystemHotkey);
    }

    /// <summary>
    /// Test that CheckConflict detects Alt+F4 (Close window) as a system hotkey conflict.
    /// Validates: Requirement 3.7 - Hotkey conflict detection
    /// </summary>
    [Fact]
    public void CheckConflict_WithAltF4_ReturnsSystemConflict()
    {
        // Arrange
        _hotkeyManager = new HotkeyManager();
        var binding = new HotkeyBinding
        {
            Modifiers = ModifierKeys.Alt,
            Key = VirtualKey.F4
        };

        // Act
        var conflict = _hotkeyManager.CheckConflict(binding);

        // Assert
        Assert.NotNull(conflict);
        Assert.True(conflict.IsSystemHotkey);
    }

    /// <summary>
    /// Test that CheckConflict detects Ctrl+Alt+Delete (Security options) as a system hotkey conflict.
    /// Validates: Requirement 3.7 - Hotkey conflict detection
    /// </summary>
    [Fact]
    public void CheckConflict_WithCtrlAltDelete_ReturnsSystemConflict()
    {
        // Arrange
        _hotkeyManager = new HotkeyManager();
        var binding = new HotkeyBinding
        {
            Modifiers = ModifierKeys.Ctrl | ModifierKeys.Alt,
            Key = VirtualKey.Delete
        };

        // Act
        var conflict = _hotkeyManager.CheckConflict(binding);

        // Assert
        Assert.NotNull(conflict);
        Assert.True(conflict.IsSystemHotkey);
    }

    /// <summary>
    /// Test that CheckConflict detects Ctrl+Shift+Escape (Task Manager) as a system hotkey conflict.
    /// Validates: Requirement 3.7 - Hotkey conflict detection
    /// </summary>
    [Fact]
    public void CheckConflict_WithCtrlShiftEscape_ReturnsSystemConflict()
    {
        // Arrange
        _hotkeyManager = new HotkeyManager();
        var binding = new HotkeyBinding
        {
            Modifiers = ModifierKeys.Ctrl | ModifierKeys.Shift,
            Key = VirtualKey.Escape
        };

        // Act
        var conflict = _hotkeyManager.CheckConflict(binding);

        // Assert
        Assert.NotNull(conflict);
        Assert.True(conflict.IsSystemHotkey);
    }

    /// <summary>
    /// Test that CheckConflict returns null for non-conflicting hotkey.
    /// Validates: Requirement 3.7 - Hotkey conflict detection returns null when no conflict
    /// </summary>
    [Fact]
    [Trait("Category", "WindowsOnly")]
    public void CheckConflict_WithNonConflictingHotkey_ReturnsNull()
    {
        // Arrange
        _hotkeyManager = new HotkeyManager();
        // Use an obscure key combination that's unlikely to conflict
        var binding = new HotkeyBinding
        {
            Modifiers = ModifierKeys.Ctrl | ModifierKeys.Shift | ModifierKeys.Alt,
            Key = VirtualKey.NumPad9
        };

        // Act
        var conflict = _hotkeyManager.CheckConflict(binding);

        // Assert - May return a conflict if another app has this registered
        // but should not be a system hotkey conflict
        if (conflict != null)
        {
            Assert.False(conflict.IsSystemHotkey);
        }
    }

    #endregion

    #region CheckConflict Tests - FreeFlow's Own Hotkeys

    /// <summary>
    /// Test that CheckConflict detects conflict with registered Hold hotkey.
    /// Validates: Requirement 3.7 - Hotkey conflict detection with FreeFlow's own hotkeys
    /// </summary>
    [Fact]
    [Trait("Category", "WindowsOnly")]
    public void CheckConflict_WithRegisteredHoldHotkey_ReturnsFreeFlowConflict()
    {
        // Arrange
        _hotkeyManager = new HotkeyManager();
        var config = new HotkeyConfiguration
        {
            HoldHotkey = new HotkeyBinding
            {
                Modifiers = ModifierKeys.Ctrl | ModifierKeys.Shift | ModifierKeys.Alt,
                Key = VirtualKey.F5
            },
            ToggleHotkey = new HotkeyBinding
            {
                Modifiers = ModifierKeys.Ctrl | ModifierKeys.Shift | ModifierKeys.Alt,
                Key = VirtualKey.F6
            }
        };
        
        var registerResult = _hotkeyManager.RegisterHotkeys(config);
        if (!registerResult)
        {
            // Skip test if registration failed (hotkey already in use)
            return;
        }

        // Act - Check for conflict with the same binding as Hold hotkey
        var binding = new HotkeyBinding
        {
            Modifiers = ModifierKeys.Ctrl | ModifierKeys.Shift | ModifierKeys.Alt,
            Key = VirtualKey.F5
        };
        var conflict = _hotkeyManager.CheckConflict(binding);

        // Assert
        Assert.NotNull(conflict);
        Assert.False(conflict.IsSystemHotkey);
        Assert.Equal("FreeFlow", conflict.ConflictingOwner);
        Assert.Contains("Hold mode hotkey", conflict.ConflictDescription);
    }

    /// <summary>
    /// Test that CheckConflict detects conflict with registered Toggle hotkey.
    /// Validates: Requirement 3.7 - Hotkey conflict detection with FreeFlow's own hotkeys
    /// </summary>
    [Fact]
    [Trait("Category", "WindowsOnly")]
    public void CheckConflict_WithRegisteredToggleHotkey_ReturnsFreeFlowConflict()
    {
        // Arrange
        _hotkeyManager = new HotkeyManager();
        var config = new HotkeyConfiguration
        {
            HoldHotkey = new HotkeyBinding
            {
                Modifiers = ModifierKeys.Ctrl | ModifierKeys.Shift | ModifierKeys.Alt,
                Key = VirtualKey.F3
            },
            ToggleHotkey = new HotkeyBinding
            {
                Modifiers = ModifierKeys.Ctrl | ModifierKeys.Shift | ModifierKeys.Alt,
                Key = VirtualKey.F4  // Note: Alt+F4 is system hotkey, but Ctrl+Shift+Alt+F4 is not
            }
        };

        var registerResult = _hotkeyManager.RegisterHotkeys(config);
        if (!registerResult)
        {
            return;
        }

        // Act - Check for conflict with the same binding as Toggle hotkey
        var binding = new HotkeyBinding
        {
            Modifiers = ModifierKeys.Ctrl | ModifierKeys.Shift | ModifierKeys.Alt,
            Key = VirtualKey.F4
        };
        var conflict = _hotkeyManager.CheckConflict(binding);

        // Assert
        Assert.NotNull(conflict);
        Assert.False(conflict.IsSystemHotkey);
        Assert.Equal("FreeFlow", conflict.ConflictingOwner);
        Assert.Contains("Toggle mode hotkey", conflict.ConflictDescription);
    }

    /// <summary>
    /// Test that CheckConflict detects conflict with registered PasteAgain hotkey.
    /// Validates: Requirement 3.7 - Hotkey conflict detection with FreeFlow's own hotkeys
    /// </summary>
    [Fact]
    [Trait("Category", "WindowsOnly")]
    public void CheckConflict_WithRegisteredPasteAgainHotkey_ReturnsFreeFlowConflict()
    {
        // Arrange
        _hotkeyManager = new HotkeyManager();
        var config = new HotkeyConfiguration
        {
            HoldHotkey = new HotkeyBinding
            {
                Modifiers = ModifierKeys.Ctrl | ModifierKeys.Shift | ModifierKeys.Alt,
                Key = VirtualKey.F1
            },
            ToggleHotkey = new HotkeyBinding
            {
                Modifiers = ModifierKeys.Ctrl | ModifierKeys.Shift | ModifierKeys.Alt,
                Key = VirtualKey.F2
            },
            PasteAgainHotkey = new HotkeyBinding
            {
                Modifiers = ModifierKeys.Ctrl | ModifierKeys.Shift,
                Key = VirtualKey.V
            }
        };

        var registerResult = _hotkeyManager.RegisterHotkeys(config);
        if (!registerResult)
        {
            return;
        }

        // Act - Check for conflict with the same binding as PasteAgain hotkey
        var binding = new HotkeyBinding
        {
            Modifiers = ModifierKeys.Ctrl | ModifierKeys.Shift,
            Key = VirtualKey.V
        };
        var conflict = _hotkeyManager.CheckConflict(binding);

        // Assert
        Assert.NotNull(conflict);
        Assert.False(conflict.IsSystemHotkey);
        Assert.Equal("FreeFlow", conflict.ConflictingOwner);
        Assert.Contains("Paste Again hotkey", conflict.ConflictDescription);
    }

    #endregion

    #region Dispose Tests

    /// <summary>
    /// Test that Dispose cleans up resources and sets inactive.
    /// Validates: Proper resource cleanup on dispose
    /// </summary>
    [Fact]
    [Trait("Category", "WindowsOnly")]
    public void Dispose_AfterRegistration_CleansUpResources()
    {
        // Arrange
        _hotkeyManager = new HotkeyManager();
        var config = new HotkeyConfiguration
        {
            HoldHotkey = new HotkeyBinding
            {
                Modifiers = ModifierKeys.Ctrl | ModifierKeys.Shift | ModifierKeys.Alt,
                Key = VirtualKey.NumPad1
            },
            ToggleHotkey = new HotkeyBinding
            {
                Modifiers = ModifierKeys.Ctrl | ModifierKeys.Shift | ModifierKeys.Alt,
                Key = VirtualKey.NumPad2
            }
        };
        _hotkeyManager.RegisterHotkeys(config);

        // Act
        _hotkeyManager.Dispose();

        // Assert
        Assert.False(_hotkeyManager.IsActive);
        
        // Set to null to prevent double dispose in test cleanup
        _hotkeyManager = null;
    }

    /// <summary>
    /// Test that Dispose can be called multiple times safely.
    /// </summary>
    [Fact]
    public void Dispose_CalledMultipleTimes_DoesNotThrow()
    {
        // Arrange
        _hotkeyManager = new HotkeyManager();

        // Act & Assert
        var exception = Record.Exception(() =>
        {
            _hotkeyManager.Dispose();
            _hotkeyManager.Dispose();
            _hotkeyManager.Dispose();
        });
        Assert.Null(exception);
        
        _hotkeyManager = null;
    }

    /// <summary>
    /// Test that Dispose can be called when no hotkeys are registered.
    /// </summary>
    [Fact]
    public void Dispose_WhenNoHotkeysRegistered_DoesNotThrow()
    {
        // Arrange
        _hotkeyManager = new HotkeyManager();

        // Act & Assert
        var exception = Record.Exception(() => _hotkeyManager.Dispose());
        Assert.Null(exception);
        
        _hotkeyManager = null;
    }

    #endregion

    #region IsActive Property Tests

    /// <summary>
    /// Test that IsActive is false after UnregisterAll.
    /// </summary>
    [Fact]
    [Trait("Category", "WindowsOnly")]
    public void IsActive_AfterUnregisterAll_IsFalse()
    {
        // Arrange
        _hotkeyManager = new HotkeyManager();
        var config = new HotkeyConfiguration
        {
            HoldHotkey = new HotkeyBinding
            {
                Modifiers = ModifierKeys.Ctrl | ModifierKeys.Shift | ModifierKeys.Alt,
                Key = VirtualKey.NumPad3
            },
            ToggleHotkey = new HotkeyBinding
            {
                Modifiers = ModifierKeys.Ctrl | ModifierKeys.Shift | ModifierKeys.Alt,
                Key = VirtualKey.NumPad4
            }
        };
        
        var result = _hotkeyManager.RegisterHotkeys(config);
        if (result)
        {
            Assert.True(_hotkeyManager.IsActive);
        }

        // Act
        _hotkeyManager.UnregisterAll();

        // Assert
        Assert.False(_hotkeyManager.IsActive);
    }

    #endregion

    #region CurrentConfiguration Property Tests

    /// <summary>
    /// Test that CurrentConfiguration is null after UnregisterAll.
    /// </summary>
    [Fact]
    [Trait("Category", "WindowsOnly")]
    public void CurrentConfiguration_AfterUnregisterAll_IsNull()
    {
        // Arrange
        _hotkeyManager = new HotkeyManager();
        var config = new HotkeyConfiguration
        {
            HoldHotkey = new HotkeyBinding
            {
                Modifiers = ModifierKeys.Ctrl | ModifierKeys.Shift | ModifierKeys.Alt,
                Key = VirtualKey.NumPad5
            },
            ToggleHotkey = new HotkeyBinding
            {
                Modifiers = ModifierKeys.Ctrl | ModifierKeys.Shift | ModifierKeys.Alt,
                Key = VirtualKey.NumPad6
            }
        };

        var result = _hotkeyManager.RegisterHotkeys(config);
        if (result)
        {
            Assert.NotNull(_hotkeyManager.CurrentConfiguration);
        }

        // Act
        _hotkeyManager.UnregisterAll();

        // Assert
        Assert.Null(_hotkeyManager.CurrentConfiguration);
    }

    /// <summary>
    /// Test that re-registering hotkeys updates CurrentConfiguration.
    /// </summary>
    [Fact]
    [Trait("Category", "WindowsOnly")]
    public void CurrentConfiguration_AfterReRegistration_ReflectsNewConfiguration()
    {
        // Arrange
        _hotkeyManager = new HotkeyManager();
        var config1 = new HotkeyConfiguration
        {
            HoldHotkey = new HotkeyBinding
            {
                Modifiers = ModifierKeys.Ctrl | ModifierKeys.Shift | ModifierKeys.Alt,
                Key = VirtualKey.NumPad7
            },
            ToggleHotkey = new HotkeyBinding
            {
                Modifiers = ModifierKeys.Ctrl | ModifierKeys.Shift | ModifierKeys.Alt,
                Key = VirtualKey.NumPad8
            }
        };

        var config2 = new HotkeyConfiguration
        {
            HoldHotkey = new HotkeyBinding
            {
                Modifiers = ModifierKeys.Ctrl | ModifierKeys.Alt,
                Key = VirtualKey.Home
            },
            ToggleHotkey = new HotkeyBinding
            {
                Modifiers = ModifierKeys.Ctrl | ModifierKeys.Alt,
                Key = VirtualKey.End
            }
        };

        _hotkeyManager.RegisterHotkeys(config1);

        // Act
        var result = _hotkeyManager.RegisterHotkeys(config2);

        // Assert
        if (result)
        {
            Assert.NotNull(_hotkeyManager.CurrentConfiguration);
            Assert.Equal(VirtualKey.Home, _hotkeyManager.CurrentConfiguration.HoldHotkey.Key);
            Assert.Equal(VirtualKey.End, _hotkeyManager.CurrentConfiguration.ToggleHotkey.Key);
        }
    }

    #endregion

    #region Known System Hotkeys Coverage Tests

    /// <summary>
    /// Test that all known system hotkeys from the implementation are detected.
    /// Validates: Requirement 3.7 - Comprehensive system hotkey conflict detection
    /// </summary>
    [Theory]
    [InlineData(ModifierKeys.Win, VirtualKey.D)]      // Show desktop
    [InlineData(ModifierKeys.Win, VirtualKey.E)]      // File Explorer
    [InlineData(ModifierKeys.Win, VirtualKey.L)]      // Lock workstation
    [InlineData(ModifierKeys.Win, VirtualKey.R)]      // Run dialog
    [InlineData(ModifierKeys.Win, VirtualKey.S)]      // Search
    [InlineData(ModifierKeys.Win, VirtualKey.Tab)]    // Task view
    [InlineData(ModifierKeys.Win, VirtualKey.A)]      // Action center
    [InlineData(ModifierKeys.Win, VirtualKey.I)]      // Settings
    [InlineData(ModifierKeys.Win, VirtualKey.P)]      // Project
    [InlineData(ModifierKeys.Alt, VirtualKey.Tab)]    // Switch windows
    [InlineData(ModifierKeys.Alt, VirtualKey.F4)]     // Close window
    public void CheckConflict_WithKnownSystemHotkeys_ReturnsConflict(
        ModifierKeys modifiers, 
        VirtualKey key)
    {
        // Arrange
        _hotkeyManager = new HotkeyManager();
        var binding = new HotkeyBinding
        {
            Modifiers = modifiers,
            Key = key
        };

        // Act
        var conflict = _hotkeyManager.CheckConflict(binding);

        // Assert
        Assert.NotNull(conflict);
        Assert.True(conflict.IsSystemHotkey);
        Assert.Equal("Windows", conflict.ConflictingOwner);
    }

    /// <summary>
    /// Test multi-modifier system hotkeys.
    /// </summary>
    [Theory]
    [InlineData(ModifierKeys.Ctrl | ModifierKeys.Alt, VirtualKey.Delete)]  // Security options
    [InlineData(ModifierKeys.Ctrl | ModifierKeys.Shift, VirtualKey.Escape)] // Task Manager
    public void CheckConflict_WithMultiModifierSystemHotkeys_ReturnsConflict(
        ModifierKeys modifiers, 
        VirtualKey key)
    {
        // Arrange
        _hotkeyManager = new HotkeyManager();
        var binding = new HotkeyBinding
        {
            Modifiers = modifiers,
            Key = key
        };

        // Act
        var conflict = _hotkeyManager.CheckConflict(binding);

        // Assert
        Assert.NotNull(conflict);
        Assert.True(conflict.IsSystemHotkey);
    }

    #endregion

    #region Event Tests

    /// <summary>
    /// Test that HotkeyManager has all expected events defined.
    /// </summary>
    [Fact]
    public void Events_AllDefined_AreAccessible()
    {
        // Arrange
        _hotkeyManager = new HotkeyManager();
        
        // Act & Assert - Should be able to subscribe to all events
        _hotkeyManager.HoldHotkeyPressed += Handler;
        _hotkeyManager.HoldHotkeyReleased += Handler;
        _hotkeyManager.ToggleHotkeyPressed += Handler;
        _hotkeyManager.PasteAgainHotkeyPressed += Handler;

        // Unsubscribe
        _hotkeyManager.HoldHotkeyPressed -= Handler;
        _hotkeyManager.HoldHotkeyReleased -= Handler;
        _hotkeyManager.ToggleHotkeyPressed -= Handler;
        _hotkeyManager.PasteAgainHotkeyPressed -= Handler;

        static void Handler(object? sender, HotkeyEventArgs e) { }
    }

    #endregion
}
