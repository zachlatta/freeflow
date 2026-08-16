using System.Windows;
using Microsoft.Extensions.DependencyInjection;
using FreeFlowWindows.Core.Interfaces;
using FreeFlowWindows.Core.Services;
using FreeFlowWindows.App.Services;
using FreeFlowWindows.App.Windows;

namespace FreeFlowWindows.App;

/// <summary>
/// Application entry point for FreeFlow Windows.
/// Configures dependency injection and initializes core services.
/// Requirements: 1.1, 1.6 - Application lifecycle and tray integration
/// </summary>
public partial class App : Application
{
    private IServiceProvider? _serviceProvider;
    private IApplicationLifecycle? _lifecycle;
    private RecordingIndicator? _recordingIndicator;
    private AppState? _appState;

    /// <summary>
    /// Gets the service provider for dependency injection.
    /// </summary>
    public static IServiceProvider Services => ((App)Current)._serviceProvider!;

    protected override async void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);

        try
        {
            // Configure dependency injection
            var services = new ServiceCollection();
            ConfigureServices(services);
            _serviceProvider = services.BuildServiceProvider();

            // Get lifecycle manager and initialize
            _lifecycle = _serviceProvider.GetRequiredService<IApplicationLifecycle>();
            await _lifecycle.InitializeAsync();

            // Create AppState to track pipeline state
            var orchestrator = _serviceProvider.GetRequiredService<IPipelineOrchestrator>();
            var settingsManager = _serviceProvider.GetRequiredService<ISettingsManager>();
            _appState = new AppState(orchestrator, settingsManager);
            
            // Create and wire up the recording indicator
            _recordingIndicator = new RecordingIndicator();
            _appState.ShowRecordingIndicator += OnShowRecordingIndicator;
            _appState.HideRecordingIndicator += OnHideRecordingIndicator;
            _appState.ErrorOccurred += OnErrorOccurred;
            
            // Wire up audio level changes
            orchestrator.AudioLevelChanged += (s, args) =>
            {
                Dispatcher.Invoke(() => _recordingIndicator?.UpdateAudioLevel(args.Level));
            };
            
            // Wire up error events to show in the indicator
            orchestrator.Error += (s, args) =>
            {
                Dispatcher.Invoke(() => _recordingIndicator?.ShowError(args.Message, TimeSpan.FromSeconds(4)));
            };
            
            // Wire up completion to dismiss the indicator
            orchestrator.Completed += (s, args) =>
            {
                Dispatcher.Invoke(() => _recordingIndicator?.Dismiss());
            };

            // Wire up hotkey events to pipeline
            var hotkeyManager = _serviceProvider.GetRequiredService<IHotkeyManager>();
            // Hold mode: start on press, stop on release
            // Wrapped in try/catch to prevent async void from crashing the app
            hotkeyManager.HoldHotkeyPressed += async (s, args) =>
            {
                try
                {
                    if (!orchestrator.IsActive)
                    {
                        var settings = settingsManager.Load();
                        await orchestrator.StartAsync(Core.Models.RecordingMode.Hold, settings.SelectedMicrophoneId);
                    }
                }
                catch (Exception ex)
                {
                    System.Diagnostics.Debug.WriteLine($"HoldHotkeyPressed error: {ex.Message}");
                }
            };

            hotkeyManager.HoldHotkeyReleased += async (s, args) =>
            {
                try
                {
                    if (orchestrator.IsActive)
                    {
                        await orchestrator.StopAsync();
                    }
                }
                catch (Exception ex)
                {
                    System.Diagnostics.Debug.WriteLine($"HoldHotkeyReleased error: {ex.Message}");
                }
            };

            // Toggle mode: toggle recording on/off
            // Wrapped in try/catch to prevent async void from crashing the app
            hotkeyManager.ToggleHotkeyPressed += async (s, args) =>
            {
                try
                {
                    if (orchestrator.IsActive)
                    {
                        await orchestrator.StopAsync();
                    }
                    else
                    {
                        var settings = settingsManager.Load();
                        await orchestrator.StartAsync(Core.Models.RecordingMode.Toggle, settings.SelectedMicrophoneId);
                    }
                }
                catch (Exception ex)
                {
                    System.Diagnostics.Debug.WriteLine($"ToggleHotkeyPressed error: {ex.Message}");
                }
            };

            // Wire up system tray settings request to open settings window
            var trayManager = _serviceProvider.GetRequiredService<ISystemTrayManager>();
            trayManager.SettingsRequested += (s, args) =>
            {
                ShowSettingsWindow();
            };
            
            // Wire up Paste Again from tray menu
            trayManager.PasteAgainRequested += async (s, args) =>
            {
                var clipboardManager = _serviceProvider.GetRequiredService<IClipboardManager>();
                await clipboardManager.PasteLastTranscriptAsync();
            };

            // Check if first launch - open settings if API key not configured
            var settings = settingsManager.Load();
            var credentialStore = _serviceProvider.GetRequiredService<ICredentialStore>();
            var apiKey = credentialStore.GetApiKey("api_key");
            
            if (string.IsNullOrWhiteSpace(apiKey))
            {
                ShowSettingsWindow();
            }
        }
        catch (Exception ex)
        {
            MessageBox.Show(
                $"Failed to start FreeFlow: {ex.Message}",
                "FreeFlow Error",
                MessageBoxButton.OK,
                MessageBoxImage.Error);
            Shutdown(1);
        }
    }

    private void OnShowRecordingIndicator(object? sender, RecordingIndicatorEventArgs e)
    {
        Dispatcher.Invoke(() =>
        {
            if (_recordingIndicator == null) return;
            
            switch (e.State)
            {
                case Core.Models.PipelineState.Initializing:
                    _recordingIndicator.ShowInitializing(e.Mode);
                    break;
                case Core.Models.PipelineState.Recording:
                    _recordingIndicator.ShowRecording(e.Mode);
                    break;
                case Core.Models.PipelineState.Transcribing:
                case Core.Models.PipelineState.PostProcessing:
                case Core.Models.PipelineState.Pasting:
                    _recordingIndicator.ShowProcessing();
                    break;
            }
        });
    }

    private void OnHideRecordingIndicator(object? sender, EventArgs e)
    {
        Dispatcher.Invoke(() =>
        {
            _recordingIndicator?.Dismiss();
        });
    }

    private void OnErrorOccurred(object? sender, ErrorEventArgs e)
    {
        Dispatcher.Invoke(() =>
        {
            _recordingIndicator?.ShowError(e.Message, TimeSpan.FromSeconds(4));
        });
    }

    private void ConfigureServices(IServiceCollection services)
    {
        // Core services
        services.AddSingleton<ISettingsManager, SettingsManager>();
        services.AddSingleton<ICredentialStore, CredentialStore>();
        services.AddSingleton<IStartupManager, StartupManager>();

        // Audio services
        services.AddSingleton<IAudioRecorder, AudioRecorder>();

        // API services - use factories to allow settings/API key changes without restart
        services.AddSingleton<ITranscriptionService, TranscriptionServiceFactory>();
        services.AddSingleton<IPostProcessingService, PostProcessingServiceFactory>();

        // Input services
        services.AddSingleton<IClipboardManager, ClipboardManager>();
        services.AddSingleton<IHotkeyManager, WpfHotkeyManager>();

        // UI services
        services.AddSingleton<ISystemTrayManager, SystemTrayManager>();
        services.AddSingleton<IToastNotificationService, ToastNotificationService>();

        // Pipeline orchestrator
        services.AddSingleton<IPipelineOrchestrator, PipelineOrchestrator>();

        // Lifecycle manager
        services.AddSingleton<IApplicationLifecycle, ApplicationLifecycle>();

        // View models
        services.AddTransient<ViewModels.SettingsViewModel>();
        services.AddTransient<ViewModels.RecordingIndicatorViewModel>();
    }

    /// <summary>
    /// Shows the settings window.
    /// </summary>
    public void ShowSettingsWindow()
    {
        // Check if settings window is already open
        foreach (Window window in Windows)
        {
            if (window is SettingsWindow existingWindow)
            {
                existingWindow.Activate();
                return;
            }
        }

        // Create and show new settings window using proper constructor with dependencies
        var serviceProvider = _serviceProvider!;
        var settingsManager = serviceProvider.GetRequiredService<ISettingsManager>();
        var credentialStore = serviceProvider.GetRequiredService<ICredentialStore>();
        var audioRecorder = serviceProvider.GetRequiredService<IAudioRecorder>();
        
        var settingsWindow = new SettingsWindow(settingsManager, credentialStore, audioRecorder);
        settingsWindow.Closed += OnSettingsWindowClosed;
        settingsWindow.Show();
    }
    
    private void OnSettingsWindowClosed(object? sender, EventArgs e)
    {
        if (sender is SettingsWindow window)
        {
            window.Closed -= OnSettingsWindowClosed;
            
            // Re-register hotkeys on the UI thread to ensure ComponentDispatcher works correctly
            Dispatcher.BeginInvoke(() =>
            {
                try
                {
                    var hotkeyManager = _serviceProvider?.GetRequiredService<IHotkeyManager>();
                    var settingsManager = _serviceProvider?.GetRequiredService<ISettingsManager>();
                    if (hotkeyManager != null && settingsManager != null)
                    {
                        var settings = settingsManager.Load();
                        var config = new Core.Models.HotkeyConfiguration
                        {
                            HoldHotkey = settings.HoldHotkey,
                            ToggleHotkey = settings.ToggleHotkey,
                            PasteAgainHotkey = null
                        };
                        hotkeyManager.RegisterHotkeys(config);
                    }
                }
                catch (Exception ex)
                {
                    System.Diagnostics.Debug.WriteLine($"OnSettingsWindowClosed error: {ex.Message}");
                }
            });
        }
    }

    protected override void OnSessionEnding(SessionEndingCancelEventArgs e)
    {
        base.OnSessionEnding(e);

        // Handle Windows shutdown/logout
        _lifecycle?.HandleSessionEnding(e.ReasonSessionEnding == ReasonSessionEnding.Logoff);
    }

    protected override async void OnExit(ExitEventArgs e)
    {
        // Clean up recording indicator
        if (_appState != null)
        {
            _appState.ShowRecordingIndicator -= OnShowRecordingIndicator;
            _appState.HideRecordingIndicator -= OnHideRecordingIndicator;
            _appState.ErrorOccurred -= OnErrorOccurred;
            _appState.Dispose();
        }
        _recordingIndicator?.CloseAndDispose();

        // Perform graceful shutdown
        if (_lifecycle != null)
        {
            try
            {
                using var cts = new CancellationTokenSource(TimeSpan.FromSeconds(5));
                await _lifecycle.ShutdownAsync(cts.Token);
            }
            catch
            {
                // Best effort shutdown
            }
        }

        // Dispose service provider
        if (_serviceProvider is IDisposable disposable)
        {
            disposable.Dispose();
        }

        base.OnExit(e);
    }
}
