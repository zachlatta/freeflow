using System.Globalization;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Data;
using System.Windows.Input;
using FreeFlowWindows.App.ViewModels;
using FreeFlowWindows.Core.Interfaces;
using FreeFlowWindows.Core.Models;
using CoreModifierKeys = FreeFlowWindows.Core.Models.ModifierKeys;

namespace FreeFlowWindows.App.Windows;

/// <summary>
/// Settings window for configuring FreeFlow application settings.
/// Matches macOS SettingsView.swift UI exactly with 5 tabs:
/// General, Prompts, Macros, Run Log, Debug
/// </summary>
public partial class SettingsWindow : Window
{
    private readonly SettingsViewModel _viewModel;
    private readonly ISettingsManager _settingsManager;
    private bool _isRecordingHotkey;
    private HotkeyType _recordingHotkeyType;

    public SettingsWindow(
        ISettingsManager settingsManager,
        ICredentialStore credentialStore,
        IAudioRecorder? audioRecorder = null)
    {
        InitializeComponent();

        _settingsManager = settingsManager;
        _viewModel = new SettingsViewModel(settingsManager, credentialStore, audioRecorder);
        DataContext = _viewModel;

        _viewModel.RequestClose += OnRequestClose;
        _viewModel.RequestHotkeyRecording += OnRequestHotkeyRecording;
        _viewModel.SettingsApplied += OnSettingsApplied;

        Loaded += OnLoaded;
    }

    /// <summary>
    /// Design-time constructor. Do not use at runtime.
    /// </summary>
    public SettingsWindow()
    {
        InitializeComponent();
        _settingsManager = null!; // Design-time only
        _viewModel = new SettingsViewModel();
        DataContext = _viewModel;
    }

    private void OnLoaded(object sender, RoutedEventArgs e)
    {
        if (!string.IsNullOrEmpty(_viewModel.ApiKey))
            ApiKeyBox.Password = _viewModel.ApiKey;
        
        UpdateBuildInfo();
        
        // Ensure General tab is selected and visible on load
        TabGeneral.IsChecked = true;
        ShowTab("General");
    }
    
    /// <summary>
    /// Handles tab switching when sidebar radio buttons are clicked.
    /// </summary>
    private void Tab_Checked(object sender, RoutedEventArgs e)
    {
        if (sender is RadioButton rb)
        {
            var tabName = rb.Name.Replace("Tab", "");
            ShowTab(tabName);
        }
    }
    
    /// <summary>
    /// Shows the specified tab and hides all others.
    /// </summary>
    private void ShowTab(string tabName)
    {
        // Hide all tabs
        if (GeneralTab != null) GeneralTab.Visibility = Visibility.Collapsed;
        if (PromptsTab != null) PromptsTab.Visibility = Visibility.Collapsed;
        if (MacrosTab != null) MacrosTab.Visibility = Visibility.Collapsed;
        if (RunLogTab != null) RunLogTab.Visibility = Visibility.Collapsed;
        if (DebugTab != null) DebugTab.Visibility = Visibility.Collapsed;
        
        // Show the selected tab
        switch (tabName)
        {
            case "General":
                if (GeneralTab != null) GeneralTab.Visibility = Visibility.Visible;
                break;
            case "Prompts":
                if (PromptsTab != null) PromptsTab.Visibility = Visibility.Visible;
                break;
            case "Macros":
                if (MacrosTab != null) MacrosTab.Visibility = Visibility.Visible;
                break;
            case "RunLog":
                if (RunLogTab != null) RunLogTab.Visibility = Visibility.Visible;
                break;
            case "Debug":
                if (DebugTab != null) DebugTab.Visibility = Visibility.Visible;
                break;
        }
    }

    private void UpdateBuildInfo()
    {
        var version = System.Reflection.Assembly.GetExecutingAssembly().GetName().Version?.ToString() ?? "1.0.0";
        var os = Environment.OSVersion;
        BuildInfoText.Text = $"FreeFlow {version}\nWindows {os.Version.Major}.{os.Version.Minor} ({(Environment.Is64BitOperatingSystem ? "x64" : "x86")})";
    }

