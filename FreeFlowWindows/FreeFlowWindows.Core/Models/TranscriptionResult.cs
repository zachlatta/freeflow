using System.Text.Json.Serialization;

namespace FreeFlowWindows.Core.Models;

/// <summary>
/// Represents the verbose JSON response from the Whisper API.
/// Used for hallucination detection via segment metadata.
/// </summary>
public class WhisperVerboseResponse
{
    /// <summary>
    /// The full transcribed text.
    /// </summary>
    [JsonPropertyName("text")]
    public string? Text { get; set; }

    /// <summary>
    /// Individual segments with timing and confidence metadata.
    /// </summary>
    [JsonPropertyName("segments")]
    public List<WhisperSegment>? Segments { get; set; }

    /// <summary>
    /// Language detected (if applicable).
    /// </summary>
    [JsonPropertyName("language")]
    public string? Language { get; set; }

    /// <summary>
    /// Duration of the audio in seconds.
    /// </summary>
    [JsonPropertyName("duration")]
    public double? Duration { get; set; }
}

/// <summary>
/// A single segment from the Whisper verbose JSON response.
/// </summary>
public class WhisperSegment
{
    /// <summary>
    /// Start time in seconds.
    /// </summary>
    [JsonPropertyName("start")]
    public double Start { get; set; }

    /// <summary>
    /// End time in seconds.
    /// </summary>
    [JsonPropertyName("end")]
    public double End { get; set; }

    /// <summary>
    /// Transcribed text for this segment.
    /// </summary>
    [JsonPropertyName("text")]
    public string? Text { get; set; }

    /// <summary>
    /// Probability that no speech was present in this segment.
    /// Used for hallucination detection - higher values indicate
    /// the model is uncertain about actual speech content.
    /// </summary>
    [JsonPropertyName("no_speech_prob")]
    public double? NoSpeechProb { get; set; }
}

/// <summary>
/// Represents a simple JSON response from the Whisper API.
/// Used for models that don't support verbose_json.
/// </summary>
public class WhisperSimpleResponse
{
    /// <summary>
    /// The transcribed text.
    /// </summary>
    [JsonPropertyName("text")]
    public string? Text { get; set; }
}
