namespace FreeFlowWindows.Core.Models;

/// <summary>
/// Represents a detected hotkey conflict.
/// </summary>
public class HotkeyConflict
{
    /// <summary>
    /// The hotkey binding that has a conflict.
    /// </summary>
    public required HotkeyBinding Binding { get; init; }

    /// <summary>
    /// Description of what the conflict is with.
    /// </summary>
    public required string ConflictDescription { get; init; }

    /// <summary>
    /// Whether this is a system-level hotkey conflict.
    /// </summary>
    public bool IsSystemHotkey { get; init; }

    /// <summary>
    /// The application or system feature that owns the conflicting hotkey.
    /// </summary>
    public string? ConflictingOwner { get; init; }
}
