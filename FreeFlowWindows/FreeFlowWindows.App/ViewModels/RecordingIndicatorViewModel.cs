using System.Windows.Input;
using FreeFlowWindows.Core.Models;

namespace FreeFlowWindows.App.ViewModels;

/// <summary>
/// ViewModel for the RecordingIndicator overlay window.
/// Manages the visual state, audio level visualization, and elapsed time display.
/// </summary>
public class RecordingIndicatorViewModel : ViewModelBase
{
    #region Enums

    /// <summary>
    /// Represents the visual state of the recording indicator.
    /// </summary>
    public enum IndicatorState
    {
        /// <summary>
        /// Hidden state - indicator is not visible.
        /// </summary>
        Hidden,

        /// <summary>
        /// Initializing state - showing dots animation.
        /// </summary>
        Initializing,

        /// <summary>
        /// Recording state - showing waveform/audio level.
        /// </summary>
        Recording,

        /// <summary>
        /// Processing state - showing spinner.
        /// </summary>
        Processing,

        /// <summary>
        /// Error state - showing error message with red indicator.
        /// </summary>
        Error
    }

    #endregion

    #region Fields

    private IndicatorState _currentState = IndicatorState.Hidden;
    private RecordingMode _recordingMode = RecordingMode.Hold;
    private float _audioLevel;
    private TimeSpan _elapsedTime;
    private string _errorMessage = string.Empty;
    private string _statusText = string.Empty;
    private bool _isVisible;

    // Audio level bars (9 bars for visualization, matching macOS WaveformView)
    private float _audioBar1;
    private float _audioBar2;
    private float _audioBar3;
    private float _audioBar4;
    private float _audioBar5;
    private float _audioBar6;
    private float _audioBar7;
    private float _audioBar8;
    private float _audioBar9;

    // macOS-matching bar multipliers: [0.35, 0.55, 0.75, 0.9, 1.0, 0.9, 0.75, 0.55, 0.35]
    private static readonly float[] BarMultipliers = { 0.35f, 0.55f, 0.75f, 0.9f, 1.0f, 0.9f, 0.75f, 0.55f, 0.35f };

    #endregion

    #region Properties

    /// <summary>
    /// Gets or sets the current indicator state.
    /// </summary>
    public IndicatorState CurrentState
    {
        get => _currentState;
        set
        {
            if (SetProperty(ref _currentState, value))
            {
                UpdateStateVisibility();
                OnPropertyChanged(nameof(IsInitializing));
                OnPropertyChanged(nameof(IsRecording));
                OnPropertyChanged(nameof(IsProcessing));
                OnPropertyChanged(nameof(IsError));
            }
        }
    }

    /// <summary>
    /// Gets or sets the current recording mode.
    /// </summary>
    public RecordingMode RecordingMode
    {
        get => _recordingMode;
        set
        {
            if (SetProperty(ref _recordingMode, value))
            {
                UpdateStatusText();
            }
        }
    }

    /// <summary>
    /// Gets or sets the normalized audio level (0.0 to 1.0).
    /// </summary>
    public float AudioLevel
    {
        get => _audioLevel;
        set
        {
            if (SetProperty(ref _audioLevel, Math.Clamp(value, 0f, 1f)))
            {
                UpdateAudioBars();
            }
        }
    }

    /// <summary>
    /// Gets or sets the elapsed recording time.
    /// </summary>
    public TimeSpan ElapsedTime
    {
        get => _elapsedTime;
        set
        {
            if (SetProperty(ref _elapsedTime, value))
            {
                OnPropertyChanged(nameof(ElapsedTimeDisplay));
            }
        }
    }

    /// <summary>
    /// Gets the elapsed time formatted as "00:00.0".
    /// </summary>
    public string ElapsedTimeDisplay
    {
        get
        {
            var minutes = (int)_elapsedTime.TotalMinutes;
            var seconds = _elapsedTime.Seconds;
            var tenths = _elapsedTime.Milliseconds / 100;
            return $"{minutes:D2}:{seconds:D2}.{tenths}";
        }
    }

    /// <summary>
    /// Gets or sets the error message to display.
    /// </summary>
    public string ErrorMessage
    {
        get => _errorMessage;
        set => SetProperty(ref _errorMessage, value ?? string.Empty);
    }

