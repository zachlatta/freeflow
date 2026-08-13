using System.IO;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Interop;
using FreeFlowWindows.Core.Interfaces;
using FreeFlowWindows.Core.Models;

namespace FreeFlowWindows.App.Services;

/// <summary>
/// Hotkey manager using Windows API RegisterHotKey with ComponentDispatcher.
/// Uses the main UI thread's message pump to receive WM_HOTKEY messages.
/// </summary>
public class WpfHotkeyManager : IHotkeyManager, IDisposable
{
    private const int WM_HOTKEY = 0x0312;
    private const int WH_KEYBOARD_LL = 13;
    private const int WM_KEYUP = 0x0101;
    private const int WM_SYSKEYUP = 0x0105;

    private const int HOLD_HOTKEY_ID = 9001;
    private const int TOGGLE_HOTKEY_ID = 9002;
    private const int PASTE_AGAIN_HOTKEY_ID = 9003;

    private readonly object _lock = new();
    private HotkeyConfiguration? _configuration;
    private IntPtr _keyboardHookHandle;
    private LowLevelKeyboardProc? _keyboardProc;
    private bool _isHoldActive;
    private bool _disposed;
    private bool _isHooked;
    private static readonly string LogPath = Path.Combine(Path.GetTempPath(), "freeflow_debug.log");

    private static readonly HashSet<(ModifierKeys, VirtualKey)> KnownSystemHotkeys = new()
    {
        (ModifierKeys.Win, VirtualKey.D), (ModifierKeys.Win, VirtualKey.E),
        (ModifierKeys.Win, VirtualKey.L), (ModifierKeys.Win, VirtualKey.R),
        (ModifierKeys.Win, VirtualKey.S), (ModifierKeys.Win, VirtualKey.Tab),
        (ModifierKeys.Alt, VirtualKey.Tab), (ModifierKeys.Alt, VirtualKey.F4),
    };

    public event EventHandler<HotkeyEventArgs>? HoldHotkeyPressed;
    public event EventHandler<HotkeyEventArgs>? HoldHotkeyReleased;
    public event EventHandler<HotkeyEventArgs>? ToggleHotkeyPressed;
    public event EventHandler<HotkeyEventArgs>? PasteAgainHotkeyPressed;

    public bool IsActive { get; private set; }
    public HotkeyConfiguration? CurrentConfiguration => _configuration;

    private void Log(string message)
    {
        try
        {
            File.AppendAllText(LogPath, $"[{DateTime.Now:HH:mm:ss.fff}] {message}\n");
        }
        catch { }
    }

    public bool RegisterHotkeys(HotkeyConfiguration config)
    {
        if (config == null) throw new ArgumentNullException(nameof(config));

        Log($"RegisterHotkeys called");

        lock (_lock)
        {
            UnregisterAll();
            _configuration = config;

            // Hook into the ComponentDispatcher to receive WM_HOTKEY messages on UI thread
            if (!_isHooked)
            {
                ComponentDispatcher.ThreadPreprocessMessage += OnThreadMessage;
                _isHooked = true;
                Log("Hooked into ComponentDispatcher");
            }

            // Register hotkeys to the thread (IntPtr.Zero)
            // This allows receiving WM_HOTKEY via the message loop

            // Register Hold hotkey
            var holdMods = GetModifiers(config.HoldHotkey.Modifiers);
            var holdKey = (uint)config.HoldHotkey.Key;
            Log($"Registering Hold: {config.HoldHotkey} (mods=0x{holdMods:X}, key=0x{holdKey:X})");
            
            if (!RegisterHotKey(IntPtr.Zero, HOLD_HOTKEY_ID, holdMods, holdKey))
            {
                var err = Marshal.GetLastWin32Error();
                Log($"Failed Hold hotkey registration: error {err}");
                return false;
            }
            Log("Hold hotkey registered successfully");

            // Register Toggle hotkey
            var toggleMods = GetModifiers(config.ToggleHotkey.Modifiers);
            var toggleKey = (uint)config.ToggleHotkey.Key;
            Log($"Registering Toggle: {config.ToggleHotkey} (mods=0x{toggleMods:X}, key=0x{toggleKey:X})");
            
            if (!RegisterHotKey(IntPtr.Zero, TOGGLE_HOTKEY_ID, toggleMods, toggleKey))
            {
                var err = Marshal.GetLastWin32Error();
                Log($"Failed Toggle hotkey registration: error {err}");
                UnregisterHotKey(IntPtr.Zero, HOLD_HOTKEY_ID);
                return false;
            }
            Log("Toggle hotkey registered successfully");

            // Register Paste Again hotkey if configured
            if (config.PasteAgainHotkey != null)
            {
                var pasteAgainMods = GetModifiers(config.PasteAgainHotkey.Modifiers);
                var pasteAgainKey = (uint)config.PasteAgainHotkey.Key;
                RegisterHotKey(IntPtr.Zero, PASTE_AGAIN_HOTKEY_ID, pasteAgainMods, pasteAgainKey);
            }

            // Install keyboard hook for detecting key release (for Hold mode)
            InstallKeyboardHook();

            IsActive = true;
            Log("All hotkeys registered, IsActive = true");
            return true;
        }
    }

