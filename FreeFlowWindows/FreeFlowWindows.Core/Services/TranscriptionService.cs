using System.Text.Json;
using FreeFlowWindows.Core.Http;
using FreeFlowWindows.Core.Interfaces;
using FreeFlowWindows.Core.Models;

namespace FreeFlowWindows.Core.Services;

/// <summary>
/// Transcription service that uploads audio to the Whisper API and returns transcripts.
/// Includes hallucination filtering for common false-positive phrases.
/// </summary>
public class TranscriptionService : ITranscriptionService, IDisposable
{
    /// <summary>
    /// Models that support verbose_json response format with segment metadata.
    /// Other models use the simpler "json" format.
    /// </summary>
    private static readonly HashSet<string> ModelsSupportingVerboseJson = new(StringComparer.OrdinalIgnoreCase)
    {
        "whisper-1",           // OpenAI's Whisper model
        "whisper-large-v3",    // Groq's hosted Whisper
        "whisper-large-v3-turbo"
    };

    /// <summary>
    /// Common hallucination phrases produced by Whisper on silence/noise.
    /// These are filtered when no_speech_prob is high.
    /// </summary>
    private static readonly HashSet<string> HallucinationPhrases = new(StringComparer.OrdinalIgnoreCase)
    {
        "thank you",
        "thank you for watching",
        "thank you very much",
        "thank you so much",
        "thanks for watching",
        "please subscribe",
        "like and subscribe",
        "subtitles by",
        "subtitles by the amara.org community",
        "you"
    };

    /// <summary>
    /// Threshold for no_speech_prob above which hallucination phrases are filtered.
    /// Must be >= this value AND match a hallucination phrase to be filtered.
    /// </summary>
    private const double HallucinationNoSpeechThreshold = 0.1;

    private readonly HttpTransport _httpTransport;
    private readonly string _apiKey;
    private readonly string _baseUrl;
    private readonly string _model;
    private readonly string? _language;
    private readonly bool _ownsTransport;
    private bool _disposed;

    /// <summary>
    /// Creates a new TranscriptionService.
    /// </summary>
    /// <param name="apiKey">The API key for authentication.</param>
    /// <param name="baseUrl">The base URL for the API (default: Groq endpoint).</param>
    /// <param name="model">The transcription model to use (default: whisper-large-v3).</param>
    /// <param name="timeoutSeconds">Request timeout in seconds (default: 20).</param>
    /// <param name="language">Optional language hint for transcription.</param>
    public TranscriptionService(
        string apiKey,
        string baseUrl = "https://api.groq.com/openai/v1",
        string model = "whisper-large-v3",
        int timeoutSeconds = 20,
        string? language = null)
    {
        _apiKey = apiKey ?? throw new ArgumentNullException(nameof(apiKey));
        _baseUrl = NormalizeBaseUrl(baseUrl);
        _model = string.IsNullOrWhiteSpace(model) ? "whisper-large-v3" : model.Trim();
        _language = string.IsNullOrWhiteSpace(language) ? null : language.Trim();
        _httpTransport = new HttpTransport(timeoutSeconds);
        _ownsTransport = true;
    }

    /// <summary>
    /// Creates a new TranscriptionService with a shared HttpTransport.
    /// </summary>
    /// <param name="httpTransport">The HTTP transport to use (not owned, won't be disposed).</param>
    /// <param name="apiKey">The API key for authentication.</param>
    /// <param name="baseUrl">The base URL for the API.</param>
    /// <param name="model">The transcription model to use.</param>
    /// <param name="language">Optional language hint for transcription.</param>
    public TranscriptionService(
        HttpTransport httpTransport,
        string apiKey,
        string baseUrl,
        string model,
        string? language = null)
    {
        _httpTransport = httpTransport ?? throw new ArgumentNullException(nameof(httpTransport));
        _apiKey = apiKey ?? throw new ArgumentNullException(nameof(apiKey));
        _baseUrl = NormalizeBaseUrl(baseUrl);
        _model = string.IsNullOrWhiteSpace(model) ? "whisper-large-v3" : model.Trim();
        _language = string.IsNullOrWhiteSpace(language) ? null : language.Trim();
        _ownsTransport = false;
    }

