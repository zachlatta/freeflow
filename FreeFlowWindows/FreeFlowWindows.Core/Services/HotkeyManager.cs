using System.Runtime.InteropServices;
using FreeFlowWindows.Core.Interfaces;
using FreeFlowWindows.Core.Models;

namespace FreeFlowWindows.Core.Services;

/// <summary>
/// Manages global system hotkeys using Win32 RegisterHotKey/UnregisterHotKey APIs.
/// Supports both Hold mode (with key release detection via low-level keyboard hook)
/// and Toggle mode hotkeys.
/// </summary>
public class HotkeyManager : IHotkeyManager
{
    private const int WM_HOTKEY = 0x0312;
    private const int WH_KEYBOARD_LL = 13;
    private const int WM_KEYDOWN = 0x0100;
    private const int WM_KEYUP = 0x0101;
    private const int WM_SYSKEYDOWN = 0x0104;
    private const int WM_SYSKEYUP = 0x0105;

    // Hotkey IDs
    private const int HOLD_HOTKEY_ID = 1;
    private const int TOGGLE_HOTKEY_ID = 2;
    private const int PASTE_AGAIN_HOTKEY_ID = 3;

    private readonly object _lock = new();
    private readonly SynchronizationContext? _syncContext;
    private HotkeyConfiguration? _configuration;
    private IntPtr _windowHandle;
    private IntPtr _keyboardHookHandle;
    private LowLevelKeyboardProc? _keyboardProc;
    private WndProcDelegate? _wndProc;
    private bool _isHoldKeyPressed;
    private bool _disposed;

    // Known system hotkey conflicts (common Windows shortcuts)
    private static readonly HashSet<(ModifierKeys, VirtualKey)> KnownSystemHotkeys = new()
    {
        (ModifierKeys.Win, VirtualKey.D),          // Show desktop
        (ModifierKeys.Win, VirtualKey.E),          // File Explorer
        (ModifierKeys.Win, VirtualKey.L),          // Lock workstation
        (ModifierKeys.Win, VirtualKey.R),          // Run dialog
        (ModifierKeys.Win, VirtualKey.S),          // Search
        (ModifierKeys.Win, VirtualKey.Tab),        // Task view
        (ModifierKeys.Win, VirtualKey.A),          // Action center
        (ModifierKeys.Win, VirtualKey.I),          // Settings
        (ModifierKeys.Win, VirtualKey.P),          // Project
        (ModifierKeys.Ctrl | ModifierKeys.Alt, VirtualKey.Delete), // Security options
        (ModifierKeys.Alt, VirtualKey.Tab),        // Switch windows
        (ModifierKeys.Alt, VirtualKey.F4),         // Close window
        (ModifierKeys.Ctrl | ModifierKeys.Shift, VirtualKey.Escape), // Task Manager
    };

    public event EventHandler<HotkeyEventArgs>? HoldHotkeyPressed;
    public event EventHandler<HotkeyEventArgs>? HoldHotkeyReleased;
    public event EventHandler<HotkeyEventArgs>? ToggleHotkeyPressed;
    public event EventHandler<HotkeyEventArgs>? PasteAgainHotkeyPressed;

    public bool IsActive { get; private set; }
    public HotkeyConfiguration? CurrentConfiguration => _configuration;

    /// <summary>
    /// Initializes a new instance of the HotkeyManager.
    /// </summary>
    public HotkeyManager()
    {
        _syncContext = SynchronizationContext.Current;
    }

    public bool RegisterHotkeys(HotkeyConfiguration config)
    {
        if (config == null)
            throw new ArgumentNullException(nameof(config));

        lock (_lock)
        {
            // Unregister existing hotkeys first
            UnregisterAll();

            _configuration = config;

            // Create message window for receiving WM_HOTKEY messages
            if (!CreateMessageWindow())
            {
                return false;
            }

            // Register Hold mode hotkey
            if (!RegisterSingleHotkey(HOLD_HOTKEY_ID, config.HoldHotkey))
            {
                CleanupResources();
                return false;
            }

            // Register Toggle mode hotkey
            if (!RegisterSingleHotkey(TOGGLE_HOTKEY_ID, config.ToggleHotkey))
            {
                UnregisterHotKey(_windowHandle, HOLD_HOTKEY_ID);
                CleanupResources();
                return false;
            }

            // Register optional Paste Again hotkey
            if (config.PasteAgainHotkey != null)
            {
                if (!RegisterSingleHotkey(PASTE_AGAIN_HOTKEY_ID, config.PasteAgainHotkey))
                {
                    UnregisterHotKey(_windowHandle, HOLD_HOTKEY_ID);
                    UnregisterHotKey(_windowHandle, TOGGLE_HOTKEY_ID);
                    CleanupResources();
                    return false;
                }
            }

            // Install low-level keyboard hook for Hold mode key release detection
            InstallKeyboardHook();

            IsActive = true;
            return true;
        }
    }

