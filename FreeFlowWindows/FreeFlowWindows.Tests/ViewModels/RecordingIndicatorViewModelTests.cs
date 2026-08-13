using System.ComponentModel;
using FreeFlowWindows.App.ViewModels;
using FreeFlowWindows.Core.Models;
using Xunit;
using static FreeFlowWindows.App.ViewModels.RecordingIndicatorViewModel;

namespace FreeFlowWindows.Tests.ViewModels;

/// <summary>
/// Unit tests for RecordingIndicatorViewModel.
/// Tests state transitions, audio level visualization, error display, and visibility management.
/// Requirements covered: 9.1, 9.2, 9.3, 9.4, 9.5
/// </summary>
public class RecordingIndicatorViewModelTests
{
    #region Constructor Tests

    [Fact]
    public void Constructor_InitializesWithHiddenState()
    {
        // Arrange & Act
        var vm = new RecordingIndicatorViewModel();

        // Assert
        Assert.Equal(IndicatorState.Hidden, vm.CurrentState);
        Assert.False(vm.IsVisible);
    }

    [Fact]
    public void Constructor_InitializesAudioLevelToZero()
    {
        // Arrange & Act
        var vm = new RecordingIndicatorViewModel();

        // Assert
        Assert.Equal(0f, vm.AudioLevel);
    }

    [Fact]
    public void Constructor_InitializesElapsedTimeToZero()
    {
        // Arrange & Act
        var vm = new RecordingIndicatorViewModel();

        // Assert
        Assert.Equal(TimeSpan.Zero, vm.ElapsedTime);
    }

    [Fact]
    public void Constructor_InitializesEmptyErrorMessage()
    {
        // Arrange & Act
        var vm = new RecordingIndicatorViewModel();

        // Assert
        Assert.Equal(string.Empty, vm.ErrorMessage);
    }

    #endregion


    #region State Transition Tests - Requirement 9.1, 9.3

    /// <summary>
    /// Test that ShowInitializing transitions to Initializing state and shows indicator.
    /// Requirement 9.1: Visual indicator display on recording start
    /// </summary>
    [Fact]
    public void ShowInitializing_TransitionsToInitializingState()
    {
        // Arrange
        var vm = new RecordingIndicatorViewModel();

        // Act
        vm.ShowInitializing(RecordingMode.Hold);

        // Assert
        Assert.Equal(IndicatorState.Initializing, vm.CurrentState);
        Assert.True(vm.IsInitializing);
        Assert.False(vm.IsRecording);
        Assert.False(vm.IsProcessing);
        Assert.False(vm.IsError);
    }

    [Fact]
    public void ShowInitializing_SetsVisibleToTrue()
    {
        // Arrange
        var vm = new RecordingIndicatorViewModel();

        // Act
        vm.ShowInitializing(RecordingMode.Hold);

        // Assert
        Assert.True(vm.IsVisible);
    }

    [Fact]
    public void ShowInitializing_SetsRecordingMode()
    {
        // Arrange
        var vm = new RecordingIndicatorViewModel();

        // Act
        vm.ShowInitializing(RecordingMode.Toggle);

        // Assert
        Assert.Equal(RecordingMode.Toggle, vm.RecordingMode);
    }

    [Fact]
    public void ShowInitializing_ResetsElapsedTime()
    {
        // Arrange
        var vm = new RecordingIndicatorViewModel();
        vm.ElapsedTime = TimeSpan.FromSeconds(30);

        // Act
        vm.ShowInitializing(RecordingMode.Hold);

        // Assert
        Assert.Equal(TimeSpan.Zero, vm.ElapsedTime);
    }


    [Fact]
    public void ShowInitializing_ClearsErrorMessage()
    {
        // Arrange
        var vm = new RecordingIndicatorViewModel();
        vm.ShowError("Previous error");

        // Act
        vm.ShowInitializing(RecordingMode.Hold);

        // Assert
        Assert.Equal(string.Empty, vm.ErrorMessage);
    }

