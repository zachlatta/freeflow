using System.ComponentModel;
using System.Globalization;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Data;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media.Animation;
using System.Windows.Threading;
using FreeFlowWindows.App.ViewModels;
using FreeFlowWindows.Core.Interfaces;
using FreeFlowWindows.Core.Models;

namespace FreeFlowWindows.App.Windows;

/// <summary>
/// Recording indicator overlay window that displays recording status, audio levels,
/// and elapsed time. Matches macOS RecordingOverlayView design exactly.
/// </summary>
public partial class RecordingIndicator : Window, IRecordingIndicator, IDisposable
{
    private readonly RecordingIndicatorViewModel _viewModel;
    private readonly DispatcherTimer _errorDismissTimer;
    private Storyboard? _initializingStoryboard;
    private Storyboard? _processingStoryboard;
    private bool _isDragging;
    private Point _dragStartPoint;
    private Point _windowStartPosition;
    private bool _disposed;

    // Toggle mode width (with stop button) - macOS uses 150
    private const double ToggleModeWidth = 150;
    // Default width (hold mode) - macOS uses 92
    private const double DefaultWidth = 92;

    #region Win32 Interop for Non-Activating Window

    private const int GWL_EXSTYLE = -20;
    private const int WS_EX_NOACTIVATE = 0x08000000;
    private const int WS_EX_TOOLWINDOW = 0x00000080;

    [DllImport("user32.dll")]
    private static extern int GetWindowLong(IntPtr hWnd, int nIndex);

    [DllImport("user32.dll")]
    private static extern int SetWindowLong(IntPtr hWnd, int nIndex, int dwNewLong);

    #endregion

    /// <summary>
    /// Event raised when the user clicks on the indicator to cancel the operation.
    /// </summary>
    public event EventHandler? CancelRequested;

    /// <summary>
    /// Creates a new RecordingIndicator window.
    /// </summary>
    public RecordingIndicator()
    {
        InitializeComponent();

        _viewModel = new RecordingIndicatorViewModel();
        DataContext = _viewModel;

        // Subscribe to ViewModel events
        _viewModel.CancelRequested += OnViewModelCancelRequested;
        _viewModel.PropertyChanged += OnViewModelPropertyChanged;

        // Set up error dismiss timer
        _errorDismissTimer = new DispatcherTimer
        {
            Interval = TimeSpan.FromSeconds(3)
        };
        _errorDismissTimer.Tick += OnErrorDismissTimerTick;

        // Position the window
        PositionWindow();

        // Wire up loaded event to set up window styles
        Loaded += OnLoaded;
        Closing += OnClosing;
    }

    #region IRecordingIndicator Implementation

    /// <inheritdoc/>
    public void ShowInitializing(RecordingMode mode)
    {
        Dispatcher.Invoke(() =>
        {
            _viewModel.ShowInitializing(mode);
            UpdateWindowWidth(mode);
            PositionWindow();
            Show();
            StartInitializingAnimation();
        });
    }

    /// <inheritdoc/>
    public void ShowRecording(RecordingMode mode)
    {
        Dispatcher.Invoke(() =>
        {
            StopAnimations();
            _viewModel.ShowRecording(mode);
            UpdateWindowWidth(mode);
            if (!IsVisible)
            {
                PositionWindow();
                Show();
            }
        });
    }

    /// <inheritdoc/>
    public void ShowProcessing()
    {
        Dispatcher.Invoke(() =>
        {
            StopAnimations();
            _viewModel.ShowProcessing();
            // Keep same width during processing (don't shrink)
            if (!IsVisible)
            {
                PositionWindow();
                Show();
            }
            StartProcessingAnimation();
        });
    }

    /// <inheritdoc/>
    public void ShowError(string message, TimeSpan duration)
    {
        Dispatcher.Invoke(() =>
        {
            StopAnimations();
            _viewModel.ShowError(message);
            if (!IsVisible)
            {
                PositionWindow();
                Show();
            }

            // Start the error dismiss timer
            _errorDismissTimer.Stop();
            if (duration > TimeSpan.Zero)
            {
                _errorDismissTimer.Interval = duration;
                _errorDismissTimer.Start();
            }
        });
    }