    /// <summary>
    /// Gets the response format to use for the configured model.
    /// </summary>
    public string ResponseFormat => GetResponseFormat(_model);

    /// <summary>
    /// Determines the appropriate response format for a given model.
    /// </summary>
    /// <param name="model">The model name.</param>
    /// <returns>"verbose_json" if the model supports it, otherwise "json".</returns>
    public static string GetResponseFormat(string model)
    {
        var normalizedModel = model?.Trim().ToLowerInvariant() ?? "";
        return ModelsSupportingVerboseJson.Contains(normalizedModel) ? "verbose_json" : "json";
    }

    /// <inheritdoc/>
    public async Task<TranscriptionResult> TranscribeAsync(
        string audioFilePath,
        CancellationToken cancellationToken = default)
    {
        if (string.IsNullOrWhiteSpace(audioFilePath))
        {
            return TranscriptionResult.Fail(
                TranscriptionError.InvalidResponse("Audio file path is required."));
        }

        if (!File.Exists(audioFilePath))
        {
            return TranscriptionResult.Fail(
                TranscriptionError.NetworkError($"Audio file not found: {audioFilePath}"));
        }

        var url = BuildTranscriptionUrl();
        var responseFormat = ResponseFormat;
        
        var additionalFields = new Dictionary<string, string>
        {
            ["model"] = _model,
            ["response_format"] = responseFormat
        };

        if (!string.IsNullOrEmpty(_language))
        {
            additionalFields["language"] = _language;
        }

        var result = await _httpTransport.UploadFileAsync(
            url,
            audioFilePath,
            "file",
            additionalFields,
            _apiKey,
            cancellationToken);

        if (!result.Success)
        {
            return TranscriptionResult.Fail(MapHttpError(result.Error!));
        }

        return ParseTranscriptResponse(result.Value!, responseFormat);
    }

    /// <summary>
    /// Builds the transcription API endpoint URL.
    /// </summary>
    private string BuildTranscriptionUrl()
    {
        var baseUrl = _baseUrl.TrimEnd('/');
        return $"{baseUrl}/audio/transcriptions";
    }

    /// <summary>
    /// Parses the transcript from the API response.
    /// </summary>
    private TranscriptionResult ParseTranscriptResponse(string responseBody, string responseFormat)
    {
        try
        {
            if (responseFormat == "verbose_json")
            {
                return ParseVerboseJsonResponse(responseBody);
            }
            else
            {
                return ParseSimpleJsonResponse(responseBody);
            }
        }
        catch (JsonException ex)
        {
            return TranscriptionResult.Fail(
                TranscriptionError.InvalidResponse($"Failed to parse transcription response: {ex.Message}"));
        }
    }

    /// <summary>
    /// Parses verbose_json response format with segment metadata for hallucination filtering.
    /// </summary>
    private TranscriptionResult ParseVerboseJsonResponse(string responseBody)
    {
        try
        {
            var response = JsonSerializer.Deserialize<WhisperVerboseResponse>(responseBody);
            
            if (response == null || response.Text == null)
            {
                return TranscriptionResult.Fail(
                    TranscriptionError.InvalidResponse("Empty or invalid response from transcription API."));
            }

            var text = response.Text;

            // Check for hallucination
            if (IsHallucination(text, response.Segments))
            {
                return TranscriptionResult.Ok(string.Empty);
            }

            return TranscriptionResult.Ok(text);
        }
        catch (JsonException ex)
        {
            return TranscriptionResult.Fail(
                TranscriptionError.InvalidResponse($"Failed to parse transcription response: {ex.Message}"));
        }
    }