    private void OnRequestClose(object? sender, bool saved)
    {
        DialogResult = saved;
        Close();
    }

    private void OnSettingsApplied(object? sender, EventArgs e)
    {
        // Re-register hotkeys immediately when settings are changed
        var logPath = System.IO.Path.Combine(System.IO.Path.GetTempPath(), "freeflow_debug.log");
        System.IO.File.AppendAllText(logPath, $"\n[{DateTime.Now:HH:mm:ss}] OnSettingsApplied - re-registering hotkeys immediately\n");
        
        // Get the hotkey manager from the App's service provider
        var hotkeyManager = App.Services.GetService(typeof(IHotkeyManager)) as IHotkeyManager;
        if (hotkeyManager != null)
        {
            var settings = _settingsManager.Load();
            System.IO.File.AppendAllText(logPath, $"  Loaded HoldHotkey: {settings.HoldHotkey}\n");
            System.IO.File.AppendAllText(logPath, $"  Loaded ToggleHotkey: {settings.ToggleHotkey}\n");
            
            var config = new HotkeyConfiguration
            {
                HoldHotkey = settings.HoldHotkey,
                ToggleHotkey = settings.ToggleHotkey,
                PasteAgainHotkey = null
            };
            
            var result = hotkeyManager.RegisterHotkeys(config);
            System.IO.File.AppendAllText(logPath, $"  RegisterHotkeys result: {result}\n");
            System.IO.File.AppendAllText(logPath, $"  Hotkeys now active immediately!\n");
        }
        else
        {
            System.IO.File.AppendAllText(logPath, $"  ERROR: Could not get IHotkeyManager\n");
        }
    }

    private void OnRequestHotkeyRecording(object? sender, HotkeyRecordingEventArgs e)
    {
        _isRecordingHotkey = true;
        _recordingHotkeyType = e.HotkeyType;

        if (e.HotkeyType == HotkeyType.Hold)
            _viewModel.HoldHotkeyDisplay = "Press keys...";
        else
            _viewModel.ToggleHotkeyDisplay = "Press keys...";

        Activate();
        Focus();
    }

    protected override void OnPreviewKeyDown(KeyEventArgs e)
    {
        base.OnPreviewKeyDown(e);

        if (!_isRecordingHotkey) return;

        if (e.Key == Key.LeftCtrl || e.Key == Key.RightCtrl ||
            e.Key == Key.LeftAlt || e.Key == Key.RightAlt ||
            e.Key == Key.LeftShift || e.Key == Key.RightShift ||
            e.Key == Key.LWin || e.Key == Key.RWin || e.Key == Key.System)
            return;

        if (e.Key == Key.Escape)
        {
            CancelHotkeyRecording();
            e.Handled = true;
            return;
        }

        var modifiers = CoreModifierKeys.None;
        if (Keyboard.IsKeyDown(Key.LeftCtrl) || Keyboard.IsKeyDown(Key.RightCtrl))
            modifiers |= CoreModifierKeys.Ctrl;
        if (Keyboard.IsKeyDown(Key.LeftAlt) || Keyboard.IsKeyDown(Key.RightAlt))
            modifiers |= CoreModifierKeys.Alt;
        if (Keyboard.IsKeyDown(Key.LeftShift) || Keyboard.IsKeyDown(Key.RightShift))
            modifiers |= CoreModifierKeys.Shift;
        if (Keyboard.IsKeyDown(Key.LWin) || Keyboard.IsKeyDown(Key.RWin))
            modifiers |= CoreModifierKeys.Win;

        if (modifiers == CoreModifierKeys.None)
        {
            if (_recordingHotkeyType == HotkeyType.Hold)
                _viewModel.HoldHotkeyDisplay = "Need modifier!";
            else
                _viewModel.ToggleHotkeyDisplay = "Need modifier!";
            e.Handled = true;
            return;
        }

        var virtualKey = ConvertToVirtualKey(e.Key);
        if (virtualKey == null)
        {
            if (_recordingHotkeyType == HotkeyType.Hold)
                _viewModel.HoldHotkeyDisplay = "Invalid key!";
            else
                _viewModel.ToggleHotkeyDisplay = "Invalid key!";
            e.Handled = true;
            return;
        }

        var binding = new HotkeyBinding { Modifiers = modifiers, Key = virtualKey.Value };
        _viewModel.SetRecordedHotkey(_recordingHotkeyType, binding);
        _isRecordingHotkey = false;
        e.Handled = true;
    }

