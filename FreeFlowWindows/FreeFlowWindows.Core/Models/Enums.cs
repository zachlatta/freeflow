namespace FreeFlowWindows.Core.Models;

/// <summary>
/// Application status for system tray icon state.
/// </summary>
public enum AppStatus
{
    /// <summary>
    /// Application is idle, ready for dictation.
    /// </summary>
    Idle,

    /// <summary>
    /// Application is recording audio.
    /// </summary>
    Recording,

    /// <summary>
    /// Application is processing (transcribing or post-processing).
    /// </summary>
    Processing,

    /// <summary>
    /// An error has occurred.
    /// </summary>
    Error
}

/// <summary>
/// Dictation recording mode.
/// </summary>
public enum RecordingMode
{
    /// <summary>
    /// Hold-to-talk mode: recording while hotkey is held.
    /// </summary>
    Hold,

    /// <summary>
    /// Toggle mode: hotkey starts/stops recording.
    /// </summary>
    Toggle
}

/// <summary>
/// States for the dictation pipeline.
/// </summary>
public enum PipelineState
{
    /// <summary>
    /// Pipeline is idle, ready for dictation.
    /// </summary>
    Idle,

    /// <summary>
    /// Initializing audio recording.
    /// </summary>
    Initializing,

    /// <summary>
    /// Recording audio from microphone.
    /// </summary>
    Recording,

    /// <summary>
    /// Transcribing audio via Whisper API.
    /// </summary>
    Transcribing,

    /// <summary>
    /// Post-processing transcript via LLM.
    /// </summary>
    PostProcessing,

    /// <summary>
    /// Pasting transcript into active application.
    /// </summary>
    Pasting,

    /// <summary>
    /// An error occurred in the pipeline.
    /// </summary>
    Error
}

/// <summary>
/// Type of notification to display.
/// </summary>
public enum NotificationType
{
    /// <summary>
    /// Informational notification.
    /// </summary>
    Info,

    /// <summary>
    /// Warning notification.
    /// </summary>
    Warning,

    /// <summary>
    /// Error notification.
    /// </summary>
    Error
}
