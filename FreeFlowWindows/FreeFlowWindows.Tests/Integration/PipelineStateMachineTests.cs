using FreeFlowWindows.Core.Interfaces;
using FreeFlowWindows.Core.Models;
using FreeFlowWindows.Core.Services;
using Moq;
using Xunit;

namespace FreeFlowWindows.Tests.Integration;

/// <summary>
/// Integration tests for pipeline state machine transitions.
/// Tests complete dictation flow and error recovery.
/// Requirements covered: 1.5, 9.3, 9.4
/// </summary>
public class PipelineStateMachineTests
{
    private readonly Mock<IAudioRecorder> _mockAudioRecorder;
    private readonly Mock<ITranscriptionService> _mockTranscriptionService;
    private readonly Mock<IPostProcessingService> _mockPostProcessingService;
    private readonly Mock<IClipboardManager> _mockClipboardManager;
    private readonly Mock<ISettingsManager> _mockSettingsManager;
    private readonly PipelineOrchestrator _orchestrator;

    public PipelineStateMachineTests()
    {
        _mockAudioRecorder = new Mock<IAudioRecorder>();
        _mockTranscriptionService = new Mock<ITranscriptionService>();
        _mockPostProcessingService = new Mock<IPostProcessingService>();
        _mockClipboardManager = new Mock<IClipboardManager>();
        _mockSettingsManager = new Mock<ISettingsManager>();

        _mockSettingsManager.Setup(s => s.Load()).Returns(new AppSettings());

        _orchestrator = new PipelineOrchestrator(
            _mockAudioRecorder.Object,
            _mockTranscriptionService.Object,
            _mockPostProcessingService.Object,
            _mockClipboardManager.Object,
            _mockSettingsManager.Object);
    }

    #region Complete Flow Tests

    [Fact]
    public async Task CompleteDictationFlow_AllStateTransitions()
    {
        // Arrange
        var stateTransitions = new List<(PipelineState Previous, PipelineState New)>();
        _orchestrator.StateChanged += (s, e) => 
            stateTransitions.Add((e.PreviousState, e.NewState));

        SetupSuccessfulPipeline("Hello, this is a test.");

        // Act - Complete flow: Start -> Stop
        await _orchestrator.StartAsync(RecordingMode.Hold);
        await _orchestrator.StopAsync();

        // Assert - Verify all expected transitions occurred in order
        Assert.True(stateTransitions.Count >= 5, 
            $"Expected at least 5 transitions, got {stateTransitions.Count}");

        // Should start with Idle -> Initializing
        Assert.Equal(PipelineState.Idle, stateTransitions[0].Previous);
        Assert.Equal(PipelineState.Initializing, stateTransitions[0].New);

        // Should include Recording state
        Assert.Contains(stateTransitions, t => t.New == PipelineState.Recording);

        // Should include Transcribing state
        Assert.Contains(stateTransitions, t => t.New == PipelineState.Transcribing);

        // Should include PostProcessing state
        Assert.Contains(stateTransitions, t => t.New == PipelineState.PostProcessing);

        // Should include Pasting state
        Assert.Contains(stateTransitions, t => t.New == PipelineState.Pasting);

        // Should end in Idle
        Assert.Equal(PipelineState.Idle, stateTransitions[^1].New);
    }

    [Fact]
    public async Task CompleteDictationFlow_HoldMode_ProducesTranscript()
    {
        // Arrange
        PipelineCompletedEventArgs? completedArgs = null;
        _orchestrator.Completed += (s, e) => completedArgs = e;

        SetupSuccessfulPipeline("This is my transcribed text.");

        // Act
        await _orchestrator.StartAsync(RecordingMode.Hold);
        await _orchestrator.StopAsync();

        // Assert
        Assert.NotNull(completedArgs);
        Assert.False(completedArgs!.WasCancelled);
        Assert.Equal("This is my transcribed text.", completedArgs.Transcript);
    }

    [Fact]
    public async Task CompleteDictationFlow_ToggleMode_ProducesTranscript()
    {
        // Arrange
        PipelineCompletedEventArgs? completedArgs = null;
        _orchestrator.Completed += (s, e) => completedArgs = e;

        SetupSuccessfulPipeline("Toggle mode transcript.");

        // Act
        await _orchestrator.StartAsync(RecordingMode.Toggle);
        await _orchestrator.StopAsync();

        // Assert
        Assert.NotNull(completedArgs);
        Assert.False(completedArgs!.WasCancelled);
        Assert.Equal("Toggle mode transcript.", completedArgs.Transcript);
    }

