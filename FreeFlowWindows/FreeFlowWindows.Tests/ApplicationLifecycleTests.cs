using FreeFlowWindows.Core.Interfaces;
using FreeFlowWindows.Core.Models;
using FreeFlowWindows.App.Services;
using Moq;
using Xunit;

namespace FreeFlowWindows.Tests;

/// <summary>
/// Unit tests for ApplicationLifecycle.
/// Tests startup initialization, graceful shutdown, and resource cleanup.
/// Requirements covered: 11.2, 11.3, 11.4, 11.5
/// </summary>
public class ApplicationLifecycleTests
{
    private readonly Mock<IPipelineOrchestrator> _mockOrchestrator;
    private readonly Mock<IHotkeyManager> _mockHotkeyManager;
    private readonly Mock<ISystemTrayManager> _mockSystemTrayManager;
    private readonly Mock<ISettingsManager> _mockSettingsManager;
    private readonly Mock<IStartupManager> _mockStartupManager;
    private readonly ApplicationLifecycle _lifecycle;

    public ApplicationLifecycleTests()
    {
        _mockOrchestrator = new Mock<IPipelineOrchestrator>();
        _mockHotkeyManager = new Mock<IHotkeyManager>();
        _mockSystemTrayManager = new Mock<ISystemTrayManager>();
        _mockSettingsManager = new Mock<ISettingsManager>();
        _mockStartupManager = new Mock<IStartupManager>();

        // Default settings
        _mockSettingsManager.Setup(s => s.Load()).Returns(new AppSettings
        {
            HoldHotkey = new HotkeyBinding { Key = VirtualKey.F2, Modifiers = ModifierKeys.None },
            ToggleHotkey = new HotkeyBinding { Key = VirtualKey.F3, Modifiers = ModifierKeys.None },
            StartWithWindows = false
        });

        _lifecycle = new ApplicationLifecycle(
            _mockOrchestrator.Object,
            _mockHotkeyManager.Object,
            _mockSystemTrayManager.Object,
            _mockSettingsManager.Object,
            _mockStartupManager.Object);
    }

    #region Constructor Tests

    [Fact]
    public void Constructor_InitializesInNotInitializedState()
    {
        // Assert
        Assert.False(_lifecycle.IsInitialized);
        Assert.False(_lifecycle.IsShuttingDown);
    }

    [Fact]
    public void Constructor_ThrowsOnNullDependencies()
    {
        Assert.Throws<ArgumentNullException>(() => new ApplicationLifecycle(
            null!,
            _mockHotkeyManager.Object,
            _mockSystemTrayManager.Object,
            _mockSettingsManager.Object,
            _mockStartupManager.Object));

        Assert.Throws<ArgumentNullException>(() => new ApplicationLifecycle(
            _mockOrchestrator.Object,
            null!,
            _mockSystemTrayManager.Object,
            _mockSettingsManager.Object,
            _mockStartupManager.Object));

        Assert.Throws<ArgumentNullException>(() => new ApplicationLifecycle(
            _mockOrchestrator.Object,
            _mockHotkeyManager.Object,
            null!,
            _mockSettingsManager.Object,
            _mockStartupManager.Object));
    }

    #endregion

    #region InitializeAsync Tests

    [Fact]
    public async Task InitializeAsync_InitializesSystemTray()
    {
        // Act
        await _lifecycle.InitializeAsync();

        // Assert
        _mockSystemTrayManager.Verify(t => t.Initialize(), Times.Once);
    }

    [Fact]
    public async Task InitializeAsync_RegistersHotkeys()
    {
        // Arrange
        var settings = new AppSettings
        {
            HoldHotkey = new HotkeyBinding { Key = VirtualKey.F2 },
            ToggleHotkey = new HotkeyBinding { Key = VirtualKey.F3 }
        };
        _mockSettingsManager.Setup(s => s.Load()).Returns(settings);

        // Act
        await _lifecycle.InitializeAsync();

        // Assert
        _mockHotkeyManager.Verify(h => h.RegisterHotkeys(It.IsAny<HotkeyConfiguration>()), Times.Once);
    }

    [Fact]
    public async Task InitializeAsync_SetsStartupRegistration()
    {
        // Arrange
        var settings = new AppSettings { StartWithWindows = true };
        _mockSettingsManager.Setup(s => s.Load()).Returns(settings);

        // Act
        await _lifecycle.InitializeAsync();

        // Assert
        _mockStartupManager.Verify(s => s.SetStartupEnabled(true), Times.Once);
    }

    [Fact]
    public async Task InitializeAsync_SetsIsInitializedTrue()
    {
        // Act
        await _lifecycle.InitializeAsync();

        // Assert
        Assert.True(_lifecycle.IsInitialized);
    }

    [Fact]
    public async Task InitializeAsync_WhenAlreadyInitialized_DoesNotReinitialize()
    {
        // Arrange
        await _lifecycle.InitializeAsync();
        _mockSystemTrayManager.Invocations.Clear();

        // Act
        await _lifecycle.InitializeAsync();

        // Assert - Should not initialize again
        _mockSystemTrayManager.Verify(t => t.Initialize(), Times.Never);
    }

    #endregion

    #region ShutdownAsync Tests

    [Fact]
    public async Task ShutdownAsync_CancelsPipelineIfActive()
    {
        // Arrange
        _mockOrchestrator.Setup(o => o.IsActive).Returns(true);
        await _lifecycle.InitializeAsync();

        // Act
        await _lifecycle.ShutdownAsync();

        // Assert
        _mockOrchestrator.Verify(o => o.Cancel(), Times.Once);
    }

