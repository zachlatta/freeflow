using System.Collections.ObjectModel;
using System.Net.Http;
using System.Net.Http.Headers;
using System.Windows.Input;
using FreeFlowWindows.Core.Interfaces;
using FreeFlowWindows.Core.Models;

namespace FreeFlowWindows.App.ViewModels;

/// <summary>
/// ViewModel for the Settings Window.
/// Binds to AppSettings and ISettingsManager for configuration management.
/// </summary>
public class SettingsViewModel : ViewModelBase, IDisposable
{
    private readonly ISettingsManager _settingsManager;
    private readonly ICredentialStore _credentialStore;
    private readonly IAudioRecorder? _audioRecorder;
    private readonly Func<HttpClient>? _httpClientFactory;

    private AppSettings _originalSettings;
    private bool _hasUnsavedChanges;
    private string? _validationError;
    private bool _isValidatingApiKey;
    private ApiKeyValidationStatus _apiKeyValidationStatus = ApiKeyValidationStatus.Unknown;
    private CancellationTokenSource? _validationCts;
    private CancellationTokenSource? _autoSaveCts;
    private bool _disposed;
    private bool _isLoadingSettings; // Prevents auto-save during initial load

    // Constants for credential store account names
    private const string ApiKeyAccountName = "api_key";

    // Known API key prefixes for different providers
    private static readonly Dictionary<string, ApiKeyPattern> KnownApiKeyPatterns = new()
    {
        { "sk-", new ApiKeyPattern("sk-", "OpenAI", 20, 200) },
        { "sk-proj-", new ApiKeyPattern("sk-proj-", "OpenAI (Project)", 20, 200) },
        { "gsk_", new ApiKeyPattern("gsk_", "Groq", 40, 100) },
        { "xai-", new ApiKeyPattern("xai-", "xAI/Grok", 20, 100) },
        { "ant-", new ApiKeyPattern("ant-", "Anthropic", 20, 200) },
        { "hf_", new ApiKeyPattern("hf_", "Hugging Face", 20, 100) },
        { "AIza", new ApiKeyPattern("AIza", "Google AI", 30, 50) },
    };

    #region Properties

    // API Settings
    private string _apiKey = string.Empty;
    public string ApiKey
    {
        get => _apiKey;
        set
        {
            if (SetProperty(ref _apiKey, value))
            {
                MarkChanged();
                ValidateApiKey();
            }
        }
    }

    /// <summary>
    /// Gets or sets whether an async API key validation is in progress.
    /// </summary>
    public bool IsValidatingApiKey
    {
        get => _isValidatingApiKey;
        private set => SetProperty(ref _isValidatingApiKey, value);
    }

    /// <summary>
    /// Gets or sets the current API key validation status.
    /// </summary>
    public ApiKeyValidationStatus ApiKeyValidationStatus
    {
        get => _apiKeyValidationStatus;
        private set
        {
            if (SetProperty(ref _apiKeyValidationStatus, value))
            {
                OnPropertyChanged(nameof(ApiKeyStatusMessage));
                OnPropertyChanged(nameof(ApiKeyStatusColor));
            }
        }
    }

    /// <summary>
    /// Gets a user-friendly status message for the API key validation state.
    /// </summary>
    public string ApiKeyStatusMessage => ApiKeyValidationStatus switch
    {
        ApiKeyValidationStatus.Unknown => "",
        ApiKeyValidationStatus.Validating => "Validating API key...",
        ApiKeyValidationStatus.Valid => "API key validated successfully",
        ApiKeyValidationStatus.InvalidFormat => ValidationError ?? "Invalid API key format",
        ApiKeyValidationStatus.InvalidCredentials => "Invalid API key - authentication failed",
        ApiKeyValidationStatus.RateLimited => "Rate limited - key may be valid, try again later",
        ApiKeyValidationStatus.NetworkError => "Network error - could not validate key",
        ApiKeyValidationStatus.ServerError => "Server error - could not validate key",
        _ => ""
    };

    /// <summary>
    /// Gets the color to use for the API key status indicator.
    /// Returns: "Green" for valid, "Red" for errors, "Orange" for warnings, "" for neutral.
    /// </summary>
    public string ApiKeyStatusColor => ApiKeyValidationStatus switch
    {
        ApiKeyValidationStatus.Valid => "Green",
        ApiKeyValidationStatus.InvalidFormat or ApiKeyValidationStatus.InvalidCredentials => "Red",
        ApiKeyValidationStatus.RateLimited => "Orange",
        ApiKeyValidationStatus.NetworkError or ApiKeyValidationStatus.ServerError => "Orange",
        ApiKeyValidationStatus.Validating => "Blue",
        _ => ""
    };

    private string _apiBaseUrl = string.Empty;
    public string ApiBaseUrl
    {
        get => _apiBaseUrl;
        set
        {
            if (SetProperty(ref _apiBaseUrl, value))
                MarkChanged();
        }
    }