    public void UnregisterAll()
    {
        lock (_lock)
        {
            if (_windowHandle != IntPtr.Zero)
            {
                UnregisterHotKey(_windowHandle, HOLD_HOTKEY_ID);
                UnregisterHotKey(_windowHandle, TOGGLE_HOTKEY_ID);
                UnregisterHotKey(_windowHandle, PASTE_AGAIN_HOTKEY_ID);
            }

            UninstallKeyboardHook();
            CleanupResources();

            _configuration = null;
            _isHoldKeyPressed = false;
            IsActive = false;
        }
    }

    public HotkeyConflict? CheckConflict(HotkeyBinding binding)
    {
        if (binding == null)
            throw new ArgumentNullException(nameof(binding));

        // Check against known system hotkeys
        var key = (binding.Modifiers, binding.Key);
        if (KnownSystemHotkeys.Contains(key))
        {
            return new HotkeyConflict
            {
                Binding = binding,
                ConflictDescription = $"This hotkey ({binding}) conflicts with a Windows system shortcut.",
                IsSystemHotkey = true,
                ConflictingOwner = "Windows"
            };
        }

        // Check against currently registered hotkeys
        if (_configuration != null)
        {
            if (_configuration.HoldHotkey.Equals(binding))
            {
                return new HotkeyConflict
                {
                    Binding = binding,
                    ConflictDescription = $"This hotkey ({binding}) is already registered as the Hold mode hotkey.",
                    IsSystemHotkey = false,
                    ConflictingOwner = "FreeFlow"
                };
            }

            if (_configuration.ToggleHotkey.Equals(binding))
            {
                return new HotkeyConflict
                {
                    Binding = binding,
                    ConflictDescription = $"This hotkey ({binding}) is already registered as the Toggle mode hotkey.",
                    IsSystemHotkey = false,
                    ConflictingOwner = "FreeFlow"
                };
            }

            if (_configuration.PasteAgainHotkey?.Equals(binding) == true)
            {
                return new HotkeyConflict
                {
                    Binding = binding,
                    ConflictDescription = $"This hotkey ({binding}) is already registered as the Paste Again hotkey.",
                    IsSystemHotkey = false,
                    ConflictingOwner = "FreeFlow"
                };
            }
        }

        // Try to register and immediately unregister to detect external conflicts
        var tempWindow = CreateWindowEx(0, "STATIC", "", 0, 0, 0, 0, 0, HWND_MESSAGE, IntPtr.Zero, IntPtr.Zero, IntPtr.Zero);
        if (tempWindow != IntPtr.Zero)
        {
            try
            {
                var modifiers = ConvertModifiers(binding.Modifiers);
                var vk = (uint)binding.Key;

                if (!RegisterHotKey(tempWindow, 9999, modifiers, vk))
                {
                    var error = Marshal.GetLastWin32Error();
                    if (error == ERROR_HOTKEY_ALREADY_REGISTERED)
                    {
                        return new HotkeyConflict
                        {
                            Binding = binding,
                            ConflictDescription = $"This hotkey ({binding}) is already registered by another application.",
                            IsSystemHotkey = false,
                            ConflictingOwner = "Another application"
                        };
                    }
                }
                else
                {
                    UnregisterHotKey(tempWindow, 9999);
                }
            }
            finally
            {
                DestroyWindow(tempWindow);
            }
        }

        return null;
    }

    private bool CreateMessageWindow()
    {
        // For WM_HOTKEY to be received, the window needs to be created on the same thread
        // that will pump the message loop. In WPF, this is the UI thread.
        // We use a message-only window (HWND_MESSAGE parent) for efficiency.
        
        // Keep a reference to the delegate to prevent garbage collection
        _wndProc = WndProcCallback;

        // Register a custom window class for our hotkey window
        var className = "FreeFlowHotkeyWindow_" + Guid.NewGuid().ToString("N");
        
        var wndClass = new WNDCLASSEX
        {
            cbSize = Marshal.SizeOf<WNDCLASSEX>(),
            lpfnWndProc = Marshal.GetFunctionPointerForDelegate(_wndProc),
            hInstance = GetModuleHandle(null),
            lpszClassName = className
        };

        var atom = RegisterClassEx(ref wndClass);
        if (atom == 0)
        {
            // If registration fails, try using a built-in class
            _windowHandle = CreateWindowEx(
                0, "STATIC", "FreeFlowHotkey", 0,
                0, 0, 0, 0,
                HWND_MESSAGE, IntPtr.Zero, IntPtr.Zero, IntPtr.Zero);
        }
        else
        {
            _windowHandle = CreateWindowEx(
                0, className, "FreeFlowHotkey", 0,
                0, 0, 0, 0,
                HWND_MESSAGE, IntPtr.Zero, GetModuleHandle(null), IntPtr.Zero);
        }

        return _windowHandle != IntPtr.Zero;
    }

