using System.Reflection;
using System.Text.Json;
using Xunit;
using FreeFlowWindows.Core.Services;
using FreeFlowWindows.Core.Http;
using FreeFlowWindows.Core.Interfaces;
using FreeFlowWindows.Core.Models;

namespace FreeFlowWindows.Tests;

/// <summary>
/// Unit tests for TranscriptionService.
/// Tests response parsing, hallucination filtering, timeout handling, and auth error mapping.
/// Validates: Requirements 4.4, 4.5, 4.6, 4.9
/// </summary>
public class TranscriptionServiceTests : IDisposable
{
    private readonly string _testAudioFilePath;
    private readonly string _tempDirectory;

    public TranscriptionServiceTests()
    {
        _tempDirectory = Path.Combine(Path.GetTempPath(), $"TranscriptionTests_{Guid.NewGuid():N}");
        Directory.CreateDirectory(_tempDirectory);
        
        // Create a minimal valid WAV file for tests that need a file to exist
        _testAudioFilePath = Path.Combine(_tempDirectory, "test_audio.wav");
        CreateMinimalWavFile(_testAudioFilePath);
    }

    public void Dispose()
    {
        // Cleanup temp directory
        try
        {
            if (Directory.Exists(_tempDirectory))
            {
                Directory.Delete(_tempDirectory, recursive: true);
            }
        }
        catch
        {
            // Ignore cleanup errors
        }
    }

    private static void CreateMinimalWavFile(string path)
    {
        // Create a minimal valid WAV file (44 byte header + minimal data)
        using var fs = File.Create(path);
        // RIFF header
        fs.Write("RIFF"u8);
        fs.Write(BitConverter.GetBytes(36)); // file size - 8
        fs.Write("WAVE"u8);
        // fmt chunk
        fs.Write("fmt "u8);
        fs.Write(BitConverter.GetBytes(16)); // chunk size
        fs.Write(BitConverter.GetBytes((short)1)); // PCM format
        fs.Write(BitConverter.GetBytes((short)1)); // mono
        fs.Write(BitConverter.GetBytes(16000)); // sample rate
        fs.Write(BitConverter.GetBytes(32000)); // byte rate
        fs.Write(BitConverter.GetBytes((short)2)); // block align
        fs.Write(BitConverter.GetBytes((short)16)); // bits per sample
        // data chunk
        fs.Write("data"u8);
        fs.Write(BitConverter.GetBytes(0)); // data size
    }

    #region Response Format Tests

    [Theory]
    [InlineData("whisper-large-v3", "verbose_json")]
    [InlineData("whisper-large-v3-turbo", "verbose_json")]
    [InlineData("whisper-1", "verbose_json")]
    [InlineData("WHISPER-LARGE-V3", "verbose_json")] // Case insensitive
    [InlineData("Whisper-Large-V3", "verbose_json")] // Mixed case
    [InlineData("other-model", "json")]
    [InlineData("gpt-4o-transcribe", "json")]
    [InlineData("", "json")]
    public void GetResponseFormat_ReturnsCorrectFormatForModel(string model, string expectedFormat)
    {
        // Act
        var result = TranscriptionService.GetResponseFormat(model);

        // Assert
        Assert.Equal(expectedFormat, result);
    }

    #endregion

    #region Successful Transcription Response Parsing Tests

    [Fact]
    public void ParseVerboseJsonResponse_ValidResponse_ReturnsTranscript()
    {
        // Arrange
        var responseJson = """
            {
                "text": "Hello, world! This is a test transcription.",
                "segments": [
                    {
                        "start": 0.0,
                        "end": 2.5,
                        "text": "Hello, world! This is a test transcription.",
                        "no_speech_prob": 0.01
                    }
                ],
                "language": "en",
                "duration": 2.5
            }
            """;

        // Act
        var result = InvokeParseVerboseJsonResponse(responseJson);

        // Assert
        Assert.True(result.Success);
        Assert.Equal("Hello, world! This is a test transcription.", result.Transcript);
    }