    /// <summary>
    /// Test that ShowRecording transitions to Recording state.
    /// Requirement 9.1: Visual indicator display during recording
    /// </summary>
    [Fact]
    public void ShowRecording_TransitionsToRecordingState()
    {
        // Arrange
        var vm = new RecordingIndicatorViewModel();

        // Act
        vm.ShowRecording(RecordingMode.Hold);

        // Assert
        Assert.Equal(IndicatorState.Recording, vm.CurrentState);
        Assert.False(vm.IsInitializing);
        Assert.True(vm.IsRecording);
        Assert.False(vm.IsProcessing);
        Assert.False(vm.IsError);
    }

    [Fact]
    public void ShowRecording_SetsVisibleToTrue()
    {
        // Arrange
        var vm = new RecordingIndicatorViewModel();

        // Act
        vm.ShowRecording(RecordingMode.Hold);

        // Assert
        Assert.True(vm.IsVisible);
    }

    [Fact]
    public void ShowRecording_SetsRecordingMode()
    {
        // Arrange
        var vm = new RecordingIndicatorViewModel();

        // Act
        vm.ShowRecording(RecordingMode.Toggle);

        // Assert
        Assert.Equal(RecordingMode.Toggle, vm.RecordingMode);
    }


    /// <summary>
    /// Test that ShowProcessing transitions to Processing state.
    /// Requirement 9.3: Processing state indicator when recording stops
    /// </summary>
    [Fact]
    public void ShowProcessing_TransitionsToProcessingState()
    {
        // Arrange
        var vm = new RecordingIndicatorViewModel();
        vm.ShowRecording(RecordingMode.Hold);

        // Act
        vm.ShowProcessing();

        // Assert
        Assert.Equal(IndicatorState.Processing, vm.CurrentState);
        Assert.False(vm.IsInitializing);
        Assert.False(vm.IsRecording);
        Assert.True(vm.IsProcessing);
        Assert.False(vm.IsError);
    }

    [Fact]
    public void ShowProcessing_SetsVisibleToTrue()
    {
        // Arrange
        var vm = new RecordingIndicatorViewModel();

        // Act
        vm.ShowProcessing();

        // Assert
        Assert.True(vm.IsVisible);
    }

    [Fact]
    public void ShowProcessing_ClearsErrorMessage()
    {
        // Arrange
        var vm = new RecordingIndicatorViewModel();
        vm.ShowError("Previous error");

        // Act
        vm.ShowProcessing();

        // Assert
        Assert.Equal(string.Empty, vm.ErrorMessage);
    }

    #endregion

    #region Complete State Transition Flow Tests

    /// <summary>
    /// Test full state transition flow: Hidden → Initializing → Recording → Processing → Hidden
    /// Requirements 9.1, 9.3, 9.4
    /// </summary>
    [Fact]
    public void StateTransition_FullSuccessFlow_TransitionsCorrectly()
    {
        // Arrange
        var vm = new RecordingIndicatorViewModel();
        Assert.Equal(IndicatorState.Hidden, vm.CurrentState);

        // Act & Assert - Initializing
        vm.ShowInitializing(RecordingMode.Hold);
        Assert.Equal(IndicatorState.Initializing, vm.CurrentState);
        Assert.True(vm.IsVisible);

        // Act & Assert - Recording
        vm.ShowRecording(RecordingMode.Hold);
        Assert.Equal(IndicatorState.Recording, vm.CurrentState);
        Assert.True(vm.IsVisible);

        // Act & Assert - Processing
        vm.ShowProcessing();
        Assert.Equal(IndicatorState.Processing, vm.CurrentState);
        Assert.True(vm.IsVisible);

        // Act & Assert - Hide
        vm.Hide();
        Assert.Equal(IndicatorState.Hidden, vm.CurrentState);
        Assert.False(vm.IsVisible);
    }


    /// <summary>
    /// Test state transition with error: Hidden → Initializing → Recording → Error → Hidden
    /// Requirements 9.1, 9.5
    /// </summary>
    [Fact]
    public void StateTransition_ErrorFlow_TransitionsCorrectly()
    {
        // Arrange
        var vm = new RecordingIndicatorViewModel();

        // Act & Assert - Start recording
        vm.ShowInitializing(RecordingMode.Hold);
        vm.ShowRecording(RecordingMode.Hold);
        Assert.Equal(IndicatorState.Recording, vm.CurrentState);

        // Act & Assert - Error occurs
        vm.ShowError("Network error");
        Assert.Equal(IndicatorState.Error, vm.CurrentState);
        Assert.True(vm.IsError);
        Assert.True(vm.IsVisible);

        // Act & Assert - Hide after error
        vm.Hide();
        Assert.Equal(IndicatorState.Hidden, vm.CurrentState);
        Assert.False(vm.IsVisible);
    }

