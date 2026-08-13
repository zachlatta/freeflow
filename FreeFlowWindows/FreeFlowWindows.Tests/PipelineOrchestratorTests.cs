using FreeFlowWindows.Core.Interfaces;
using FreeFlowWindows.Core.Models;
using FreeFlowWindows.Core.Services;
using Moq;
using Xunit;

namespace FreeFlowWindows.Tests;

/// <summary>
/// Unit tests for PipelineOrchestrator.
/// Tests state machine flow, error handling, cancellation, and event firing.
/// Requirements covered: 2.1, 4.1, 5.1, 6.1
/// </summary>
public class PipelineOrchestratorTests
{
    private readonly Mock<IAudioRecorder> _mockAudioRecorder;
    private readonly Mock<ITranscriptionService> _mockTranscriptionService;
    private readonly Mock<IPostProcessingService> _mockPostProcessingService;
    private readonly Mock<IClipboardManager> _mockClipboardManager;
    private readonly Mock<ISettingsManager> _mockSettingsManager;
    private readonly PipelineOrchestrator _orchestrator;

    public PipelineOrchestratorTests()
    {
        _mockAudioRecorder = new Mock<IAudioRecorder>();
        _mockTranscriptionService = new Mock<ITranscriptionService>();
        _mockPostProcessingService = new Mock<IPostProcessingService>();
        _mockClipboardManager = new Mock<IClipboardManager>();
        _mockSettingsManager = new Mock<ISettingsManager>();

        // Default settings
        _mockSettingsManager.Setup(s => s.Load()).Returns(new AppSettings());

        _orchestrator = new PipelineOrchestrator(
            _mockAudioRecorder.Object,
            _mockTranscriptionService.Object,
            _mockPostProcessingService.Object,
            _mockClipboardManager.Object,
            _mockSettingsManager.Object);
    }

    #region Initial State Tests

    [Fact]
    public void Constructor_InitializesToIdleState()
    {
        // Assert
        Assert.Equal(PipelineState.Idle, _orchestrator.CurrentState);
        Assert.False(_orchestrator.IsActive);
        Assert.Null(_orchestrator.ActiveRecordingMode);
    }

    [Fact]
    public void Constructor_LastTranscriptIsNull()
    {
        // Assert
        Assert.Null(_orchestrator.LastTranscript);
    }

    #endregion

    #region StartAsync Tests

    [Fact]
    public async Task StartAsync_TransitionsToInitializingThenRecording()
    {
        // Arrange
        var stateChanges = new List<PipelineState>();
        _orchestrator.StateChanged += (s, e) => stateChanges.Add(e.NewState);

        _mockAudioRecorder
            .Setup(r => r.StartRecordingAsync(It.IsAny<string?>()))
            .Returns(Task.CompletedTask);

        // Act
        await _orchestrator.StartAsync(RecordingMode.Hold);

        // Assert
        Assert.Contains(PipelineState.Initializing, stateChanges);
        Assert.Contains(PipelineState.Recording, stateChanges);
        Assert.Equal(PipelineState.Recording, _orchestrator.CurrentState);
    }

    [Fact]
    public async Task StartAsync_SetsActiveRecordingMode()
    {
        // Arrange
        _mockAudioRecorder
            .Setup(r => r.StartRecordingAsync(It.IsAny<string?>()))
            .Returns(Task.CompletedTask);

        // Act
        await _orchestrator.StartAsync(RecordingMode.Toggle);

        // Assert
        Assert.Equal(RecordingMode.Toggle, _orchestrator.ActiveRecordingMode);
    }

    [Fact]
    public async Task StartAsync_WhenAlreadyActive_ThrowsInvalidOperationException()
    {
        // Arrange
        _mockAudioRecorder
            .Setup(r => r.StartRecordingAsync(It.IsAny<string?>()))
            .Returns(Task.CompletedTask);

        await _orchestrator.StartAsync(RecordingMode.Hold);

        // Act & Assert
        await Assert.ThrowsAsync<InvalidOperationException>(
            () => _orchestrator.StartAsync(RecordingMode.Hold));
    }