    private string? _transcriptionApiUrl;
    public string? TranscriptionApiUrl
    {
        get => _transcriptionApiUrl;
        set
        {
            if (SetProperty(ref _transcriptionApiUrl, value))
                MarkChanged();
        }
    }

    // Model Settings
    private string _transcriptionModel = string.Empty;
    public string TranscriptionModel
    {
        get => _transcriptionModel;
        set
        {
            if (SetProperty(ref _transcriptionModel, value))
                MarkChanged();
        }
    }

    private string _postProcessingModel = string.Empty;
    public string PostProcessingModel
    {
        get => _postProcessingModel;
        set
        {
            if (SetProperty(ref _postProcessingModel, value))
                MarkChanged();
        }
    }

    private string _postProcessingFallbackModel = string.Empty;
    public string PostProcessingFallbackModel
    {
        get => _postProcessingFallbackModel;
        set
        {
            if (SetProperty(ref _postProcessingFallbackModel, value))
                MarkChanged();
        }
    }

    // Audio Settings
    private string? _selectedMicrophoneId;
    public string? SelectedMicrophoneId
    {
        get => _selectedMicrophoneId;
        set
        {
            if (SetProperty(ref _selectedMicrophoneId, value))
                MarkChanged();
        }
    }

    public ObservableCollection<AudioDevice> AvailableDevices { get; } = new();

    // Hotkey Settings
    private HotkeyBinding _holdHotkey = new();
    public HotkeyBinding HoldHotkey
    {
        get => _holdHotkey;
        set
        {
            if (SetProperty(ref _holdHotkey, value))
                MarkChanged();
        }
    }

    private string _holdHotkeyDisplay = string.Empty;
    public string HoldHotkeyDisplay
    {
        get => _holdHotkeyDisplay;
        set => SetProperty(ref _holdHotkeyDisplay, value);
    }

    private HotkeyBinding _toggleHotkey = new();
    public HotkeyBinding ToggleHotkey
    {
        get => _toggleHotkey;
        set
        {
            if (SetProperty(ref _toggleHotkey, value))
                MarkChanged();
        }
    }

    private string _toggleHotkeyDisplay = string.Empty;
    public string ToggleHotkeyDisplay
    {
        get => _toggleHotkeyDisplay;
        set => SetProperty(ref _toggleHotkeyDisplay, value);
    }

    // Post-processing Settings
    private PostProcessingMode _postProcessingMode = PostProcessingMode.Cleanup;
    public PostProcessingMode PostProcessingMode
    {
        get => _postProcessingMode;
        set
        {
            if (SetProperty(ref _postProcessingMode, value))
                MarkChanged();
        }
    }

    private string _customVocabulary = string.Empty;
    public string CustomVocabulary
    {
        get => _customVocabulary;
        set
        {
            if (SetProperty(ref _customVocabulary, value))
                MarkChanged();
        }
    }

    // Application Settings
    private bool _preserveClipboard = true;
    public bool PreserveClipboard
    {
        get => _preserveClipboard;
        set
        {
            if (SetProperty(ref _preserveClipboard, value))
                MarkChanged();
        }
    }

    private bool _startWithWindows;
    public bool StartWithWindows
    {
        get => _startWithWindows;
        set
        {
            if (SetProperty(ref _startWithWindows, value))
                MarkChanged();
        }
    }

    private bool _showTrayIcon = true;
    public bool ShowTrayIcon
    {
        get => _showTrayIcon;
        set
        {
            if (SetProperty(ref _showTrayIcon, value))
                MarkChanged();
        }
    }

    private bool _autoCheckUpdates = true;
    public bool AutoCheckUpdates
    {
        get => _autoCheckUpdates;
        set
        {
            if (SetProperty(ref _autoCheckUpdates, value))
                MarkChanged();
        }
    }

    private bool _muteAudioDuringDictation;
    public bool MuteAudioDuringDictation
    {
        get => _muteAudioDuringDictation;
        set
        {
            if (SetProperty(ref _muteAudioDuringDictation, value))
                MarkChanged();
        }
    }

    private bool _useCompactOverlay = true;
    public bool UseCompactOverlay
    {
        get => _useCompactOverlay;
        set
        {
            if (SetProperty(ref _useCompactOverlay, value))
                MarkChanged();
        }
    }

    private bool _enableEditMode;
    public bool EnableEditMode
    {
        get => _enableEditMode;
        set
        {
            if (SetProperty(ref _enableEditMode, value))
                MarkChanged();
        }
    }

    private bool _editModeAutomatic = true;
    public bool EditModeAutomatic
    {
        get => _editModeAutomatic;
        set
        {
            if (SetProperty(ref _editModeAutomatic, value))
                MarkChanged();
        }
    }