    #endregion

    #region Error Recovery Tests

    [Fact]
    public async Task ErrorRecovery_TranscriptionError_TransitionsToError()
    {
        // Arrange
        var stateTransitions = new List<PipelineState>();
        _orchestrator.StateChanged += (s, e) => stateTransitions.Add(e.NewState);

        _mockAudioRecorder.Setup(r => r.StartRecordingAsync(It.IsAny<string?>()))
            .Returns(Task.CompletedTask);
        _mockAudioRecorder.Setup(r => r.StopRecordingAsync())
            .ReturnsAsync("test.wav");
        _mockTranscriptionService.Setup(t => t.TranscribeAsync(It.IsAny<string>(), It.IsAny<CancellationToken>()))
            .ReturnsAsync(TranscriptionResult.Fail(
                new TranscriptionError(TranscriptionErrorType.NetworkError, "API Error")));

        // Act
        await _orchestrator.StartAsync(RecordingMode.Hold);
        await _orchestrator.StopAsync();

        // Assert - Should transition through Error state
        Assert.Contains(PipelineState.Error, stateTransitions);
        
        // Should end in Idle (recovered from error)
        Assert.Equal(PipelineState.Idle, stateTransitions[^1]);
    }

    [Fact]
    public async Task ErrorRecovery_RecordingError_FiresErrorEvent()
    {
        // Arrange
        PipelineErrorEventArgs? errorArgs = null;
        _orchestrator.Error += (s, e) => errorArgs = e;

        _mockAudioRecorder.Setup(r => r.StartRecordingAsync(It.IsAny<string?>()))
            .ThrowsAsync(new Exception("No microphone found"));

        // Act
        await _orchestrator.StartAsync(RecordingMode.Hold);

        // Assert
        Assert.NotNull(errorArgs);
        Assert.Equal(PipelineState.Initializing, errorArgs!.StateAtError);
    }

    [Fact]
    public async Task ErrorRecovery_PostProcessingError_FallsBackToRawTranscript()
    {
        // Arrange
        PipelineCompletedEventArgs? completedArgs = null;
        _orchestrator.Completed += (s, e) => completedArgs = e;

        _mockAudioRecorder.Setup(r => r.StartRecordingAsync(It.IsAny<string?>()))
            .Returns(Task.CompletedTask);
        _mockAudioRecorder.Setup(r => r.StopRecordingAsync())
            .ReturnsAsync("test.wav");
        _mockTranscriptionService.Setup(t => t.TranscribeAsync(It.IsAny<string>(), It.IsAny<CancellationToken>()))
            .ReturnsAsync(TranscriptionResult.Ok("Raw transcript"));
        _mockPostProcessingService.Setup(p => p.ProcessAsync(
                It.IsAny<string>(),
                It.IsAny<string>(),
                It.IsAny<IReadOnlyList<string>>(),
                It.IsAny<string?>(),
                It.IsAny<string?>(),
                It.IsAny<CancellationToken>()))
            .ReturnsAsync(PostProcessingResult.Fail(PostProcessingError.EmptyOutput()));
        _mockClipboardManager.Setup(c => c.PasteTextAsync(It.IsAny<string>(), It.IsAny<bool>(), It.IsAny<CancellationToken>()))
            .Returns(Task.CompletedTask);

        // Act
        await _orchestrator.StartAsync(RecordingMode.Hold);
        await _orchestrator.StopAsync();

        // Assert - Should use raw transcript as fallback
        Assert.NotNull(completedArgs);
        Assert.Equal("Raw transcript", completedArgs!.Transcript);
    }

    [Fact]
    public async Task ErrorRecovery_CanStartNewPipelineAfterError()
    {
        // Arrange - First pipeline fails
        _mockAudioRecorder.Setup(r => r.StartRecordingAsync(It.IsAny<string?>()))
            .ThrowsAsync(new Exception("First error"));

        await _orchestrator.StartAsync(RecordingMode.Hold);

        // Verify first pipeline ended in Idle
        Assert.Equal(PipelineState.Idle, _orchestrator.CurrentState);

        // Arrange - Second pipeline succeeds
        _mockAudioRecorder.Setup(r => r.StartRecordingAsync(It.IsAny<string?>()))
            .Returns(Task.CompletedTask);

        // Act - Start new pipeline
        await _orchestrator.StartAsync(RecordingMode.Hold);

        // Assert - Should be in Recording state
        Assert.Equal(PipelineState.Recording, _orchestrator.CurrentState);

        // Cleanup
        _orchestrator.Cancel();
    }