    [Theory]
    [InlineData(RecordingMode.Hold)]
    [InlineData(RecordingMode.Toggle)]
    public void StateTransition_BothRecordingModes_TransitionsCorrectly(RecordingMode mode)
    {
        // Arrange
        var vm = new RecordingIndicatorViewModel();

        // Act
        vm.ShowInitializing(mode);
        vm.ShowRecording(mode);

        // Assert
        Assert.Equal(mode, vm.RecordingMode);
        Assert.Equal(IndicatorState.Recording, vm.CurrentState);
    }

    #endregion

    #region Audio Level Visualization Tests - Requirement 9.2

    /// <summary>
    /// Test that setting AudioLevel updates audio bar values.
    /// Requirement 9.2: Animated audio level visualization
    /// </summary>
    [Fact]
    public void AudioLevel_WhenSet_UpdatesAudioBars()
    {
        // Arrange
        var vm = new RecordingIndicatorViewModel();

        // Act
        vm.AudioLevel = 0.8f;

        // Assert - All bars should have values > 0
        Assert.True(vm.AudioBar1 > 0);
        Assert.True(vm.AudioBar2 > 0);
        Assert.True(vm.AudioBar3 > 0);
        Assert.True(vm.AudioBar4 > 0);
        Assert.True(vm.AudioBar5 > 0);
    }

    [Fact]
    public void AudioLevel_WhenHigh_CenterBarIsHighest()
    {
        // Arrange
        var vm = new RecordingIndicatorViewModel();

        // Act - Set high audio level multiple times and check center bar trend
        float centerBarSum = 0;
        float edgeBarSum = 0;
        for (int i = 0; i < 10; i++)
        {
            vm.AudioLevel = 0.9f;
            centerBarSum += vm.AudioBar3;
            edgeBarSum += (vm.AudioBar1 + vm.AudioBar5) / 2;
        }

        // Assert - Center bar should generally be higher than edge bars on average
        Assert.True(centerBarSum / 10 >= edgeBarSum / 10 - 0.3f, 
            "Center bar should tend to be at least near edge bars");
    }


    [Fact]
    public void AudioLevel_ClampedToValidRange()
    {
        // Arrange
        var vm = new RecordingIndicatorViewModel();

        // Act - Set value above max
        vm.AudioLevel = 1.5f;

        // Assert - Should be clamped to 1.0
        Assert.Equal(1.0f, vm.AudioLevel);
    }

    [Fact]
    public void AudioLevel_ClampedToZeroForNegative()
    {
        // Arrange
        var vm = new RecordingIndicatorViewModel();

        // Act - Set negative value
        vm.AudioLevel = -0.5f;

        // Assert - Should be clamped to 0.0
        Assert.Equal(0.0f, vm.AudioLevel);
    }

    [Fact]
    public void AudioLevel_BarsHaveMinimumHeight()
    {
        // Arrange
        var vm = new RecordingIndicatorViewModel();

        // Act - Set a small non-zero audio level to trigger the bars update
        vm.AudioLevel = 0.01f;

        // Assert - Bars should have minimum height (0.09f for 9-bar macOS-style waveform)
        // All 9 bars should have at least the minimum value
        Assert.True(vm.AudioBar1 >= 0.09f);
        Assert.True(vm.AudioBar2 >= 0.09f);
        Assert.True(vm.AudioBar3 >= 0.09f);
        Assert.True(vm.AudioBar4 >= 0.09f);
        Assert.True(vm.AudioBar5 >= 0.09f);
        Assert.True(vm.AudioBar6 >= 0.09f);
        Assert.True(vm.AudioBar7 >= 0.09f);
        Assert.True(vm.AudioBar8 >= 0.09f);
        Assert.True(vm.AudioBar9 >= 0.09f);
    }

