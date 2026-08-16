using FreeFlowWindows.Core.Interfaces;
using FreeFlowWindows.Core.Models;

namespace FreeFlowWindows.Core.Services;

/// <summary>
/// Orchestrates the dictation pipeline: recording → transcription → post-processing → pasting.
/// Implements a state machine that coordinates between all pipeline services.
/// </summary>
public class PipelineOrchestrator : IPipelineOrchestrator, IDisposable
{
    private readonly IAudioRecorder _audioRecorder;
    private readonly ITranscriptionService _transcriptionService;
    private readonly IPostProcessingService _postProcessingService;
    private readonly IClipboardManager _clipboardManager;
    private readonly ISettingsManager _settingsManager;

    private readonly object _stateLock = new();
    private PipelineState _currentState = PipelineState.Idle;
    private RecordingMode? _activeRecordingMode;
    private CancellationTokenSource? _pipelineCts;
    private string? _currentAudioFilePath;
    private string? _lastTranscript;
    private string? _rawTranscript;
    private bool _disposed;

    /// <inheritdoc />
    public event EventHandler<PipelineStateChangedEventArgs>? StateChanged;

    /// <inheritdoc />
    public event EventHandler<PipelineCompletedEventArgs>? Completed;

    /// <inheritdoc />
    public event EventHandler<PipelineErrorEventArgs>? Error;

    /// <inheritdoc />
    public event EventHandler<AudioLevelEventArgs>? AudioLevelChanged;

    /// <inheritdoc />
    public PipelineState CurrentState
    {
        get
        {
            lock (_stateLock)
            {
                return _currentState;
            }
        }
    }

    /// <inheritdoc />
    public bool IsActive => CurrentState != PipelineState.Idle;

    /// <inheritdoc />
    public RecordingMode? ActiveRecordingMode
    {
        get
        {
            lock (_stateLock)
            {
                return _activeRecordingMode;
            }
        }
    }

    /// <inheritdoc />
    public string? LastTranscript => _lastTranscript;

    /// <summary>
    /// Creates a new PipelineOrchestrator with the specified dependencies.
    /// </summary>
    public PipelineOrchestrator(
        IAudioRecorder audioRecorder,
        ITranscriptionService transcriptionService,
        IPostProcessingService postProcessingService,
        IClipboardManager clipboardManager,
        ISettingsManager settingsManager)
    {
        _audioRecorder = audioRecorder ?? throw new ArgumentNullException(nameof(audioRecorder));
        _transcriptionService = transcriptionService ?? throw new ArgumentNullException(nameof(transcriptionService));
        _postProcessingService = postProcessingService ?? throw new ArgumentNullException(nameof(postProcessingService));
        _clipboardManager = clipboardManager ?? throw new ArgumentNullException(nameof(clipboardManager));
        _settingsManager = settingsManager ?? throw new ArgumentNullException(nameof(settingsManager));

        // Subscribe to audio level changes for UI feedback
        _audioRecorder.AudioLevelChanged += OnAudioLevelChanged;
    }

    /// <inheritdoc />
    public async Task StartAsync(RecordingMode mode, string? deviceId = null)
    {
        lock (_stateLock)
        {
            if (_currentState != PipelineState.Idle)
            {
                throw new InvalidOperationException(
                    $"Cannot start pipeline: already in state {_currentState}");
            }
        }

        // Create a new cancellation token for this pipeline run
        _pipelineCts = new CancellationTokenSource();
        _activeRecordingMode = mode;
        _currentAudioFilePath = null;
        _rawTranscript = null;

        try
        {
            // Transition to Initializing
            SetState(PipelineState.Initializing);

            // Start recording
            await _audioRecorder.StartRecordingAsync(deviceId);

            // Transition to Recording
            SetState(PipelineState.Recording);
        }
        catch (OperationCanceledException)
        {
            // Cancelled during initialization
            HandleCancellation();
        }
        catch (Exception ex)
        {
            HandleError(PipelineState.Initializing, "Failed to start recording", ex);
        }
    }