    /// <inheritdoc/>
    public void UpdateAudioLevel(float level)
    {
        Dispatcher.Invoke(() =>
        {
            _viewModel.AudioLevel = level;
        });
    }

    /// <inheritdoc/>
    public void UpdateElapsedTime(TimeSpan elapsed)
    {
        Dispatcher.Invoke(() =>
        {
            _viewModel.ElapsedTime = elapsed;
        });
    }

    /// <inheritdoc/>
    public void Dismiss()
    {
        Dispatcher.Invoke(() =>
        {
            StopAnimations();
            _errorDismissTimer.Stop();
            _viewModel.Hide();
            Hide();
        });
    }

    #endregion

    #region Event Handlers

    private void OnLoaded(object sender, RoutedEventArgs e)
    {
        // Make the window non-activating so it doesn't steal focus
        MakeWindowNonActivating();

        // Get animation storyboards
        _initializingStoryboard = Resources["InitializingAnimation"] as Storyboard;
        _processingStoryboard = Resources["ProcessingAnimation"] as Storyboard;
    }

    private void OnClosing(object? sender, CancelEventArgs e)
    {
        // Prevent closing, just hide instead (unless we're disposing)
        if (!_disposed)
        {
            e.Cancel = true;
            Dismiss();
        }
    }

    /// <summary>
    /// Actually closes the window and disposes resources. Call this instead of Close() when shutting down.
    /// </summary>
    public void CloseAndDispose()
    {
        Dispose();
        // After dispose, the OnClosing handler won't cancel
        Close();
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
            // Stop and clean up the timer
            _errorDismissTimer.Stop();
            _errorDismissTimer.Tick -= OnErrorDismissTimerTick;

            // Unsubscribe from ViewModel events
            _viewModel.CancelRequested -= OnViewModelCancelRequested;
            _viewModel.PropertyChanged -= OnViewModelPropertyChanged;

            // Unsubscribe from window events
            Loaded -= OnLoaded;
            Closing -= OnClosing;

            // Stop any running animations
            StopAnimations();
        }