    [Fact]
    public async Task StartAsync_PassesDeviceIdToRecorder()
    {
        // Arrange
        var deviceId = "test-device-id";
        _mockAudioRecorder
            .Setup(r => r.StartRecordingAsync(deviceId))
            .Returns(Task.CompletedTask);

        // Act
        await _orchestrator.StartAsync(RecordingMode.Hold, deviceId);

        // Assert
        _mockAudioRecorder.Verify(r => r.StartRecordingAsync(deviceId), Times.Once);
    }

    [Fact]
    public async Task StartAsync_OnRecorderFailure_FiresErrorEvent()
    {
        // Arrange
        PipelineErrorEventArgs? errorArgs = null;
        _orchestrator.Error += (s, e) => errorArgs = e;

        _mockAudioRecorder
            .Setup(r => r.StartRecordingAsync(It.IsAny<string?>()))
            .ThrowsAsync(new Exception("Microphone not found"));

        // Act
        await _orchestrator.StartAsync(RecordingMode.Hold);

        // Assert
        Assert.NotNull(errorArgs);
        Assert.Contains("recording", errorArgs!.Message.ToLower());
    }

    #endregion

    #region StopAsync - Successful Flow Tests

    [Fact]
    public async Task StopAsync_SuccessfulFlow_TransitionsThroughAllStates()
    {
        // Arrange
        var stateChanges = new List<PipelineState>();
        _orchestrator.StateChanged += (s, e) => stateChanges.Add(e.NewState);

        SetupSuccessfulPipeline("Hello world");

        await _orchestrator.StartAsync(RecordingMode.Hold);
        stateChanges.Clear();

        // Act
        await _orchestrator.StopAsync();

        // Assert - Should go through: Transcribing -> PostProcessing -> Pasting -> Idle
        Assert.Contains(PipelineState.Transcribing, stateChanges);
        Assert.Contains(PipelineState.PostProcessing, stateChanges);
        Assert.Contains(PipelineState.Pasting, stateChanges);
        Assert.Contains(PipelineState.Idle, stateChanges);
    }

    [Fact]
    public async Task StopAsync_SuccessfulFlow_CallsAllServices()
    {
        // Arrange
        SetupSuccessfulPipeline("Test transcript");

        await _orchestrator.StartAsync(RecordingMode.Hold);

        // Act
        await _orchestrator.StopAsync();

        // Assert
        _mockAudioRecorder.Verify(r => r.StopRecordingAsync(), Times.Once);
        _mockTranscriptionService.Verify(t => t.TranscribeAsync(
            It.IsAny<string>(),
            It.IsAny<CancellationToken>()), Times.Once);
        _mockPostProcessingService.Verify(p => p.ProcessAsync(
            It.IsAny<string>(),
            It.IsAny<string>(),
            It.IsAny<IReadOnlyList<string>>(),
            It.IsAny<string?>(),
            It.IsAny<string?>(),
            It.IsAny<CancellationToken>()), Times.Once);
        _mockClipboardManager.Verify(c => c.PasteTextAsync(
            It.IsAny<string>(),
            It.IsAny<bool>(),
            It.IsAny<CancellationToken>()), Times.Once);
    }

    [Fact]
    public async Task StopAsync_SuccessfulFlow_FiresCompletedEvent()
    {
        // Arrange
        PipelineCompletedEventArgs? completedArgs = null;
        _orchestrator.Completed += (s, e) => completedArgs = e;

        SetupSuccessfulPipeline("Hello world");

        await _orchestrator.StartAsync(RecordingMode.Hold);

        // Act
        await _orchestrator.StopAsync();

        // Assert
        Assert.NotNull(completedArgs);
        Assert.Equal("Hello world", completedArgs!.Transcript);
        Assert.False(completedArgs.WasCancelled);
    }