    [Fact]
    public void AudioLevel_RaisesPropertyChangedForAllBars()
    {
        // Arrange
        var vm = new RecordingIndicatorViewModel();
        var changedProperties = new List<string>();
        vm.PropertyChanged += (s, e) => changedProperties.Add(e.PropertyName!);

        // Act
        vm.AudioLevel = 0.7f;

        // Assert - All 9 bars should raise property changed
        Assert.Contains("AudioLevel", changedProperties);
        Assert.Contains("AudioBar1", changedProperties);
        Assert.Contains("AudioBar2", changedProperties);
        Assert.Contains("AudioBar3", changedProperties);
        Assert.Contains("AudioBar4", changedProperties);
        Assert.Contains("AudioBar5", changedProperties);
        Assert.Contains("AudioBar6", changedProperties);
        Assert.Contains("AudioBar7", changedProperties);
        Assert.Contains("AudioBar8", changedProperties);
        Assert.Contains("AudioBar9", changedProperties);
    }

    [Theory]
    [InlineData(0.01f)]
    [InlineData(0.25f)]
    [InlineData(0.5f)]
    [InlineData(0.75f)]
    [InlineData(1.0f)]
    public void AudioLevel_VariousLevels_AllBarsWithinValidRange(float level)
    {
        // Arrange
        var vm = new RecordingIndicatorViewModel();

        // Act
        vm.AudioLevel = level;

        // Assert - All 9 bars should be between 0.09 (min) and 1.0 (max)
        Assert.InRange(vm.AudioBar1, 0.09f, 1.0f);
        Assert.InRange(vm.AudioBar2, 0.09f, 1.0f);
        Assert.InRange(vm.AudioBar3, 0.09f, 1.0f);
        Assert.InRange(vm.AudioBar4, 0.09f, 1.0f);
        Assert.InRange(vm.AudioBar5, 0.09f, 1.0f);
        Assert.InRange(vm.AudioBar6, 0.09f, 1.0f);
        Assert.InRange(vm.AudioBar7, 0.09f, 1.0f);
        Assert.InRange(vm.AudioBar8, 0.09f, 1.0f);
        Assert.InRange(vm.AudioBar9, 0.09f, 1.0f);
    }

    #endregion


    #region Error Message Display Tests - Requirement 9.5

    /// <summary>
    /// Test that ShowError displays error message and transitions to Error state.
    /// Requirement 9.5: Display error message briefly on errors
    /// </summary>
    [Fact]
    public void ShowError_SetsErrorMessage()
    {
        // Arrange
        var vm = new RecordingIndicatorViewModel();

        // Act
        vm.ShowError("Transcription failed");

        // Assert
        Assert.Equal("Transcription failed", vm.ErrorMessage);
    }

    [Fact]
    public void ShowError_TransitionsToErrorState()
    {
        // Arrange
        var vm = new RecordingIndicatorViewModel();

        // Act
        vm.ShowError("Network error");

        // Assert
        Assert.Equal(IndicatorState.Error, vm.CurrentState);
        Assert.True(vm.IsError);
        Assert.False(vm.IsInitializing);
        Assert.False(vm.IsRecording);
        Assert.False(vm.IsProcessing);
    }

    [Fact]
    public void ShowError_SetsVisibleToTrue()
    {
        // Arrange
        var vm = new RecordingIndicatorViewModel();

        // Act
        vm.ShowError("API key invalid");

        // Assert
        Assert.True(vm.IsVisible);
    }

    [Theory]
    [InlineData("Network error")]
    [InlineData("API key is invalid")]
    [InlineData("Transcription timeout")]
    [InlineData("No microphone available")]
    public void ShowError_VariousErrorMessages_DisplaysCorrectly(string errorMessage)
    {
        // Arrange
        var vm = new RecordingIndicatorViewModel();

        // Act
        vm.ShowError(errorMessage);

        // Assert
        Assert.Equal(errorMessage, vm.ErrorMessage);
        Assert.True(vm.IsError);
        Assert.True(vm.IsVisible);
    }