    [Fact]
    public void ParseVerboseJsonResponse_MultipleSegments_ReturnsFullText()
    {
        // Arrange
        var responseJson = """
            {
                "text": "First segment. Second segment.",
                "segments": [
                    {
                        "start": 0.0,
                        "end": 1.0,
                        "text": "First segment.",
                        "no_speech_prob": 0.02
                    },
                    {
                        "start": 1.0,
                        "end": 2.0,
                        "text": "Second segment.",
                        "no_speech_prob": 0.03
                    }
                ]
            }
            """;

        // Act
        var result = InvokeParseVerboseJsonResponse(responseJson);

        // Assert
        Assert.True(result.Success);
        Assert.Equal("First segment. Second segment.", result.Transcript);
    }

    [Fact]
    public void ParseSimpleJsonResponse_ValidResponse_ReturnsTranscript()
    {
        // Arrange
        var responseJson = """
            {
                "text": "Simple transcription without segments."
            }
            """;

        // Act
        var result = InvokeParseSimpleJsonResponse(responseJson);

        // Assert
        Assert.True(result.Success);
        Assert.Equal("Simple transcription without segments.", result.Transcript);
    }

    [Fact]
    public void ParseVerboseJsonResponse_EmptyText_ReturnsEmptyString()
    {
        // Arrange
        var responseJson = """
            {
                "text": "",
                "segments": []
            }
            """;

        // Act
        var result = InvokeParseVerboseJsonResponse(responseJson);

        // Assert
        Assert.True(result.Success);
        Assert.Equal("", result.Transcript);
    }

    [Fact]
    public void ParseVerboseJsonResponse_NullResponse_ReturnsError()
    {
        // Arrange
        var responseJson = "null";

        // Act
        var result = InvokeParseVerboseJsonResponse(responseJson);

        // Assert
        Assert.False(result.Success);
        Assert.Equal(TranscriptionErrorType.InvalidResponse, result.Error?.Type);
    }

    [Fact]
    public void ParseVerboseJsonResponse_InvalidJson_ReturnsError()
    {
        // Arrange
        var responseJson = "{ invalid json }";

        // Act
        var result = InvokeParseVerboseJsonResponse(responseJson);

        // Assert
        Assert.False(result.Success);
        Assert.Equal(TranscriptionErrorType.InvalidResponse, result.Error?.Type);
        Assert.Contains("Failed to parse", result.Error?.Message);
    }

    [Fact]
    public void ParseSimpleJsonResponse_NullText_ReturnsError()
    {
        // Arrange
        var responseJson = """
            {
                "text": null
            }
            """;

        // Act
        var result = InvokeParseSimpleJsonResponse(responseJson);

        // Assert
        Assert.False(result.Success);
        Assert.Equal(TranscriptionErrorType.InvalidResponse, result.Error?.Type);
    }

    #endregion

    #region Hallucination Filtering Tests

    [Theory]
    [InlineData("Thank you", 0.15, true)]
    [InlineData("thank you for watching", 0.2, true)]
    [InlineData("Thank you very much", 0.11, true)]
    [InlineData("please subscribe", 0.5, true)]
    [InlineData("like and subscribe", 0.3, true)]
    [InlineData("subtitles by the amara.org community", 0.9, true)]
    [InlineData("You", 0.8, true)]
    public void Hallucination_HighNoSpeechProb_FiltersKnownPhrase(string text, double noSpeechProb, bool shouldFilter)
    {
        // Arrange
        var responseJson = $$"""
            {
                "text": "{{text}}",
                "segments": [
                    {
                        "start": 0.0,
                        "end": 1.0,
                        "text": "{{text}}",
                        "no_speech_prob": {{noSpeechProb}}
                    }
                ]
            }
            """;

        // Act
        var result = InvokeParseVerboseJsonResponse(responseJson);

        // Assert
        Assert.True(result.Success);
        if (shouldFilter)
        {
            Assert.Equal(string.Empty, result.Transcript);
        }
        else
        {
            Assert.NotEmpty(result.Transcript!);
        }
    }

    [Theory]
    [InlineData("Thank you", 0.05)] // Below threshold
    [InlineData("thank you for watching", 0.09)] // Below threshold
    [InlineData("Thank you very much", 0.0)] // Zero
    public void Hallucination_LowNoSpeechProb_DoesNotFilter(string text, double noSpeechProb)
    {
        // Arrange
        var responseJson = $$"""
            {
                "text": "{{text}}",
                "segments": [
                    {
                        "start": 0.0,
                        "end": 1.0,
                        "text": "{{text}}",
                        "no_speech_prob": {{noSpeechProb}}
                    }
                ]
            }
            """;

        // Act
        var result = InvokeParseVerboseJsonResponse(responseJson);

        // Assert
        Assert.True(result.Success);
        Assert.Equal(text, result.Transcript);
    }