    [Fact]
    public async Task StopAsync_SuccessfulFlow_SetsLastTranscript()
    {
        // Arrange
        SetupSuccessfulPipeline("Test transcript");

        await _orchestrator.StartAsync(RecordingMode.Hold);

        // Act
        await _orchestrator.StopAsync();

        // Assert
        Assert.Equal("Test transcript", _orchestrator.LastTranscript);
    }

    [Fact]
    public async Task StopAsync_SuccessfulFlow_ReturnsToIdleState()
    {
        // Arrange
        SetupSuccessfulPipeline("Test");

        await _orchestrator.StartAsync(RecordingMode.Hold);

        // Act
        await _orchestrator.StopAsync();

        // Assert
        Assert.Equal(PipelineState.Idle, _orchestrator.CurrentState);
        Assert.False(_orchestrator.IsActive);
        Assert.Null(_orchestrator.ActiveRecordingMode);
    }

    #endregion

    #region StopAsync - Empty Transcript Tests

    [Fact]
    public async Task StopAsync_EmptyAudioFile_CompletesWithEmptyTranscript()
    {
        // Arrange
        PipelineCompletedEventArgs? completedArgs = null;
        _orchestrator.Completed += (s, e) => completedArgs = e;

        _mockAudioRecorder
            .Setup(r => r.StartRecordingAsync(It.IsAny<string?>()))
            .Returns(Task.CompletedTask);
        _mockAudioRecorder
            .Setup(r => r.StopRecordingAsync())
            .ReturnsAsync(string.Empty); // No audio recorded

        await _orchestrator.StartAsync(RecordingMode.Hold);

        // Act
        await _orchestrator.StopAsync();

        // Assert
        Assert.NotNull(completedArgs);
        Assert.Equal(string.Empty, completedArgs!.Transcript);
        Assert.False(completedArgs.WasCancelled);
    }

    [Fact]
    public async Task StopAsync_EmptyTranscription_CompletesWithEmptyTranscript()
    {
        // Arrange
        PipelineCompletedEventArgs? completedArgs = null;
        _orchestrator.Completed += (s, e) => completedArgs = e;

        _mockAudioRecorder
            .Setup(r => r.StartRecordingAsync(It.IsAny<string?>()))
            .Returns(Task.CompletedTask);
        _mockAudioRecorder
            .Setup(r => r.StopRecordingAsync())
            .ReturnsAsync("test-audio.wav");
        _mockTranscriptionService
            .Setup(t => t.TranscribeAsync(It.IsAny<string>(), It.IsAny<CancellationToken>()))
            .ReturnsAsync(TranscriptionResult.Ok(""));

        await _orchestrator.StartAsync(RecordingMode.Hold);

        // Act
        await _orchestrator.StopAsync();

        // Assert
        Assert.NotNull(completedArgs);
        Assert.Equal(string.Empty, completedArgs!.Transcript);
        // Post-processing and pasting should NOT be called
        _mockPostProcessingService.Verify(p => p.ProcessAsync(
            It.IsAny<string>(),
            It.IsAny<string>(),
            It.IsAny<IReadOnlyList<string>>(),
            It.IsAny<string?>(),
            It.IsAny<string?>(),
            It.IsAny<CancellationToken>()), Times.Never);
    }

    #endregion

    #region StopAsync - Error Handling Tests