    private IntPtr WndProcCallback(IntPtr hWnd, uint msg, IntPtr wParam, IntPtr lParam)
    {
        if (msg == WM_HOTKEY)
        {
            ProcessHotkeyMessage(wParam.ToInt32());
            return IntPtr.Zero;
        }

        return DefWindowProc(hWnd, msg, wParam, lParam);
    }

    private void ProcessHotkeyMessage(int hotkeyId)
    {
        lock (_lock)
        {
            switch (hotkeyId)
            {
                case HOLD_HOTKEY_ID:
                    if (_configuration?.HoldHotkey != null)
                    {
                        _isHoldKeyPressed = true;
                        RaiseEvent(() => OnHoldHotkeyPressed(_configuration.HoldHotkey));
                    }
                    break;

                case TOGGLE_HOTKEY_ID:
                    if (_configuration?.ToggleHotkey != null)
                    {
                        RaiseEvent(() => OnToggleHotkeyPressed(_configuration.ToggleHotkey));
                    }
                    break;

                case PASTE_AGAIN_HOTKEY_ID:
                    if (_configuration?.PasteAgainHotkey != null)
                    {
                        RaiseEvent(() => OnPasteAgainHotkeyPressed(_configuration.PasteAgainHotkey));
                    }
                    break;
            }
        }
    }

    private void RaiseEvent(Action eventAction)
    {
        if (_syncContext != null)
        {
            _syncContext.Post(_ => eventAction(), null);
        }
        else
        {
            eventAction();
        }
    }

    private void CleanupResources()
    {
        if (_windowHandle != IntPtr.Zero)
        {
            DestroyWindow(_windowHandle);
            _windowHandle = IntPtr.Zero;
        }
        _wndProc = null;
    }

    private bool RegisterSingleHotkey(int id, HotkeyBinding binding)
    {
        var modifiers = ConvertModifiers(binding.Modifiers);
        var vk = (uint)binding.Key;

        // Add MOD_NOREPEAT to prevent repeated WM_HOTKEY messages when key is held
        modifiers |= MOD_NOREPEAT;

        if (!RegisterHotKey(_windowHandle, id, modifiers, vk))
        {
            var error = Marshal.GetLastWin32Error();
            return false;
        }

        return true;
    }

    private static uint ConvertModifiers(ModifierKeys modifiers)
    {
        uint result = 0;

        if (modifiers.HasFlag(ModifierKeys.Alt))
            result |= MOD_ALT;
        if (modifiers.HasFlag(ModifierKeys.Ctrl))
            result |= MOD_CONTROL;
        if (modifiers.HasFlag(ModifierKeys.Shift))
            result |= MOD_SHIFT;
        if (modifiers.HasFlag(ModifierKeys.Win))
            result |= MOD_WIN;

        return result;
    }

    private void InstallKeyboardHook()
    {
        _keyboardProc = LowLevelKeyboardProcCallback;
        _keyboardHookHandle = SetWindowsHookEx(
            WH_KEYBOARD_LL,
            _keyboardProc,
            IntPtr.Zero,
            0);
    }

    private void UninstallKeyboardHook()
    {
        if (_keyboardHookHandle != IntPtr.Zero)
        {
            UnhookWindowsHookEx(_keyboardHookHandle);
            _keyboardHookHandle = IntPtr.Zero;
        }
        _keyboardProc = null;
    }

    private IntPtr LowLevelKeyboardProcCallback(int nCode, IntPtr wParam, IntPtr lParam)
    {
        if (nCode >= 0 && _isHoldKeyPressed && _configuration?.HoldHotkey != null)
        {
            var kbStruct = Marshal.PtrToStructure<KBDLLHOOKSTRUCT>(lParam);
            var vkCode = (VirtualKey)kbStruct.vkCode;
            var msgType = wParam.ToInt32();

            // Check if this is a key-up event for the main key of the Hold hotkey
            if ((msgType == WM_KEYUP || msgType == WM_SYSKEYUP) && 
                vkCode == _configuration.HoldHotkey.Key)
            {
                // Verify modifiers are still held or were just released
                if (IsModifierKeyUp(vkCode, _configuration.HoldHotkey.Modifiers))
                {
                    _isHoldKeyPressed = false;
                    var binding = _configuration.HoldHotkey;
                    RaiseEvent(() => OnHoldHotkeyReleased(binding));
                }
            }
        }

        return CallNextHookEx(_keyboardHookHandle, nCode, wParam, lParam);
    }