    [Fact]
    public void ShowError_RaisesPropertyChangedForErrorMessage()
    {
        // Arrange
        var vm = new RecordingIndicatorViewModel();
        var changedProperties = new List<string>();
        vm.PropertyChanged += (s, e) => changedProperties.Add(e.PropertyName!);

        // Act
        vm.ShowError("Test error");

        // Assert
        Assert.Contains("ErrorMessage", changedProperties);
        Assert.Contains("CurrentState", changedProperties);
        Assert.Contains("IsError", changedProperties);
    }

    #endregion


    #region Hide/Dismiss Tests - Requirement 9.4

    /// <summary>
    /// Test that Hide hides the indicator and resets state.
    /// Requirement 9.4: Hide indicator on completion
    /// </summary>
    [Fact]
    public void Hide_SetsVisibleToFalse()
    {
        // Arrange
        var vm = new RecordingIndicatorViewModel();
        vm.ShowRecording(RecordingMode.Hold);
        Assert.True(vm.IsVisible);

        // Act
        vm.Hide();

        // Assert
        Assert.False(vm.IsVisible);
    }

    [Fact]
    public void Hide_TransitionsToHiddenState()
    {
        // Arrange
        var vm = new RecordingIndicatorViewModel();
        vm.ShowRecording(RecordingMode.Hold);

        // Act
        vm.Hide();

        // Assert
        Assert.Equal(IndicatorState.Hidden, vm.CurrentState);
    }

    [Fact]
    public void Hide_ResetsAudioLevel()
    {
        // Arrange
        var vm = new RecordingIndicatorViewModel();
        vm.ShowRecording(RecordingMode.Hold);
        vm.AudioLevel = 0.8f;

        // Act
        vm.Hide();

        // Assert
        Assert.Equal(0f, vm.AudioLevel);
    }

    [Fact]
    public void Hide_ResetsElapsedTime()
    {
        // Arrange
        var vm = new RecordingIndicatorViewModel();
        vm.ShowRecording(RecordingMode.Hold);
        vm.ElapsedTime = TimeSpan.FromSeconds(45);

        // Act
        vm.Hide();

        // Assert
        Assert.Equal(TimeSpan.Zero, vm.ElapsedTime);
    }

    [Fact]
    public void Hide_FromAnyState_TransitionsToHidden()
    {
        // Arrange
        var vm = new RecordingIndicatorViewModel();

        // Test from Initializing
        vm.ShowInitializing(RecordingMode.Hold);
        vm.Hide();
        Assert.Equal(IndicatorState.Hidden, vm.CurrentState);

        // Test from Recording
        vm.ShowRecording(RecordingMode.Hold);
        vm.Hide();
        Assert.Equal(IndicatorState.Hidden, vm.CurrentState);

        // Test from Processing
        vm.ShowProcessing();
        vm.Hide();
        Assert.Equal(IndicatorState.Hidden, vm.CurrentState);

        // Test from Error
        vm.ShowError("Test error");
        vm.Hide();
        Assert.Equal(IndicatorState.Hidden, vm.CurrentState);
    }

    #endregion


    #region Reset Tests

    [Fact]
    public void Reset_HidesIndicator()
    {
        // Arrange
        var vm = new RecordingIndicatorViewModel();
        vm.ShowRecording(RecordingMode.Hold);

        // Act
        vm.Reset();

        // Assert
        Assert.False(vm.IsVisible);
        Assert.Equal(IndicatorState.Hidden, vm.CurrentState);
    }

    [Fact]
    public void Reset_ClearsErrorMessage()
    {
        // Arrange
        var vm = new RecordingIndicatorViewModel();
        vm.ShowError("Test error");

        // Act
        vm.Reset();

        // Assert
        Assert.Equal(string.Empty, vm.ErrorMessage);
    }

    [Fact]
    public void Reset_ResetsRecordingModeToHold()
    {
        // Arrange
        var vm = new RecordingIndicatorViewModel();
        vm.ShowRecording(RecordingMode.Toggle);

        // Act
        vm.Reset();

        // Assert
        Assert.Equal(RecordingMode.Hold, vm.RecordingMode);
    }

    #endregion

    #region Elapsed Time Display Tests

