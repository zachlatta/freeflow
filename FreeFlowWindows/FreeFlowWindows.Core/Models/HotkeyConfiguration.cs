namespace FreeFlowWindows.Core.Models;

/// <summary>
/// Configuration for all application hotkeys.
/// </summary>
public class HotkeyConfiguration
{
    /// <summary>
    /// Hotkey binding for hold-to-talk mode.
    /// </summary>
    public HotkeyBinding HoldHotkey { get; set; } = new()
    {
        Modifiers = ModifierKeys.Ctrl | ModifierKeys.Shift,
        Key = VirtualKey.Space
    };

    /// <summary>
    /// Hotkey binding for toggle mode.
    /// </summary>
    public HotkeyBinding ToggleHotkey { get; set; } = new()
    {
        Modifiers = ModifierKeys.Ctrl | ModifierKeys.Alt,
        Key = VirtualKey.Space
    };

    /// <summary>
    /// Optional hotkey binding for "Paste Again" functionality.
    /// </summary>
    public HotkeyBinding? PasteAgainHotkey { get; set; }
}