    [Fact]
    public async Task StopAsync_TranscriptionFails_FiresErrorEvent()
    {
        // Arrange
        PipelineErrorEventArgs? errorArgs = null;
        _orchestrator.Error += (s, e) => errorArgs = e;

        _mockAudioRecorder
            .Setup(r => r.StartRecordingAsync(It.IsAny<string?>()))
            .Returns(Task.CompletedTask);
        _mockAudioRecorder
            .Setup(r => r.StopRecordingAsync())
            .ReturnsAsync("test-audio.wav");
        _mockTranscriptionService
            .Setup(t => t.TranscribeAsync(It.IsAny<string>(), It.IsAny<CancellationToken>()))
            .ReturnsAsync(TranscriptionResult.Fail(new TranscriptionError(TranscriptionErrorType.AuthenticationError, "API key invalid")));

        await _orchestrator.StartAsync(RecordingMode.Hold);

        // Act
        await _orchestrator.StopAsync();

        // Assert
        Assert.NotNull(errorArgs);
        Assert.Equal(PipelineState.Transcribing, errorArgs!.StateAtError);
    }

    [Fact]
    public async Task StopAsync_PostProcessingFails_FallsBackToRawTranscript()
    {
        // Arrange
        PipelineCompletedEventArgs? completedArgs = null;
        _orchestrator.Completed += (s, e) => completedArgs = e;

        _mockAudioRecorder
            .Setup(r => r.StartRecordingAsync(It.IsAny<string?>()))
            .Returns(Task.CompletedTask);
        _mockAudioRecorder
            .Setup(r => r.StopRecordingAsync())
            .ReturnsAsync("test-audio.wav");
        _mockTranscriptionService
            .Setup(t => t.TranscribeAsync(It.IsAny<string>(), It.IsAny<CancellationToken>()))
            .ReturnsAsync(TranscriptionResult.Ok("Raw transcript text"));
        _mockPostProcessingService
            .Setup(p => p.ProcessAsync(
                It.IsAny<string>(),
                It.IsAny<string>(),
                It.IsAny<IReadOnlyList<string>>(),
                It.IsAny<string?>(),
                It.IsAny<string?>(),
                It.IsAny<CancellationToken>()))
            .ReturnsAsync(PostProcessingResult.Fallback("Raw transcript text"));
        _mockClipboardManager
            .Setup(c => c.PasteTextAsync(It.IsAny<string>(), It.IsAny<bool>(), It.IsAny<CancellationToken>()))
            .Returns(Task.CompletedTask);

        await _orchestrator.StartAsync(RecordingMode.Hold);

        // Act
        await _orchestrator.StopAsync();

        // Assert
        Assert.NotNull(completedArgs);
        Assert.Equal("Raw transcript text", completedArgs!.Transcript);
    }

    #endregion

    #region Cancel Tests

    [Fact]
    public async Task Cancel_DuringRecording_StopsRecording()
    {
        // Arrange
        _mockAudioRecorder
            .Setup(r => r.StartRecordingAsync(It.IsAny<string?>()))
            .Returns(Task.CompletedTask);

        await _orchestrator.StartAsync(RecordingMode.Hold);

        // Act
        _orchestrator.Cancel();

        // Assert
        _mockAudioRecorder.Verify(r => r.CancelRecording(), Times.Once);
    }

    [Fact]
    public async Task Cancel_DuringRecording_FiresCompletedWithCancelledFlag()
    {
        // Arrange
        PipelineCompletedEventArgs? completedArgs = null;
        _orchestrator.Completed += (s, e) => completedArgs = e;

        _mockAudioRecorder
            .Setup(r => r.StartRecordingAsync(It.IsAny<string?>()))
            .Returns(Task.CompletedTask);

        await _orchestrator.StartAsync(RecordingMode.Hold);

        // Act
        _orchestrator.Cancel();

        // Assert
        Assert.NotNull(completedArgs);
        Assert.True(completedArgs!.WasCancelled);
        Assert.Equal(string.Empty, completedArgs.Transcript);
    }