    /// <summary>
    /// Gets or sets the status text (e.g., "Recording", "Processing").
    /// </summary>
    public string StatusText
    {
        get => _statusText;
        set => SetProperty(ref _statusText, value ?? string.Empty);
    }

    /// <summary>
    /// Gets or sets whether the indicator is visible.
    /// </summary>
    public bool IsVisible
    {
        get => _isVisible;
        set => SetProperty(ref _isVisible, value);
    }

    /// <summary>
    /// Gets whether the indicator is in the initializing state.
    /// </summary>
    public bool IsInitializing => CurrentState == IndicatorState.Initializing;

    /// <summary>
    /// Gets whether the indicator is in the recording state.
    /// </summary>
    public bool IsRecording => CurrentState == IndicatorState.Recording;

    /// <summary>
    /// Gets whether the indicator is in the processing state.
    /// </summary>
    public bool IsProcessing => CurrentState == IndicatorState.Processing;

    /// <summary>
    /// Gets whether the indicator is in the error state.
    /// </summary>
    public bool IsError => CurrentState == IndicatorState.Error;

    /// <summary>
    /// Gets whether to show the stop button (only for Toggle mode while recording).
    /// Matches macOS RecordingOverlayView behavior.
    /// </summary>
    public bool ShowStopButton => CurrentState == IndicatorState.Recording && RecordingMode == RecordingMode.Toggle;

    #region Audio Level Bars

    /// <summary>
    /// Gets the height percentage (0.0-1.0) for audio bar 1.
    /// </summary>
    public float AudioBar1
    {
        get => _audioBar1;
        private set => SetProperty(ref _audioBar1, value);
    }

    /// <summary>
    /// Gets the height percentage (0.0-1.0) for audio bar 2.
    /// </summary>
    public float AudioBar2
    {
        get => _audioBar2;
        private set => SetProperty(ref _audioBar2, value);
    }

    /// <summary>
    /// Gets the height percentage (0.0-1.0) for audio bar 3.
    /// </summary>
    public float AudioBar3
    {
        get => _audioBar3;
        private set => SetProperty(ref _audioBar3, value);
    }

    /// <summary>
    /// Gets the height percentage (0.0-1.0) for audio bar 4.
    /// </summary>
    public float AudioBar4
    {
        get => _audioBar4;
        private set => SetProperty(ref _audioBar4, value);
    }

    /// <summary>
    /// Gets the height percentage (0.0-1.0) for audio bar 5.
    /// </summary>
    public float AudioBar5
    {
        get => _audioBar5;
        private set => SetProperty(ref _audioBar5, value);
    }

    /// <summary>
    /// Gets the height percentage (0.0-1.0) for audio bar 6.
    /// </summary>
    public float AudioBar6
    {
        get => _audioBar6;
        private set => SetProperty(ref _audioBar6, value);
    }

    /// <summary>
    /// Gets the height percentage (0.0-1.0) for audio bar 7.
    /// </summary>
    public float AudioBar7
    {
        get => _audioBar7;
        private set => SetProperty(ref _audioBar7, value);
    }

    /// <summary>
    /// Gets the height percentage (0.0-1.0) for audio bar 8.
    /// </summary>
    public float AudioBar8
    {
        get => _audioBar8;
        private set => SetProperty(ref _audioBar8, value);
    }

    /// <summary>
    /// Gets the height percentage (0.0-1.0) for audio bar 9.
    /// </summary>
    public float AudioBar9
    {
        get => _audioBar9;
        private set => SetProperty(ref _audioBar9, value);
    }

    #endregion

    #endregion

    #region Commands

    /// <summary>
    /// Command executed when the user clicks the indicator to cancel.
    /// </summary>
    public ICommand CancelCommand { get; }

    #endregion

    #region Events

    /// <summary>
    /// Event raised when the user requests to cancel the current operation.
    /// </summary>
    public event EventHandler? CancelRequested;

    #endregion

    #region Constructor

    /// <summary>
    /// Creates a new RecordingIndicatorViewModel.
    /// </summary>
    public RecordingIndicatorViewModel()
    {
        CancelCommand = new RelayCommand(OnCancel);
        UpdateStatusText();
    }

    #endregion

    #region Public Methods

