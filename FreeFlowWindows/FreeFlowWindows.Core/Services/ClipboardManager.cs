using System.Runtime.InteropServices;
using System.Text;
using FreeFlowWindows.Core.Interfaces;
using InputSimulatorStandard;
using InputSimulatorStandard.Native;

namespace FreeFlowWindows.Core.Services;

/// <summary>
/// Manages clipboard operations using Windows Clipboard APIs (User32.dll P/Invoke).
/// Provides async clipboard access with retry logic, paste simulation, and clipboard preservation.
/// </summary>
/// <remarks>
/// The Windows clipboard can be locked by other applications, so this implementation
/// includes retry logic with exponential backoff. All clipboard operations must run
/// on an STA thread, which is handled automatically by this class.
/// 
/// Validates: Requirements 6.1, 6.2, 6.3, 6.4, 6.5, 6.6
/// </remarks>
public sealed class ClipboardManager : IClipboardManager, IDisposable
{
    #region Native Methods and Constants

    /// <summary>
    /// Standard clipboard format for Unicode text.
    /// </summary>
    private const uint CF_UNICODETEXT = 13;

    /// <summary>
    /// Global memory allocation flag.
    /// </summary>
    private const uint GMEM_MOVEABLE = 0x0002;

    /// <summary>
    /// Maximum number of retry attempts for clipboard operations.
    /// </summary>
    private const int MaxRetryAttempts = 10;

    /// <summary>
    /// Initial delay between retry attempts in milliseconds.
    /// </summary>
    private const int InitialRetryDelayMs = 10;

    /// <summary>
    /// Maximum delay between retry attempts in milliseconds.
    /// </summary>
    private const int MaxRetryDelayMs = 100;

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool OpenClipboard(IntPtr hWndNewOwner);

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool CloseClipboard();

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool EmptyClipboard();

    [DllImport("user32.dll", SetLastError = true)]
    private static extern IntPtr SetClipboardData(uint uFormat, IntPtr hMem);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern IntPtr GetClipboardData(uint uFormat);

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool IsClipboardFormatAvailable(uint format);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern IntPtr GlobalAlloc(uint uFlags, UIntPtr dwBytes);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern IntPtr GlobalLock(IntPtr hMem);

    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GlobalUnlock(IntPtr hMem);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern IntPtr GlobalFree(IntPtr hMem);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern UIntPtr GlobalSize(IntPtr hMem);

    #endregion

    private readonly IInputSimulator _inputSimulator;
    private readonly object _lock = new();
    private string? _lastTranscript;
    private bool _disposed;

    /// <summary>
    /// Gets or sets the delay after pasting before restoring the original clipboard contents.
    /// Default is 1 second.
    /// </summary>
    public TimeSpan ClipboardRestoreDelay { get; set; } = TimeSpan.FromSeconds(1);

    /// <summary>
    /// Creates a new ClipboardManager with the default InputSimulator.
    /// </summary>
    public ClipboardManager()
        : this(new InputSimulator())
    {
    }

    /// <summary>
    /// Creates a new ClipboardManager with a custom InputSimulator (for testing).
    /// </summary>
    /// <param name="inputSimulator">The input simulator to use for paste simulation.</param>
    public ClipboardManager(IInputSimulator inputSimulator)
    {
        _inputSimulator = inputSimulator ?? throw new ArgumentNullException(nameof(inputSimulator));
    }

