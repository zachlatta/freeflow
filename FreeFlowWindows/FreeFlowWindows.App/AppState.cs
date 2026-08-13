using System.ComponentModel;
using System.Runtime.CompilerServices;
using FreeFlowWindows.Core.Interfaces;
using FreeFlowWindows.Core.Models;

namespace FreeFlowWindows.App;

/// <summary>
/// Central state management for the FreeFlow application.
/// Provides observable properties for UI binding and coordinates state across components.
/// Requirements: 1.5, 9.1, 9.3 - Application status and recording indicator state
/// </summary>
public class AppState : INotifyPropertyChanged, IDisposable
{
    private readonly IPipelineOrchestrator _orchestrator;
    private readonly ISettingsManager _settingsManager;

    private AppStatus _currentStatus = AppStatus.Idle;
    private PipelineState _pipelineState = PipelineState.Idle;
    private RecordingMode? _activeRecordingMode;
    private float _audioLevel;
    private TimeSpan _recordingDuration;
    private string _lastError = string.Empty;
    private string? _lastTranscript;
    private bool _isSetupComplete;
    private bool _disposed;

    /// <summary>
    /// Raised when a property value changes.
    /// </summary>
    public event PropertyChangedEventHandler? PropertyChanged;

    /// <summary>
    /// Raised when the recording indicator should be shown.
    /// </summary>
    public event EventHandler<RecordingIndicatorEventArgs>? ShowRecordingIndicator;

    /// <summary>
    /// Raised when the recording indicator should be hidden.
    /// </summary>
    public event EventHandler? HideRecordingIndicator;

    /// <summary>
    /// Raised when an error should be displayed.
    /// </summary>
    public event EventHandler<ErrorEventArgs>? ErrorOccurred;

    /// <summary>
    /// Gets the current application status (Idle, Recording, Processing, Error).
    /// </summary>
    public AppStatus CurrentStatus
    {
        get => _currentStatus;
        private set => SetProperty(ref _currentStatus, value);
    }

    /// <summary>
    /// Gets the current pipeline state.
    /// </summary>
    public PipelineState PipelineState
    {
        get => _pipelineState;
        private set => SetProperty(ref _pipelineState, value);
    }

    /// <summary>
    /// Gets the active recording mode, or null if not recording.
    /// </summary>
    public RecordingMode? ActiveRecordingMode
    {
        get => _activeRecordingMode;
        private set => SetProperty(ref _activeRecordingMode, value);
    }

    /// <summary>
    /// Gets the current audio level (0.0 to 1.0) during recording.
    /// </summary>
    public float AudioLevel
    {
        get => _audioLevel;
        private set => SetProperty(ref _audioLevel, value);
    }

    /// <summary>
    /// Gets the current recording duration.
    /// </summary>
    public TimeSpan RecordingDuration
    {
        get => _recordingDuration;
        private set => SetProperty(ref _recordingDuration, value);
    }

    /// <summary>
    /// Gets the last error message.
    /// </summary>
    public string LastError
    {
        get => _lastError;
        private set => SetProperty(ref _lastError, value);
    }

    /// <summary>
    /// Gets the last successfully transcribed text.
    /// </summary>
    public string? LastTranscript
    {
        get => _lastTranscript;
        private set => SetProperty(ref _lastTranscript, value);
    }

    /// <summary>
    /// Gets whether the initial setup is complete (API key configured).
    /// </summary>
    public bool IsSetupComplete
    {
        get => _isSetupComplete;
        private set => SetProperty(ref _isSetupComplete, value);
    }

    /// <summary>
    /// Gets whether the application is currently recording.
    /// </summary>
    public bool IsRecording => CurrentStatus == AppStatus.Recording;

    /// <summary>
    /// Gets whether the application is currently processing.
    /// </summary>
    public bool IsProcessing => CurrentStatus == AppStatus.Processing;

    /// <summary>
    /// Gets whether the application is idle.
    /// </summary>
    public bool IsIdle => CurrentStatus == AppStatus.Idle;

    /// <summary>
    /// Creates a new AppState with the specified dependencies.
    /// </summary>
    public AppState(IPipelineOrchestrator orchestrator, ISettingsManager settingsManager)
    {
        _orchestrator = orchestrator ?? throw new ArgumentNullException(nameof(orchestrator));
        _settingsManager = settingsManager ?? throw new ArgumentNullException(nameof(settingsManager));

        // Subscribe to pipeline events
        _orchestrator.StateChanged += OnPipelineStateChanged;
        _orchestrator.AudioLevelChanged += OnAudioLevelChanged;
        _orchestrator.Completed += OnPipelineCompleted;
        _orchestrator.Error += OnPipelineError;
    }

    /// <summary>
    /// Checks if setup is complete and updates the state.
    /// </summary>
    public void CheckSetupStatus(ICredentialStore credentialStore)
    {
        var apiKey = credentialStore.GetApiKey("api_key");
        IsSetupComplete = !string.IsNullOrWhiteSpace(apiKey);
    }

    /// <summary>
    /// Updates the recording duration (called by a timer during recording).
    /// </summary>
    public void UpdateRecordingDuration(TimeSpan duration)
    {
        RecordingDuration = duration;
    }

