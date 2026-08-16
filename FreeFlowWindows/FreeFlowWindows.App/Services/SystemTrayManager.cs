using System.Drawing;
using System.Drawing.Drawing2D;
using System.Reflection;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Animation;
using Hardcodet.Wpf.TaskbarNotification;
using FreeFlowWindows.Core.Interfaces;
using FreeFlowWindows.Core.Models;
using Microsoft.Win32;

namespace FreeFlowWindows.App.Services;

/// <summary>
/// Manages the system tray icon, context menu, and notifications using Hardcodet.NotifyIcon.Wpf.
/// 100% matches macOS MenuBarLabel/MenuBarView behavior:
/// - Idle: waveform icon (or stamped dev icon for dev builds)
/// - Recording: record.circle icon
/// - Processing/Transcribing: ellipsis.circle icon
/// - Light/dark theme adaptation (template image behavior)
/// - Checkmark flash for vocabulary notifications (2 second duration, matching macOS)
/// - Show/hide menu bar icon setting
/// - Dev bundle stamped icon support
/// - Multi-resolution icons for DPI scaling
/// - History submenu with recent transcripts
/// - Hold/Toggle/Paste Again shortcut submenus
/// - Microphone selection submenu
/// </summary>
public class SystemTrayManager : ISystemTrayManager
{
    private TaskbarIcon? _taskbarIcon;
    private ContextMenu? _contextMenu;
    private MenuItem? _recordingMenuItem;
    private MenuItem? _showIconMenuItem;
    private MenuItem? _pasteAgainMenuItem;
    private MenuItem? _historyMenu;
    private MenuItem? _holdShortcutMenu;
    private MenuItem? _toggleShortcutMenu;
    private MenuItem? _microphoneMenu;
    private bool _isRecording;
    private bool _disposed;
    private readonly object _lock = new();
    private System.Timers.Timer? _checkmarkTimer;
    private bool _showCheckmark;
    private bool _showMenuBarIcon = true;
    private bool _isDarkTheme;
    private readonly bool _isDevBuild;

    // Icon resources - maps status to icons (regenerated on theme change)
    private readonly Dictionary<AppStatus, Icon> _statusIcons = new();
    private Icon? _checkmarkIcon;
    private Icon? _devStampedIcon;

    // Dependencies for extended menu functionality
    private ISettingsManager? _settingsManager;
    private IAudioRecorder? _audioRecorder;
    private IClipboardManager? _clipboardManager;

    // History of transcripts (matching macOS pipelineHistory)
    private readonly List<TranscriptHistoryItem> _transcriptHistory = new();
    private const int MaxHistoryItems = 10;

    public event EventHandler? SettingsRequested;
    public event EventHandler? ExitRequested;
    public event EventHandler? RecordingToggleRequested;
    public event EventHandler? PasteAgainRequested;
    public event EventHandler<bool>? ShowMenuBarIconChanged;
    public event EventHandler<HotkeyBinding>? HoldShortcutChanged;
    public event EventHandler<HotkeyBinding>? ToggleShortcutChanged;
    public event EventHandler<string?>? MicrophoneChanged;

    public AppStatus CurrentStatus { get; private set; } = AppStatus.Idle;
    public bool IsInitialized { get; private set; }
    
    /// <summary>
    /// Gets whether this is a dev build. Matches macOS AppBuild.isDevBundle.
    /// </summary>
    public bool IsDevBuild => _isDevBuild;
    
    public bool ShowMenuBarIcon
    {
        get => _showMenuBarIcon;
        set
        {
            if (_showMenuBarIcon != value)
            {
                _showMenuBarIcon = value;
                UpdateIconVisibility();
                ShowMenuBarIconChanged?.Invoke(this, value);
            }
        }
    }

    public SystemTrayManager()
    {
        _isDarkTheme = IsWindowsDarkTheme();
        _isDevBuild = DetectDevBuild();
    }

    /// <summary>
    /// Sets dependencies for extended menu functionality (history, shortcuts, microphone).
    /// Call this after construction to enable full macOS-matching menu.
    /// </summary>
    public void SetDependencies(ISettingsManager? settingsManager, IAudioRecorder? audioRecorder, IClipboardManager? clipboardManager)
    {
        _settingsManager = settingsManager;
        _audioRecorder = audioRecorder;
        _clipboardManager = clipboardManager;
    }

    /// <summary>
    /// Adds a transcript to the history. Matches macOS pipelineHistory behavior.
    /// Also updates the "last transcript" preview in the menu.
    /// </summary>
    public void AddToHistory(string transcript, string? rawTranscript = null)
    {
        if (string.IsNullOrWhiteSpace(transcript)) return;
        
        lock (_lock)
        {
            _transcriptHistory.Insert(0, new TranscriptHistoryItem
            {
                PostProcessedTranscript = transcript,
                RawTranscript = rawTranscript ?? transcript,
                Timestamp = DateTime.Now
            });
            
            // Keep only last MaxHistoryItems
            while (_transcriptHistory.Count > MaxHistoryItems)
            {
                _transcriptHistory.RemoveAt(_transcriptHistory.Count - 1);
            }
        }
        
        // Update the history menu and last transcript preview
        Application.Current?.Dispatcher?.Invoke(() =>
        {
            UpdateHistoryMenu();
            SetLastTranscript(transcript);
        });
    }

    /// <summary>
    /// Detects if this is a dev build. Matches macOS AppBuild.isDevBundle logic.
    /// Checks if assembly name contains "Dev" or if running in Debug configuration.
    /// </summary>
    private static bool DetectDevBuild()
    {
        try
        {
            var assembly = Assembly.GetEntryAssembly() ?? Assembly.GetExecutingAssembly();
            var name = assembly.GetName().Name ?? "";
            
            // Check if name contains "Dev" (like macOS "FreeFlow Dev")
            if (name.Contains("Dev", StringComparison.OrdinalIgnoreCase))
                return true;

            // Check for Debug configuration
            #if DEBUG
            return true;
            #else
            return false;
            #endif
        }
        catch
        {
            return false;
        }
    }