    /// <inheritdoc />
    public async Task PasteTextAsync(string text, bool preserveClipboard = true, CancellationToken cancellationToken = default)
    {
        if (string.IsNullOrEmpty(text))
        {
            return;
        }

        // Store as last transcript for "Paste Again"
        lock (_lock)
        {
            _lastTranscript = text;
        }

        string? originalClipboardContent = null;

        try
        {
            // Save original clipboard content if preservation is enabled
            if (preserveClipboard)
            {
                originalClipboardContent = await GetTextAsync(cancellationToken);
            }

            // Set the transcript on the clipboard
            await SetTextAsync(text, cancellationToken);

            // Small delay to ensure clipboard is ready
            await Task.Delay(50, cancellationToken);

            // Simulate Ctrl+V to paste
            SimulatePaste();

            // Restore original clipboard content after delay if preservation is enabled
            if (preserveClipboard && originalClipboardContent != null)
            {
                // Don't cancel the restore operation even if the main token is cancelled
                _ = Task.Run(async () =>
                {
                    try
                    {
                        await Task.Delay(ClipboardRestoreDelay, CancellationToken.None);
                        await SetTextAsync(originalClipboardContent, CancellationToken.None);
                    }
                    catch
                    {
                        // Silently ignore restore failures
                    }
                });
            }
        }
        catch (OperationCanceledException)
        {
            throw;
        }
        catch (Exception ex)
        {
            throw new InvalidOperationException($"Failed to paste text: {ex.Message}", ex);
        }
    }

    /// <inheritdoc />
    public async Task PasteLastTranscriptAsync(CancellationToken cancellationToken = default)
    {
        string? lastTranscript;
        lock (_lock)
        {
            lastTranscript = _lastTranscript;
        }

        if (string.IsNullOrEmpty(lastTranscript))
        {
            return;
        }

        // For "Paste Again", we don't preserve clipboard - the user explicitly wants this text
        await SetTextAsync(lastTranscript, cancellationToken);
        await Task.Delay(50, cancellationToken);
        SimulatePaste();
    }

    /// <inheritdoc />
    public string? GetLastTranscript()
    {
        lock (_lock)
        {
            return _lastTranscript;
        }
    }

    /// <inheritdoc />
    public Task<string?> GetTextAsync(CancellationToken cancellationToken = default)
    {
        return RunOnStaThreadAsync(() => GetTextFromClipboardWithRetry(cancellationToken), cancellationToken);
    }

    /// <inheritdoc />
    public Task SetTextAsync(string text, CancellationToken cancellationToken = default)
    {
        return RunOnStaThreadAsync(() =>
        {
            SetTextToClipboardWithRetry(text, cancellationToken);
            return (object?)null;
        }, cancellationToken);
    }

    /// <summary>
    /// Simulates a Ctrl+V keystroke to paste from the clipboard.
    /// </summary>
    private void SimulatePaste()
    {
        _inputSimulator.Keyboard.ModifiedKeyStroke(
            VirtualKeyCode.CONTROL,
            VirtualKeyCode.VK_V);
    }

    /// <summary>
    /// Gets text from the clipboard with retry logic.
    /// </summary>
    private string? GetTextFromClipboardWithRetry(CancellationToken cancellationToken)
    {
        var delay = InitialRetryDelayMs;

        for (var attempt = 0; attempt < MaxRetryAttempts; attempt++)
        {
            cancellationToken.ThrowIfCancellationRequested();

            try
            {
                return GetTextFromClipboard();
            }
            catch (ClipboardLockedException)
            {
                if (attempt == MaxRetryAttempts - 1)
                {
                    throw;
                }

                Thread.Sleep(delay);
                delay = Math.Min(delay * 2, MaxRetryDelayMs);
            }
        }

        return null;
    }

    /// <summary>
    /// Sets text to the clipboard with retry logic.
    /// </summary>
    private void SetTextToClipboardWithRetry(string text, CancellationToken cancellationToken)
    {
        var delay = InitialRetryDelayMs;

        for (var attempt = 0; attempt < MaxRetryAttempts; attempt++)
        {
            cancellationToken.ThrowIfCancellationRequested();

            try
            {
                SetTextToClipboard(text);
                return;
            }
            catch (ClipboardLockedException)
            {
                if (attempt == MaxRetryAttempts - 1)
                {
                    throw;
                }

                Thread.Sleep(delay);
                delay = Math.Min(delay * 2, MaxRetryDelayMs);
            }
        }
    }