    /// <inheritdoc />
    public async Task StopAsync()
    {
        var currentState = CurrentState;
        
        if (currentState != PipelineState.Recording)
        {
            // Not recording, nothing to stop
            return;
        }

        var ct = _pipelineCts?.Token ?? CancellationToken.None;

        try
        {
            // Stop recording and get the audio file path
            _currentAudioFilePath = await _audioRecorder.StopRecordingAsync();

            if (string.IsNullOrEmpty(_currentAudioFilePath))
            {
                // No audio recorded (possibly too short)
                HandleCompletion(string.Empty, wasCancelled: false);
                return;
            }

            // Check for cancellation
            ct.ThrowIfCancellationRequested();

            // Transition to Transcribing
            SetState(PipelineState.Transcribing);

            // Transcribe the audio
            var transcriptionResult = await _transcriptionService.TranscribeAsync(_currentAudioFilePath, ct);

            if (!transcriptionResult.Success)
            {
                HandleError(
                    PipelineState.Transcribing,
                    transcriptionResult.Error?.Message ?? "Transcription failed");
                return;
            }

            _rawTranscript = transcriptionResult.Transcript;

            // Check for empty transcript (silence/noise)
            if (string.IsNullOrWhiteSpace(_rawTranscript))
            {
                HandleCompletion(string.Empty, wasCancelled: false);
                return;
            }

            ct.ThrowIfCancellationRequested();

            // Transition to PostProcessing
            SetState(PipelineState.PostProcessing);

            // Load settings for post-processing
            var settings = _settingsManager.Load();
            var vocabularyLines = ParseVocabulary(settings.CustomVocabulary);

            // Post-process the transcript
            var postProcessingResult = await _postProcessingService.ProcessAsync(
                _rawTranscript,
                contextSummary: string.Empty, // TODO: Add context capture support
                customVocabulary: vocabularyLines,
                customSystemPrompt: null,
                outputLanguage: null,
                cancellationToken: ct);

            string finalTranscript;
            if (!postProcessingResult.Success)
            {
                // Fall back to raw transcript if post-processing fails
                finalTranscript = _rawTranscript.Trim();
            }
            else if (string.IsNullOrWhiteSpace(postProcessingResult.CleanedTranscript))
            {
                // Post-processing returned empty (determined to be noise)
                HandleCompletion(string.Empty, wasCancelled: false);
                return;
            }
            else
            {
                finalTranscript = postProcessingResult.CleanedTranscript!;
            }

            ct.ThrowIfCancellationRequested();

            // Transition to Pasting
            SetState(PipelineState.Pasting);

            // Paste the transcript
            await _clipboardManager.PasteTextAsync(
                finalTranscript,
                preserveClipboard: settings.PreserveClipboard,
                cancellationToken: ct);

            // Store for "Paste Again" functionality
            _lastTranscript = finalTranscript;

            // Success!
            HandleCompletion(finalTranscript, wasCancelled: false);
        }
        catch (OperationCanceledException)
        {
            HandleCancellation();
        }
        catch (Exception ex)
        {
            HandleError(CurrentState, ex.Message, ex);
        }
        finally
        {
            // Clean up the audio file
            CleanupAudioFile();
        }
    }

    /// <inheritdoc />
    public void Cancel()
    {
        var currentState = CurrentState;
        if (currentState == PipelineState.Idle)
        {
            return;
        }

        // Signal cancellation
        _pipelineCts?.Cancel();

        // If we're recording, cancel the recording
        if (currentState == PipelineState.Recording || currentState == PipelineState.Initializing)
        {
            _audioRecorder.CancelRecording();
        }

        HandleCancellation();
    }

    /// <summary>
    /// Sets the pipeline state and fires the StateChanged event.
    /// </summary>
    private void SetState(PipelineState newState)
    {
        PipelineState previousState;
        lock (_stateLock)
        {
            previousState = _currentState;
            _currentState = newState;
        }

        if (previousState != newState)
        {
            StateChanged?.Invoke(this, new PipelineStateChangedEventArgs(previousState, newState));
        }
    }