    private bool _preserveExactWording;
    public bool PreserveExactWording
    {
        get => _preserveExactWording;
        set
        {
            if (SetProperty(ref _preserveExactWording, value))
                MarkChanged();
        }
    }

    private bool _keepInClipboardHistory;
    public bool KeepInClipboardHistory
    {
        get => _keepInClipboardHistory;
        set
        {
            if (SetProperty(ref _keepInClipboardHistory, value))
                MarkChanged();
        }
    }

    private bool _pressEnterAfterPaste;
    public bool PressEnterAfterPaste
    {
        get => _pressEnterAfterPaste;
        set
        {
            if (SetProperty(ref _pressEnterAfterPaste, value))
                MarkChanged();
        }
    }

    private bool _playAlertSounds = true;
    public bool PlayAlertSounds
    {
        get => _playAlertSounds;
        set
        {
            if (SetProperty(ref _playAlertSounds, value))
                MarkChanged();
        }
    }

    private double _soundVolume = 100;
    public double SoundVolume
    {
        get => _soundVolume;
        set
        {
            if (SetProperty(ref _soundVolume, value))
                MarkChanged();
        }
    }

    private int _shortcutStartDelay;
    public int ShortcutStartDelay
    {
        get => _shortcutStartDelay;
        set
        {
            if (SetProperty(ref _shortcutStartDelay, value))
                MarkChanged();
        }
    }

    private string _outputLanguage = "Same as spoken";
    public string OutputLanguage
    {
        get => _outputLanguage;
        set
        {
            if (SetProperty(ref _outputLanguage, value))
                MarkChanged();
        }
    }

    // Timeout Settings
    private int _transcriptionTimeoutSeconds = 20;
    public int TranscriptionTimeoutSeconds
    {
        get => _transcriptionTimeoutSeconds;
        set
        {
            if (SetProperty(ref _transcriptionTimeoutSeconds, value))
                MarkChanged();
        }
    }

    private int _postProcessingTimeoutSeconds = 20;
    public int PostProcessingTimeoutSeconds
    {
        get => _postProcessingTimeoutSeconds;
        set
        {
            if (SetProperty(ref _postProcessingTimeoutSeconds, value))
                MarkChanged();
        }
    }

    // UI State
    public bool HasUnsavedChanges
    {
        get => _hasUnsavedChanges;
        private set => SetProperty(ref _hasUnsavedChanges, value);
    }

    public string? ValidationError
    {
        get => _validationError;
        private set => SetProperty(ref _validationError, value);
    }

    public bool HasValidationError => !string.IsNullOrEmpty(ValidationError);

    // Available post-processing modes for the dropdown
    public IReadOnlyList<PostProcessingModeItem> PostProcessingModes { get; } = new List<PostProcessingModeItem>
    {
        new(PostProcessingMode.None, "None", "No post-processing, use raw transcript"),
        new(PostProcessingMode.Cleanup, "Cleanup", "Remove filler words and fix punctuation"),
        new(PostProcessingMode.Proofread, "Proofread", "Full proofreading with grammar corrections"),
        new(PostProcessingMode.Custom, "Custom", "Use custom system prompt")
    };

    #endregion

    #region Commands

    public ICommand SaveCommand { get; }
    public ICommand CancelCommand { get; }
    public ICommand ResetCommand { get; }
    public ICommand RefreshDevicesCommand { get; }
    public ICommand RecordHoldHotkeyCommand { get; }
    public ICommand RecordToggleHotkeyCommand { get; }
    public ICommand ValidateApiKeyCommand { get; }

    #endregion

    /// <summary>
    /// Event raised when the window should be closed.
    /// </summary>
    public event EventHandler<bool>? RequestClose;

    /// <summary>
    /// Event raised when the user wants to record a hotkey.
    /// </summary>
    public event EventHandler<HotkeyRecordingEventArgs>? RequestHotkeyRecording;

    /// <summary>
    /// Creates a new SettingsViewModel.
    /// </summary>
    /// <param name="settingsManager">The settings manager for persisting settings.</param>
    /// <param name="credentialStore">The credential store for API keys.</param>
    /// <param name="audioRecorder">Optional audio recorder for device enumeration.</param>
    /// <param name="httpClientFactory">Optional factory for creating HTTP clients for API validation.</param>
    public SettingsViewModel(
        ISettingsManager settingsManager,
        ICredentialStore credentialStore,
        IAudioRecorder? audioRecorder = null,
        Func<HttpClient>? httpClientFactory = null)
    {
        _settingsManager = settingsManager ?? throw new ArgumentNullException(nameof(settingsManager));
        _credentialStore = credentialStore ?? throw new ArgumentNullException(nameof(credentialStore));
        _audioRecorder = audioRecorder;
        _httpClientFactory = httpClientFactory;

        // Initialize commands
        SaveCommand = new RelayCommand(Save, CanSave);
        CancelCommand = new RelayCommand(Cancel);
        ResetCommand = new RelayCommand(Reset);
        RefreshDevicesCommand = new RelayCommand(RefreshDevices);
        RecordHoldHotkeyCommand = new RelayCommand(StartRecordHoldHotkey);
        RecordToggleHotkeyCommand = new RelayCommand(StartRecordToggleHotkey);
        ValidateApiKeyCommand = new RelayCommand(async () => await ValidateApiKeyWithApiAsync(), CanValidateApiKey);

        // Load settings
        _originalSettings = _settingsManager.Load();
        LoadFromSettings(_originalSettings);
        LoadApiKey();
        RefreshDevices();

        HasUnsavedChanges = false;
    }