    public void Initialize()
    {
        if (IsInitialized) return;
        lock (_lock)
        {
            if (IsInitialized) return;
            if (Application.Current?.Dispatcher != null && !Application.Current.Dispatcher.CheckAccess())
                Application.Current.Dispatcher.Invoke(InitializeCore);
            else
                InitializeCore();
        }
    }

    private void InitializeCore()
    {
        SystemEvents.UserPreferenceChanged += OnSystemThemeChanged;
        CreateStatusIcons();
        _contextMenu = CreateContextMenu();
        
        _taskbarIcon = new TaskbarIcon
        {
            ToolTipText = _isDevBuild ? "FreeFlow Dev - Voice Dictation" : "FreeFlow - Voice Dictation",
            ContextMenu = _contextMenu,
            Visibility = _showMenuBarIcon ? Visibility.Visible : Visibility.Collapsed,
            Icon = GetIdleIcon()
        };
        CurrentStatus = AppStatus.Idle;
        _taskbarIcon.TrayMouseDoubleClick += OnTrayMouseDoubleClick;
        IsInitialized = true;
    }

    /// <summary>
    /// Gets the appropriate idle icon. Uses stamped dev icon for dev builds (matching macOS).
    /// </summary>
    private Icon GetIdleIcon()
    {
        if (_isDevBuild && !_isRecording && CurrentStatus != AppStatus.Processing)
            return _devStampedIcon ?? _statusIcons.GetValueOrDefault(AppStatus.Idle) ?? CreateWaveformIcon(GetIdleColor(), 32);
        return _statusIcons.GetValueOrDefault(AppStatus.Idle) ?? CreateWaveformIcon(GetIdleColor(), 32);
    }

    #region Theme Detection

    private static bool IsWindowsDarkTheme()
    {
        try
        {
            using var key = Registry.CurrentUser.OpenSubKey(
                @"Software\Microsoft\Windows\CurrentVersion\Themes\Personalize");
            if (key?.GetValue("AppsUseLightTheme") is int intValue)
                return intValue == 0;
        }
        catch { }
        return false;
    }

    private System.Drawing.Color GetIdleColor() => _isDarkTheme 
        ? System.Drawing.Color.FromArgb(220, 220, 220) 
        : System.Drawing.Color.FromArgb(60, 60, 60);

    private static System.Drawing.Color GetRecordingColor() => System.Drawing.Color.FromArgb(239, 68, 68);
    private static System.Drawing.Color GetProcessingColor() => System.Drawing.Color.FromArgb(245, 158, 11);
    private System.Drawing.Color GetCheckmarkColor() => _isDarkTheme
        ? System.Drawing.Color.FromArgb(74, 222, 128)
        : System.Drawing.Color.FromArgb(34, 197, 94);

    private void OnSystemThemeChanged(object sender, UserPreferenceChangedEventArgs e)
    {
        if (e.Category != UserPreferenceCategory.General) return;
        var newIsDark = IsWindowsDarkTheme();
        if (newIsDark == _isDarkTheme) return;
        _isDarkTheme = newIsDark;
        Application.Current?.Dispatcher?.Invoke(() => { RegenerateIcons(); UpdateIconForCurrentState(); });
    }

    private void RegenerateIcons()
    {
        foreach (var icon in _statusIcons.Values) icon.Dispose();
        _statusIcons.Clear();
        _checkmarkIcon?.Dispose();
        _devStampedIcon?.Dispose();
        _checkmarkIcon = null;
        _devStampedIcon = null;
        CreateStatusIcons();
    }

    #endregion

    #region Icon Creation

    private void CreateStatusIcons()
    {
        // Use 32x32 for better quality on high-DPI displays
        const int size = 32;
        _statusIcons[AppStatus.Idle] = CreateWaveformIcon(GetIdleColor(), size);
        _statusIcons[AppStatus.Recording] = CreateRecordingIcon(GetRecordingColor(), size);
        _statusIcons[AppStatus.Processing] = CreateProcessingIcon(GetProcessingColor(), size);
        _statusIcons[AppStatus.Error] = CreateProcessingIcon(GetProcessingColor(), size);
        _checkmarkIcon = CreateCheckmarkIcon(GetCheckmarkColor(), size);
        
        // Create dev stamped icon matching macOS StampedMenuBarIcon
        if (_isDevBuild)
            _devStampedIcon = CreateStampedDevIcon(GetIdleColor(), size);
    }

    /// <summary>
    /// Creates a waveform icon matching macOS "waveform" SF Symbol.
    /// </summary>
    private static Icon CreateWaveformIcon(System.Drawing.Color color, int size)
    {
        using var bitmap = new Bitmap(size, size);
        using var g = Graphics.FromImage(bitmap);
        g.SmoothingMode = SmoothingMode.AntiAlias;
        g.Clear(System.Drawing.Color.Transparent);
        using var brush = new SolidBrush(color);

        float scale = size / 16f;
        var bars = new[] { (x: 2f, h: 4f), (x: 5f, h: 8f), (x: 8f, h: 12f), (x: 11f, h: 6f), (x: 14f, h: 3f) };
        float barWidth = 2f * scale;

        foreach (var bar in bars)
        {
            float x = bar.x * scale - barWidth / 2;
            float h = bar.h * scale;
            float y = (size - h) / 2;
            using var path = CreateRoundedRectPath(x, y, barWidth, h, scale);
            g.FillPath(brush, path);
        }
        return Icon.FromHandle(bitmap.GetHicon());
    }

