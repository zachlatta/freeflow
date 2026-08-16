namespace FreeFlowWindows.Core.Models;

/// <summary>
/// Modifier keys for hotkey bindings.
/// Values correspond to Win32 MOD_* constants for RegisterHotKey.
/// </summary>
[Flags]
public enum ModifierKeys
{
    /// <summary>
    /// No modifier keys.
    /// </summary>
    None = 0,

    /// <summary>
    /// Alt key (MOD_ALT = 0x0001).
    /// </summary>
    Alt = 1,

    /// <summary>
    /// Ctrl key (MOD_CONTROL = 0x0002).
    /// </summary>
    Ctrl = 2,

    /// <summary>
    /// Shift key (MOD_SHIFT = 0x0004).
    /// </summary>
    Shift = 4,

    /// <summary>
    /// Windows key (MOD_WIN = 0x0008).
    /// </summary>
    Win = 8
}
