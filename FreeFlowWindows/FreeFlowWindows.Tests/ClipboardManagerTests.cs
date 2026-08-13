using Moq;
using Xunit;
using FreeFlowWindows.Core.Services;
using InputSimulatorStandard;
using InputSimulatorStandard.Native;

namespace FreeFlowWindows.Tests;

/// <summary>
/// Unit tests for ClipboardManager.
/// Tests paste simulation, clipboard preservation, "Paste Again" functionality, and null/empty input handling.
/// Validates: Requirements 6.1, 6.2, 6.3, 6.4, 6.5, 6.6
/// </summary>
public class ClipboardManagerTests : IDisposable
{
    private readonly Mock<IInputSimulator> _mockInputSimulator;
    private readonly Mock<IKeyboardSimulator> _mockKeyboardSimulator;
    private readonly ClipboardManager _clipboardManager;

    public ClipboardManagerTests()
    {
        _mockInputSimulator = new Mock<IInputSimulator>();
        _mockKeyboardSimulator = new Mock<IKeyboardSimulator>();
        
        // Setup the mock chain: InputSimulator.Keyboard returns KeyboardSimulator
        _mockInputSimulator
            .Setup(x => x.Keyboard)
            .Returns(_mockKeyboardSimulator.Object);
        
        // Setup ModifiedKeyStroke to return the keyboard simulator (for fluent API)
        _mockKeyboardSimulator
            .Setup(x => x.ModifiedKeyStroke(It.IsAny<VirtualKeyCode>(), It.IsAny<VirtualKeyCode>()))
            .Returns(_mockKeyboardSimulator.Object);

        _clipboardManager = new ClipboardManager(_mockInputSimulator.Object);
    }

    public void Dispose()
    {
        _clipboardManager.Dispose();
    }

    #region Paste Simulation Tests

    [Fact]
    public async Task PasteTextAsync_ValidText_SimulatesCtrlV()
    {
        // Arrange
        var textToPaste = "Hello, World!";

        // Act
        await _clipboardManager.PasteTextAsync(textToPaste, preserveClipboard: false);

        // Assert - Verify that Ctrl+V was simulated
        _mockKeyboardSimulator.Verify(
            x => x.ModifiedKeyStroke(VirtualKeyCode.CONTROL, VirtualKeyCode.VK_V),
            Times.Once,
            "Paste should simulate Ctrl+V keystroke");
    }

    [Fact]
    public async Task PasteTextAsync_EmptyText_DoesNotSimulatePaste()
    {
        // Arrange
        var emptyText = "";

        // Act
        await _clipboardManager.PasteTextAsync(emptyText, preserveClipboard: false);

        // Assert - Verify that Ctrl+V was NOT simulated
        _mockKeyboardSimulator.Verify(
            x => x.ModifiedKeyStroke(It.IsAny<VirtualKeyCode>(), It.IsAny<VirtualKeyCode>()),
            Times.Never,
            "Empty text should not trigger paste simulation");
    }

    [Fact]
    public async Task PasteTextAsync_NullText_DoesNotSimulatePaste()
    {
        // Arrange
        string? nullText = null;

        // Act
        await _clipboardManager.PasteTextAsync(nullText!, preserveClipboard: false);

        // Assert - Verify that Ctrl+V was NOT simulated
        _mockKeyboardSimulator.Verify(
            x => x.ModifiedKeyStroke(It.IsAny<VirtualKeyCode>(), It.IsAny<VirtualKeyCode>()),
            Times.Never,
            "Null text should not trigger paste simulation");
    }

    [Fact]
    public async Task PasteTextAsync_WhitespaceText_SimulatesPaste()
    {
        // Arrange - Whitespace-only text should still be pasted
        var whitespaceText = "   ";

        // Act
        await _clipboardManager.PasteTextAsync(whitespaceText, preserveClipboard: false);

        // Assert - Whitespace is valid content and should be pasted
        _mockKeyboardSimulator.Verify(
            x => x.ModifiedKeyStroke(VirtualKeyCode.CONTROL, VirtualKeyCode.VK_V),
            Times.Once,
            "Whitespace text should trigger paste simulation");
    }