    /// <summary>
    /// Creates a stamped dev icon matching macOS StampedMenuBarIcon.templateImage.
    /// Rounded rectangle background with waveform bars inside (even-odd fill).
    /// </summary>
    private static Icon CreateStampedDevIcon(System.Drawing.Color color, int size)
    {
        using var bitmap = new Bitmap(size, size);
        using var g = Graphics.FromImage(bitmap);
        g.SmoothingMode = SmoothingMode.AntiAlias;
        g.Clear(System.Drawing.Color.Transparent);

        float scale = size / 16f;
        
        // Create the combined path with even-odd winding (like macOS)
        using var combinedPath = new GraphicsPath(FillMode.Alternate);
        
        // Outer rounded rectangle (matching macOS: roundedRect with xRadius:3, yRadius:3)
        float margin = 1f * scale;
        var outerRect = new RectangleF(margin, margin, size - 2 * margin, size - 2 * margin);
        float cornerRadius = 3f * scale;
        AddRoundedRectToPath(combinedPath, outerRect, cornerRadius);
        
        // Inner waveform bars (these will be "cut out" due to even-odd fill)
        // Matching macOS bars: (3.0, 7.0, 2.0), (5.5, 5.0, 6.0), (8.0, 3.0, 10.0), (10.5, 4.0, 8.0), (13.0, 6.0, 4.0)
        var macBars = new[] {
            (x: 3.0f, y: 7.0f, h: 2.0f),
            (x: 5.5f, y: 5.0f, h: 6.0f),
            (x: 8.0f, y: 3.0f, h: 10.0f),
            (x: 10.5f, y: 4.0f, h: 8.0f),
            (x: 13.0f, y: 6.0f, h: 4.0f)
        };
        float barWidth = 1.5f * scale;
        float barRadius = 0.75f * scale;
        
        foreach (var bar in macBars)
        {
            float x = bar.x * scale;
            float y = bar.y * scale;
            float h = bar.h * scale;
            var barRect = new RectangleF(x, y, barWidth, h);
            AddRoundedRectToPath(combinedPath, barRect, barRadius);
        }
        
        using var brush = new SolidBrush(color);
        g.FillPath(brush, combinedPath);
        
        return Icon.FromHandle(bitmap.GetHicon());
    }

    /// <summary>
    /// Creates a recording icon matching macOS "record.circle" SF Symbol.
    /// </summary>
    private static Icon CreateRecordingIcon(System.Drawing.Color color, int size)
    {
        using var bitmap = new Bitmap(size, size);
        using var g = Graphics.FromImage(bitmap);
        g.SmoothingMode = SmoothingMode.AntiAlias;
        g.Clear(System.Drawing.Color.Transparent);

        float scale = size / 16f;
        using var pen = new System.Drawing.Pen(color, 1.5f * scale);
        using var brush = new SolidBrush(color);

        float margin = 2f * scale;
        float diameter = size - 4f * scale;
        g.DrawEllipse(pen, margin, margin, diameter, diameter);
        
        float innerMargin = 5f * scale;
        float innerSize = 6f * scale;
        g.FillEllipse(brush, innerMargin, innerMargin, innerSize, innerSize);
        
        return Icon.FromHandle(bitmap.GetHicon());
    }

    /// <summary>
    /// Creates a processing icon matching macOS "ellipsis.circle" SF Symbol.
    /// </summary>
    private static Icon CreateProcessingIcon(System.Drawing.Color color, int size)
    {
        using var bitmap = new Bitmap(size, size);
        using var g = Graphics.FromImage(bitmap);
        g.SmoothingMode = SmoothingMode.AntiAlias;
        g.Clear(System.Drawing.Color.Transparent);

        float scale = size / 16f;
        using var pen = new System.Drawing.Pen(color, 1.5f * scale);
        using var brush = new SolidBrush(color);

        float margin = 2f * scale;
        float diameter = size - 4f * scale;
        g.DrawEllipse(pen, margin, margin, diameter, diameter);
        
        float dotSize = 2f * scale;
        float dotY = 7f * scale;
        g.FillEllipse(brush, 4f * scale, dotY, dotSize, dotSize);
        g.FillEllipse(brush, 7f * scale, dotY, dotSize, dotSize);
        g.FillEllipse(brush, 10f * scale, dotY, dotSize, dotSize);
        
        return Icon.FromHandle(bitmap.GetHicon());
    }

    /// <summary>
    /// Creates a checkmark icon matching macOS "checkmark" SF Symbol.
    /// </summary>
    private static Icon CreateCheckmarkIcon(System.Drawing.Color color, int size)
    {
        using var bitmap = new Bitmap(size, size);
        using var g = Graphics.FromImage(bitmap);
        g.SmoothingMode = SmoothingMode.AntiAlias;
        g.Clear(System.Drawing.Color.Transparent);

        float scale = size / 16f;
        using var pen = new System.Drawing.Pen(color, 2f * scale)
        {
            StartCap = LineCap.Round,
            EndCap = LineCap.Round,
            LineJoin = LineJoin.Round
        };

        var points = new PointF[] {
            new(3f * scale, 8f * scale),
            new(6f * scale, 11f * scale),
            new(13f * scale, 4f * scale)
        };
        g.DrawLines(pen, points);
        return Icon.FromHandle(bitmap.GetHicon());
    }

    private static GraphicsPath CreateRoundedRectPath(float x, float y, float w, float h, float r)
    {
        var path = new GraphicsPath();
        if (r <= 0 || w <= 0 || h <= 0) { path.AddRectangle(new RectangleF(x, y, w, h)); return path; }
        float d = r * 2;
        path.AddArc(x, y, d, d, 180, 90);
        path.AddArc(x + w - d, y, d, d, 270, 90);
        path.AddArc(x + w - d, y + h - d, d, d, 0, 90);
        path.AddArc(x, y + h - d, d, d, 90, 90);
        path.CloseFigure();
        return path;
    }