    #endregion

    #region Cancellation Tests

    [Fact]
    public async Task Cancellation_DuringRecording_ReturnsToIdle()
    {
        // Arrange
        var stateTransitions = new List<PipelineState>();
        _orchestrator.StateChanged += (s, e) => stateTransitions.Add(e.NewState);

        _mockAudioRecorder.Setup(r => r.StartRecordingAsync(It.IsAny<string?>()))
            .Returns(Task.CompletedTask);

        await _orchestrator.StartAsync(RecordingMode.Hold);

        // Act
        _orchestrator.Cancel();

        // Assert
        Assert.Equal(PipelineState.Idle, _orchestrator.CurrentState);
        Assert.Contains(PipelineState.Idle, stateTransitions);
    }

    [Fact]
    public async Task Cancellation_FiresCompletedEventWithCancelledFlag()
    {
        // Arrange
        PipelineCompletedEventArgs? completedArgs = null;
        _orchestrator.Completed += (s, e) => completedArgs = e;

        _mockAudioRecorder.Setup(r => r.StartRecordingAsync(It.IsAny<string?>()))
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
    public async Task Cancellation_CallsCancelOnRecorder()
    {
        // Arrange
        _mockAudioRecorder.Setup(r => r.StartRecordingAsync(It.IsAny<string?>()))
            .Returns(Task.CompletedTask);

        await _orchestrator.StartAsync(RecordingMode.Hold);

        // Act
        _orchestrator.Cancel();

        // Assert
        _mockAudioRecorder.Verify(r => r.CancelRecording(), Times.Once);
    }

    #endregion

    #region State Property Tests

    [Fact]
    public void IsActive_FalseWhenIdle()
    {
        Assert.False(_orchestrator.IsActive);
    }

    [Fact]
    public async Task IsActive_TrueWhenRecording()
    {
        // Arrange
        _mockAudioRecorder.Setup(r => r.StartRecordingAsync(It.IsAny<string?>()))
            .Returns(Task.CompletedTask);

        // Act
        await _orchestrator.StartAsync(RecordingMode.Hold);

        // Assert
        Assert.True(_orchestrator.IsActive);

        // Cleanup
        _orchestrator.Cancel();
    }

    [Fact]
    public async Task ActiveRecordingMode_SetDuringRecording()
    {
        // Arrange
        _mockAudioRecorder.Setup(r => r.StartRecordingAsync(It.IsAny<string?>()))
            .Returns(Task.CompletedTask);

        // Act
        await _orchestrator.StartAsync(RecordingMode.Toggle);

        // Assert
        Assert.Equal(RecordingMode.Toggle, _orchestrator.ActiveRecordingMode);

        // Cleanup
        _orchestrator.Cancel();
    }

    [Fact]
    public async Task ActiveRecordingMode_NullAfterCompletion()
    {
        // Arrange
        SetupSuccessfulPipeline("Test");

        // Act
        await _orchestrator.StartAsync(RecordingMode.Hold);
        await _orchestrator.StopAsync();

        // Assert
        Assert.Null(_orchestrator.ActiveRecordingMode);
    }

    #endregion

    #region Helper Methods

    private void SetupSuccessfulPipeline(string transcript)
    {
        _mockAudioRecorder.Setup(r => r.StartRecordingAsync(It.IsAny<string?>()))
            .Returns(Task.CompletedTask);
        _mockAudioRecorder.Setup(r => r.StopRecordingAsync())
            .ReturnsAsync("test-audio.wav");
        _mockTranscriptionService.Setup(t => t.TranscribeAsync(It.IsAny<string>(), It.IsAny<CancellationToken>()))
            .ReturnsAsync(TranscriptionResult.Ok(transcript));
        _mockPostProcessingService.Setup(p => p.ProcessAsync(
                It.IsAny<string>(),
                It.IsAny<string>(),
                It.IsAny<IReadOnlyList<string>>(),
                It.IsAny<string?>(),
                It.IsAny<string?>(),
                It.IsAny<CancellationToken>()))
            .ReturnsAsync(PostProcessingResult.Ok(transcript, "test-prompt"));
        _mockClipboardManager.Setup(c => c.PasteTextAsync(It.IsAny<string>(), It.IsAny<bool>(), It.IsAny<CancellationToken>()))
            .Returns(Task.CompletedTask);
    }

    #endregion
}