    /// <summary>
    /// Creates a SettingsViewModel for design-time use.
    /// </summary>
    internal SettingsViewModel()
    {
        _settingsManager = null!;
        _credentialStore = null!;
        _originalSettings = new AppSettings();

        // Initialize commands with no-op handlers for design-time
        SaveCommand = new RelayCommand(() => { });
        CancelCommand = new RelayCommand(() => { });
        ResetCommand = new RelayCommand(() => { });
        RefreshDevicesCommand = new RelayCommand(() => { });
        RecordHoldHotkeyCommand = new RelayCommand(() => { });
        RecordToggleHotkeyCommand = new RelayCommand(() => { });
        ValidateApiKeyCommand = new RelayCommand(() => { });

        // Set some design-time data
        ApiBaseUrl = "https://api.groq.com/openai/v1";
        TranscriptionModel = "whisper-large-v3";
        PostProcessingModel = "openai/gpt-oss-20b";
        HoldHotkeyDisplay = "Ctrl+Shift+Space";
        ToggleHotkeyDisplay = "Ctrl+Alt+Space";

        AvailableDevices.Add(new AudioDevice("0", "Default Microphone", true));
        AvailableDevices.Add(new AudioDevice("1", "USB Microphone", false));
    }

    #region Private Methods

    private void LoadFromSettings(AppSettings settings)
    {
        _isLoadingSettings = true; // Prevent auto-save during load
        try
        {
            ApiBaseUrl = settings.ApiBaseUrl;
            TranscriptionApiUrl = settings.TranscriptionApiUrl;
            TranscriptionModel = settings.TranscriptionModel;
            PostProcessingModel = settings.PostProcessingModel;
            PostProcessingFallbackModel = settings.PostProcessingFallbackModel;
            SelectedMicrophoneId = settings.SelectedMicrophoneId;
            CustomVocabulary = settings.CustomVocabulary;
            PreserveClipboard = settings.PreserveClipboard;
            StartWithWindows = settings.StartWithWindows;
            TranscriptionTimeoutSeconds = settings.TranscriptionTimeoutSeconds;
            PostProcessingTimeoutSeconds = settings.PostProcessingTimeoutSeconds;

            // New settings properties
            ShowTrayIcon = settings.ShowTrayIcon;
            AutoCheckUpdates = settings.AutoCheckUpdates;
            MuteAudioDuringDictation = settings.MuteAudioDuringDictation;
            UseCompactOverlay = settings.UseCompactOverlay;
            EnableEditMode = settings.EnableEditMode;
            EditModeAutomatic = settings.EditModeAutomatic;
            PreserveExactWording = settings.PreserveExactWording;
            KeepInClipboardHistory = settings.KeepInClipboardHistory;
            PressEnterAfterPaste = settings.PressEnterAfterPaste;
            PlayAlertSounds = settings.PlayAlertSounds;
            SoundVolume = settings.SoundVolume;
            ShortcutStartDelay = settings.ShortcutStartDelay;
            OutputLanguage = settings.OutputLanguage;

            HoldHotkey = settings.HoldHotkey.Clone();
            HoldHotkeyDisplay = HoldHotkey.ToString();

            ToggleHotkey = settings.ToggleHotkey.Clone();
            ToggleHotkeyDisplay = ToggleHotkey.ToString();
        }
        finally
        {
            _isLoadingSettings = false;
        }
    }

    private void LoadApiKey()
    {
        var apiKey = _credentialStore.GetApiKey(ApiKeyAccountName);
        _apiKey = apiKey ?? string.Empty;
        OnPropertyChanged(nameof(ApiKey));
        ValidateApiKey();
    }