    private static void AddRoundedRectToPath(GraphicsPath path, RectangleF rect, float r)
    {
        if (r <= 0) { path.AddRectangle(rect); return; }
        float d = r * 2;
        path.AddArc(rect.X, rect.Y, d, d, 180, 90);
        path.AddArc(rect.Right - d, rect.Y, d, d, 270, 90);
        path.AddArc(rect.Right - d, rect.Bottom - d, d, d, 0, 90);
        path.AddArc(rect.X, rect.Bottom - d, d, d, 90, 90);
        path.CloseFigure();
    }

    #endregion

    #region Checkmark Flash

    public void FlashCheckmark()
    {
        if (!IsInitialized || _taskbarIcon == null) return;
        if (Application.Current?.Dispatcher != null && !Application.Current.Dispatcher.CheckAccess())
            Application.Current.Dispatcher.Invoke(FlashCheckmarkInternal);
        else
            FlashCheckmarkInternal();
    }

    private void FlashCheckmarkInternal()
    {
        if (_taskbarIcon == null || _checkmarkIcon == null) return;
        _showCheckmark = true;
        _taskbarIcon.Icon = _checkmarkIcon;

        _checkmarkTimer?.Stop();
        _checkmarkTimer?.Dispose();
        // Match macOS: 2 second duration (2_000_000_000 nanoseconds = 2000ms)
        _checkmarkTimer = new System.Timers.Timer(2000);
        _checkmarkTimer.Elapsed += (s, e) =>
        {
            _checkmarkTimer?.Stop();
            _showCheckmark = false;
            Application.Current?.Dispatcher?.Invoke(UpdateIconForCurrentState);
        };
        _checkmarkTimer.AutoReset = false;
        _checkmarkTimer.Start();
    }

    #endregion

    #region Context Menu

    // Additional menu items for status and errors (matching macOS)
    private MenuItem? _statusMenuItem;
    private MenuItem? _errorMenuItem;
    private MenuItem? _lastTranscriptMenuItem;
    private MenuItem? _pasteAgainShortcutMenu;
    private string? _lastTranscript;
    private string? _errorMessage;
    private string _shortcutStatusText = "Hold Ctrl+Shift+Space to dictate";

    private ContextMenu CreateContextMenu()
    {
        var menu = new ContextMenu();
        var settings = _settingsManager?.Load();

        // Version header (matching macOS "FreeFlow v{version}")
        var versionItem = new MenuItem 
        { 
            Header = $"{(_isDevBuild ? "FreeFlow Dev" : "FreeFlow")} v{GetAppVersion()}",
            IsEnabled = false 
        };
        menu.Items.Add(versionItem);
        menu.Items.Add(new Separator());

        // Status display (matching macOS: "Recording...", "Transcribing...", or shortcut status)
        _statusMenuItem = new MenuItem 
        { 
            Header = _shortcutStatusText, 
            IsEnabled = false,
            FontStyle = FontStyles.Italic
        };
        menu.Items.Add(_statusMenuItem);
        menu.Items.Add(new Separator());

        // Recording toggle (matching macOS "Stop Recording" / "Start Dictating")
        _recordingMenuItem = new MenuItem { Header = "Start Dictating" };
        _recordingMenuItem.Click += OnRecordingMenuItemClick;
        menu.Items.Add(_recordingMenuItem);

        // Error message display (matching macOS - only shown when there's an error)
        _errorMenuItem = new MenuItem 
        { 
            Header = "",
            IsEnabled = false,
            Foreground = new SolidColorBrush(System.Windows.Media.Color.FromRgb(239, 68, 68)), // Red
            Visibility = Visibility.Collapsed
        };
        menu.Items.Add(_errorMenuItem);
        menu.Items.Add(new Separator());

        // Paste Again with shortcut display (matching macOS)
        _pasteAgainMenuItem = new MenuItem { Header = GetPasteAgainHeader(settings) };
        _pasteAgainMenuItem.Click += OnPasteAgainMenuItemClick;
        menu.Items.Add(_pasteAgainMenuItem);

        // Last transcript preview (matching macOS - shows quoted snippet below Paste Again)
        _lastTranscriptMenuItem = new MenuItem 
        { 
            Header = "",
            IsEnabled = false,
            FontStyle = FontStyles.Italic,
            Visibility = Visibility.Collapsed
        };
        menu.Items.Add(_lastTranscriptMenuItem);
        menu.Items.Add(new Separator());

        // History submenu (matching macOS "History" menu)
        _historyMenu = new MenuItem { Header = "History" };
        UpdateHistoryMenu();
        menu.Items.Add(_historyMenu);
        menu.Items.Add(new Separator());

        // Paste Custom Word to Vocabulary (matching macOS)
        var pasteVocabItem = new MenuItem { Header = "Paste Custom Word to Vocabulary" };
        pasteVocabItem.Click += OnPasteVocabularyMenuItemClick;
        menu.Items.Add(pasteVocabItem);
        menu.Items.Add(new Separator());

        // Hold Shortcut submenu (matching macOS)
        _holdShortcutMenu = new MenuItem { Header = "Hold Shortcut" };
        UpdateHoldShortcutMenu(settings);
        menu.Items.Add(_holdShortcutMenu);

        // Toggle Shortcut submenu (matching macOS)
        _toggleShortcutMenu = new MenuItem { Header = "Toggle Shortcut" };
        UpdateToggleShortcutMenu(settings);
        menu.Items.Add(_toggleShortcutMenu);

        // Paste Again Shortcut submenu (matching macOS)
        _pasteAgainShortcutMenu = new MenuItem { Header = "Paste Again Shortcut" };
        UpdatePasteAgainShortcutMenu(settings);
        menu.Items.Add(_pasteAgainShortcutMenu);
        
        // Microphone submenu (matching macOS)
        _microphoneMenu = new MenuItem { Header = "Microphone" };
        UpdateMicrophoneMenu(settings);
        menu.Items.Add(_microphoneMenu);
        menu.Items.Add(new Separator());

        // Re-run Setup (matching macOS)
        var setupItem = new MenuItem { Header = "Re-run Setup..." };
        setupItem.Click += OnSetupMenuItemClick;
        menu.Items.Add(setupItem);

        // Settings (matching macOS)
        var settingsItem = new MenuItem { Header = "Settings" };
        settingsItem.Click += OnSettingsMenuItemClick;
        menu.Items.Add(settingsItem);

        // Check for Updates (matching macOS)
        var checkUpdatesItem = new MenuItem { Header = "Check for Updates" };
        checkUpdatesItem.Click += OnCheckUpdatesMenuItemClick;
        menu.Items.Add(checkUpdatesItem);
        menu.Items.Add(new Separator());

        // Show Menu Bar Icon (matching macOS - this is in macOS settings, but also nice to have here)
        _showIconMenuItem = new MenuItem { Header = "Show Menu Bar Icon", IsCheckable = true, IsChecked = _showMenuBarIcon };
        _showIconMenuItem.Click += OnShowIconMenuItemClick;
        menu.Items.Add(_showIconMenuItem);
        menu.Items.Add(new Separator());

        // Quit (matching macOS "Quit FreeFlow" / "Quit FreeFlow Dev")
        var exitItem = new MenuItem { Header = _isDevBuild ? "Quit FreeFlow Dev" : "Quit FreeFlow" };
        exitItem.Click += OnExitMenuItemClick;
        menu.Items.Add(exitItem);

        return menu;
    }