    private void CancelHotkeyRecording()
    {
        if (!_isRecordingHotkey) return;
        _isRecordingHotkey = false;
        if (_recordingHotkeyType == HotkeyType.Hold)
            _viewModel.HoldHotkeyDisplay = _viewModel.HoldHotkey.ToString();
        else
            _viewModel.ToggleHotkeyDisplay = _viewModel.ToggleHotkey.ToString();
    }

    private void ApiKeyBox_PasswordChanged(object sender, RoutedEventArgs e)
    {
        if (DataContext is SettingsViewModel vm)
            vm.ApiKey = ApiKeyBox.Password;
    }

    private void SaveApiKeyButton_Click(object sender, RoutedEventArgs e)
    {
        var logPath = System.IO.Path.Combine(System.IO.Path.GetTempPath(), "freeflow_debug.log");
        System.IO.File.AppendAllText(logPath, $"\n[{DateTime.Now:HH:mm:ss}] SaveApiKeyButton_Click\n");
        System.IO.File.AppendAllText(logPath, $"  HasUnsavedChanges: {_viewModel.HasUnsavedChanges}\n");
        System.IO.File.AppendAllText(logPath, $"  HasValidationError: {_viewModel.HasValidationError}\n");
        System.IO.File.AppendAllText(logPath, $"  CanExecute: {_viewModel.SaveCommand.CanExecute(null)}\n");
        System.IO.File.AppendAllText(logPath, $"  HoldHotkey: {_viewModel.HoldHotkey}\n");
        System.IO.File.AppendAllText(logPath, $"  ToggleHotkey: {_viewModel.ToggleHotkey}\n");
        
        if (_viewModel.SaveCommand.CanExecute(null))
            _viewModel.SaveCommand.Execute(null);
        else
            System.IO.File.AppendAllText(logPath, $"  CANNOT SAVE - command disabled\n");
    }

    private void StartDelaySlider_ValueChanged(object sender, RoutedPropertyChangedEventArgs<double> e)
    {
        if (DelayValueText != null)
            DelayValueText.Text = $"{(int)e.NewValue} ms";
    }

    private void VolumeSlider_ValueChanged(object sender, RoutedPropertyChangedEventArgs<double> e)
    {
        if (VolumeValueText != null)
            VolumeValueText.Text = $"{(int)e.NewValue}%";
    }

    private void CopyBuildInfoButton_Click(object sender, RoutedEventArgs e)
    {
        Clipboard.SetText(BuildInfoText.Text);
        CopyBuildInfoButton.Content = "Copied!";
        var timer = new System.Windows.Threading.DispatcherTimer { Interval = TimeSpan.FromSeconds(1.5) };
        timer.Tick += (s, args) => { CopyBuildInfoButton.Content = "Copy"; timer.Stop(); };
        timer.Start();
    }

    private void MicrophoneItem_Click(object sender, System.Windows.Input.MouseButtonEventArgs e)
    {
        if (sender is Border border && border.DataContext is AudioDevice device)
            _viewModel.SelectedMicrophoneId = device.Id;
    }
    
    private void CheckUpdatesButton_Click(object sender, RoutedEventArgs e)
    {
        // TODO: Implement update check
        MessageBox.Show("Checking for updates...\n\nYou are running the latest version.", "Check for Updates", MessageBoxButton.OK, MessageBoxImage.Information);
    }
    
    private void PreviewSoundButton_Click(object sender, RoutedEventArgs e)
    {
        // Play a system sound as preview
        System.Media.SystemSounds.Asterisk.Play();
    }
    
    private void DebugOverlayButton_Click(object sender, RoutedEventArgs e)
    {
        // TODO: Show debug overlay
        MessageBox.Show("Debug overlay feature coming soon.", "Debug Overlay", MessageBoxButton.OK, MessageBoxImage.Information);
    }
    
