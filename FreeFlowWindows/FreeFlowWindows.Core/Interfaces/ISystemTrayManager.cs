using FreeFlowWindows.Core.Models;

namespace FreeFlowWindows.Core.Interfaces;

/// <summary>
/// Interface for managing the system tray icon, context menu, and notifications.
/// Provides visual feedback for application state and user interaction.
/// 
/// 100% matches macOS MenuBarLabel/MenuBarView behavior:
/// - Icon states: waveform (idle), record.circle (recording), ellipsis.circle (processing)
/// - Light/dark theme adaptation
/// - Checkmark flash for vocabulary notifications (2 second duration)
/// - Show/hide menu bar icon setting
/// - History submenu with recent transcripts
/// - Hold/Toggle shortcut submenus
/// - Microphone selection submenu
/// </summary>
public interface ISystemTrayManager : IDisposable
{
    /// <summary>
    /// Raised when the user requests to open the settings window.
    /// </summary>
    event EventHandler? SettingsRequested;

    /// <summary>
    /// Raised when the user requests to exit the application.
    /// </summary>
    event EventHandler? ExitRequested;

    /// <summary>
    /// Raised when the user requests to start or stop recording from the context menu.
    /// </summary>
    event EventHandler? RecordingToggleRequested;

    /// <summary>
    /// Raised when the user requests to paste the last transcript again.
    /// Matches macOS "Paste Again" menu item.
    /// </summary>
    event EventHandler? PasteAgainRequested;

    /// <summary>
    /// Raised when the show/hide menu bar icon setting changes.
    /// Matches macOS "show_menu_bar_icon" AppStorage setting.
    /// </summary>
    event EventHandler<bool>? ShowMenuBarIconChanged;

    /// <summary>
    /// Raised when the hold shortcut is changed from the menu.
    /// Matches macOS Hold Shortcut submenu.
    /// </summary>
    event EventHandler<HotkeyBinding>? HoldShortcutChanged;

    /// <summary>
    /// Raised when the toggle shortcut is changed from the menu.
    /// Matches macOS Toggle Shortcut submenu.
    /// </summary>
    event EventHandler<HotkeyBinding>? ToggleShortcutChanged;

    /// <summary>
    /// Raised when the microphone selection is changed from the menu.
    /// Matches macOS Microphone submenu.
    /// </summary>
    event EventHandler<string?>? MicrophoneChanged;

    /// <summary>
    /// Initializes the system tray icon and context menu.
    /// Must be called on the UI thread.
    /// </summary>
    void Initialize();

    /// <summary>
    /// Updates the tray icon to reflect the current application status.
    /// Icons match macOS SF Symbols:
    /// - Idle: waveform
    /// - Recording: record.circle
    /// - Processing: ellipsis.circle
    /// </summary>
    /// <param name="status">The current application status.</param>
    void UpdateIcon(AppStatus status);

    /// <summary>
    /// Shows a balloon notification with the specified title, message, and type.
    /// </summary>
    /// <param name="title">The notification title.</param>
    /// <param name="message">The notification message.</param>
    /// <param name="type">The type of notification (Info, Warning, Error).</param>
    void ShowBalloonNotification(string title, string message, NotificationType type);

    /// <summary>
    /// Updates the tooltip text displayed when hovering over the tray icon.
    /// </summary>
    /// <param name="tooltip">The tooltip text to display.</param>
    void UpdateTooltip(string tooltip);

    /// <summary>
    /// Gets the current application status displayed by the tray icon.
    /// </summary>
    AppStatus CurrentStatus { get; }

    /// <summary>
    /// Gets whether the system tray manager has been initialized.
    /// </summary>
    bool IsInitialized { get; }

    /// <summary>
    /// Sets whether the recording menu item should show "Start Dictating" or "Stop Recording".
    /// Matches macOS menu item text.
    /// </summary>
    /// <param name="isRecording">True if currently recording, false otherwise.</param>
    void SetRecordingState(bool isRecording);

    /// <summary>
    /// Gets or sets whether the menu bar icon is visible.
    /// Matches macOS "show_menu_bar_icon" AppStorage setting.
    /// </summary>
    bool ShowMenuBarIcon { get; set; }

    /// <summary>
    /// Shows a brief checkmark flash in the system tray icon.
    /// Matches macOS VocabularyNotificationManager.shared.flashCheckmark() behavior.
    /// Used when a vocabulary word is successfully added.
    /// </summary>
    void FlashCheckmark();

    /// <summary>
    /// Gets whether this is a dev build.
    /// Matches macOS AppBuild.isDevBundle property.
    /// When true, displays a stamped dev icon for idle state.
    /// </summary>
    bool IsDevBuild { get; }

    /// <summary>
    /// Adds a transcript to the history for the History submenu.
    /// Matches macOS pipelineHistory behavior.
    /// </summary>
    /// <param name="transcript">The post-processed transcript text.</param>
    /// <param name="rawTranscript">Optional raw transcript before post-processing.</param>
    void AddToHistory(string transcript, string? rawTranscript = null);

    /// <summary>
    /// Sets dependencies for extended menu functionality (history, shortcuts, microphone).
    /// Call this after construction to enable full macOS-matching menu.
    /// </summary>
    /// <param name="settingsManager">Settings manager for shortcut/microphone changes.</param>
    /// <param name="audioRecorder">Audio recorder for microphone enumeration.</param>
    /// <param name="clipboardManager">Clipboard manager for paste operations.</param>
    void SetDependencies(ISettingsManager? settingsManager, IAudioRecorder? audioRecorder, IClipboardManager? clipboardManager);
}