    [Fact]
    public async Task Cancel_DuringRecording_ReturnsToIdleState()
    {
        // Arrange
        _mockAudioRecorder
            .Setup(r => r.StartRecordingAsync(It.IsAny<string?>()))
            .Returns(Task.CompletedTask);

        await _orchestrator.StartAsync(RecordingMode.Hold);

        // Act
        _orchestrator.Cancel();

        // Assert
        Assert.Equal(PipelineState.Idle, _orchestrator.CurrentState);
        Assert.False(_orchestrator.IsActive);
    }

    [Fact]
    public void Cancel_WhenIdle_DoesNothing()
    {
        // Arrange & Act
        _orchestrator.Cancel(); // Should not throw

        // Assert
        Assert.Equal(PipelineState.Idle, _orchestrator.CurrentState);
    }

    #endregion

    #region State Event Tests

    [Fact]
    public async Task StateChanged_IncludesPreviousAndNewState()
    {
        // Arrange
        var stateChangeArgs = new List<PipelineStateChangedEventArgs>();
        _orchestrator.StateChanged += (s, e) => stateChangeArgs.Add(e);

        _mockAudioRecorder
            .Setup(r => r.StartRecordingAsync(It.IsAny<string?>()))
            .Returns(Task.CompletedTask);

        // Act
        await _orchestrator.StartAsync(RecordingMode.Hold);

        // Assert
        Assert.True(stateChangeArgs.Count >= 2);
        
        // First transition: Idle -> Initializing
        var firstChange = stateChangeArgs[0];
        Assert.Equal(PipelineState.Idle, firstChange.PreviousState);
        Assert.Equal(PipelineState.Initializing, firstChange.NewState);

        // Second transition: Initializing -> Recording
        var secondChange = stateChangeArgs[1];
        Assert.Equal(PipelineState.Initializing, secondChange.PreviousState);
        Assert.Equal(PipelineState.Recording, secondChange.NewState);
    }

    #endregion

    #region AudioLevel Event Tests

    [Fact]
    public async Task AudioLevelChanged_ForwardedDuringRecording()
    {
        // Arrange
        var levelChanges = new List<AudioLevelEventArgs>();
        _orchestrator.AudioLevelChanged += (s, e) => levelChanges.Add(e);

        _mockAudioRecorder
            .Setup(r => r.StartRecordingAsync(It.IsAny<string?>()))
            .Returns(Task.CompletedTask);

        await _orchestrator.StartAsync(RecordingMode.Hold);

        // Act - Simulate audio level change from recorder
        _mockAudioRecorder.Raise(r => r.AudioLevelChanged += null,
            _mockAudioRecorder.Object,
            new AudioLevelEventArgs(0.75f));

        // Assert
        Assert.Single(levelChanges);
        Assert.Equal(0.75f, levelChanges[0].Level);
    }

    #endregion

    #region Audio File Cleanup Tests

    [Fact]
    public async Task StopAsync_CleansUpAudioFile_OnSuccess()
    {
        // Arrange
        var audioPath = Path.Combine(Path.GetTempPath(), $"test-audio-{Guid.NewGuid()}.wav");
        
        // Create a temp file to simulate audio recording
        await File.WriteAllTextAsync(audioPath, "test audio content");
        Assert.True(File.Exists(audioPath));

        _mockAudioRecorder
            .Setup(r => r.StartRecordingAsync(It.IsAny<string?>()))
            .Returns(Task.CompletedTask);
        _mockAudioRecorder
            .Setup(r => r.StopRecordingAsync())
            .ReturnsAsync(audioPath);
        _mockTranscriptionService
            .Setup(t => t.TranscribeAsync(audioPath, It.IsAny<CancellationToken>()))
            .ReturnsAsync(TranscriptionResult.Ok("Test"));
        _mockPostProcessingService
            .Setup(p => p.ProcessAsync(
                It.IsAny<string>(),
                It.IsAny<string>(),
                It.IsAny<IReadOnlyList<string>>(),
                It.IsAny<string?>(),
                It.IsAny<string?>(),
                It.IsAny<CancellationToken>()))
            .ReturnsAsync(PostProcessingResult.Ok("Test", null));
        _mockClipboardManager
            .Setup(c => c.PasteTextAsync(It.IsAny<string>(), It.IsAny<bool>(), It.IsAny<CancellationToken>()))
            .Returns(Task.CompletedTask);

        await _orchestrator.StartAsync(RecordingMode.Hold);

        // Act
        await _orchestrator.StopAsync();

        // Assert - File should be cleaned up
        Assert.False(File.Exists(audioPath));
    }