    /// <summary>
    /// Transitions to the initializing state.
    /// </summary>
    /// <param name="mode">The recording mode.</param>
    public void ShowInitializing(RecordingMode mode)
    {
        RecordingMode = mode;
        CurrentState = IndicatorState.Initializing;
        ElapsedTime = TimeSpan.Zero;
        ErrorMessage = string.Empty;
        IsVisible = true;
    }

    /// <summary>
    /// Transitions to the recording state.
    /// </summary>
    /// <param name="mode">The recording mode.</param>
    public void ShowRecording(RecordingMode mode)
    {
        RecordingMode = mode;
        CurrentState = IndicatorState.Recording;
        ErrorMessage = string.Empty;
        IsVisible = true;
    }

    /// <summary>
    /// Transitions to the processing state.
    /// </summary>
    public void ShowProcessing()
    {
        CurrentState = IndicatorState.Processing;
        ErrorMessage = string.Empty;
        IsVisible = true;
    }

    /// <summary>
    /// Transitions to the error state with the specified message.
    /// </summary>
    /// <param name="message">The error message to display.</param>
    public void ShowError(string message)
    {
        ErrorMessage = message;
        CurrentState = IndicatorState.Error;
        IsVisible = true;
    }

    /// <summary>
    /// Hides the indicator.
    /// </summary>
    public void Hide()
    {
        IsVisible = false;
        CurrentState = IndicatorState.Hidden;
        AudioLevel = 0;
        ElapsedTime = TimeSpan.Zero;
    }

    /// <summary>
    /// Resets the indicator to initial state.
    /// </summary>
    public void Reset()
    {
        Hide();
        ErrorMessage = string.Empty;
        RecordingMode = RecordingMode.Hold;
    }

    #endregion

    #region Private Methods

    private void OnCancel()
    {
        CancelRequested?.Invoke(this, EventArgs.Empty);
    }

    private void UpdateStateVisibility()
    {
        IsVisible = CurrentState != IndicatorState.Hidden;
        UpdateStatusText();
    }

    private void UpdateStatusText()
    {
        StatusText = CurrentState switch
        {
            IndicatorState.Initializing => "Initializing...",
            IndicatorState.Recording => RecordingMode == RecordingMode.Hold
                ? "Recording (release to stop)"
                : "Recording (click to stop)",
            IndicatorState.Processing => "Processing...",
            IndicatorState.Error => "Error",
            _ => string.Empty
        };
    }

    private void UpdateAudioBars()
    {
        // macOS WaveformView amplitude calculation:
        // barAmplitude = min(audioLevel * multipliers[index], 1.0)
        // Multipliers: [0.35, 0.55, 0.75, 0.9, 1.0, 0.9, 0.75, 0.55, 0.35]
        var level = Math.Max(_audioLevel, 0f);
        
        // macOS uses minHeight=2, maxHeight=22, but we need to output 0.0-1.0 for the converter
        // The converter will apply: 2 + (value * 20) for final height
        // So we output the amplitude directly (already 0.0-1.0)
        
        // Minimum visual amplitude to ensure bars are always visible (2px / 22px ≈ 0.09)
        const float minAmplitude = 0.09f;
        
        AudioBar1 = Math.Max(Math.Min(level * BarMultipliers[0], 1f), minAmplitude);
        AudioBar2 = Math.Max(Math.Min(level * BarMultipliers[1], 1f), minAmplitude);
        AudioBar3 = Math.Max(Math.Min(level * BarMultipliers[2], 1f), minAmplitude);
        AudioBar4 = Math.Max(Math.Min(level * BarMultipliers[3], 1f), minAmplitude);
        AudioBar5 = Math.Max(Math.Min(level * BarMultipliers[4], 1f), minAmplitude);  // Center bar - full level
        AudioBar6 = Math.Max(Math.Min(level * BarMultipliers[5], 1f), minAmplitude);
        AudioBar7 = Math.Max(Math.Min(level * BarMultipliers[6], 1f), minAmplitude);
        AudioBar8 = Math.Max(Math.Min(level * BarMultipliers[7], 1f), minAmplitude);
        AudioBar9 = Math.Max(Math.Min(level * BarMultipliers[8], 1f), minAmplitude);
    }

    #endregion
}