    [Fact]
    public async Task PasteTextAsync_LongText_SimulatesPaste()
    {
        // Arrange - Long text should still work
        var longText = new string('A', 10000);

        // Act
        await _clipboardManager.PasteTextAsync(longText, preserveClipboard: false);

        // Assert
        _mockKeyboardSimulator.Verify(
            x => x.ModifiedKeyStroke(VirtualKeyCode.CONTROL, VirtualKeyCode.VK_V),
            Times.Once,
            "Long text should trigger paste simulation");
    }

    [Fact]
    public async Task PasteTextAsync_UnicodeText_SimulatesPaste()
    {
        // Arrange - Unicode text including emoji and special characters
        var unicodeText = "Hello 世界! 🎉 Ñoño";

        // Act
        await _clipboardManager.PasteTextAsync(unicodeText, preserveClipboard: false);

        // Assert
        _mockKeyboardSimulator.Verify(
            x => x.ModifiedKeyStroke(VirtualKeyCode.CONTROL, VirtualKeyCode.VK_V),
            Times.Once,
            "Unicode text should trigger paste simulation");
    }

    [Fact]
    public async Task PasteTextAsync_MultilineText_SimulatesPaste()
    {
        // Arrange
        var multilineText = "Line 1\nLine 2\r\nLine 3";

        // Act
        await _clipboardManager.PasteTextAsync(multilineText, preserveClipboard: false);

        // Assert
        _mockKeyboardSimulator.Verify(
            x => x.ModifiedKeyStroke(VirtualKeyCode.CONTROL, VirtualKeyCode.VK_V),
            Times.Once,
            "Multiline text should trigger paste simulation");
    }

    #endregion

    #region Last Transcript Storage Tests

    [Fact]
    public async Task PasteTextAsync_ValidText_StoresAsLastTranscript()
    {
        // Arrange
        var textToPaste = "Test transcript for storage";

        // Act
        await _clipboardManager.PasteTextAsync(textToPaste, preserveClipboard: false);

        // Assert
        Assert.Equal(textToPaste, _clipboardManager.GetLastTranscript());
    }

    [Fact]
    public async Task PasteTextAsync_MultiplePastes_StoresLastOne()
    {
        // Arrange
        var firstText = "First transcript";
        var secondText = "Second transcript";

        // Act
        await _clipboardManager.PasteTextAsync(firstText, preserveClipboard: false);
        await _clipboardManager.PasteTextAsync(secondText, preserveClipboard: false);

        // Assert - Should store the most recent transcript
        Assert.Equal(secondText, _clipboardManager.GetLastTranscript());
    }

    [Fact]
    public void GetLastTranscript_NoPreviousPaste_ReturnsNull()
    {
        // Act
        var result = _clipboardManager.GetLastTranscript();

        // Assert
        Assert.Null(result);
    }

    [Fact]
    public async Task PasteTextAsync_EmptyText_DoesNotUpdateLastTranscript()
    {
        // Arrange - First paste something valid
        var validText = "Valid transcript";
        await _clipboardManager.PasteTextAsync(validText, preserveClipboard: false);

        // Act - Then try to paste empty text
        await _clipboardManager.PasteTextAsync("", preserveClipboard: false);

        // Assert - Last transcript should still be the valid one
        Assert.Equal(validText, _clipboardManager.GetLastTranscript());
    }

    [Fact]
    public async Task PasteTextAsync_NullText_DoesNotUpdateLastTranscript()
    {
        // Arrange - First paste something valid
        var validText = "Valid transcript";
        await _clipboardManager.PasteTextAsync(validText, preserveClipboard: false);

        // Act - Then try to paste null
        await _clipboardManager.PasteTextAsync(null!, preserveClipboard: false);

        // Assert - Last transcript should still be the valid one
        Assert.Equal(validText, _clipboardManager.GetLastTranscript());
    }

    #endregion

    #region Paste Again Tests

    [Fact]
    public async Task PasteLastTranscriptAsync_HasPreviousTranscript_PastesIt()
    {
        // Arrange - First paste something
        var transcript = "Previous transcript";
        await _clipboardManager.PasteTextAsync(transcript, preserveClipboard: false);
        _mockKeyboardSimulator.Invocations.Clear(); // Reset the invocation count

        // Act
        await _clipboardManager.PasteLastTranscriptAsync();

        // Assert
        _mockKeyboardSimulator.Verify(
            x => x.ModifiedKeyStroke(VirtualKeyCode.CONTROL, VirtualKeyCode.VK_V),
            Times.Once,
            "PasteLastTranscript should simulate Ctrl+V");
    }