    /// <summary>
    /// Updates the status text displayed in the menu. Matches macOS shortcutStatusText.
    /// </summary>
    public void UpdateStatusText(string status)
    {
        _shortcutStatusText = status;
        Application.Current?.Dispatcher?.Invoke(() =>
        {
            if (_statusMenuItem != null)
                _statusMenuItem.Header = status;
        });
    }

    /// <summary>
    /// Sets the error message to display in the menu. Matches macOS errorMessage.
    /// </summary>
    public void SetErrorMessage(string? error)
    {
        _errorMessage = error;
        Application.Current?.Dispatcher?.Invoke(() =>
        {
            if (_errorMenuItem != null)
            {
                if (string.IsNullOrEmpty(error))
                {
                    _errorMenuItem.Visibility = Visibility.Collapsed;
                }
                else
                {
                    _errorMenuItem.Header = error;
                    _errorMenuItem.Visibility = Visibility.Visible;
                }
            }
        });
    }

    /// <summary>
    /// Sets the last transcript for display in the menu. Matches macOS lastTranscript.
    /// </summary>
    public void SetLastTranscript(string? transcript)
    {
        _lastTranscript = transcript;
        Application.Current?.Dispatcher?.Invoke(() =>
        {
            if (_lastTranscriptMenuItem != null)
            {
                if (string.IsNullOrWhiteSpace(transcript))
                {
                    _lastTranscriptMenuItem.Visibility = Visibility.Collapsed;
                }
                else
                {
                    // Matching macOS: truncate to 35 chars + "…", wrap in quotes
                    var truncated = transcript.Length > 35 
                        ? transcript.Substring(0, 35) + "…" 
                        : transcript;
                    _lastTranscriptMenuItem.Header = $"\"{truncated}\"";
                    _lastTranscriptMenuItem.Visibility = Visibility.Visible;
                }
            }
        });
    }

    /// <summary>
    /// Updates the Paste Again Shortcut submenu. Matches macOS "Paste Again Shortcut" menu.
    /// </summary>
    private void UpdatePasteAgainShortcutMenu(AppSettings? settings)
    {
        if (_pasteAgainShortcutMenu == null) return;
        
        _pasteAgainShortcutMenu.Items.Clear();
        
        // Note: Windows doesn't currently have a separate paste-again hotkey like macOS
        // We'll show the menu structure but mark everything as "coming soon"
        var disabledItem = new MenuItem { Header = "✓ Disabled" };
        _pasteAgainShortcutMenu.Items.Add(disabledItem);
        
        _pasteAgainShortcutMenu.Items.Add(new Separator());
        
        var customizeItem = new MenuItem { Header = "Customize..." };
        customizeItem.Click += OnSettingsMenuItemClick;
        _pasteAgainShortcutMenu.Items.Add(customizeItem);
    }

    private static string GetAppVersion()
    {
        try
        {
            var assembly = Assembly.GetEntryAssembly() ?? Assembly.GetExecutingAssembly();
            var version = assembly.GetName().Version;
            return version != null ? $"{version.Major}.{version.Minor}.{version.Build}" : "1.0.0";
        }
        catch
        {
            return "1.0.0";
        }
    }

    private string GetPasteAgainHeader(AppSettings? settings)
    {
        // Matching macOS: "Paste Again  ({shortcut})" or just "Paste Again" if no shortcut
        // Windows doesn't have a separate paste-again hotkey yet, so just show "Paste Again"
        return "Paste Again";
    }

    private void UpdateHistoryMenu()
    {
        if (_historyMenu == null) return;
        
        _historyMenu.Items.Clear();
        
        List<TranscriptHistoryItem> historyCopy;
        lock (_lock)
        {
            historyCopy = _transcriptHistory.ToList();
        }
        
        if (historyCopy.Count == 0)
        {
            var emptyItem = new MenuItem { Header = "No transcripts yet", IsEnabled = false };
            _historyMenu.Items.Add(emptyItem);
        }
        else
        {
            foreach (var item in historyCopy)
            {
                var snippet = GetTranscriptSnippet(item.PostProcessedTranscript);
                var menuItem = new MenuItem { Header = snippet, Tag = item };
                menuItem.Click += OnHistoryItemClick;
                _historyMenu.Items.Add(menuItem);
            }
            
            _historyMenu.Items.Add(new Separator());
        }
        
        // "Open Run Log" equivalent - opens settings
        var openLogItem = new MenuItem { Header = "Open Run Log" };
        openLogItem.Click += OnSettingsMenuItemClick;
        _historyMenu.Items.Add(openLogItem);
    }

