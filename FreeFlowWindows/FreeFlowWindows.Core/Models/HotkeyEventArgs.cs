namespace FreeFlowWindows.Core.Models;

/// <summary>
/// Event arguments for hotkey press/release events.
/// </summary>
public class HotkeyEventArgs : EventArgs
{
    /// <summary>
    /// The hotkey binding that was pressed or released.
    /// </summary>
    public required HotkeyBinding Hotkey { get; init; }

    /// <summary>
    /// The timestamp when the event occurred.
    /// </summary>
    public DateTime Timestamp { get; init; } = DateTime.UtcNow;

    /// <summary>
    /// The recording mode associated with this hotkey, if applicable.
    /// </summary>
    public RecordingMode? RecordingMode { get; init; }
}
