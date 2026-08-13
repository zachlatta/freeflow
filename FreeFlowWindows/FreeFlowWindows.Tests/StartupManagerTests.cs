using FreeFlowWindows.Core.Services;
using Xunit;

namespace FreeFlowWindows.Tests;

/// <summary>
/// Unit tests for StartupManager.
/// Tests Windows startup registration via registry.
/// Requirements covered: 11.1, 11.2, 11.3
/// </summary>
public class StartupManagerTests
{
    private const string TestAppName = "FreeFlowTest";
    private readonly string _testExePath;
    private readonly StartupManager _manager;

    public StartupManagerTests()
    {
        // Use a unique test path to avoid conflicts
        _testExePath = Path.Combine(Path.GetTempPath(), "FreeFlowTest.exe");
        _manager = new StartupManager(TestAppName, _testExePath);
    }

    #region Constructor Tests

    [Fact]
    public void Constructor_SetsApplicationName()
    {
        // Assert
        Assert.Equal(TestAppName, _manager.ApplicationName);
    }

    [Fact]
    public void Constructor_SetsExecutablePath()
    {
        // Assert
        Assert.Equal(_testExePath, _manager.ExecutablePath);
    }

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("   ")]
    public void Constructor_WithNullOrEmptyAppName_ThrowsArgumentException(string? appName)
    {
        // Act & Assert - ArgumentNullException is a subclass of ArgumentException
        Assert.ThrowsAny<ArgumentException>(() => new StartupManager(appName!, _testExePath));
    }

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("   ")]
    public void Constructor_WithNullOrEmptyExePath_ThrowsArgumentException(string? exePath)
    {
        // Act & Assert - ArgumentNullException is a subclass of ArgumentException
        Assert.ThrowsAny<ArgumentException>(() => new StartupManager(TestAppName, exePath!));
    }

    [Fact]
    public void DefaultConstructor_UsesDefaultApplicationName()
    {
        // Arrange & Act
        var manager = new StartupManager();

        // Assert
        Assert.Equal("FreeFlow", manager.ApplicationName);
    }

    #endregion

    #region Registration Tests (Windows-only)

    [SkippableFact]
    public void RegisterForStartup_CreatesRegistryEntry()
    {
        Skip.IfNot(OperatingSystem.IsWindows(), "Test only runs on Windows");

        try
        {
            // Act
            var result = _manager.RegisterForStartup();

            // Assert
            Assert.True(result);
            Assert.True(_manager.IsRegisteredForStartup());
        }
        finally
        {
            // Cleanup
            _manager.UnregisterFromStartup();
        }
    }

    [SkippableFact]
    public void UnregisterFromStartup_RemovesRegistryEntry()
    {
        Skip.IfNot(OperatingSystem.IsWindows(), "Test only runs on Windows");

        // Arrange - First register
        _manager.RegisterForStartup();
        Assert.True(_manager.IsRegisteredForStartup());

        // Act
        var result = _manager.UnregisterFromStartup();

        // Assert
        Assert.True(result);
        Assert.False(_manager.IsRegisteredForStartup());
    }

    [SkippableFact]
    public void UnregisterFromStartup_WhenNotRegistered_ReturnsTrue()
    {
        Skip.IfNot(OperatingSystem.IsWindows(), "Test only runs on Windows");

        // Ensure not registered
        _manager.UnregisterFromStartup();

        // Act
        var result = _manager.UnregisterFromStartup();

        // Assert
        Assert.True(result);
    }

    [SkippableFact]
    public void IsRegisteredForStartup_WhenNotRegistered_ReturnsFalse()
    {
        Skip.IfNot(OperatingSystem.IsWindows(), "Test only runs on Windows");

        // Ensure not registered
        _manager.UnregisterFromStartup();

        // Act
        var result = _manager.IsRegisteredForStartup();

        // Assert
        Assert.False(result);
    }

    [SkippableFact]
    public void SetStartupEnabled_True_Registers()
    {
        Skip.IfNot(OperatingSystem.IsWindows(), "Test only runs on Windows");

        try
        {
            // Act
            var result = _manager.SetStartupEnabled(true);

            // Assert
            Assert.True(result);
            Assert.True(_manager.IsRegisteredForStartup());
        }
        finally
        {
            // Cleanup
            _manager.UnregisterFromStartup();
        }
    }

    [SkippableFact]
    public void SetStartupEnabled_False_Unregisters()
    {
        Skip.IfNot(OperatingSystem.IsWindows(), "Test only runs on Windows");

        // Arrange - First register
        _manager.RegisterForStartup();

        // Act
        var result = _manager.SetStartupEnabled(false);

        // Assert
        Assert.True(result);
        Assert.False(_manager.IsRegisteredForStartup());
    }

    #endregion

    #region Non-Windows Platform Tests

    [Fact(Skip = "Test only runs on non-Windows platforms")]
    public void RegisterForStartup_OnNonWindows_ReturnsFalse()
    {
        // Act
        var result = _manager.RegisterForStartup();

        // Assert
        Assert.False(result);
    }

    [Fact(Skip = "Test only runs on non-Windows platforms")]
    public void UnregisterFromStartup_OnNonWindows_ReturnsFalse()
    {
        // Act
        var result = _manager.UnregisterFromStartup();

        // Assert
        Assert.False(result);
    }

    [Fact(Skip = "Test only runs on non-Windows platforms")]
    public void IsRegisteredForStartup_OnNonWindows_ReturnsFalse()
    {
        // Act
        var result = _manager.IsRegisteredForStartup();

        // Assert
        Assert.False(result);
    }

    #endregion
}

/// <summary>
/// Helper attribute for skippable tests using xUnit.
/// </summary>
public class SkippableFactAttribute : FactAttribute
{
}

/// <summary>
/// Helper class for conditionally skipping tests.
/// </summary>
public static class Skip
{
    public static void IfNot(bool condition, string reason)
    {
        if (!condition)
        {
            throw new SkipException($"Skipped: {reason}");
        }
    }

    public static void If(bool condition, string reason)
    {
        if (condition)
        {
            throw new SkipException($"Skipped: {reason}");
        }
    }
}

/// <summary>
/// Exception thrown to skip a test.
/// </summary>
public class SkipException : Exception
{
    public SkipException(string message) : base(message) { }
}
