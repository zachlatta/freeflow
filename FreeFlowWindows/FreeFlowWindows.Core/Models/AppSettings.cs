using System.Text.Json.Serialization;

namespace FreeFlowWindows.Core.Models;

/// <summary>
/// Application settings that are persisted to the configuration file.
/// </summary>
public class AppSettings : IEquatable<AppSettings>
{
    /// <summary>
    /// Base URL for the API (default: Groq's endpoint).
    /// </summary>
    [JsonPropertyName("apiBaseUrl")]
    public string ApiBaseUrl { get; set; } = "https://api.groq.com/openai/v1";

    /// <summary>
    /// Model to use for transcription.
    /// </summary>
    [JsonPropertyName("transcriptionModel")]
    public string TranscriptionModel { get; set; } = "whisper-large-v3";

    /// <summary>
    /// Optional separate API URL for transcription (for different providers).
    /// </summary>
    [JsonPropertyName("transcriptionApiUrl")]
    public string? TranscriptionApiUrl { get; set; }

    /// <summary>
    /// Model to use for post-processing cleanup.
    /// </summary>
    [JsonPropertyName("postProcessingModel")]
    public string PostProcessingModel { get; set; } = "openai/gpt-oss-20b";

    /// <summary>
    /// Fallback model when primary post-processing model fails.
    /// </summary>
    [JsonPropertyName("postProcessingFallbackModel")]
    public string PostProcessingFallbackModel { get; set; } = "qwen/qwen3.6-27b";

    /// <summary>
    /// Hotkey binding for hold-to-talk mode.
    /// </summary>
    [JsonPropertyName("holdHotkey")]
    public HotkeyBinding HoldHotkey { get; set; } = new() 
    { 
        Modifiers = ModifierKeys.Ctrl | ModifierKeys.Shift, 
        Key = VirtualKey.Space 
    };

    /// <summary>
    /// Hotkey binding for toggle mode.
    /// </summary>
    [JsonPropertyName("toggleHotkey")]
    public HotkeyBinding ToggleHotkey { get; set; } = new() 
    { 
        Modifiers = ModifierKeys.Ctrl | ModifierKeys.Alt, 
        Key = VirtualKey.Space 
    };

    /// <summary>
    /// Device ID of the selected microphone, or null for default.
    /// </summary>
    [JsonPropertyName("selectedMicrophoneId")]
    public string? SelectedMicrophoneId { get; set; }

    /// <summary>
    /// Custom vocabulary terms, one per line.
    /// </summary>
    [JsonPropertyName("customVocabulary")]
    public string CustomVocabulary { get; set; } = "";

    /// <summary>
    /// Whether to preserve clipboard contents after pasting.
    /// </summary>
    [JsonPropertyName("preserveClipboard")]
    public bool PreserveClipboard { get; set; } = true;

    /// <summary>
    /// Whether to start the application with Windows.
    /// </summary>
    [JsonPropertyName("startWithWindows")]
    public bool StartWithWindows { get; set; } = false;

    /// <summary>
    /// Timeout in seconds for transcription requests.
    /// </summary>
    [JsonPropertyName("transcriptionTimeoutSeconds")]
    public int TranscriptionTimeoutSeconds { get; set; } = 20;

    /// <summary>
    /// Timeout in seconds for post-processing requests.
    /// </summary>
    [JsonPropertyName("postProcessingTimeoutSeconds")]
    public int PostProcessingTimeoutSeconds { get; set; } = 20;

    /// <summary>
    /// Whether to show the system tray icon.
    /// </summary>
    [JsonPropertyName("showTrayIcon")]
    public bool ShowTrayIcon { get; set; } = true;

    /// <summary>
    /// Whether to automatically check for updates.
    /// </summary>
    [JsonPropertyName("autoCheckUpdates")]
    public bool AutoCheckUpdates { get; set; } = true;

    /// <summary>
    /// Whether to mute system audio during dictation.
    /// </summary>
    [JsonPropertyName("muteAudioDuringDictation")]
    public bool MuteAudioDuringDictation { get; set; } = false;

    /// <summary>
    /// Whether to use compact overlay mode.
    /// </summary>
    [JsonPropertyName("useCompactOverlay")]
    public bool UseCompactOverlay { get; set; } = true;

    /// <summary>
    /// Whether edit mode is enabled.
    /// </summary>
    [JsonPropertyName("enableEditMode")]
    public bool EnableEditMode { get; set; } = false;

    /// <summary>
    /// Whether edit mode should automatically activate.
    /// </summary>
    [JsonPropertyName("editModeAutomatic")]
    public bool EditModeAutomatic { get; set; } = true;

    /// <summary>
    /// Whether to preserve exact wording (no cleanup).
    /// </summary>
    [JsonPropertyName("preserveExactWording")]
    public bool PreserveExactWording { get; set; } = false;

    /// <summary>
    /// Whether to keep transcriptions in clipboard history.
    /// </summary>
    [JsonPropertyName("keepInClipboardHistory")]
    public bool KeepInClipboardHistory { get; set; } = false;

    /// <summary>
    /// Whether to press Enter after pasting.
    /// </summary>
    [JsonPropertyName("pressEnterAfterPaste")]
    public bool PressEnterAfterPaste { get; set; } = false;

    /// <summary>
    /// Whether to play alert sounds.
    /// </summary>
    [JsonPropertyName("playAlertSounds")]
    public bool PlayAlertSounds { get; set; } = true;