    /// <summary>
    /// Handles successful pipeline completion.
    /// </summary>
    private void HandleCompletion(string transcript, bool wasCancelled)
    {
        CleanupAudioFile();

        PipelineState previousState;
        lock (_stateLock)
        {
            previousState = _currentState; // Capture before changing
            _activeRecordingMode = null;
            _currentState = PipelineState.Idle;
        }

        // Fire state changed to Idle with correct previous state
        StateChanged?.Invoke(this, new PipelineStateChangedEventArgs(previousState, PipelineState.Idle));

        // Fire completion event
        Completed?.Invoke(this, new PipelineCompletedEventArgs(transcript, wasCancelled, _rawTranscript));

        // Dispose the CTS
        _pipelineCts?.Dispose();
        _pipelineCts = null;
    }

    /// <summary>
    /// Handles pipeline cancellation.
    /// </summary>
    private void HandleCancellation()
    {
        CleanupAudioFile();

        var previousState = CurrentState;
        lock (_stateLock)
        {
            _activeRecordingMode = null;
            _currentState = PipelineState.Idle;
        }

        // Fire state changed to Idle
        StateChanged?.Invoke(this, new PipelineStateChangedEventArgs(previousState, PipelineState.Idle));

        // Fire completion event with cancelled flag
        Completed?.Invoke(this, new PipelineCompletedEventArgs(string.Empty, wasCancelled: true, _rawTranscript));

        // Dispose the CTS
        _pipelineCts?.Dispose();
        _pipelineCts = null;
    }

    /// <summary>
    /// Handles pipeline errors.
    /// </summary>
    private void HandleError(PipelineState stateAtError, string message, Exception? exception = null)
    {
        CleanupAudioFile();

        var previousState = CurrentState;
        lock (_stateLock)
        {
            _activeRecordingMode = null;
            _currentState = PipelineState.Error;
        }

        // Fire state changed to Error
        StateChanged?.Invoke(this, new PipelineStateChangedEventArgs(previousState, PipelineState.Error));

        // Fire error event
        Error?.Invoke(this, new PipelineErrorEventArgs(stateAtError, message, exception));

        // Transition back to Idle after error
        lock (_stateLock)
        {
            _currentState = PipelineState.Idle;
        }
        StateChanged?.Invoke(this, new PipelineStateChangedEventArgs(PipelineState.Error, PipelineState.Idle));

        // Dispose the CTS
        _pipelineCts?.Dispose();
        _pipelineCts = null;
    }

    /// <summary>
    /// Cleans up the temporary audio file.
    /// </summary>
    private void CleanupAudioFile()
    {
        if (!string.IsNullOrEmpty(_currentAudioFilePath))
        {
            try
            {
                if (File.Exists(_currentAudioFilePath))
                {
                    File.Delete(_currentAudioFilePath);
                }
            }
            catch
            {
                // Best effort cleanup - don't throw
            }
            finally
            {
                _currentAudioFilePath = null;
            }
        }
    }

    /// <summary>
    /// Parses the custom vocabulary string into individual lines.
    /// </summary>
    private static IReadOnlyList<string> ParseVocabulary(string vocabulary)
    {
        if (string.IsNullOrWhiteSpace(vocabulary))
        {
            return Array.Empty<string>();
        }

        return vocabulary
            .Split(new[] { '\r', '\n' }, StringSplitOptions.RemoveEmptyEntries)
            .Select(line => line.Trim())
            .Where(line => !string.IsNullOrEmpty(line))
            .ToList();
    }

    /// <summary>
    /// Forwards audio level events.
    /// </summary>
    private void OnAudioLevelChanged(object? sender, AudioLevelEventArgs e)
    {
        // Only forward if we're in Recording state
        if (CurrentState == PipelineState.Recording)
        {
            AudioLevelChanged?.Invoke(this, e);
        }
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
            // Unsubscribe from audio recorder events to prevent memory leaks
            _audioRecorder.AudioLevelChanged -= OnAudioLevelChanged;

            // Cancel any active pipeline operation
            _pipelineCts?.Cancel();
            _pipelineCts?.Dispose();
            _pipelineCts = null;

            // Clean up any remaining audio file
            CleanupAudioFile();
        }

        _disposed = true;
    }
}
