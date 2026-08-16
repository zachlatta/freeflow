namespace FreeFlowWindows.Core.Models;

/// <summary>
/// Represents an audio input device available for recording.
/// </summary>
public class AudioDevice
{
    /// <summary>
    /// The unique device identifier (typically the device number for NAudio).
    /// </summary>
    public string Id { get; set; } = string.Empty;

    /// <summary>
    /// The human-readable name of the device.
    /// </summary>
    public string Name { get; set; } = string.Empty;

    /// <summary>
    /// Indicates whether this is the system default audio input device.
    /// </summary>
    public bool IsDefault { get; set; }

    /// <summary>
    /// Creates a new AudioDevice instance.
    /// </summary>
    public AudioDevice()
    {
    }

    /// <summary>
    /// Creates a new AudioDevice instance with the specified values.
    /// </summary>
    /// <param name="id">The device identifier.</param>
    /// <param name="name">The device name.</param>
    /// <param name="isDefault">Whether this is the default device.</param>
    public AudioDevice(string id, string name, bool isDefault = false)
    {
        Id = id;
        Name = name;
        IsDefault = isDefault;
    }

    public override string ToString() => Name;
}