    private void OnThreadMessage(ref MSG msg, ref bool handled)
    {
        if (msg.message == WM_HOTKEY)
        {
            var hotkeyId = msg.wParam.ToInt32();
            Log($"WM_HOTKEY received via ComponentDispatcher! ID={hotkeyId}");
            
            handled = true;
            ProcessHotkey(hotkeyId);
        }
    }

    private void ProcessHotkey(int hotkeyId)
    {
        lock (_lock)
        {
            if (_configuration == null)
            {
                Log("Configuration is null, ignoring hotkey");
                return;
            }

            switch (hotkeyId)
            {
                case HOLD_HOTKEY_ID:
                    Log("Processing HOLD hotkey press");
                    _isHoldActive = true;
                    OnHoldHotkeyPressed(_configuration.HoldHotkey);
                    break;
                case TOGGLE_HOTKEY_ID:
                    Log("Processing TOGGLE hotkey press");
                    OnToggleHotkeyPressed(_configuration.ToggleHotkey);
                    break;
                case PASTE_AGAIN_HOTKEY_ID:
                    Log("Processing PASTE_AGAIN hotkey press");
                    if (_configuration.PasteAgainHotkey != null)
                        OnPasteAgainHotkeyPressed(_configuration.PasteAgainHotkey);
                    break;
            }
        }
    }

    private uint GetModifiers(ModifierKeys modifiers)
    {
        uint result = MOD_NOREPEAT;
        if (modifiers.HasFlag(ModifierKeys.Alt)) result |= MOD_ALT;
        if (modifiers.HasFlag(ModifierKeys.Ctrl)) result |= MOD_CONTROL;
        if (modifiers.HasFlag(ModifierKeys.Shift)) result |= MOD_SHIFT;
        if (modifiers.HasFlag(ModifierKeys.Win)) result |= MOD_WIN;
        return result;
    }

    public void UnregisterAll()
    {
        Log("UnregisterAll called");
        lock (_lock)
        {
            UnregisterHotKey(IntPtr.Zero, HOLD_HOTKEY_ID);
            UnregisterHotKey(IntPtr.Zero, TOGGLE_HOTKEY_ID);
            UnregisterHotKey(IntPtr.Zero, PASTE_AGAIN_HOTKEY_ID);
            
            if (_isHooked)
            {
                ComponentDispatcher.ThreadPreprocessMessage -= OnThreadMessage;
                _isHooked = false;
            }
            
            UninstallKeyboardHook();
            _configuration = null;
            _isHoldActive = false;
            IsActive = false;
        }
    }

    public HotkeyConflict? CheckConflict(HotkeyBinding binding)
    {
        if (binding == null) throw new ArgumentNullException(nameof(binding));
        var key = (binding.Modifiers, binding.Key);
        if (KnownSystemHotkeys.Contains(key))
            return new HotkeyConflict { Binding = binding, ConflictDescription = "Conflicts with Windows shortcut.", IsSystemHotkey = true, ConflictingOwner = "Windows" };
        return null;
    }

    private void InstallKeyboardHook()
    {
        Log("Installing keyboard hook for key release detection");
        _keyboardProc = LowLevelKeyboardProcCallback;
        using var curProcess = System.Diagnostics.Process.GetCurrentProcess();
        using var curModule = curProcess.MainModule;
        var moduleHandle = curModule != null ? GetModuleHandle(curModule.ModuleName) : IntPtr.Zero;
        _keyboardHookHandle = SetWindowsHookEx(WH_KEYBOARD_LL, _keyboardProc, moduleHandle, 0);
        
        if (_keyboardHookHandle == IntPtr.Zero)
        {
            Log($"Failed to install keyboard hook: {Marshal.GetLastWin32Error()}");
        }
        else
        {
            Log("Keyboard hook installed successfully");
        }
    }