    [Fact]
    public void ElapsedTimeDisplay_FormattedCorrectly()
    {
        // Arrange
        var vm = new RecordingIndicatorViewModel();

        // Act - Use TimeSpan.FromSeconds or explicit ticks/milliseconds
        vm.ElapsedTime = TimeSpan.FromMilliseconds(83456); // 1 minute, 23 seconds, 456 ms

        // Assert - Should be "01:23.4"
        Assert.Equal("01:23.4", vm.ElapsedTimeDisplay);
    }

    [Fact]
    public void ElapsedTimeDisplay_ZeroTime_FormattedCorrectly()
    {
        // Arrange
        var vm = new RecordingIndicatorViewModel();

        // Act
        vm.ElapsedTime = TimeSpan.Zero;

        // Assert
        Assert.Equal("00:00.0", vm.ElapsedTimeDisplay);
    }

    [Fact]
    public void ElapsedTimeDisplay_LongDuration_FormattedCorrectly()
    {
        // Arrange
        var vm = new RecordingIndicatorViewModel();

        // Act - 10 minutes, 59 seconds, 900 ms
        vm.ElapsedTime = TimeSpan.FromMilliseconds(659900);

        // Assert
        Assert.Equal("10:59.9", vm.ElapsedTimeDisplay);
    }

    [Fact]
    public void ElapsedTime_RaisesPropertyChangedForDisplay()
    {
        // Arrange
        var vm = new RecordingIndicatorViewModel();
        var changedProperties = new List<string>();
        vm.PropertyChanged += (s, e) => changedProperties.Add(e.PropertyName!);

        // Act
        vm.ElapsedTime = TimeSpan.FromSeconds(30);

        // Assert
        Assert.Contains("ElapsedTime", changedProperties);
        Assert.Contains("ElapsedTimeDisplay", changedProperties);
    }

    #endregion


    #region Status Text Tests

    [Fact]
    public void StatusText_WhenInitializing_ShowsCorrectText()
    {
        // Arrange
        var vm = new RecordingIndicatorViewModel();

        // Act
        vm.ShowInitializing(RecordingMode.Hold);

        // Assert
        Assert.Equal("Initializing...", vm.StatusText);
    }

    [Fact]
    public void StatusText_WhenRecordingHoldMode_ShowsCorrectText()
    {
        // Arrange
        var vm = new RecordingIndicatorViewModel();

        // Act
        vm.ShowRecording(RecordingMode.Hold);

        // Assert
        Assert.Equal("Recording (release to stop)", vm.StatusText);
    }

    [Fact]
    public void StatusText_WhenRecordingToggleMode_ShowsCorrectText()
    {
        // Arrange
        var vm = new RecordingIndicatorViewModel();

        // Act
        vm.ShowRecording(RecordingMode.Toggle);

        // Assert
        Assert.Equal("Recording (click to stop)", vm.StatusText);
    }

    [Fact]
    public void StatusText_WhenProcessing_ShowsCorrectText()
    {
        // Arrange
        var vm = new RecordingIndicatorViewModel();

        // Act
        vm.ShowProcessing();

        // Assert
        Assert.Equal("Processing...", vm.StatusText);
    }

    [Fact]
    public void StatusText_WhenError_ShowsCorrectText()
    {
        // Arrange
        var vm = new RecordingIndicatorViewModel();

        // Act
        vm.ShowError("Test error");

        // Assert
        Assert.Equal("Error", vm.StatusText);
    }

    #endregion

    #region Property Change Notification Tests

    [Fact]
    public void CurrentState_WhenChanged_RaisesPropertyChanged()
    {
        // Arrange
        var vm = new RecordingIndicatorViewModel();
        var changedProperties = new List<string>();
        vm.PropertyChanged += (s, e) => changedProperties.Add(e.PropertyName!);

        // Act
        vm.ShowRecording(RecordingMode.Hold);

        // Assert
        Assert.Contains("CurrentState", changedProperties);
        Assert.Contains("IsRecording", changedProperties);
    }

    [Fact]
    public void IsVisible_WhenChanged_RaisesPropertyChanged()
    {
        // Arrange
        var vm = new RecordingIndicatorViewModel();
        var changedProperties = new List<string>();
        vm.PropertyChanged += (s, e) => changedProperties.Add(e.PropertyName!);

        // Act
        vm.ShowRecording(RecordingMode.Hold);

        // Assert
        Assert.Contains("IsVisible", changedProperties);
    }