    /// <summary>
    /// Parses simple json response format (no segment metadata).
    /// </summary>
    private TranscriptionResult ParseSimpleJsonResponse(string responseBody)
    {
        try
        {
            var response = JsonSerializer.Deserialize<WhisperSimpleResponse>(responseBody);
            
            if (response == null || response.Text == null)
            {
                return TranscriptionResult.Fail(
                    TranscriptionError.InvalidResponse("Empty or invalid response from transcription API."));
            }

            return TranscriptionResult.Ok(response.Text);
        }
        catch (JsonException ex)
        {
            return TranscriptionResult.Fail(
                TranscriptionError.InvalidResponse($"Failed to parse transcription response: {ex.Message}"));
        }
    }

    /// <summary>
    /// Determines if a transcript is a hallucination based on known phrases
    /// and the no_speech_prob threshold.
    /// </summary>
    /// <param name="text">The transcript text.</param>
    /// <param name="segments">The segment metadata (may be null if not available).</param>
    /// <returns>True if the transcript should be filtered as a hallucination.</returns>
    private static bool IsHallucination(string text, List<WhisperSegment>? segments)
    {
        // Normalize text for comparison: lowercase and strip punctuation
        var normalized = NormalizeForHallucinationCheck(text);

        // Check if it matches any hallucination phrase
        if (!HallucinationPhrases.Contains(normalized))
        {
            return false;
        }

        // Need segment metadata to check no_speech_prob
        if (segments == null || segments.Count == 0)
        {
            // Can't verify - don't filter
            return false;
        }

        // Check the first segment's no_speech_prob
        var firstSegment = segments[0];
        if (firstSegment.NoSpeechProb == null)
        {
            // Can't verify - don't filter
            return false;
        }

        // Filter if no_speech_prob is at or above threshold
        return firstSegment.NoSpeechProb >= HallucinationNoSpeechThreshold;
    }

    /// <summary>
    /// Normalizes text for hallucination checking by converting to lowercase
    /// and removing punctuation and whitespace from the edges.
    /// </summary>
    private static string NormalizeForHallucinationCheck(string text)
    {
        if (string.IsNullOrEmpty(text))
        {
            return string.Empty;
        }

        var normalized = text.ToLowerInvariant().Trim();
        
        // Remove leading/trailing punctuation
        var chars = normalized.ToCharArray();
        int start = 0;
        int end = chars.Length - 1;

        while (start <= end && char.IsPunctuation(chars[start]))
        {
            start++;
        }

        while (end >= start && char.IsPunctuation(chars[end]))
        {
            end--;
        }

        if (start > end)
        {
            return string.Empty;
        }

        return new string(chars, start, end - start + 1);
    }

    /// <summary>
    /// Maps an HTTP error to a transcription error.
    /// </summary>
    private static TranscriptionError MapHttpError(HttpError httpError)
    {
        return httpError.Type switch
        {
            HttpErrorType.AuthenticationError => 
                TranscriptionError.AuthenticationError(httpError.Message),
            HttpErrorType.AuthorizationError => 
                TranscriptionError.AuthenticationError(httpError.Message),
            HttpErrorType.Timeout => 
                new TranscriptionError(TranscriptionErrorType.Timeout, httpError.Message),
            HttpErrorType.ServerError => 
                TranscriptionError.ServerError(httpError.Message),
            HttpErrorType.NetworkError => 
                TranscriptionError.NetworkError(httpError.Message),
            _ => 
                TranscriptionError.NetworkError(httpError.Message)
        };
    }

    /// <summary>
    /// Normalizes the base URL by removing trailing slashes.
    /// </summary>
    private static string NormalizeBaseUrl(string baseUrl)
    {
        if (string.IsNullOrWhiteSpace(baseUrl))
        {
            return "https://api.groq.com/openai/v1";
        }
        return baseUrl.TrimEnd('/');
    }

    /// <summary>
    /// Disposes resources.
    /// </summary>
    public void Dispose()
    {
        if (!_disposed)
        {
            if (_ownsTransport)
            {
                _httpTransport.Dispose();
            }
            _disposed = true;
        }
        GC.SuppressFinalize(this);
    }
}