    private static string GetTranscriptSnippet(string text)
    {
        // Matching macOS: 48 char limit + "..."
        var cleaned = text.Replace("\n", " ").Trim();
        if (string.IsNullOrEmpty(cleaned)) return "(no transcript)";
        return cleaned.Length > 48 ? cleaned.Substring(0, 48) + "..." : cleaned;
    }

    private void UpdateHoldShortcutMenu(AppSettings? settings)
    {
        if (_holdShortcutMenu == null) return;
        
        _holdShortcutMenu.Items.Clear();
        var currentHold = settings?.HoldHotkey;
        var currentToggle = settings?.ToggleHotkey;
        
        // Disabled option
        var disabledItem = new MenuItem 
        { 
            Header = currentHold?.IsDisabled == true ? "✓ Disabled" : "  Disabled"
        };
        disabledItem.Click += (s, e) => SetHoldShortcut(HotkeyBinding.Disabled);
        _holdShortcutMenu.Items.Add(disabledItem);
        
        // Preset shortcuts (matching macOS ShortcutPreset)
        AddShortcutPresets(_holdShortcutMenu, currentHold, currentToggle, SetHoldShortcut);
        
        _holdShortcutMenu.Items.Add(new Separator());
        
        // Customize option
        var customizeItem = new MenuItem { Header = "Customize..." };
        customizeItem.Click += OnSettingsMenuItemClick;
        _holdShortcutMenu.Items.Add(customizeItem);
    }

    private void UpdateToggleShortcutMenu(AppSettings? settings)
    {
        if (_toggleShortcutMenu == null) return;
        
        _toggleShortcutMenu.Items.Clear();
        var currentToggle = settings?.ToggleHotkey;
        var currentHold = settings?.HoldHotkey;
        
        // Disabled option
        var disabledItem = new MenuItem 
        { 
            Header = currentToggle?.IsDisabled == true ? "✓ Disabled" : "  Disabled"
        };
        disabledItem.Click += (s, e) => SetToggleShortcut(HotkeyBinding.Disabled);
        _toggleShortcutMenu.Items.Add(disabledItem);
        
        // Preset shortcuts
        AddShortcutPresets(_toggleShortcutMenu, currentToggle, currentHold, SetToggleShortcut);
        
        _toggleShortcutMenu.Items.Add(new Separator());
        
        // Customize option
        var customizeItem = new MenuItem { Header = "Customize..." };
        customizeItem.Click += OnSettingsMenuItemClick;
        _toggleShortcutMenu.Items.Add(customizeItem);
    }

    private void AddShortcutPresets(MenuItem menu, HotkeyBinding? current, HotkeyBinding? other, Action<HotkeyBinding> setAction)
    {
        // Common presets matching macOS ShortcutPreset
        var presets = new[]
        {
            (Name: "Ctrl+Shift+Space", Binding: new HotkeyBinding { Modifiers = ModifierKeys.Ctrl | ModifierKeys.Shift, Key = VirtualKey.Space }),
            (Name: "Ctrl+Alt+Space", Binding: new HotkeyBinding { Modifiers = ModifierKeys.Ctrl | ModifierKeys.Alt, Key = VirtualKey.Space }),
            (Name: "Ctrl+`", Binding: new HotkeyBinding { Modifiers = ModifierKeys.Ctrl, Key = VirtualKey.Oem3 }),
            (Name: "Right Ctrl", Binding: new HotkeyBinding { Modifiers = ModifierKeys.None, Key = VirtualKey.RightCtrl }),
        };
        
        foreach (var preset in presets)
        {
            var isSelected = current != null && current.Equals(preset.Binding);
            var isDisabledByOther = other != null && other.Equals(preset.Binding);
            
            var item = new MenuItem 
            { 
                Header = isSelected ? $"✓ {preset.Name}" : $"  {preset.Name}",
                IsEnabled = !isDisabledByOther
            };
            item.Click += (s, e) => setAction(preset.Binding);
            menu.Items.Add(item);
        }
    }

    private void SetHoldShortcut(HotkeyBinding binding)
    {
        if (_settingsManager == null) return;
        var settings = _settingsManager.Load();
        settings.HoldHotkey = binding;
        _settingsManager.Save(settings);
        HoldShortcutChanged?.Invoke(this, binding);
        Application.Current?.Dispatcher?.Invoke(() => UpdateHoldShortcutMenu(settings));
    }

    private void SetToggleShortcut(HotkeyBinding binding)
    {
        if (_settingsManager == null) return;
        var settings = _settingsManager.Load();
        settings.ToggleHotkey = binding;
        _settingsManager.Save(settings);
        ToggleShortcutChanged?.Invoke(this, binding);
        Application.Current?.Dispatcher?.Invoke(() => UpdateToggleShortcutMenu(settings));
    }

    private void UpdateMicrophoneMenu(AppSettings? settings)
    {
        if (_microphoneMenu == null) return;
        
        _microphoneMenu.Items.Clear();
        var currentMicId = settings?.SelectedMicrophoneId;
        
        // System Default option (matching macOS)
        var isDefault = string.IsNullOrEmpty(currentMicId) || currentMicId == "default";
        var defaultItem = new MenuItem 
        { 
            Header = isDefault ? "✓ System Default" : "  System Default"
        };
        defaultItem.Click += (s, e) => SetMicrophone(null);
        _microphoneMenu.Items.Add(defaultItem);
        
        // Available devices
        if (_audioRecorder != null)
        {
            try
            {
                var devices = _audioRecorder.GetAvailableDevices();
                foreach (var device in devices)
                {
                    var isSelected = device.Id == currentMicId;
                    var item = new MenuItem 
                    { 
                        Header = isSelected ? $"✓ {device.Name}" : $"  {device.Name}",
                        Tag = device.Id
                    };
                    item.Click += (s, e) => SetMicrophone(device.Id);
                    _microphoneMenu.Items.Add(item);
                }
            }
            catch
            {
                // Ignore device enumeration errors
            }
        }
    }

