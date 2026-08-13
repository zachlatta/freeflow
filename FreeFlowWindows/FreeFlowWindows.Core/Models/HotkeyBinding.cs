using System.Text.Json.Serialization;

namespace FreeFlowWindows.Core.Models;

/// <summary>
/// Represents a keyboard hotkey binding with modifiers and a key.
/// </summary>
public class HotkeyBinding : IEquatable<HotkeyBinding>
{
    /// <summary>
    /// Gets a disabled hotkey binding (no key assigned).
    /// Matches macOS .disabled shortcut state.
    /// </summary>
    public static HotkeyBinding Disabled => new() { Modifiers = ModifierKeys.None, Key = VirtualKey.None };

    /// <summary>
    /// Modifier keys (Ctrl, Alt, Shift, Win) for the hotkey.
    /// </summary>
    [JsonPropertyName("modifiers")]
    public ModifierKeys Modifiers { get; set; }

    /// <summary>
    /// The virtual key code for the hotkey.
    /// </summary>
    [JsonPropertyName("key")]
    public VirtualKey Key { get; set; }

    /// <summary>
    /// Gets whether this hotkey is disabled (no key assigned).
    /// Matches macOS shortcut.isDisabled property.
    /// </summary>
    [JsonIgnore]
    public bool IsDisabled => Key == VirtualKey.None;

    /// <summary>
    /// Creates a deep copy of the hotkey binding.
    /// </summary>
    public HotkeyBinding Clone()
    {
        return new HotkeyBinding
        {
            Modifiers = Modifiers,
            Key = Key
        };
    }

    public bool Equals(HotkeyBinding? other)
    {
        if (other is null) return false;
        if (ReferenceEquals(this, other)) return true;

        return Modifiers == other.Modifiers && Key == other.Key;
    }

    public override bool Equals(object? obj) => Equals(obj as HotkeyBinding);

    public override int GetHashCode() => HashCode.Combine(Modifiers, Key);

    /// <summary>
    /// Returns a human-readable string representation of the hotkey.
    /// </summary>
    public override string ToString()
    {
        if (IsDisabled) return "Disabled";
        
        var parts = new List<string>();

        if (Modifiers.HasFlag(ModifierKeys.Ctrl)) parts.Add("Ctrl");
        if (Modifiers.HasFlag(ModifierKeys.Alt)) parts.Add("Alt");
        if (Modifiers.HasFlag(ModifierKeys.Shift)) parts.Add("Shift");
        if (Modifiers.HasFlag(ModifierKeys.Win)) parts.Add("Win");

        parts.Add(Key.ToString());

        return string.Join("+", parts);
    }
}