    private void ShowUpdateOverlayButton_Click(object sender, RoutedEventArgs e)
    {
        // TODO: Show update overlay
        MessageBox.Show("Update overlay feature coming soon.", "Update Overlay", MessageBoxButton.OK, MessageBoxImage.Information);
    }
    
    private void OpenDebugLogButton_Click(object sender, RoutedEventArgs e)
    {
        var logPath = System.IO.Path.Combine(System.IO.Path.GetTempPath(), "freeflow_debug.log");
        if (System.IO.File.Exists(logPath))
        {
            System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo
            {
                FileName = logPath,
                UseShellExecute = true
            });
        }
        else
        {
            MessageBox.Show($"Debug log not found at:\n{logPath}", "Debug Log", MessageBoxButton.OK, MessageBoxImage.Information);
        }
    }
    
    private void ClearDebugLogButton_Click(object sender, RoutedEventArgs e)
    {
        var logPath = System.IO.Path.Combine(System.IO.Path.GetTempPath(), "freeflow_debug.log");
        try
        {
            if (System.IO.File.Exists(logPath))
            {
                System.IO.File.WriteAllText(logPath, string.Empty);
                MessageBox.Show("Debug log cleared.", "Debug Log", MessageBoxButton.OK, MessageBoxImage.Information);
            }
            else
            {
                MessageBox.Show("Debug log file does not exist.", "Debug Log", MessageBoxButton.OK, MessageBoxImage.Information);
            }
        }
        catch (Exception ex)
        {
            MessageBox.Show($"Failed to clear debug log:\n{ex.Message}", "Error", MessageBoxButton.OK, MessageBoxImage.Error);
        }
    }
    
    private void AddMacroButton_Click(object sender, RoutedEventArgs e)
    {
        // TODO: Show macro editor dialog
        MessageBox.Show("Voice macro editor coming soon.\n\nThis feature will let you define voice commands that instantly paste predefined text.", "Add Macro", MessageBoxButton.OK, MessageBoxImage.Information);
    }
    
    private void ClearHistoryButton_Click(object sender, RoutedEventArgs e)
    {
        var result = MessageBox.Show("Clear all run history?", "Clear History", MessageBoxButton.YesNo, MessageBoxImage.Question);
        if (result == MessageBoxResult.Yes)
        {
            // TODO: Clear run log history
            MessageBox.Show("Run history cleared.", "Clear History", MessageBoxButton.OK, MessageBoxImage.Information);
        }
    }

    private static VirtualKey? ConvertToVirtualKey(Key key) => key switch
    {
        Key.A => VirtualKey.A, Key.B => VirtualKey.B, Key.C => VirtualKey.C, Key.D => VirtualKey.D,
        Key.E => VirtualKey.E, Key.F => VirtualKey.F, Key.G => VirtualKey.G, Key.H => VirtualKey.H,
        Key.I => VirtualKey.I, Key.J => VirtualKey.J, Key.K => VirtualKey.K, Key.L => VirtualKey.L,
        Key.M => VirtualKey.M, Key.N => VirtualKey.N, Key.O => VirtualKey.O, Key.P => VirtualKey.P,
        Key.Q => VirtualKey.Q, Key.R => VirtualKey.R, Key.S => VirtualKey.S, Key.T => VirtualKey.T,
        Key.U => VirtualKey.U, Key.V => VirtualKey.V, Key.W => VirtualKey.W, Key.X => VirtualKey.X,
        Key.Y => VirtualKey.Y, Key.Z => VirtualKey.Z,
        Key.D0 => VirtualKey.D0, Key.D1 => VirtualKey.D1, Key.D2 => VirtualKey.D2, Key.D3 => VirtualKey.D3,
        Key.D4 => VirtualKey.D4, Key.D5 => VirtualKey.D5, Key.D6 => VirtualKey.D6, Key.D7 => VirtualKey.D7,
        Key.D8 => VirtualKey.D8, Key.D9 => VirtualKey.D9,
        Key.F1 => VirtualKey.F1, Key.F2 => VirtualKey.F2, Key.F3 => VirtualKey.F3, Key.F4 => VirtualKey.F4,
        Key.F5 => VirtualKey.F5, Key.F6 => VirtualKey.F6, Key.F7 => VirtualKey.F7, Key.F8 => VirtualKey.F8,
        Key.F9 => VirtualKey.F9, Key.F10 => VirtualKey.F10, Key.F11 => VirtualKey.F11, Key.F12 => VirtualKey.F12,
        Key.Space => VirtualKey.Space, Key.Enter => VirtualKey.Enter, Key.Tab => VirtualKey.Tab,
        Key.Escape => VirtualKey.Escape, Key.Back => VirtualKey.Backspace, Key.Delete => VirtualKey.Delete,
        Key.Insert => VirtualKey.Insert, Key.Home => VirtualKey.Home, Key.End => VirtualKey.End,
        Key.PageUp => VirtualKey.PageUp, Key.PageDown => VirtualKey.PageDown,
        Key.Left => VirtualKey.Left, Key.Up => VirtualKey.Up, Key.Right => VirtualKey.Right, Key.Down => VirtualKey.Down,
        Key.NumPad0 => VirtualKey.NumPad0, Key.NumPad1 => VirtualKey.NumPad1, Key.NumPad2 => VirtualKey.NumPad2,
        Key.NumPad3 => VirtualKey.NumPad3, Key.NumPad4 => VirtualKey.NumPad4, Key.NumPad5 => VirtualKey.NumPad5,
        Key.NumPad6 => VirtualKey.NumPad6, Key.NumPad7 => VirtualKey.NumPad7, Key.NumPad8 => VirtualKey.NumPad8,
        Key.NumPad9 => VirtualKey.NumPad9,
        Key.Multiply => VirtualKey.Multiply, Key.Add => VirtualKey.Add, Key.Subtract => VirtualKey.Subtract,
        Key.Decimal => VirtualKey.Decimal, Key.Divide => VirtualKey.Divide,
        Key.OemSemicolon => VirtualKey.OemSemicolon, Key.OemPlus => VirtualKey.OemPlus,
        Key.OemComma => VirtualKey.OemComma, Key.OemMinus => VirtualKey.OemMinus,
        Key.OemPeriod => VirtualKey.OemPeriod, Key.OemQuestion => VirtualKey.OemQuestion,
        Key.OemTilde => VirtualKey.OemTilde, Key.OemOpenBrackets => VirtualKey.OemOpenBrackets,
        Key.OemPipe => VirtualKey.OemPipe, Key.OemCloseBrackets => VirtualKey.OemCloseBrackets,
        Key.OemQuotes => VirtualKey.OemQuotes, Key.OemBackslash => VirtualKey.OemBackslash,
        _ => null
    };

    protected override void OnClosing(System.ComponentModel.CancelEventArgs e)
    {
        base.OnClosing(e);
        if (_viewModel.HasUnsavedChanges)
        {
            var result = MessageBox.Show("Save changes before closing?", "Unsaved Changes",
                MessageBoxButton.YesNoCancel, MessageBoxImage.Question);
            switch (result)
            {
                case MessageBoxResult.Yes:
                    if (_viewModel.SaveCommand.CanExecute(null)) _viewModel.SaveCommand.Execute(null);
                    else e.Cancel = true;
                    break;
                case MessageBoxResult.Cancel:
                    e.Cancel = true;
                    break;
            }
        }
        
        if (!e.Cancel)
        {
            _viewModel.RequestClose -= OnRequestClose;
            _viewModel.RequestHotkeyRecording -= OnRequestHotkeyRecording;
            _viewModel.SettingsApplied -= OnSettingsApplied;
            _viewModel.Dispose();
        }
    }
}

public class BooleanToVisibilityConverter : IValueConverter
{
    public object Convert(object value, Type targetType, object parameter, CultureInfo culture)
        => value is bool b && b ? Visibility.Visible : Visibility.Collapsed;
    public object ConvertBack(object value, Type targetType, object parameter, CultureInfo culture)
        => value is Visibility v && v == Visibility.Visible;
}