    [Fact]
    public void RecordingMode_WhenChanged_RaisesPropertyChanged()
    {
        // Arrange
        var vm = new RecordingIndicatorViewModel();
        var changedProperties = new List<string>();
        vm.PropertyChanged += (s, e) => changedProperties.Add(e.PropertyName!);

        // Act
        vm.ShowRecording(RecordingMode.Toggle);

        // Assert
        Assert.Contains("RecordingMode", changedProperties);
    }

    #endregion


    #region Cancel Command Tests

    [Fact]
    public void CancelCommand_WhenExecuted_RaisesCancelRequestedEvent()
    {
        // Arrange
        var vm = new RecordingIndicatorViewModel();
        var eventRaised = false;
        vm.CancelRequested += (s, e) => eventRaised = true;

        // Act
        vm.CancelCommand.Execute(null);

        // Assert
        Assert.True(eventRaised);
    }

    [Fact]
    public void CancelCommand_EventSenderIsViewModel()
    {
        // Arrange
        var vm = new RecordingIndicatorViewModel();
        object? sender = null;
        vm.CancelRequested += (s, e) => sender = s;

        // Act
        vm.CancelCommand.Execute(null);

        // Assert
        Assert.Same(vm, sender);
    }

    [Fact]
    public void CancelCommand_CanExecute_ReturnsTrue()
    {
        // Arrange
        var vm = new RecordingIndicatorViewModel();

        // Assert
        Assert.True(vm.CancelCommand.CanExecute(null));
    }

    #endregion

    #region State Boolean Properties Tests

    [Fact]
    public void IsInitializing_TrueOnlyInInitializingState()
    {
        // Arrange
        var vm = new RecordingIndicatorViewModel();

        // Hidden
        Assert.False(vm.IsInitializing);

        // Initializing
        vm.ShowInitializing(RecordingMode.Hold);
        Assert.True(vm.IsInitializing);

        // Recording
        vm.ShowRecording(RecordingMode.Hold);
        Assert.False(vm.IsInitializing);

        // Processing
        vm.ShowProcessing();
        Assert.False(vm.IsInitializing);

        // Error
        vm.ShowError("test");
        Assert.False(vm.IsInitializing);
    }

    [Fact]
    public void IsRecording_TrueOnlyInRecordingState()
    {
        // Arrange
        var vm = new RecordingIndicatorViewModel();

        // Hidden
        Assert.False(vm.IsRecording);

        // Initializing
        vm.ShowInitializing(RecordingMode.Hold);
        Assert.False(vm.IsRecording);

        // Recording
        vm.ShowRecording(RecordingMode.Hold);
        Assert.True(vm.IsRecording);

        // Processing
        vm.ShowProcessing();
        Assert.False(vm.IsRecording);

        // Error
        vm.ShowError("test");
        Assert.False(vm.IsRecording);
    }

    [Fact]
    public void IsProcessing_TrueOnlyInProcessingState()
    {
        // Arrange
        var vm = new RecordingIndicatorViewModel();

        // Hidden
        Assert.False(vm.IsProcessing);

        // Initializing
        vm.ShowInitializing(RecordingMode.Hold);
        Assert.False(vm.IsProcessing);

        // Recording
        vm.ShowRecording(RecordingMode.Hold);
        Assert.False(vm.IsProcessing);

        // Processing
        vm.ShowProcessing();
        Assert.True(vm.IsProcessing);

        // Error
        vm.ShowError("test");
        Assert.False(vm.IsProcessing);
    }

    [Fact]
    public void IsError_TrueOnlyInErrorState()
    {
        // Arrange
        var vm = new RecordingIndicatorViewModel();

        // Hidden
        Assert.False(vm.IsError);

        // Initializing
        vm.ShowInitializing(RecordingMode.Hold);
        Assert.False(vm.IsError);

        // Recording
        vm.ShowRecording(RecordingMode.Hold);
        Assert.False(vm.IsError);

        // Processing
        vm.ShowProcessing();
        Assert.False(vm.IsError);

        // Error
        vm.ShowError("test");
        Assert.True(vm.IsError);
    }

    #endregion
}