    [Fact]
    public async Task ShutdownAsync_UnregistersAllHotkeys()
    {
        // Arrange
        await _lifecycle.InitializeAsync();

        // Act
        await _lifecycle.ShutdownAsync();

        // Assert
        _mockHotkeyManager.Verify(h => h.UnregisterAll(), Times.Once);
    }

    [Fact]
    public async Task ShutdownAsync_DisposesSystemTrayManager()
    {
        // Arrange
        var disposableTray = _mockSystemTrayManager.As<IDisposable>();
        await _lifecycle.InitializeAsync();

        // Act
        await _lifecycle.ShutdownAsync();

        // Assert
        disposableTray.Verify(d => d.Dispose(), Times.Once);
    }

    [Fact]
    public async Task ShutdownAsync_FiresShutdownInitiatedEvent()
    {
        // Arrange
        var eventFired = false;
        _lifecycle.ShutdownInitiated += (s, e) => eventFired = true;
        await _lifecycle.InitializeAsync();

        // Act
        await _lifecycle.ShutdownAsync();

        // Assert
        Assert.True(eventFired);
    }

    [Fact]
    public async Task ShutdownAsync_FiresShutdownCompletedEvent()
    {
        // Arrange
        var eventFired = false;
        _lifecycle.ShutdownCompleted += (s, e) => eventFired = true;
        await _lifecycle.InitializeAsync();

        // Act
        await _lifecycle.ShutdownAsync();

        // Assert
        Assert.True(eventFired);
    }

    [Fact]
    public async Task ShutdownAsync_SetsIsInitializedFalse()
    {
        // Arrange
        await _lifecycle.InitializeAsync();
        Assert.True(_lifecycle.IsInitialized);

        // Act
        await _lifecycle.ShutdownAsync();

        // Assert
        Assert.False(_lifecycle.IsInitialized);
    }

    [Fact]
    public async Task ShutdownAsync_WhenCalledTwice_OnlyExecutesOnce()
    {
        // Arrange
        await _lifecycle.InitializeAsync();

        // Act
        await _lifecycle.ShutdownAsync();
        await _lifecycle.ShutdownAsync();

        // Assert - Should only unregister once
        _mockHotkeyManager.Verify(h => h.UnregisterAll(), Times.Once);
    }

    #endregion

    #region HandleSessionEnding Tests

    [Fact]
    public async Task HandleSessionEnding_CancelsPipelineIfActive()
    {
        // Arrange
        _mockOrchestrator.Setup(o => o.IsActive).Returns(true);
        await _lifecycle.InitializeAsync();

        // Act
        _lifecycle.HandleSessionEnding(isLoggingOff: true);

        // Assert
        _mockOrchestrator.Verify(o => o.Cancel(), Times.Once);
    }

    [Fact]
    public async Task HandleSessionEnding_UnregistersHotkeys()
    {
        // Arrange
        await _lifecycle.InitializeAsync();

        // Act
        _lifecycle.HandleSessionEnding(isLoggingOff: false);

        // Assert
        _mockHotkeyManager.Verify(h => h.UnregisterAll(), Times.Once);
    }

    [Fact]
    public async Task HandleSessionEnding_DisposesSystemTray()
    {
        // Arrange
        var disposableTray = _mockSystemTrayManager.As<IDisposable>();
        await _lifecycle.InitializeAsync();

        // Act
        _lifecycle.HandleSessionEnding(isLoggingOff: true);

        // Assert
        disposableTray.Verify(d => d.Dispose(), Times.Once);
    }

    [Fact]
    public async Task HandleSessionEnding_SetsIsShuttingDownTrue()
    {
        // Arrange
        await _lifecycle.InitializeAsync();

        // Act
        _lifecycle.HandleSessionEnding(isLoggingOff: false);

        // Assert
        Assert.True(_lifecycle.IsShuttingDown);
    }

    #endregion

    #region Dispose Tests

    [Fact]
    public async Task Dispose_CleansUpResources()
    {
        // Arrange
        var disposableTray = _mockSystemTrayManager.As<IDisposable>();
        await _lifecycle.InitializeAsync();

        // Act
        _lifecycle.Dispose();

        // Assert
        _mockHotkeyManager.Verify(h => h.UnregisterAll(), Times.Once);
        disposableTray.Verify(d => d.Dispose(), Times.Once);
    }

    [Fact]
    public void Dispose_WhenCalledTwice_OnlyExecutesOnce()
    {
        // Act
        _lifecycle.Dispose();
        _lifecycle.Dispose();

        // Assert - Should only unregister once
        _mockHotkeyManager.Verify(h => h.UnregisterAll(), Times.Once);
    }

    #endregion

    #region Pipeline Event Handling Tests

    [Fact]
    public async Task PipelineStateChanged_UpdatesTrayIconStatus()
    {
        // Arrange
        await _lifecycle.InitializeAsync();

        // Act - Simulate pipeline state change
        _mockOrchestrator.Raise(o => o.StateChanged += null,
            _mockOrchestrator.Object,
            new PipelineStateChangedEventArgs(PipelineState.Idle, PipelineState.Recording));

        // Assert
        _mockSystemTrayManager.Verify(t => t.UpdateIcon(AppStatus.Recording), Times.Once);
    }

    [Fact]
    public async Task PipelineError_ShowsNotification()
    {
        // Arrange
        await _lifecycle.InitializeAsync();

        // Act - Simulate pipeline error
        _mockOrchestrator.Raise(o => o.Error += null,
            _mockOrchestrator.Object,
            new PipelineErrorEventArgs(PipelineState.Transcribing, "API error"));

        // Assert
        _mockSystemTrayManager.Verify(t => t.ShowBalloonNotification(
            It.IsAny<string>(),
            "API error",
            NotificationType.Error), Times.Once);
    }

    #endregion
}