    #endregion

    #region Custom Vocabulary Tests

    [Fact]
    public async Task StopAsync_PassesCustomVocabularyToPostProcessing()
    {
        // Arrange
        IReadOnlyList<string>? passedVocabulary = null;

        _mockSettingsManager
            .Setup(s => s.Load())
            .Returns(new AppSettings { CustomVocabulary = "FreeFlow\nWhisper API\nOpenAI" });

        _mockAudioRecorder
            .Setup(r => r.StartRecordingAsync(It.IsAny<string?>()))
            .Returns(Task.CompletedTask);
        _mockAudioRecorder
            .Setup(r => r.StopRecordingAsync())
            .ReturnsAsync("test.wav");
        _mockTranscriptionService
            .Setup(t => t.TranscribeAsync(It.IsAny<string>(), It.IsAny<CancellationToken>()))
            .ReturnsAsync(TranscriptionResult.Ok("Test"));
        _mockPostProcessingService
            .Setup(p => p.ProcessAsync(
                It.IsAny<string>(),
                It.IsAny<string>(),
                It.IsAny<IReadOnlyList<string>>(),
                It.IsAny<string?>(),
                It.IsAny<string?>(),
                It.IsAny<CancellationToken>()))
            .Callback<string, string, IReadOnlyList<string>, string?, string?, CancellationToken>(
                (transcript, context, vocab, prompt, lang, ct) => passedVocabulary = vocab)
            .ReturnsAsync(PostProcessingResult.Ok("Test", null));
        _mockClipboardManager
            .Setup(c => c.PasteTextAsync(It.IsAny<string>(), It.IsAny<bool>(), It.IsAny<CancellationToken>()))
            .Returns(Task.CompletedTask);

        await _orchestrator.StartAsync(RecordingMode.Hold);

        // Act
        await _orchestrator.StopAsync();

        // Assert
        Assert.NotNull(passedVocabulary);
        Assert.Equal(3, passedVocabulary!.Count);
        Assert.Contains("FreeFlow", passedVocabulary);
        Assert.Contains("Whisper API", passedVocabulary);
        Assert.Contains("OpenAI", passedVocabulary);
    }

    #endregion

    #region Helper Methods

    private void SetupSuccessfulPipeline(string transcript)
    {
        _mockAudioRecorder
            .Setup(r => r.StartRecordingAsync(It.IsAny<string?>()))
            .Returns(Task.CompletedTask);
        _mockAudioRecorder
            .Setup(r => r.StopRecordingAsync())
            .ReturnsAsync("test-audio.wav");
        _mockTranscriptionService
            .Setup(t => t.TranscribeAsync(It.IsAny<string>(), It.IsAny<CancellationToken>()))
            .ReturnsAsync(TranscriptionResult.Ok(transcript));
        _mockPostProcessingService
            .Setup(p => p.ProcessAsync(
                It.IsAny<string>(),
                It.IsAny<string>(),
                It.IsAny<IReadOnlyList<string>>(),
                It.IsAny<string?>(),
                It.IsAny<string?>(),
                It.IsAny<CancellationToken>()))
            .ReturnsAsync(PostProcessingResult.Ok(transcript, null));
        _mockClipboardManager
            .Setup(c => c.PasteTextAsync(It.IsAny<string>(), It.IsAny<bool>(), It.IsAny<CancellationToken>()))
            .Returns(Task.CompletedTask);
    }

    #endregion
}