    [Fact]
    public void Hallucination_RealContent_NotFiltered()
    {
        // Arrange - Real speech that happens to include "thank you"
        var responseJson = """
            {
                "text": "I wanted to thank you for your help with the project.",
                "segments": [
                    {
                        "start": 0.0,
                        "end": 3.0,
                        "text": "I wanted to thank you for your help with the project.",
                        "no_speech_prob": 0.02
                    }
                ]
            }
            """;

        // Act
        var result = InvokeParseVerboseJsonResponse(responseJson);

        // Assert
        Assert.True(result.Success);
        Assert.Equal("I wanted to thank you for your help with the project.", result.Transcript);
    }

    [Fact]
    public void Hallucination_NoSegments_DoesNotFilter()
    {
        // Arrange - Hallucination phrase but no segment metadata to verify
        var responseJson = """
            {
                "text": "Thank you",
                "segments": null
            }
            """;

        // Act
        var result = InvokeParseVerboseJsonResponse(responseJson);

        // Assert
        Assert.True(result.Success);
        Assert.Equal("Thank you", result.Transcript);
    }

    [Fact]
    public void Hallucination_EmptySegments_DoesNotFilter()
    {
        // Arrange
        var responseJson = """
            {
                "text": "Thank you",
                "segments": []
            }
            """;

        // Act
        var result = InvokeParseVerboseJsonResponse(responseJson);

        // Assert
        Assert.True(result.Success);
        Assert.Equal("Thank you", result.Transcript);
    }

    [Fact]
    public void Hallucination_NoNoSpeechProb_DoesNotFilter()
    {
        // Arrange - Segment exists but no_speech_prob is missing
        var responseJson = """
            {
                "text": "Thank you",
                "segments": [
                    {
                        "start": 0.0,
                        "end": 1.0,
                        "text": "Thank you"
                    }
                ]
            }
            """;

        // Act
        var result = InvokeParseVerboseJsonResponse(responseJson);

        // Assert
        Assert.True(result.Success);
        Assert.Equal("Thank you", result.Transcript);
    }

    [Theory]
    [InlineData("Thank you.", 0.15)] // With trailing punctuation
    [InlineData(".Thank you", 0.15)] // With leading punctuation
    [InlineData("...Thank you...", 0.15)] // With multiple punctuation
    [InlineData("  Thank you  ", 0.15)] // With whitespace
    public void Hallucination_WithPunctuation_StillFiltered(string text, double noSpeechProb)
    {
        // Arrange
        var responseJson = $$"""
            {
                "text": "{{text}}",
                "segments": [
                    {
                        "start": 0.0,
                        "end": 1.0,
                        "text": "{{text}}",
                        "no_speech_prob": {{noSpeechProb}}
                    }
                ]
            }
            """;

        // Act
        var result = InvokeParseVerboseJsonResponse(responseJson);

        // Assert
        Assert.True(result.Success);
        Assert.Equal(string.Empty, result.Transcript);
    }

    [Fact]
    public void Hallucination_ExactlyAtThreshold_Filtered()
    {
        // Arrange - Exactly at 0.1 threshold
        var responseJson = """
            {
                "text": "Thank you",
                "segments": [
                    {
                        "start": 0.0,
                        "end": 1.0,
                        "text": "Thank you",
                        "no_speech_prob": 0.1
                    }
                ]
            }
            """;

        // Act
        var result = InvokeParseVerboseJsonResponse(responseJson);

        // Assert
        Assert.True(result.Success);
        Assert.Equal(string.Empty, result.Transcript);
    }

    #endregion

    #region Error Mapping Tests

    [Fact]
    public void MapHttpError_AuthenticationError_MapsCorrectly()
    {
        // Arrange
        var httpError = new HttpError(HttpErrorType.AuthenticationError, "Invalid API key for api.groq.com", 401);

        // Act
        var result = InvokeMapHttpError(httpError);

        // Assert
        Assert.Equal(TranscriptionErrorType.AuthenticationError, result.Type);
        Assert.Contains("Invalid API key", result.Message);
    }