    private void UninstallKeyboardHook()
    {
        if (_keyboardHookHandle != IntPtr.Zero)
        {
            UnhookWindowsHookEx(_keyboardHookHandle);
            _keyboardHookHandle = IntPtr.Zero;
            Log("Keyboard hook uninstalled");
        }
        _keyboardProc = null;
    }

    private IntPtr LowLevelKeyboardProcCallback(int nCode, IntPtr wParam, IntPtr lParam)
    {
        if (nCode >= 0 && _isHoldActive && _configuration?.HoldHotkey != null)
        {
            var kbStruct = Marshal.PtrToStructure<KBDLLHOOKSTRUCT>(lParam);
            var vkCode = (VirtualKey)kbStruct.vkCode;
            var msgType = wParam.ToInt32();

            // Check if the hotkey's main key was released
            if ((msgType == WM_KEYUP || msgType == WM_SYSKEYUP) && vkCode == _configuration.HoldHotkey.Key)
            {
                Log($"Hold key released: {vkCode}");
                _isHoldActive = false;
                var binding = _configuration.HoldHotkey;
                Application.Current?.Dispatcher.BeginInvoke(() => OnHoldHotkeyReleased(binding));
            }
        }
        return CallNextHookEx(_keyboardHookHandle, nCode, wParam, lParam);
    }

    private void OnHoldHotkeyPressed(HotkeyBinding b)
    {
        Log("Firing HoldHotkeyPressed event");
        HoldHotkeyPressed?.Invoke(this, new HotkeyEventArgs { Hotkey = b, RecordingMode = RecordingMode.Hold, Timestamp = DateTime.UtcNow });
    }

    private void OnHoldHotkeyReleased(HotkeyBinding b)
    {
        Log("Firing HoldHotkeyReleased event");
        HoldHotkeyReleased?.Invoke(this, new HotkeyEventArgs { Hotkey = b, RecordingMode = RecordingMode.Hold, Timestamp = DateTime.UtcNow });
    }

    private void OnToggleHotkeyPressed(HotkeyBinding b)
    {
        Log("Firing ToggleHotkeyPressed event");
        ToggleHotkeyPressed?.Invoke(this, new HotkeyEventArgs { Hotkey = b, RecordingMode = RecordingMode.Toggle, Timestamp = DateTime.UtcNow });
    }

    private void OnPasteAgainHotkeyPressed(HotkeyBinding b)
    {
        Log("Firing PasteAgainHotkeyPressed event");
        PasteAgainHotkeyPressed?.Invoke(this, new HotkeyEventArgs { Hotkey = b, Timestamp = DateTime.UtcNow });
    }

    public void Dispose()
    {
        Dispose(true);
        GC.SuppressFinalize(this);
    }

    protected virtual void Dispose(bool disposing)
    {
        if (!_disposed)
        {
            if (disposing)
            {
                UnregisterAll();
            }
            _disposed = true;
        }
    }

    ~WpfHotkeyManager()
    {
        Dispose(false);
    }

    #region Win32

    private const uint MOD_ALT = 0x0001;
    private const uint MOD_CONTROL = 0x0002;
    private const uint MOD_SHIFT = 0x0004;
    private const uint MOD_WIN = 0x0008;
    private const uint MOD_NOREPEAT = 0x4000;

    [StructLayout(LayoutKind.Sequential)]
    private struct KBDLLHOOKSTRUCT
    {
        public uint vkCode;
        public uint scanCode;
        public uint flags;
        public uint time;
        public IntPtr dwExtraInfo;
    }

    private delegate IntPtr LowLevelKeyboardProc(int nCode, IntPtr wParam, IntPtr lParam);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool RegisterHotKey(IntPtr hWnd, int id, uint fsModifiers, uint vk);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool UnregisterHotKey(IntPtr hWnd, int id);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern IntPtr SetWindowsHookEx(int idHook, LowLevelKeyboardProc lpfn, IntPtr hMod, uint dwThreadId);

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool UnhookWindowsHookEx(IntPtr hhk);

    [DllImport("user32.dll")]
    private static extern IntPtr CallNextHookEx(IntPtr hhk, int nCode, IntPtr wParam, IntPtr lParam);

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)]
    private static extern IntPtr GetModuleHandle(string lpModuleName);

    #endregion
}