    /// <summary>
    /// Gets Unicode text from the clipboard using Windows APIs.
    /// </summary>
    /// <exception cref="ClipboardLockedException">Thrown when the clipboard cannot be opened.</exception>
    private static string? GetTextFromClipboard()
    {
        if (!IsClipboardFormatAvailable(CF_UNICODETEXT))
        {
            return null;
        }

        if (!OpenClipboard(IntPtr.Zero))
        {
            throw new ClipboardLockedException("Failed to open clipboard for reading.");
        }

        try
        {
            var handle = GetClipboardData(CF_UNICODETEXT);
            if (handle == IntPtr.Zero)
            {
                return null;
            }

            var pointer = GlobalLock(handle);
            if (pointer == IntPtr.Zero)
            {
                return null;
            }

            try
            {
                // Read the Unicode string from unmanaged memory
                return Marshal.PtrToStringUni(pointer);
            }
            finally
            {
                GlobalUnlock(handle);
            }
        }
        finally
        {
            CloseClipboard();
        }
    }

    /// <summary>
    /// Sets Unicode text to the clipboard using Windows APIs.
    /// </summary>
    /// <exception cref="ClipboardLockedException">Thrown when the clipboard cannot be opened.</exception>
    /// <exception cref="InvalidOperationException">Thrown when clipboard operations fail.</exception>
    private static void SetTextToClipboard(string text)
    {
        if (!OpenClipboard(IntPtr.Zero))
        {
            throw new ClipboardLockedException("Failed to open clipboard for writing.");
        }

        IntPtr hGlobal = IntPtr.Zero;
        try
        {
            if (!EmptyClipboard())
            {
                throw new InvalidOperationException("Failed to empty clipboard.");
            }

            // Convert string to Unicode bytes (including null terminator)
            var bytes = Encoding.Unicode.GetBytes(text + '\0');
            var size = (UIntPtr)bytes.Length;

            hGlobal = GlobalAlloc(GMEM_MOVEABLE, size);
            if (hGlobal == IntPtr.Zero)
            {
                throw new InvalidOperationException("Failed to allocate global memory for clipboard.");
            }

            var pointer = GlobalLock(hGlobal);
            if (pointer == IntPtr.Zero)
            {
                throw new InvalidOperationException("Failed to lock global memory.");
            }

            try
            {
                Marshal.Copy(bytes, 0, pointer, bytes.Length);
            }
            finally
            {
                GlobalUnlock(hGlobal);
            }

            if (SetClipboardData(CF_UNICODETEXT, hGlobal) == IntPtr.Zero)
            {
                throw new InvalidOperationException("Failed to set clipboard data.");
            }

            // Clipboard now owns the memory, don't free it
            hGlobal = IntPtr.Zero;
        }
        finally
        {
            // Free memory if SetClipboardData failed (clipboard didn't take ownership)
            if (hGlobal != IntPtr.Zero)
            {
                GlobalFree(hGlobal);
            }

            CloseClipboard();
        }
    }

    /// <summary>
    /// Runs an action on an STA thread. Required for clipboard operations in Windows.
    /// </summary>
    private static Task<T?> RunOnStaThreadAsync<T>(Func<T?> action, CancellationToken cancellationToken)
    {
        var tcs = new TaskCompletionSource<T?>();

        var thread = new Thread(() =>
        {
            try
            {
                cancellationToken.ThrowIfCancellationRequested();
                var result = action();
                tcs.TrySetResult(result);
            }
            catch (OperationCanceledException)
            {
                tcs.TrySetCanceled(cancellationToken);
            }
            catch (Exception ex)
            {
                tcs.TrySetException(ex);
            }
        });

        thread.SetApartmentState(ApartmentState.STA);
        thread.IsBackground = true;
        thread.Start();

        return tcs.Task;
    }

    /// <summary>
    /// Disposes resources.
    /// </summary>
    public void Dispose()
    {
        if (!_disposed)
        {
            _disposed = true;
        }
        GC.SuppressFinalize(this);
    }
}

/// <summary>
/// Exception thrown when the clipboard is locked by another application.
/// </summary>
public class ClipboardLockedException : InvalidOperationException
{
    /// <summary>
    /// Creates a new ClipboardLockedException with the specified message.
    /// </summary>
    public ClipboardLockedException(string message)
        : base(message)
    {
    }

    /// <summary>
    /// Creates a new ClipboardLockedException with the specified message and inner exception.
    /// </summary>
    public ClipboardLockedException(string message, Exception innerException)
        : base(message, innerException)
    {
    }
}
