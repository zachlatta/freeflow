using FreeFlowWindows.Core.Audio;
using FreeFlowWindows.Core.Interfaces;
using FreeFlowWindows.Core.Models;
using NAudio.Wave;

namespace FreeFlowWindows.Core.Services;

/// <summary>
/// Audio recorder implementation using NAudio for microphone capture.
/// Records audio in 16kHz, 16-bit, Mono PCM WAV format compatible with Whisper API.
/// </summary>
public class AudioRecorder : IAudioRecorder
{
    #region Constants

    /// <summary>
    /// Sample rate for Whisper API compatibility (16kHz).
    /// </summary>
    private const int SampleRate = 16000;

    /// <summary>
    /// Bits per sample (16-bit).
    /// </summary>
    private const int BitsPerSample = 16;

    /// <summary>
    /// Number of channels (mono).
    /// </summary>
    private const int Channels = 1;

    /// <summary>
    /// Watchdog timeout in milliseconds to detect microphone failure.
    /// </summary>
    private const int WatchdogTimeoutMs = 2000;

    #endregion

    #region Fields

    private WaveInEvent? _waveIn;
    private WaveFileWriter? _waveFileWriter;
    private string? _currentFilePath;
    private readonly LiveAudioLevelNormalizer _levelNormalizer;
    private DateTime _recordingStartTime;
    private DateTime _lastDataReceivedTime;
    private System.Timers.Timer? _watchdogTimer;
    private readonly object _recordingLock = new();
    private bool _isRecording;
    private bool _isDisposed;
    private int _usedDeviceNumber = -1;

    #endregion

    #region Events

    /// <inheritdoc />
    public event EventHandler<AudioLevelEventArgs>? AudioLevelChanged;

    /// <inheritdoc />
    public event EventHandler<RecordingReadyEventArgs>? RecordingReady;

    /// <inheritdoc />
    public event EventHandler<RecordingErrorEventArgs>? RecordingFailed;

    #endregion

    #region Properties

    /// <inheritdoc />
    public bool IsRecording
    {
        get
        {
            lock (_recordingLock)
            {
                return _isRecording;
            }
        }
    }

    #endregion

    #region Constructor

    /// <summary>
    /// Creates a new AudioRecorder instance.
    /// </summary>
    public AudioRecorder()
    {
        _levelNormalizer = new LiveAudioLevelNormalizer();
    }

    #endregion

    #region Public Methods

    /// <inheritdoc />
    public IReadOnlyList<AudioDevice> GetAvailableDevices()
    {
        var devices = new List<AudioDevice>();
        int deviceCount = WaveIn.DeviceCount;

        for (int i = 0; i < deviceCount; i++)
        {
            var capabilities = WaveIn.GetCapabilities(i);
            devices.Add(new AudioDevice(
                id: i.ToString(),
                name: capabilities.ProductName,
                isDefault: i == 0  // Device 0 is typically the default
            ));
        }

        return devices.AsReadOnly();
    }

    /// <inheritdoc />
    public Task StartRecordingAsync(string? deviceId = null)
    {
        ThrowIfDisposed();

        lock (_recordingLock)
        {
            if (_isRecording)
            {
                throw new InvalidOperationException("Recording is already in progress.");
            }

            var devices = GetAvailableDevices();
            if (devices.Count == 0)
            {
                RaiseRecordingFailed(
                    RecordingErrorType.NoDevice,
                    "No microphone available. Please connect one and try again.");
                return Task.CompletedTask;
            }

            // Determine which device to use
            int deviceNumber = GetDeviceNumber(deviceId, devices);

            try
            {
                // Reset level normalizer for new session
                _levelNormalizer.Reset();

                // Create wave format: 16kHz, 16-bit, Mono
                var waveFormat = new WaveFormat(SampleRate, BitsPerSample, Channels);

                // Create temp file with GUID filename
                _currentFilePath = Path.Combine(
                    Path.GetTempPath(),
                    $"freeflow_{Guid.NewGuid():N}.wav");

                // Initialize WaveIn
                _waveIn = new WaveInEvent
                {
                    DeviceNumber = deviceNumber,
                    WaveFormat = waveFormat,
                    BufferMilliseconds = 50  // 50ms buffer for responsive level updates
                };

                _usedDeviceNumber = deviceNumber;
                _waveIn.DataAvailable += OnDataAvailable;
                _waveIn.RecordingStopped += OnRecordingStopped;

                // Initialize file writer
                _waveFileWriter = new WaveFileWriter(_currentFilePath, waveFormat);

                // Start recording
                _recordingStartTime = DateTime.UtcNow;
                _lastDataReceivedTime = DateTime.UtcNow;
                _isRecording = true;

                // Start watchdog timer
                StartWatchdogTimer();

                _waveIn.StartRecording();
            }
            catch (Exception ex)
            {
                CleanupRecording();
                
                // Determine error type
                var errorType = ex is NAudio.MmException
                    ? RecordingErrorType.DeviceUnavailable
                    : RecordingErrorType.Unknown;

                RaiseRecordingFailed(
                    errorType,
                    $"Failed to start recording: {ex.Message}",
                    ex);
            }
        }

        return Task.CompletedTask;
    }