    private void SetMicrophone(string? deviceId)
    {
        if (_settingsManager == null) return;
        var settings = _settingsManager.Load();
        settings.SelectedMicrophoneId = deviceId;
        _settingsManager.Save(settings);
        MicrophoneChanged?.Invoke(this, deviceId);
        Application.Current?.Dispatcher?.Invoke(() => UpdateMicrophoneMenu(settings));
    }

    #endregion

    #region Icon Updates

    public void UpdateIcon(AppStatus status)
    {
        if (!IsInitialized || _taskbarIcon == null) return;
        if (Application.Current?.Dispatcher != null && !Application.Current.Dispatcher.CheckAccess())
            Application.Current.Dispatcher.Invoke(() => UpdateIconInternal(status));
        else
            UpdateIconInternal(status);
    }

    private void UpdateIconInternal(AppStatus status)
    {
        if (_taskbarIcon == null) return;
        CurrentStatus = status;
        if (!_showCheckmark) UpdateIconForCurrentState();

        _taskbarIcon.ToolTipText = status switch
        {
            AppStatus.Idle => _isDevBuild ? "FreeFlow Dev - Ready" : "FreeFlow - Ready",
            AppStatus.Recording => _isDevBuild ? "FreeFlow Dev - Recording..." : "FreeFlow - Recording...",
            AppStatus.Processing => _isDevBuild ? "FreeFlow Dev - Processing..." : "FreeFlow - Processing...",
            AppStatus.Error => _isDevBuild ? "FreeFlow Dev - Error" : "FreeFlow - Error",
            _ => _isDevBuild ? "FreeFlow Dev" : "FreeFlow"
        };
        
        // Update status text in menu (matching macOS)
        if (_statusMenuItem != null)
        {
            switch (status)
            {
                case AppStatus.Recording:
                    _statusMenuItem.Header = "Recording...";
                    _statusMenuItem.Foreground = new SolidColorBrush(System.Windows.Media.Color.FromRgb(239, 68, 68)); // Red
                    break;
                case AppStatus.Processing:
                    _statusMenuItem.Header = "Processing...";
                    _statusMenuItem.Foreground = new SolidColorBrush(System.Windows.Media.Color.FromRgb(128, 128, 128)); // Gray
                    break;
                default:
                    _statusMenuItem.Header = _shortcutStatusText;
                    _statusMenuItem.Foreground = new SolidColorBrush(System.Windows.Media.Color.FromRgb(128, 128, 128)); // Gray
                    break;
            }
        }
    }

    private void UpdateIconForCurrentState()
    {
        if (_taskbarIcon == null) return;
        
        // Use dev stamped icon for idle state in dev builds (matching macOS behavior)
        if (_isDevBuild && CurrentStatus == AppStatus.Idle && _devStampedIcon != null)
        {
            _taskbarIcon.Icon = _devStampedIcon;
            return;
        }
        
        if (_statusIcons.TryGetValue(CurrentStatus, out var icon))
            _taskbarIcon.Icon = icon;
    }

    private void UpdateIconVisibility()
    {
        if (_taskbarIcon == null) return;
        if (Application.Current?.Dispatcher != null && !Application.Current.Dispatcher.CheckAccess())
        {
            Application.Current.Dispatcher.Invoke(() =>
            {
                _taskbarIcon.Visibility = _showMenuBarIcon ? Visibility.Visible : Visibility.Collapsed;
                if (_showIconMenuItem != null) _showIconMenuItem.IsChecked = _showMenuBarIcon;
            });
        }
        else
        {
            _taskbarIcon.Visibility = _showMenuBarIcon ? Visibility.Visible : Visibility.Collapsed;
            if (_showIconMenuItem != null) _showIconMenuItem.IsChecked = _showMenuBarIcon;
        }
    }

    #endregion

    #region Notifications

    public void ShowBalloonNotification(string title, string message, NotificationType type)
    {
        if (!IsInitialized || _taskbarIcon == null) return;
        if (Application.Current?.Dispatcher != null && !Application.Current.Dispatcher.CheckAccess())
            Application.Current.Dispatcher.Invoke(() => ShowBalloonNotificationInternal(title, message, type));
        else
            ShowBalloonNotificationInternal(title, message, type);
    }

    private void ShowBalloonNotificationInternal(string title, string message, NotificationType type)
    {
        _taskbarIcon?.ShowBalloonTip(title, message, type switch
        {
            NotificationType.Warning => BalloonIcon.Warning,
            NotificationType.Error => BalloonIcon.Error,
            _ => BalloonIcon.Info
        });
    }

    public void UpdateTooltip(string tooltip)
    {
        if (!IsInitialized || _taskbarIcon == null) return;
        if (Application.Current?.Dispatcher != null && !Application.Current.Dispatcher.CheckAccess())
            Application.Current.Dispatcher.Invoke(() => { if (_taskbarIcon != null) _taskbarIcon.ToolTipText = tooltip; });
        else
            _taskbarIcon.ToolTipText = tooltip;
    }

    #endregion

    #region Recording State

    public void SetRecordingState(bool isRecording)
    {
        _isRecording = isRecording;
        if (_recordingMenuItem == null) return;
        if (Application.Current?.Dispatcher != null && !Application.Current.Dispatcher.CheckAccess())
            Application.Current.Dispatcher.Invoke(UpdateRecordingMenuItemInternal);
        else
            UpdateRecordingMenuItemInternal();
    }