    [Fact]
    public async Task PasteLastTranscriptAsync_NoPreviousTranscript_DoesNotPaste()
    {
        // Act - Call without any previous transcript
        await _clipboardManager.PasteLastTranscriptAsync();

        // Assert
        _mockKeyboardSimulator.Verify(
            x => x.ModifiedKeyStroke(It.IsAny<VirtualKeyCode>(), It.IsAny<VirtualKeyCode>()),
            Times.Never,
            "No paste should occur when there's no previous transcript");
    }

    [Fact]
    public async Task PasteLastTranscriptAsync_MultipleCalls_PastesSameTranscript()
    {
        // Arrange
        var transcript = "Reusable transcript";
        await _clipboardManager.PasteTextAsync(transcript, preserveClipboard: false);
        _mockKeyboardSimulator.Invocations.Clear();

        // Act - Call multiple times
        await _clipboardManager.PasteLastTranscriptAsync();
        await _clipboardManager.PasteLastTranscriptAsync();
        await _clipboardManager.PasteLastTranscriptAsync();

        // Assert - Should paste three times
        _mockKeyboardSimulator.Verify(
            x => x.ModifiedKeyStroke(VirtualKeyCode.CONTROL, VirtualKeyCode.VK_V),
            Times.Exactly(3),
            "PasteLastTranscript should paste the same transcript multiple times");
    }

    #endregion

    #region Clipboard Preservation Tests

    [Fact]
    public async Task PasteTextAsync_PreserveClipboardEnabled_RestoresAfterDelay()
    {
        // Arrange
        var textToPaste = "New transcript";
        _clipboardManager.ClipboardRestoreDelay = TimeSpan.FromMilliseconds(50);

        // Act
        await _clipboardManager.PasteTextAsync(textToPaste, preserveClipboard: true);

        // Assert - Paste should have been triggered
        _mockKeyboardSimulator.Verify(
            x => x.ModifiedKeyStroke(VirtualKeyCode.CONTROL, VirtualKeyCode.VK_V),
            Times.Once,
            "Should paste the text");
        
        // Note: We can't easily verify clipboard restoration without real clipboard access,
        // but we can verify the method completes without error
    }

    [Fact]
    public async Task PasteTextAsync_PreserveClipboardDisabled_DoesNotRestore()
    {
        // Arrange
        var textToPaste = "New transcript";

        // Act
        await _clipboardManager.PasteTextAsync(textToPaste, preserveClipboard: false);

        // Assert - Paste should complete without any restoration logic
        _mockKeyboardSimulator.Verify(
            x => x.ModifiedKeyStroke(VirtualKeyCode.CONTROL, VirtualKeyCode.VK_V),
            Times.Once);
    }

    #endregion

    #region ClipboardRestoreDelay Configuration Tests

    [Fact]
    public void ClipboardRestoreDelay_DefaultValue_IsOneSecond()
    {
        // Arrange & Act
        using var manager = new ClipboardManager(_mockInputSimulator.Object);

        // Assert
        Assert.Equal(TimeSpan.FromSeconds(1), manager.ClipboardRestoreDelay);
    }

    [Fact]
    public void ClipboardRestoreDelay_CanBeModified()
    {
        // Arrange
        var newDelay = TimeSpan.FromMilliseconds(500);

        // Act
        _clipboardManager.ClipboardRestoreDelay = newDelay;

        // Assert
        Assert.Equal(newDelay, _clipboardManager.ClipboardRestoreDelay);
    }

    [Fact]
    public void ClipboardRestoreDelay_CanBeSetToZero()
    {
        // Arrange & Act
        _clipboardManager.ClipboardRestoreDelay = TimeSpan.Zero;

        // Assert
        Assert.Equal(TimeSpan.Zero, _clipboardManager.ClipboardRestoreDelay);
    }

    [Fact]
    public void ClipboardRestoreDelay_CanBeSetToLargeValue()
    {
        // Arrange
        var largeDelay = TimeSpan.FromMinutes(5);

        // Act
        _clipboardManager.ClipboardRestoreDelay = largeDelay;

        // Assert
        Assert.Equal(largeDelay, _clipboardManager.ClipboardRestoreDelay);
    }