    [Fact]
    public void MapHttpError_AuthorizationError_MapsToAuthenticationError()
    {
        // Arrange - HTTP 403 should map to auth error for user
        var httpError = new HttpError(HttpErrorType.AuthorizationError, "Key lacks permission", 403);

        // Act
        var result = InvokeMapHttpError(httpError);

        // Assert
        Assert.Equal(TranscriptionErrorType.AuthenticationError, result.Type);
    }

    [Fact]
    public void MapHttpError_TimeoutError_MapsCorrectly()
    {
        // Arrange
        var httpError = HttpError.TimeoutFailure(20);

        // Act
        var result = InvokeMapHttpError(httpError);

        // Assert
        Assert.Equal(TranscriptionErrorType.Timeout, result.Type);
        Assert.Contains("timed out", result.Message);
    }

    [Fact]
    public void MapHttpError_ServerError_MapsCorrectly()
    {
        // Arrange
        var httpError = new HttpError(HttpErrorType.ServerError, "Provider error at api.groq.com", 500);

        // Act
        var result = InvokeMapHttpError(httpError);

        // Assert
        Assert.Equal(TranscriptionErrorType.ServerError, result.Type);
    }

    [Fact]
    public void MapHttpError_NetworkError_MapsCorrectly()
    {
        // Arrange
        var httpError = HttpError.NetworkFailure("Connection refused");

        // Act
        var result = InvokeMapHttpError(httpError);

        // Assert
        Assert.Equal(TranscriptionErrorType.NetworkError, result.Type);
    }

    [Fact]
    public void MapHttpError_UnknownError_MapsToNetworkError()
    {
        // Arrange
        var httpError = new HttpError(HttpErrorType.Unknown, "Unknown error", 418);

        // Act
        var result = InvokeMapHttpError(httpError);

        // Assert
        Assert.Equal(TranscriptionErrorType.NetworkError, result.Type);
    }

    #endregion

    #region Input Validation Tests

    [Fact]
    public async Task TranscribeAsync_NullFilePath_ReturnsError()
    {
        // Arrange
        using var service = CreateServiceForValidation();

        // Act
        var result = await service.TranscribeAsync(null!);

        // Assert
        Assert.False(result.Success);
        Assert.Equal(TranscriptionErrorType.InvalidResponse, result.Error?.Type);
        Assert.Contains("required", result.Error?.Message);
    }

    [Fact]
    public async Task TranscribeAsync_EmptyFilePath_ReturnsError()
    {
        // Arrange
        using var service = CreateServiceForValidation();

        // Act
        var result = await service.TranscribeAsync("");

        // Assert
        Assert.False(result.Success);
        Assert.Equal(TranscriptionErrorType.InvalidResponse, result.Error?.Type);
    }

    [Fact]
    public async Task TranscribeAsync_WhitespaceFilePath_ReturnsError()
    {
        // Arrange
        using var service = CreateServiceForValidation();

        // Act
        var result = await service.TranscribeAsync("   ");

        // Assert
        Assert.False(result.Success);
        Assert.Equal(TranscriptionErrorType.InvalidResponse, result.Error?.Type);
    }

    [Fact]
    public async Task TranscribeAsync_NonExistentFile_ReturnsError()
    {
        // Arrange
        using var service = CreateServiceForValidation();
        var nonExistentPath = Path.Combine(_tempDirectory, "nonexistent.wav");

        // Act
        var result = await service.TranscribeAsync(nonExistentPath);

        // Assert
        Assert.False(result.Success);
        Assert.Equal(TranscriptionErrorType.NetworkError, result.Error?.Type);
        Assert.Contains("not found", result.Error?.Message);
    }

    #endregion

    #region Constructor and Configuration Tests

    [Fact]
    public void Constructor_DefaultValues_SetsCorrectDefaults()
    {
        // Arrange & Act
        using var service = new TranscriptionService("test-api-key");

        // Assert
        Assert.Equal("verbose_json", service.ResponseFormat);
    }