    private AppSettings CreateSettingsFromViewModel()
    {
        return new AppSettings
        {
            ApiBaseUrl = ApiBaseUrl,
            TranscriptionApiUrl = string.IsNullOrWhiteSpace(TranscriptionApiUrl) ? null : TranscriptionApiUrl,
            TranscriptionModel = TranscriptionModel,
            PostProcessingModel = PostProcessingModel,
            PostProcessingFallbackModel = PostProcessingFallbackModel,
            SelectedMicrophoneId = SelectedMicrophoneId,
            CustomVocabulary = CustomVocabulary,
            PreserveClipboard = PreserveClipboard,
            StartWithWindows = StartWithWindows,
            TranscriptionTimeoutSeconds = TranscriptionTimeoutSeconds,
            PostProcessingTimeoutSeconds = PostProcessingTimeoutSeconds,
            HoldHotkey = HoldHotkey.Clone(),
            ToggleHotkey = ToggleHotkey.Clone(),
            // New settings properties
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

    private void ValidateApiKey()
    {
        // Reset validation status when key changes
        ApiKeyValidationStatus = ApiKeyValidationStatus.Unknown;

        // Basic validation: API key should not be empty for the app to work
        if (string.IsNullOrWhiteSpace(ApiKey))
        {
            ValidationError = "API key is required";
            ApiKeyValidationStatus = ApiKeyValidationStatus.InvalidFormat;
            OnPropertyChanged(nameof(HasValidationError));
            return;
        }

        if (ApiKey.Length < 10)
        {
            ValidationError = "API key appears too short";
            ApiKeyValidationStatus = ApiKeyValidationStatus.InvalidFormat;
            OnPropertyChanged(nameof(HasValidationError));
            return;
        }

        // Check for provider-specific prefix patterns
        var validationResult = ValidateApiKeyFormat(ApiKey);
        if (!validationResult.IsValid)
        {
            ValidationError = validationResult.ErrorMessage;
            ApiKeyValidationStatus = ApiKeyValidationStatus.InvalidFormat;
            OnPropertyChanged(nameof(HasValidationError));
            return;
        }

        // Format is valid
        ValidationError = null;
        OnPropertyChanged(nameof(HasValidationError));
    }

    /// <summary>
    /// Validates API key format based on known provider patterns.
    /// </summary>
    /// <param name="apiKey">The API key to validate.</param>
    /// <returns>Validation result with IsValid flag and optional error message.</returns>
    internal static ApiKeyFormatValidationResult ValidateApiKeyFormat(string apiKey)
    {
        if (string.IsNullOrWhiteSpace(apiKey))
        {
            return new ApiKeyFormatValidationResult(false, "API key is required");
        }

        if (apiKey.Length < 10)
        {
            return new ApiKeyFormatValidationResult(false, "API key appears too short");
        }

        // Try to match against known patterns
        foreach (var (prefix, pattern) in KnownApiKeyPatterns)
        {
            if (apiKey.StartsWith(prefix, StringComparison.Ordinal))
            {
                // Validate length for this provider
                if (apiKey.Length < pattern.MinLength)
                {
                    return new ApiKeyFormatValidationResult(
                        false,
                        $"{pattern.ProviderName} API key appears too short (expected at least {pattern.MinLength} characters)");
                }

                if (apiKey.Length > pattern.MaxLength)
                {
                    return new ApiKeyFormatValidationResult(
                        false,
                        $"{pattern.ProviderName} API key appears too long (expected at most {pattern.MaxLength} characters)");
                }

                // Validate characters (should be alphanumeric with some special chars)
                if (!IsValidApiKeyCharacters(apiKey))
                {
                    return new ApiKeyFormatValidationResult(
                        false,
                        $"{pattern.ProviderName} API key contains invalid characters");
                }

                return new ApiKeyFormatValidationResult(true, null, pattern.ProviderName);
            }
        }

        // Unknown prefix - allow it but warn if it contains suspicious characters
        if (!IsValidApiKeyCharacters(apiKey))
        {
            return new ApiKeyFormatValidationResult(false, "API key contains invalid characters");
        }

        // Unknown format but appears valid
        return new ApiKeyFormatValidationResult(true, null);
    }

    /// <summary>
    /// Checks if the API key contains only valid characters.
    /// Valid characters are: alphanumeric, hyphen, underscore.
    /// </summary>
    private static bool IsValidApiKeyCharacters(string apiKey)
    {
        foreach (char c in apiKey)
        {
            if (!char.IsLetterOrDigit(c) && c != '-' && c != '_')
            {
                return false;
            }
        }
        return true;
    }

    /// <summary>
    /// Determines if async API validation can be performed.
    /// </summary>
    private bool CanValidateApiKey()
    {
        return !IsValidatingApiKey &&
               !string.IsNullOrWhiteSpace(ApiKey) &&
               !string.IsNullOrWhiteSpace(ApiBaseUrl) &&
               !HasValidationError;
    }

    /// <summary>
    /// Validates the API key by making a lightweight API call.
    /// This is non-blocking and updates the validation status asynchronously.
    /// </summary>
    public async Task ValidateApiKeyWithApiAsync()
    {
        if (!CanValidateApiKey())
            return;

        // Cancel any previous validation
        _validationCts?.Cancel();
        _validationCts = new CancellationTokenSource();
        var cancellationToken = _validationCts.Token;

        IsValidatingApiKey = true;
        ApiKeyValidationStatus = ApiKeyValidationStatus.Validating;

        try
        {
            var result = await PerformApiKeyValidationAsync(ApiKey, ApiBaseUrl, cancellationToken);
            
            if (!cancellationToken.IsCancellationRequested)
            {
                ApiKeyValidationStatus = result;
                
                // Update validation error based on result
                if (result == ApiKeyValidationStatus.InvalidCredentials)
                {
                    ValidationError = "API key authentication failed";
                    OnPropertyChanged(nameof(HasValidationError));
                }
            }
        }
        catch (OperationCanceledException)
        {
            // Validation was cancelled, don't update status
        }
        catch (Exception)
        {
            if (!cancellationToken.IsCancellationRequested)
            {
                ApiKeyValidationStatus = ApiKeyValidationStatus.NetworkError;
            }
        }
        finally
        {
            if (!cancellationToken.IsCancellationRequested)
            {
                IsValidatingApiKey = false;
            }
        }
    }

    /// <summary>
    /// Performs the actual API key validation by making a lightweight API call.
    /// Uses the /models endpoint which is typically available on OpenAI-compatible APIs.
    /// </summary>
    private async Task<ApiKeyValidationStatus> PerformApiKeyValidationAsync(
        string apiKey,
        string baseUrl,
        CancellationToken cancellationToken)
    {
        // Create HTTP client
        HttpClient httpClient;
        if (_httpClientFactory != null)
        {
            httpClient = _httpClientFactory();
        }
        else
        {
            httpClient = new HttpClient { Timeout = TimeSpan.FromSeconds(10) };
        }

        try
        {
            // Normalize the base URL
            var normalizedBaseUrl = baseUrl.TrimEnd('/');
            
            // Use the /models endpoint for validation - it's lightweight and available on most providers
            var modelsUrl = $"{normalizedBaseUrl}/models";

            using var request = new HttpRequestMessage(HttpMethod.Get, modelsUrl);
            request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", apiKey);
            request.Headers.Accept.Add(new System.Net.Http.Headers.MediaTypeWithQualityHeaderValue("application/json"));

            using var response = await httpClient.SendAsync(request, cancellationToken);

            return response.StatusCode switch
            {
                System.Net.HttpStatusCode.OK => ApiKeyValidationStatus.Valid,
                System.Net.HttpStatusCode.Unauthorized => ApiKeyValidationStatus.InvalidCredentials,
                System.Net.HttpStatusCode.Forbidden => ApiKeyValidationStatus.InvalidCredentials,
                System.Net.HttpStatusCode.TooManyRequests => ApiKeyValidationStatus.RateLimited,
                System.Net.HttpStatusCode.NotFound => 
                    // /models endpoint doesn't exist - try alternate validation or assume valid format
                    ApiKeyValidationStatus.Valid, // If we got this far without auth error, key format is likely valid
                >= System.Net.HttpStatusCode.InternalServerError => ApiKeyValidationStatus.ServerError,
                _ => ApiKeyValidationStatus.NetworkError
            };
        }
        catch (TaskCanceledException) when (!cancellationToken.IsCancellationRequested)
        {
            // Timeout
            return ApiKeyValidationStatus.NetworkError;
        }
        catch (HttpRequestException)
        {
            return ApiKeyValidationStatus.NetworkError;
        }
        finally
        {
            // Only dispose if we created the client
            if (_httpClientFactory == null)
            {
                httpClient.Dispose();
            }
        }
    }

    private bool CanSave()
    {
        // Allow saving even if API key has validation warnings
        // The save will proceed with whatever API key is entered (or empty)
        return HasUnsavedChanges;
    }

    private void Save()
    {
        if (!CanSave())
            return;

        // Save settings (including hotkeys, regardless of API key validation state)
        var settings = CreateSettingsFromViewModel();
        
        // Debug logging
        var logPath = System.IO.Path.Combine(System.IO.Path.GetTempPath(), "freeflow_debug.log");
        System.IO.File.AppendAllText(logPath, $"\n[{DateTime.Now:HH:mm:ss}] SettingsViewModel.Save() called\n");
        System.IO.File.AppendAllText(logPath, $"  Saving HoldHotkey: {settings.HoldHotkey}\n");
        System.IO.File.AppendAllText(logPath, $"  Saving ToggleHotkey: {settings.ToggleHotkey}\n");
        
        _settingsManager.Save(settings);
        System.IO.File.AppendAllText(logPath, $"  Settings saved to disk\n");

        // Save API key to credential store (even if validation showed warnings)
        if (!string.IsNullOrWhiteSpace(ApiKey))
        {
            _credentialStore.SetApiKey(ApiKeyAccountName, ApiKey);
        }
        else
        {
            _credentialStore.DeleteApiKey(ApiKeyAccountName);
        }

        _originalSettings = settings;
        HasUnsavedChanges = false;

        RequestClose?.Invoke(this, true);
    }

    private void Cancel()
    {
        // Revert to original settings
        LoadFromSettings(_originalSettings);
        LoadApiKey();
        HasUnsavedChanges = false;

        RequestClose?.Invoke(this, false);
    }

    private void Reset()
    {
        // Reset to default values
        _settingsManager.Reset();
        _originalSettings = _settingsManager.Load();
        LoadFromSettings(_originalSettings);

        // Clear API key
        _apiKey = string.Empty;
        OnPropertyChanged(nameof(ApiKey));

        HasUnsavedChanges = true;
    }

    private void RefreshDevices()
    {
        AvailableDevices.Clear();

        // Add a "Default" option
        AvailableDevices.Add(new AudioDevice(string.Empty, "(System Default)", true));

        if (_audioRecorder != null)
        {
            try
            {
                var devices = _audioRecorder.GetAvailableDevices();
                foreach (var device in devices)
                {
                    AvailableDevices.Add(device);
                }
            }
            catch (Exception)
            {
                // If enumeration fails, just show the default option
            }
        }
    }

    private void StartRecordHoldHotkey()
    {
        RequestHotkeyRecording?.Invoke(this, new HotkeyRecordingEventArgs(HotkeyType.Hold));
    }

    private void StartRecordToggleHotkey()
    {
        RequestHotkeyRecording?.Invoke(this, new HotkeyRecordingEventArgs(HotkeyType.Toggle));
    }

    /// <summary>
    /// Called when a hotkey has been recorded.
    /// Immediately saves and applies the hotkey change (matching macOS auto-save behavior).
    /// </summary>
    public void SetRecordedHotkey(HotkeyType type, HotkeyBinding binding)
    {
        var logPath = System.IO.Path.Combine(System.IO.Path.GetTempPath(), "freeflow_debug.log");
        System.IO.File.AppendAllText(logPath, $"\n[{DateTime.Now:HH:mm:ss}] SetRecordedHotkey called\n");
        System.IO.File.AppendAllText(logPath, $"  Type: {type}, Binding: {binding}\n");
        
        // Cancel any pending auto-save since we're going to save immediately
        _autoSaveCts?.Cancel();
        _autoSaveCts = null;
        
        // Set property using backing field to avoid triggering debounced auto-save
        switch (type)
        {
            case HotkeyType.Hold:
                SetProperty(ref _holdHotkey, binding, nameof(HoldHotkey));
                HoldHotkeyDisplay = binding.ToString();
                break;
            case HotkeyType.Toggle:
                SetProperty(ref _toggleHotkey, binding, nameof(ToggleHotkey));
                ToggleHotkeyDisplay = binding.ToString();
                break;
        }

        // Auto-save and apply immediately (matching macOS behavior - no debounce for hotkeys)
        AutoSaveAndApplySettings();
    }

    /// <summary>
    /// Event raised when settings have been saved and should be applied immediately.
    /// </summary>
    public event EventHandler? SettingsApplied;

    /// <summary>
    /// Marks that a setting has changed and schedules an auto-save with debouncing.
    /// This matches macOS behavior where settings are auto-saved immediately.
    /// </summary>
    private void MarkChanged()
    {
        if (_isLoadingSettings) return; // Don't trigger during initial load
        
        HasUnsavedChanges = true;
        ScheduleAutoSave();
    }

    /// <summary>
    /// Schedules an auto-save with a 300ms debounce delay.
    /// Multiple rapid changes will be batched into a single save.
    /// </summary>
    private void ScheduleAutoSave()
    {
        var logPath = System.IO.Path.Combine(System.IO.Path.GetTempPath(), "freeflow_debug.log");
        System.IO.File.AppendAllText(logPath, $"\n[{DateTime.Now:HH:mm:ss}] ScheduleAutoSave called - will save in 300ms\n");
        
        // Cancel any pending auto-save
        _autoSaveCts?.Cancel();
        _autoSaveCts = new CancellationTokenSource();
        var token = _autoSaveCts.Token;

        // Schedule auto-save after 300ms delay (allows batching rapid changes)
        Task.Run(async () =>
        {
            try
            {
                await Task.Delay(300, token);
                if (!token.IsCancellationRequested)
                {
                    System.IO.File.AppendAllText(logPath, $"[{DateTime.Now:HH:mm:ss}] Debounce complete, executing auto-save\n");
                    // Must invoke on UI thread
                    System.Windows.Application.Current?.Dispatcher?.Invoke(() =>
                    {
                        if (!token.IsCancellationRequested)
                        {
                            AutoSaveAndApplySettings();
                        }
                    });
                }
            }
            catch (OperationCanceledException)
            {
                // Auto-save was cancelled by another change - that's fine
            }
        }, token);
    }

    /// <summary>
    /// Immediately saves current settings to disk and notifies listeners to apply them.
    /// Used for auto-save when settings are changed.
    /// </summary>
    private void AutoSaveAndApplySettings()
    {
        var logPath = System.IO.Path.Combine(System.IO.Path.GetTempPath(), "freeflow_debug.log");
        
        try
        {
            var settings = CreateSettingsFromViewModel();
            System.IO.File.AppendAllText(logPath, $"  AutoSaving HoldHotkey: {settings.HoldHotkey}\n");
            System.IO.File.AppendAllText(logPath, $"  AutoSaving ToggleHotkey: {settings.ToggleHotkey}\n");
            
            _settingsManager.Save(settings);
            System.IO.File.AppendAllText(logPath, $"  AutoSave complete\n");
            
            // Update original settings so HasUnsavedChanges becomes false
            _originalSettings = settings;
            HasUnsavedChanges = false;
            
            // Notify listeners to apply settings immediately (e.g., re-register hotkeys)
            System.IO.File.AppendAllText(logPath, $"  Raising SettingsApplied event\n");
            SettingsApplied?.Invoke(this, EventArgs.Empty);
        }
        catch (Exception ex)
        {
            System.IO.File.AppendAllText(logPath, $"  AutoSave failed: {ex.Message}\n");
            // Don't throw - auto-save failure shouldn't break the UI
        }
    }

    /// <summary>
    /// Disposes resources.
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
            // Cancel any in-progress validation and dispose the CTS
            _validationCts?.Cancel();
            _validationCts?.Dispose();
            _validationCts = null;
            
            // Cancel any pending auto-save and dispose the CTS
            _autoSaveCts?.Cancel();
            _autoSaveCts?.Dispose();
            _autoSaveCts = null;
        }

        _disposed = true;
    }