    private bool IsModifierKeyUp(VirtualKey releasedKey, ModifierKeys expectedModifiers)
    {
        // For simplicity, we consider the hotkey released when the main key is released
        // Regardless of modifier state (this matches typical user expectation)
        return true;
    }

    private void OnHoldHotkeyPressed(HotkeyBinding binding)
    {
        HoldHotkeyPressed?.Invoke(this, new HotkeyEventArgs
        {
            Hotkey = binding,
            RecordingMode = RecordingMode.Hold,
            Timestamp = DateTime.UtcNow
        });
    }

    private void OnHoldHotkeyReleased(HotkeyBinding binding)
    {
        HoldHotkeyReleased?.Invoke(this, new HotkeyEventArgs
        {
            Hotkey = binding,
            RecordingMode = RecordingMode.Hold,
            Timestamp = DateTime.UtcNow
        });
    }

    private void OnToggleHotkeyPressed(HotkeyBinding binding)
    {
        ToggleHotkeyPressed?.Invoke(this, new HotkeyEventArgs
        {
            Hotkey = binding,
            RecordingMode = RecordingMode.Toggle,
            Timestamp = DateTime.UtcNow
        });
    }

    private void OnPasteAgainHotkeyPressed(HotkeyBinding binding)
    {
        PasteAgainHotkeyPressed?.Invoke(this, new HotkeyEventArgs
        {
            Hotkey = binding,
            Timestamp = DateTime.UtcNow
        });
    }

    public void Dispose()
    {
        Dispose(true);
        GC.SuppressFinalize(this);
    }

    protected virtual void Dispose(bool disposing)
    {
        if (_disposed)
            return;

        if (disposing)
        {
            UnregisterAll();
        }

        _disposed = true;
    }

    ~HotkeyManager()
    {
        Dispose(false);
    }

    #region Win32 P/Invoke Constants

    private const uint MOD_ALT = 0x0001;
    private const uint MOD_CONTROL = 0x0002;
    private const uint MOD_SHIFT = 0x0004;
    private const uint MOD_WIN = 0x0008;
    private const uint MOD_NOREPEAT = 0x4000;

    private const int ERROR_HOTKEY_ALREADY_REGISTERED = 1409;

    private static readonly IntPtr HWND_MESSAGE = new IntPtr(-3);

    #endregion

    #region Win32 P/Invoke Structs

    [StructLayout(LayoutKind.Sequential)]
    private struct KBDLLHOOKSTRUCT
    {
        public uint vkCode;
        public uint scanCode;
        public uint flags;
        public uint time;
        public IntPtr dwExtraInfo;
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct WNDCLASSEX
    {
        public int cbSize;
        public int style;
        public IntPtr lpfnWndProc;
        public int cbClsExtra;
        public int cbWndExtra;
        public IntPtr hInstance;
        public IntPtr hIcon;
        public IntPtr hCursor;
        public IntPtr hbrBackground;
        public string? lpszMenuName;
        public string lpszClassName;
        public IntPtr hIconSm;
    }

    #endregion

    #region Win32 P/Invoke Delegates

    private delegate IntPtr LowLevelKeyboardProc(int nCode, IntPtr wParam, IntPtr lParam);
    private delegate IntPtr WndProcDelegate(IntPtr hWnd, uint msg, IntPtr wParam, IntPtr lParam);

    #endregion

    #region Win32 P/Invoke Methods

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool RegisterHotKey(IntPtr hWnd, int id, uint fsModifiers, uint vk);

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool UnregisterHotKey(IntPtr hWnd, int id);

    [DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    private static extern IntPtr CreateWindowEx(
        uint dwExStyle,
        string lpClassName,
        string lpWindowName,
        uint dwStyle,
        int x,
        int y,
        int nWidth,
        int nHeight,
        IntPtr hWndParent,
        IntPtr hMenu,
        IntPtr hInstance,
        IntPtr lpParam);

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool DestroyWindow(IntPtr hWnd);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern IntPtr SetWindowsHookEx(int idHook, LowLevelKeyboardProc lpfn, IntPtr hMod, uint dwThreadId);

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool UnhookWindowsHookEx(IntPtr hhk);

    [DllImport("user32.dll")]
    private static extern IntPtr CallNextHookEx(IntPtr hhk, int nCode, IntPtr wParam, IntPtr lParam);

    [DllImport("user32.dll")]
    private static extern short GetAsyncKeyState(int vKey);

    [DllImport("user32.dll")]
    private static extern IntPtr DefWindowProc(IntPtr hWnd, uint msg, IntPtr wParam, IntPtr lParam);

    [DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    private static extern ushort RegisterClassEx(ref WNDCLASSEX lpWndClass);

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)]
    private static extern IntPtr GetModuleHandle(string? lpModuleName);

    #endregion
}