    /// <inheritdoc />
    public Task<string?> StopRecordingAsync()
    {
        ThrowIfDisposed();

        string? resultPath = null;

        lock (_recordingLock)
        {
            if (!_isRecording || _waveIn == null)
            {
                return Task.FromResult<string?>(null);
            }

            try
            {
                // Stop watchdog
                StopWatchdogTimer();

                // Stop recording
                _waveIn.StopRecording();

                // Finalize and close the file writer
                _waveFileWriter?.Dispose();
                _waveFileWriter = null;

                resultPath = _currentFilePath;
                var duration = DateTime.UtcNow - _recordingStartTime;

                // Cleanup WaveIn
                _waveIn.DataAvailable -= OnDataAvailable;
                _waveIn.RecordingStopped -= OnRecordingStopped;
                _waveIn.Dispose();
                _waveIn = null;

                _isRecording = false;

                // Raise RecordingReady event
                if (resultPath != null)
                {
                    RecordingReady?.Invoke(this, new RecordingReadyEventArgs(resultPath, duration));
                }
            }
            catch (Exception ex)
            {
                CleanupRecording();
                RaiseRecordingFailed(
                    RecordingErrorType.WriteError,
                    $"Failed to finalize recording: {ex.Message}",
                    ex);
                return Task.FromResult<string?>(null);
            }
        }

        return Task.FromResult(resultPath);
    }

    /// <inheritdoc />
    public void CancelRecording()
    {
        lock (_recordingLock)
        {
            if (!_isRecording)
            {
                return;
            }

            CleanupRecording();
        }
    }

    /// <inheritdoc />
    public void Dispose()
    {
        if (_isDisposed)
        {
            return;
        }

        lock (_recordingLock)
        {
            CleanupRecording();
            _isDisposed = true;
        }

        GC.SuppressFinalize(this);
    }

    #endregion

    #region Private Methods

    /// <summary>
    /// Gets the device number to use for recording.
    /// Falls back to default device if the selected device is unavailable.
    /// </summary>
    private int GetDeviceNumber(string? deviceId, IReadOnlyList<AudioDevice> devices)
    {
        // Try to use the specified device
        if (!string.IsNullOrEmpty(deviceId) && int.TryParse(deviceId, out int requestedDevice))
        {
            // Verify the device exists
            if (requestedDevice >= 0 && requestedDevice < WaveIn.DeviceCount)
            {
                return requestedDevice;
            }
        }

        // Fall back to default device (device 0)
        return 0;
    }

    /// <summary>
    /// Handles incoming audio data from the microphone.
    /// Thread-safe: uses lock to prevent races with StopRecordingAsync.
    /// </summary>
    private void OnDataAvailable(object? sender, WaveInEventArgs e)
    {
        // Update last data received time for watchdog
        _lastDataReceivedTime = DateTime.UtcNow;

        // Write data to file under lock to prevent race with disposal
        lock (_recordingLock)
        {
            if (!_isRecording || _waveFileWriter == null)
            {
                return; // Recording has stopped, ignore this callback
            }

            try
            {
                _waveFileWriter.Write(e.Buffer, 0, e.BytesRecorded);
            }
            catch (ObjectDisposedException)
            {
                // Writer was disposed between our check and write - ignore
                return;
            }
            catch (Exception ex)
            {
                // Handle write error
                CleanupRecording();
                RaiseRecordingFailed(
                    RecordingErrorType.WriteError,
                    $"Failed to write audio data: {ex.Message}",
                    ex);
                return;
            }
        }

        // Calculate and report audio level (outside lock for performance)
        float rms = CalculateRms(e.Buffer, e.BytesRecorded);
        float normalizedLevel = _levelNormalizer.NormalizedLevel(rms);

        AudioLevelChanged?.Invoke(this, new AudioLevelEventArgs(normalizedLevel));
    }