    #endregion
}

/// <summary>
/// Represents a post-processing mode option for the dropdown.
/// </summary>
public class PostProcessingModeItem
{
    public PostProcessingMode Mode { get; }
    public string Name { get; }
    public string Description { get; }

    public PostProcessingModeItem(PostProcessingMode mode, string name, string description)
    {
        Mode = mode;
        Name = name;
        Description = description;
    }
}

/// <summary>
/// Post-processing mode options.
/// </summary>
public enum PostProcessingMode
{
    None,
    Cleanup,
    Proofread,
    Custom
}

/// <summary>
/// Type of hotkey being recorded.
/// </summary>
public enum HotkeyType
{
    Hold,
    Toggle
}

/// <summary>
/// Event args for hotkey recording requests.
/// </summary>
public class HotkeyRecordingEventArgs : EventArgs
{
    public HotkeyType HotkeyType { get; }

    public HotkeyRecordingEventArgs(HotkeyType type)
    {
        HotkeyType = type;
    }
}

/// <summary>
/// Status of API key validation.
/// </summary>
public enum ApiKeyValidationStatus
{
    /// <summary>
    /// Validation has not been performed.
    /// </summary>
    Unknown,

    /// <summary>
    /// Validation is in progress.
    /// </summary>
    Validating,

    /// <summary>
    /// API key is valid and working.
    /// </summary>
    Valid,