        _disposed = true;
    }

    private void OnViewModelPropertyChanged(object? sender, PropertyChangedEventArgs e)
    {
        if (e.PropertyName == nameof(RecordingIndicatorViewModel.CurrentState))
        {
            HandleStateChange();
        }
    }

    private void OnViewModelCancelRequested(object? sender, EventArgs e)
    {
        CancelRequested?.Invoke(this, EventArgs.Empty);
    }

    private void OnErrorDismissTimerTick(object? sender, EventArgs e)
    {
        _errorDismissTimer.Stop();
        Dismiss();
    }

    private void Border_MouseLeftButtonDown(object sender, MouseButtonEventArgs e)
    {
        if (e.ClickCount == 1)
        {
            // Start dragging
            _isDragging = true;
            _dragStartPoint = e.GetPosition(null);
            _windowStartPosition = new Point(Left, Top);
            CaptureMouse();
        }
    }

    private void StopButton_Click(object sender, RoutedEventArgs e)
    {
        // Trigger cancel when stop button is clicked (Toggle mode)
        _viewModel.CancelCommand.Execute(null);
    }

    protected override void OnMouseMove(MouseEventArgs e)
    {
        base.OnMouseMove(e);

        if (_isDragging && e.LeftButton == MouseButtonState.Pressed)
        {
            var currentPosition = e.GetPosition(null);
            var offset = currentPosition - _dragStartPoint;

            Left = _windowStartPosition.X + offset.X;
            Top = _windowStartPosition.Y + offset.Y;
        }
    }

    protected override void OnMouseLeftButtonUp(MouseButtonEventArgs e)
    {
        base.OnMouseLeftButtonUp(e);

        if (_isDragging)
        {
            _isDragging = false;
            ReleaseMouseCapture();
        }
    }

    #endregion

    #region Private Methods

    private void MakeWindowNonActivating()
    {
        var helper = new WindowInteropHelper(this);
        var exStyle = GetWindowLong(helper.Handle, GWL_EXSTYLE);
        SetWindowLong(helper.Handle, GWL_EXSTYLE, exStyle | WS_EX_NOACTIVATE | WS_EX_TOOLWINDOW);
    }

    private void UpdateWindowWidth(RecordingMode mode)
    {
        // Toggle mode needs more width for the stop button (matching macOS toggleWidth=150)
        Width = mode == RecordingMode.Toggle ? ToggleModeWidth : DefaultWidth;
    }

    private void PositionWindow()
    {
        // Position at top-center of screen (matching macOS RecordingOverlay)
        // The pill drops down from the top, centered horizontally
        var workArea = SystemParameters.WorkArea;
        Left = workArea.Left + (workArea.Width - Width) / 2;
        Top = workArea.Top;  // Flush with top of screen (macOS style)
    }

    private void HandleStateChange()
    {
        switch (_viewModel.CurrentState)
        {
            case RecordingIndicatorViewModel.IndicatorState.Initializing:
                StartInitializingAnimation();
                break;
            case RecordingIndicatorViewModel.IndicatorState.Processing:
                StopInitializingAnimation();
                StartProcessingAnimation();
                break;
            case RecordingIndicatorViewModel.IndicatorState.Recording:
            case RecordingIndicatorViewModel.IndicatorState.Error:
                StopAnimations();
                break;
            case RecordingIndicatorViewModel.IndicatorState.Hidden:
                StopAnimations();
                break;
        }
    }

    private void StartInitializingAnimation()
    {
        _initializingStoryboard?.Begin(this, true);
    }

    private void StopInitializingAnimation()
    {
        _initializingStoryboard?.Stop(this);
    }

    private void StartProcessingAnimation()
    {
        _processingStoryboard?.Begin(this, true);
    }

    private void StopProcessingAnimation()
    {
        _processingStoryboard?.Stop(this);
    }

    private void StopAnimations()
    {
        StopInitializingAnimation();
        StopProcessingAnimation();
    }

    #endregion
}

/// <summary>
/// Converter that converts a normalized audio level (0.0-1.0) to a pixel height.
/// Matches macOS WaveformBar: minHeight=2, maxHeight=22 (from parameter).
/// </summary>
public class AudioLevelToHeightConverter : IValueConverter
{
    /// <inheritdoc/>
    public object Convert(object value, Type targetType, object parameter, CultureInfo culture)
    {
        if (value is float level && parameter is string maxHeightStr && 
            double.TryParse(maxHeightStr, NumberStyles.Float, CultureInfo.InvariantCulture, out var maxHeight))
        {
            // macOS WaveformBar: minHeight=2, maxHeight from parameter (22)
            var minHeight = 2.0;
            return minHeight + (level * (maxHeight - minHeight));
        }

        return 2.0; // Default minimum height (macOS minHeight)
    }

    /// <inheritdoc/>
    public object ConvertBack(object value, Type targetType, object parameter, CultureInfo culture)
    {
        throw new NotImplementedException();
    }
}

/// <summary>
/// Converter that inverts a boolean value for visibility (inverse of BooleanToVisibilityConverter).
/// </summary>
public class InverseBooleanToVisibilityConverter : IValueConverter
{
    /// <inheritdoc/>
    public object Convert(object value, Type targetType, object parameter, CultureInfo culture)
    {
        if (value is bool boolValue)
        {
            return boolValue ? Visibility.Collapsed : Visibility.Visible;
        }
        return Visibility.Visible;
    }

    /// <inheritdoc/>
    public object ConvertBack(object value, Type targetType, object parameter, CultureInfo culture)
    {
        throw new NotImplementedException();
    }
}