    [Fact]
    public void Constructor_CustomModel_UsesCorrectResponseFormat()
    {
        // Arrange & Act
        using var service = new TranscriptionService("test-api-key", model: "gpt-4o-transcribe");

        // Assert
        Assert.Equal("json", service.ResponseFormat);
    }

    [Fact]
    public void Constructor_EmptyModel_UsesDefault()
    {
        // Arrange & Act
        using var service = new TranscriptionService("test-api-key", model: "");

        // Assert - Default model is whisper-large-v3 which supports verbose_json
        Assert.Equal("verbose_json", service.ResponseFormat);
    }

    [Fact]
    public void Constructor_WhitespaceModel_UsesDefault()
    {
        // Arrange & Act
        using var service = new TranscriptionService("test-api-key", model: "   ");

        // Assert
        Assert.Equal("verbose_json", service.ResponseFormat);
    }

    [Fact]
    public void Constructor_NullApiKey_ThrowsArgumentNullException()
    {
        // Act & Assert
        Assert.Throws<ArgumentNullException>(() => new TranscriptionService(null!));
    }

    [Theory]
    [InlineData("https://api.groq.com/openai/v1")]
    [InlineData("https://api.groq.com/openai/v1/")]
    [InlineData("https://api.openai.com/v1")]
    [InlineData("https://custom-endpoint.com/api")]
    public void Constructor_VariousBaseUrls_AcceptsAll(string baseUrl)
    {
        // Act
        using var service = new TranscriptionService("test-key", baseUrl);

        // Assert - No exception thrown
        Assert.NotNull(service);
    }

    [Fact]
    public void Constructor_EmptyBaseUrl_UsesDefault()
    {
        // Arrange & Act - Should not throw, uses default
        using var service = new TranscriptionService("test-key", baseUrl: "");

        // Assert
        Assert.NotNull(service);
    }

    #endregion

    #region Dispose Tests

    [Fact]
    public void Dispose_CalledMultipleTimes_DoesNotThrow()
    {
        // Arrange
        var service = new TranscriptionService("test-api-key");

        // Act & Assert - Should not throw
        service.Dispose();
        service.Dispose();
        service.Dispose();
    }

    #endregion

    #region Helper Methods

    /// <summary>
    /// Creates a TranscriptionService for validation tests (won't make actual HTTP calls).
    /// </summary>
    private TranscriptionService CreateServiceForValidation()
    {
        return new TranscriptionService("test-api-key", timeoutSeconds: 1);
    }

    /// <summary>
    /// Invokes the private ParseVerboseJsonResponse method via reflection.
    /// </summary>
    private static TranscriptionResult InvokeParseVerboseJsonResponse(string responseBody)
    {
        // Create instance to invoke private method
        using var service = new TranscriptionService("test-api-key");
        
        var method = typeof(TranscriptionService).GetMethod(
            "ParseVerboseJsonResponse",
            BindingFlags.NonPublic | BindingFlags.Instance);
        
        if (method == null)
            throw new InvalidOperationException("ParseVerboseJsonResponse method not found");
        
        return (TranscriptionResult)method.Invoke(service, new object[] { responseBody })!;
    }

    /// <summary>
    /// Invokes the private ParseSimpleJsonResponse method via reflection.
    /// </summary>
    private static TranscriptionResult InvokeParseSimpleJsonResponse(string responseBody)
    {
        using var service = new TranscriptionService("test-api-key");
        
        var method = typeof(TranscriptionService).GetMethod(
            "ParseSimpleJsonResponse",
            BindingFlags.NonPublic | BindingFlags.Instance);
        
        if (method == null)
            throw new InvalidOperationException("ParseSimpleJsonResponse method not found");
        
        return (TranscriptionResult)method.Invoke(service, new object[] { responseBody })!;
    }

    /// <summary>
    /// Invokes the private MapHttpError method via reflection.
    /// </summary>
    private static TranscriptionError InvokeMapHttpError(HttpError httpError)
    {
        var method = typeof(TranscriptionService).GetMethod(
            "MapHttpError",
            BindingFlags.NonPublic | BindingFlags.Static);
        
        if (method == null)
            throw new InvalidOperationException("MapHttpError method not found");
        
        return (TranscriptionError)method.Invoke(null, new object[] { httpError })!;
    }

    #endregion
}