    /// <summary>
    /// Sound volume (0-100).
    /// </summary>
    [JsonPropertyName("soundVolume")]
    public double SoundVolume { get; set; } = 100;

    /// <summary>
    /// Delay before starting recording after shortcut press (milliseconds).
    /// </summary>
    [JsonPropertyName("shortcutStartDelay")]
    public int ShortcutStartDelay { get; set; } = 0;

    /// <summary>
    /// Output language for transcription.
    /// </summary>
    [JsonPropertyName("outputLanguage")]
    public string OutputLanguage { get; set; } = "Same as spoken";

    /// <summary>
    /// Creates a deep copy of the settings.
    /// </summary>
    public AppSettings Clone()
    {
        return new AppSettings
        {
            ApiBaseUrl = ApiBaseUrl,
            TranscriptionModel = TranscriptionModel,
            TranscriptionApiUrl = TranscriptionApiUrl,
            PostProcessingModel = PostProcessingModel,
            PostProcessingFallbackModel = PostProcessingFallbackModel,
            HoldHotkey = HoldHotkey.Clone(),
            ToggleHotkey = ToggleHotkey.Clone(),
            SelectedMicrophoneId = SelectedMicrophoneId,
            CustomVocabulary = CustomVocabulary,
            PreserveClipboard = PreserveClipboard,
            StartWithWindows = StartWithWindows,
            TranscriptionTimeoutSeconds = TranscriptionTimeoutSeconds,
            PostProcessingTimeoutSeconds = PostProcessingTimeoutSeconds,
            ShowTrayIcon = ShowTrayIcon,
            AutoCheckUpdates = AutoCheckUpdates,
            MuteAudioDuringDictation = MuteAudioDuringDictation,
            UseCompactOverlay = UseCompactOverlay,
            EnableEditMode = EnableEditMode,
            EditModeAutomatic = EditModeAutomatic,
            PreserveExactWording = PreserveExactWording,
            KeepInClipboardHistory = KeepInClipboardHistory,
            PressEnterAfterPaste = PressEnterAfterPaste,
            PlayAlertSounds = PlayAlertSounds,
            SoundVolume = SoundVolume,
            ShortcutStartDelay = ShortcutStartDelay,
            OutputLanguage = OutputLanguage
        };
    }

    public bool Equals(AppSettings? other)
    {
        if (other is null) return false;
        if (ReferenceEquals(this, other)) return true;

        return ApiBaseUrl == other.ApiBaseUrl &&
               TranscriptionModel == other.TranscriptionModel &&
               TranscriptionApiUrl == other.TranscriptionApiUrl &&
               PostProcessingModel == other.PostProcessingModel &&
               PostProcessingFallbackModel == other.PostProcessingFallbackModel &&
               HoldHotkey.Equals(other.HoldHotkey) &&
               ToggleHotkey.Equals(other.ToggleHotkey) &&
               SelectedMicrophoneId == other.SelectedMicrophoneId &&
               CustomVocabulary == other.CustomVocabulary &&
               PreserveClipboard == other.PreserveClipboard &&
               StartWithWindows == other.StartWithWindows &&
               TranscriptionTimeoutSeconds == other.TranscriptionTimeoutSeconds &&
               PostProcessingTimeoutSeconds == other.PostProcessingTimeoutSeconds &&
               ShowTrayIcon == other.ShowTrayIcon &&
               AutoCheckUpdates == other.AutoCheckUpdates &&
               MuteAudioDuringDictation == other.MuteAudioDuringDictation &&
               UseCompactOverlay == other.UseCompactOverlay &&
               EnableEditMode == other.EnableEditMode &&
               EditModeAutomatic == other.EditModeAutomatic &&
               PreserveExactWording == other.PreserveExactWording &&
               KeepInClipboardHistory == other.KeepInClipboardHistory &&
               PressEnterAfterPaste == other.PressEnterAfterPaste &&
               PlayAlertSounds == other.PlayAlertSounds &&
               Math.Abs(SoundVolume - other.SoundVolume) < 0.001 &&
               ShortcutStartDelay == other.ShortcutStartDelay &&
               OutputLanguage == other.OutputLanguage;
    }

    public override bool Equals(object? obj) => Equals(obj as AppSettings);

    public override int GetHashCode()
    {
        var hash = new HashCode();
        hash.Add(ApiBaseUrl);
        hash.Add(TranscriptionModel);
        hash.Add(TranscriptionApiUrl);
        hash.Add(PostProcessingModel);
        hash.Add(PostProcessingFallbackModel);
        hash.Add(HoldHotkey);
        hash.Add(ToggleHotkey);
        hash.Add(SelectedMicrophoneId);
        hash.Add(CustomVocabulary);
        hash.Add(PreserveClipboard);
        hash.Add(StartWithWindows);
        hash.Add(TranscriptionTimeoutSeconds);
        hash.Add(PostProcessingTimeoutSeconds);
        hash.Add(ShowTrayIcon);
        hash.Add(AutoCheckUpdates);
        hash.Add(MuteAudioDuringDictation);
        hash.Add(UseCompactOverlay);
        hash.Add(EnableEditMode);
        hash.Add(EditModeAutomatic);
        hash.Add(PreserveExactWording);
        hash.Add(KeepInClipboardHistory);
        hash.Add(PressEnterAfterPaste);
        hash.Add(PlayAlertSounds);
        hash.Add(SoundVolume);
        hash.Add(ShortcutStartDelay);
        hash.Add(OutputLanguage);
        return hash.ToHashCode();
    }
}