    /// <summary>
    /// Handles pipeline state changes.
    /// </summary>
    private void OnPipelineStateChanged(object? sender, PipelineStateChangedEventArgs e)
    {
        PipelineState = e.NewState;
        ActiveRecordingMode = _orchestrator.ActiveRecordingMode;

        // Map pipeline state to app status
        CurrentStatus = e.NewState switch
        {
            Core.Models.PipelineState.Idle => AppStatus.Idle,
            Core.Models.PipelineState.Initializing => AppStatus.Recording,
            Core.Models.PipelineState.Recording => AppStatus.Recording,
            Core.Models.PipelineState.Transcribing => AppStatus.Processing,
            Core.Models.PipelineState.PostProcessing => AppStatus.Processing,
            Core.Models.PipelineState.Pasting => AppStatus.Processing,
            Core.Models.PipelineState.Error => AppStatus.Error,
            _ => AppStatus.Idle
        };

        // Raise recording indicator events
        switch (e.NewState)
        {
            case Core.Models.PipelineState.Initializing:
            case Core.Models.PipelineState.Recording:
            case Core.Models.PipelineState.Transcribing:
            case Core.Models.PipelineState.PostProcessing:
            case Core.Models.PipelineState.Pasting:
                ShowRecordingIndicator?.Invoke(this, new RecordingIndicatorEventArgs(
                    e.NewState,
                    _orchestrator.ActiveRecordingMode ?? RecordingMode.Hold));
                break;

            case Core.Models.PipelineState.Idle:
                HideRecordingIndicator?.Invoke(this, EventArgs.Empty);
                break;

            case Core.Models.PipelineState.Error:
                // Error state is handled by OnPipelineError
                break;
        }

        // Raise property changed for computed properties
        OnPropertyChanged(nameof(IsRecording));
        OnPropertyChanged(nameof(IsProcessing));
        OnPropertyChanged(nameof(IsIdle));
    }

    /// <summary>
    /// Handles audio level changes during recording.
    /// </summary>
    private void OnAudioLevelChanged(object? sender, AudioLevelEventArgs e)
    {
        AudioLevel = e.Level;
    }

    /// <summary>
    /// Handles pipeline completion.
    /// </summary>
    private void OnPipelineCompleted(object? sender, PipelineCompletedEventArgs e)
    {
        if (!e.WasCancelled && !string.IsNullOrEmpty(e.Transcript))
        {
            LastTranscript = e.Transcript;
        }

        // Reset recording state
        AudioLevel = 0;
        RecordingDuration = TimeSpan.Zero;
    }

    /// <summary>
    /// Handles pipeline errors.
    /// </summary>
    private void OnPipelineError(object? sender, PipelineErrorEventArgs e)
    {
        LastError = e.Message;
        ErrorOccurred?.Invoke(this, new ErrorEventArgs(e.StateAtError, e.Message, e.Exception));
    }

    /// <summary>
    /// Sets a property value and raises PropertyChanged if the value changed.
    /// </summary>
    protected bool SetProperty<T>(ref T field, T value, [CallerMemberName] string? propertyName = null)
    {
        if (EqualityComparer<T>.Default.Equals(field, value))
        {
            return false;
        }

        field = value;
        OnPropertyChanged(propertyName);
        return true;
    }

    /// <summary>
    /// Raises the PropertyChanged event.
    /// </summary>
    protected void OnPropertyChanged([CallerMemberName] string? propertyName = null)
    {
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));
    }

    /// <summary>
    /// Disposes resources and unsubscribes from events.
    /// </summary>
    public void Dispose()
    {
        Dispose(true);
        GC.SuppressFinalize(this);
    }

    /// <summary>
    /// Disposes managed and unmanaged resources.
    /// </summary>
    protected virtual void Dispose(bool disposing)
    {
        if (_disposed)
            return;

        if (disposing)
        {
            // Unsubscribe from pipeline events to prevent memory leaks
            _orchestrator.StateChanged -= OnPipelineStateChanged;
            _orchestrator.AudioLevelChanged -= OnAudioLevelChanged;
            _orchestrator.Completed -= OnPipelineCompleted;
            _orchestrator.Error -= OnPipelineError;
        }

        _disposed = true;
    }
}

/// <summary>
/// Event arguments for recording indicator display.
/// </summary>
public class RecordingIndicatorEventArgs : EventArgs
{
    /// <summary>
    /// Gets the current pipeline state.
    /// </summary>
    public PipelineState State { get; }

    /// <summary>
    /// Gets the active recording mode.
    /// </summary>
    public RecordingMode Mode { get; }

    public RecordingIndicatorEventArgs(PipelineState state, RecordingMode mode)
    {
        State = state;
        Mode = mode;
    }
}

/// <summary>
/// Event arguments for error events.
/// </summary>
public class ErrorEventArgs : EventArgs
{
    /// <summary>
    /// Gets the pipeline state when the error occurred.
    /// </summary>
    public PipelineState StateAtError { get; }

    /// <summary>
    /// Gets the error message.
    /// </summary>
    public string Message { get; }

    /// <summary>
    /// Gets the underlying exception, if any.
    /// </summary>
    public Exception? Exception { get; }

    public ErrorEventArgs(PipelineState stateAtError, string message, Exception? exception = null)
    {
        StateAtError = stateAtError;
        Message = message;
        Exception = exception;
    }
}