    /// <summary>
    /// API key format is invalid.
    /// </summary>
    InvalidFormat,

    /// <summary>
    /// API key failed authentication.
    /// </summary>
    InvalidCredentials,

    /// <summary>
    /// Rate limit hit during validation.
    /// </summary>
    RateLimited,

    /// <summary>
    /// Network error during validation.
    /// </summary>
    NetworkError,

    /// <summary>
    /// Server error during validation.
    /// </summary>
    ServerError
}

/// <summary>
/// Result of API key format validation.
/// </summary>
public class ApiKeyFormatValidationResult
{
    /// <summary>
    /// Whether the API key format is valid.
    /// </summary>
    public bool IsValid { get; }

    /// <summary>
    /// Error message if validation failed.
    /// </summary>
    public string? ErrorMessage { get; }

    /// <summary>
    /// Detected provider name if the key matches a known pattern.
    /// </summary>
    public string? DetectedProvider { get; }

    public ApiKeyFormatValidationResult(bool isValid, string? errorMessage, string? detectedProvider = null)
    {
        IsValid = isValid;
        ErrorMessage = errorMessage;
        DetectedProvider = detectedProvider;
    }
}

/// <summary>
/// Pattern for validating API keys from a specific provider.
/// </summary>
internal class ApiKeyPattern
{
    public string Prefix { get; }
    public string ProviderName { get; }
    public int MinLength { get; }
    public int MaxLength { get; }

    public ApiKeyPattern(string prefix, string providerName, int minLength, int maxLength)
    {
        Prefix = prefix;
        ProviderName = providerName;
        MinLength = minLength;
        MaxLength = maxLength;
    }
}
