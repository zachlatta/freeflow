using FreeFlowWindows.Core.Models;

namespace FreeFlowWindows.Core.Interfaces;

/// <summary>
/// Interface for managing global system hotkeys using Win32 APIs.
/// Supports both Hold mode (key press/release) and Toggle mode hotkeys.
/// </summary>
public interface IHotkeyManager : IDisposable
{
    /// <summary>
    /// Raised when the Hold mode hotkey is pressed down.
    /// </summary>
    event EventHandler<HotkeyEventArgs>? HoldHotkeyPressed;

    /// <summary>
    /// Raised when the Hold mode hotkey is released.
    /// </summary>
    event EventHandler<HotkeyEventArgs>? HoldHotkeyReleased;

    /// <summary>
    /// Raised when the Toggle mode hotkey is pressed.
    /// </summary>
    event EventHandler<HotkeyEventArgs>? ToggleHotkeyPressed;

    /// <summary>
    /// Raised when the Paste Again hotkey is pressed.
    /// </summary>
    event EventHandler<HotkeyEventArgs>? PasteAgainHotkeyPressed;

    /// <summary>
    /// Registers all hotkeys from the provided configuration.
    /// </summary>
    /// <param name="config">The hotkey configuration to register.</param>
    /// <returns>True if all hotkeys were registered successfully, false if any failed.</returns>
    bool RegisterHotkeys(HotkeyConfiguration config);

    /// <summary>
    /// Unregisters all currently registered hotkeys.
    /// </summary>
    void UnregisterAll();

    /// <summary>
    /// Checks if the specified hotkey binding conflicts with existing registrations.
    /// </summary>
    /// <param name="binding">The hotkey binding to check.</param>
    /// <returns>A HotkeyConflict if a conflict exists, null otherwise.</returns>
    HotkeyConflict? CheckConflict(HotkeyBinding binding);

    /// <summary>
    /// Gets whether the hotkey manager is currently active and listening.
    /// </summary>
    bool IsActive { get; }

    /// <summary>
    /// Gets the current hotkey configuration.
    /// </summary>
    HotkeyConfiguration? CurrentConfiguration { get; }
}