    /// <summary>
    /// Handles recording stopped event from NAudio.
    /// </summary>
    private void OnRecordingStopped(object? sender, StoppedEventArgs e)
    {
        if (e.Exception != null)
        {
            lock (_recordingLock)
            {
                CleanupRecording();
                RaiseRecordingFailed(
                    RecordingErrorType.Unknown,
                    $"Recording stopped unexpectedly: {e.Exception.Message}",
                    e.Exception);
            }
        }
    }

    /// <summary>
    /// Calculates the RMS (root mean square) of the audio buffer.
    /// </summary>
    private static float CalculateRms(byte[] buffer, int bytesRecorded)
    {
        if (bytesRecorded == 0)
        {
            return 0f;
        }

        // Convert bytes to 16-bit samples and calculate RMS
        double sumOfSquares = 0;
        int sampleCount = bytesRecorded / 2;  // 16-bit = 2 bytes per sample

        for (int i = 0; i < bytesRecorded; i += 2)
        {
            short sample = (short)(buffer[i] | (buffer[i + 1] << 8));
            double normalizedSample = sample / 32768.0;  // Normalize to -1.0 to 1.0
            sumOfSquares += normalizedSample * normalizedSample;
        }

        return (float)Math.Sqrt(sumOfSquares / sampleCount);
    }

    /// <summary>
    /// Starts the watchdog timer to detect microphone failures.
    /// </summary>
    private void StartWatchdogTimer()
    {
        _watchdogTimer = new System.Timers.Timer(500);  // Check every 500ms
        _watchdogTimer.Elapsed += OnWatchdogTimerElapsed;
        _watchdogTimer.AutoReset = true;
        _watchdogTimer.Start();
    }

    /// <summary>
    /// Stops the watchdog timer.
    /// </summary>
    private void StopWatchdogTimer()
    {
        if (_watchdogTimer != null)
        {
            _watchdogTimer.Stop();
            _watchdogTimer.Elapsed -= OnWatchdogTimerElapsed;
            _watchdogTimer.Dispose();
            _watchdogTimer = null;
        }
    }

    /// <summary>
    /// Handles watchdog timer elapsed event.
    /// </summary>
    private void OnWatchdogTimerElapsed(object? sender, System.Timers.ElapsedEventArgs e)
    {
        var timeSinceLastData = DateTime.UtcNow - _lastDataReceivedTime;

        if (timeSinceLastData.TotalMilliseconds > WatchdogTimeoutMs)
        {
            lock (_recordingLock)
            {
                if (_isRecording)
                {
                    CleanupRecording();
                    RaiseRecordingFailed(
                        RecordingErrorType.MicrophoneFailure,
                        "Microphone stopped responding. Please check your microphone connection.");
                }
            }
        }
    }

    /// <summary>
    /// Cleans up all recording resources and deletes any temp files.
    /// </summary>
    private void CleanupRecording()
    {
        StopWatchdogTimer();

        // Stop and dispose WaveIn
        if (_waveIn != null)
        {
            try
            {
                _waveIn.StopRecording();
            }
            catch
            {
                // Ignore errors during cleanup
            }

            _waveIn.DataAvailable -= OnDataAvailable;
            _waveIn.RecordingStopped -= OnRecordingStopped;
            _waveIn.Dispose();
            _waveIn = null;
        }

        // Dispose file writer
        if (_waveFileWriter != null)
        {
            try
            {
                _waveFileWriter.Dispose();
            }
            catch
            {
                // Ignore errors during cleanup
            }
            _waveFileWriter = null;
        }

        // Delete temp file if it exists
        if (!string.IsNullOrEmpty(_currentFilePath) && File.Exists(_currentFilePath))
        {
            try
            {
                File.Delete(_currentFilePath);
            }
            catch
            {
                // Ignore errors during cleanup
            }
        }

        _currentFilePath = null;
        _isRecording = false;
        _usedDeviceNumber = -1;
    }

    /// <summary>
    /// Raises the RecordingFailed event.
    /// </summary>
    private void RaiseRecordingFailed(RecordingErrorType errorType, string message, Exception? exception = null)
    {
        RecordingFailed?.Invoke(this, new RecordingErrorEventArgs(errorType, message, exception));
    }

    /// <summary>
    /// Throws ObjectDisposedException if the recorder has been disposed.
    /// </summary>
    private void ThrowIfDisposed()
    {
        if (_isDisposed)
        {
            throw new ObjectDisposedException(nameof(AudioRecorder));
        }
    }

    #endregion
}