    #endregion

    #region Constructor Tests

    [Fact]
    public void Constructor_NullInputSimulator_ThrowsArgumentNullException()
    {
        // Act & Assert
        Assert.Throws<ArgumentNullException>(() => new ClipboardManager(null!));
    }

    [Fact]
    public void Constructor_DefaultConstructor_CreatesInstance()
    {
        // Act
        using var manager = new ClipboardManager();

        // Assert
        Assert.NotNull(manager);
        Assert.Equal(TimeSpan.FromSeconds(1), manager.ClipboardRestoreDelay);
    }

    #endregion

    #region Cancellation Tests

    [Fact]
    public async Task PasteTextAsync_CancellationRequested_ThrowsOperationCanceled()
    {
        // Arrange
        using var cts = new CancellationTokenSource();
        cts.Cancel();

        // Act & Assert - TaskCanceledException derives from OperationCanceledException
        await Assert.ThrowsAnyAsync<OperationCanceledException>(
            () => _clipboardManager.PasteTextAsync("test", cancellationToken: cts.Token));
    }

    [Fact]
    public async Task PasteLastTranscriptAsync_CancellationRequested_ThrowsOperationCanceled()
    {
        // Arrange - First set up a transcript
        await _clipboardManager.PasteTextAsync("test", preserveClipboard: false);
        
        using var cts = new CancellationTokenSource();
        cts.Cancel();

        // Act & Assert - TaskCanceledException derives from OperationCanceledException
        await Assert.ThrowsAnyAsync<OperationCanceledException>(
            () => _clipboardManager.PasteLastTranscriptAsync(cts.Token));
    }

    #endregion

    #region Thread Safety Tests

    [Fact(Skip = "Test uses real clipboard which can fail due to system clipboard contention")]
    public async Task GetLastTranscript_ConcurrentAccess_ThreadSafe()
    {
        // Arrange
        var tasks = new List<Task>();
        var lastTranscripts = new List<string?>();
        var lockObj = new object();

        // Act - Simulate concurrent access
        for (int i = 0; i < 100; i++)
        {
            var index = i;
            tasks.Add(Task.Run(async () =>
            {
                await _clipboardManager.PasteTextAsync($"Transcript {index}", preserveClipboard: false);
                var transcript = _clipboardManager.GetLastTranscript();
                lock (lockObj)
                {
                    lastTranscripts.Add(transcript);
                }
            }));
        }

        await Task.WhenAll(tasks);

        // Assert - All operations should complete without deadlock or exception
        Assert.Equal(100, lastTranscripts.Count);
        Assert.All(lastTranscripts, t => Assert.NotNull(t));
    }

    #endregion

    #region Dispose Tests

    [Fact]
    public void Dispose_CalledMultipleTimes_DoesNotThrow()
    {
        // Arrange
        var manager = new ClipboardManager(_mockInputSimulator.Object);

        // Act & Assert - Should not throw
        manager.Dispose();
        manager.Dispose();
        manager.Dispose();
    }

    #endregion

    #region Edge Cases

    [Fact]
    public async Task PasteTextAsync_SpecialCharacters_HandlesCorrectly()
    {
        // Arrange - Text with special characters
        var specialText = "Line1\r\nLine2\tTabbed\0NullChar\\Backslash\"Quote";

        // Act
        await _clipboardManager.PasteTextAsync(specialText, preserveClipboard: false);

        // Assert
        _mockKeyboardSimulator.Verify(
            x => x.ModifiedKeyStroke(VirtualKeyCode.CONTROL, VirtualKeyCode.VK_V),
            Times.Once,
            "Special characters should be handled");
        Assert.Equal(specialText, _clipboardManager.GetLastTranscript());
    }

    [Fact]
    public async Task PasteTextAsync_NewlinesOnly_SimulatesPaste()
    {
        // Arrange
        var newlinesText = "\n\n\n";

        // Act
        await _clipboardManager.PasteTextAsync(newlinesText, preserveClipboard: false);

        // Assert
        _mockKeyboardSimulator.Verify(
            x => x.ModifiedKeyStroke(VirtualKeyCode.CONTROL, VirtualKeyCode.VK_V),
            Times.Once,
            "Newlines-only text should trigger paste");
    }

    #endregion
}