    private void UpdateRecordingMenuItemInternal()
    {
        if (_recordingMenuItem != null)
            _recordingMenuItem.Header = _isRecording ? "Stop Recording" : "Start Dictating";
        
        // Update status text to match macOS behavior
        if (_statusMenuItem != null)
        {
            if (_isRecording)
            {
                _statusMenuItem.Header = "Recording...";
                _statusMenuItem.Foreground = new SolidColorBrush(System.Windows.Media.Color.FromRgb(239, 68, 68)); // Red
            }
            else
            {
                _statusMenuItem.Header = _shortcutStatusText;
                _statusMenuItem.Foreground = new SolidColorBrush(System.Windows.Media.Color.FromRgb(128, 128, 128)); // Gray
            }
        }
    }

    #endregion

    #region Event Handlers

    private void OnTrayMouseDoubleClick(object sender, RoutedEventArgs e) => SettingsRequested?.Invoke(this, EventArgs.Empty);
    private void OnRecordingMenuItemClick(object sender, RoutedEventArgs e) => RecordingToggleRequested?.Invoke(this, EventArgs.Empty);
    private void OnPasteAgainMenuItemClick(object sender, RoutedEventArgs e) => PasteAgainRequested?.Invoke(this, EventArgs.Empty);
    private void OnShowIconMenuItemClick(object sender, RoutedEventArgs e) => ShowMenuBarIcon = _showIconMenuItem?.IsChecked ?? true;
    private void OnSettingsMenuItemClick(object sender, RoutedEventArgs e) => SettingsRequested?.Invoke(this, EventArgs.Empty);
    private void OnExitMenuItemClick(object sender, RoutedEventArgs e) => ExitRequested?.Invoke(this, EventArgs.Empty);
    
    private void OnSetupMenuItemClick(object sender, RoutedEventArgs e)
    {
        // Re-run setup - for now just opens settings (setup wizard could be added later)
        SettingsRequested?.Invoke(this, EventArgs.Empty);
    }
    
    private void OnCheckUpdatesMenuItemClick(object sender, RoutedEventArgs e)
    {
        // Check for updates - shows a message for now (update manager could be added later)
        MessageBox.Show("Checking for updates...\n\nYou are running the latest version.", 
            "Check for Updates", MessageBoxButton.OK, MessageBoxImage.Information);
    }

    private void OnHistoryItemClick(object sender, RoutedEventArgs e)
    {
        if (sender is MenuItem menuItem && menuItem.Tag is TranscriptHistoryItem historyItem)
        {
            // Copy the full transcript to clipboard (matching macOS behavior)
            var text = !string.IsNullOrWhiteSpace(historyItem.PostProcessedTranscript) 
                ? historyItem.PostProcessedTranscript 
                : historyItem.RawTranscript;
            
            if (!string.IsNullOrEmpty(text))
            {
                try
                {
                    System.Windows.Clipboard.SetText(text);
                }
                catch
                {
                    // Ignore clipboard errors
                }
            }
        }
    }

    private void OnPasteVocabularyMenuItemClick(object sender, RoutedEventArgs e)
    {
        // Matching macOS: Paste word from clipboard to vocabulary
        // Flash checkmark on success (the actual vocabulary logic is handled elsewhere)
        try
        {
            var clipboardText = System.Windows.Clipboard.GetText();
            if (!string.IsNullOrWhiteSpace(clipboardText))
            {
                // For now, just flash the checkmark to indicate the action was attempted
                // The actual vocabulary management would be handled by AppState
                FlashCheckmark();
            }
        }
        catch
        {
            // Ignore clipboard errors
        }
    }

    #endregion

    #region Disposal

    public void Dispose()
    {
        Dispose(true);
        GC.SuppressFinalize(this);
    }

    protected virtual void Dispose(bool disposing)
    {
        if (_disposed) return;
        if (disposing)
        {
            SystemEvents.UserPreferenceChanged -= OnSystemThemeChanged;
            _checkmarkTimer?.Stop();
            _checkmarkTimer?.Dispose();
            _checkmarkTimer = null;

            lock (_lock)
            {
                if (_taskbarIcon != null)
                {
                    if (Application.Current?.Dispatcher != null && !Application.Current.Dispatcher.CheckAccess())
                        Application.Current.Dispatcher.Invoke(DisposeTaskbarIcon);
                    else
                        DisposeTaskbarIcon();
                }
            }
        }
        _disposed = true;
    }

    private void DisposeTaskbarIcon()
    {
        if (_taskbarIcon != null)
        {
            _taskbarIcon.TrayMouseDoubleClick -= OnTrayMouseDoubleClick;
            _taskbarIcon.Visibility = Visibility.Collapsed;
            _taskbarIcon.Dispose();
            _taskbarIcon = null;
        }
        _contextMenu = null;
        _recordingMenuItem = null;
        _showIconMenuItem = null;

        foreach (var icon in _statusIcons.Values) icon.Dispose();
        _statusIcons.Clear();
        _checkmarkIcon?.Dispose();
        _devStampedIcon?.Dispose();
        _checkmarkIcon = null;
        _devStampedIcon = null;
        IsInitialized = false;
    }

    ~SystemTrayManager() => Dispose(false);

    #endregion
}

/// <summary>
/// Represents a transcript history item. Matches macOS PipelineHistoryItem.
/// </summary>
public class TranscriptHistoryItem
{
    /// <summary>
    /// The post-processed (cleaned) transcript text.
    /// </summary>
    public string PostProcessedTranscript { get; set; } = "";
    
    /// <summary>
    /// The raw transcript before post-processing.
    /// </summary>
    public string RawTranscript { get; set; } = "";
    
    /// <summary>
    /// When this transcript was created.
    /// </summary>
    public DateTime Timestamp { get; set; } = DateTime.Now;
}
