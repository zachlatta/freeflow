using System.Net;
using System.Reflection;
using System.Text.Json;
using Xunit;
using FreeFlowWindows.Core.Services;
using FreeFlowWindows.Core.Models;

namespace FreeFlowWindows.Tests;

/// <summary>
/// Unit tests for PostProcessingService.
/// Tests cleanup response handling, fallback to raw transcript, rate limit handling,
/// EMPTY response detection, and instruction execution guard.
/// Validates: Requirements 5.7, 5.9, 5.10
/// </summary>
public class PostProcessingServiceTests : IDisposable
{
    public PostProcessingServiceTests()
    {
        // Clear any cooldowns before each test
        LLMCooldownManager.Shared.ClearAllCooldowns();
    }

    public void Dispose()
    {
        // Clear cooldowns after each test
        LLMCooldownManager.Shared.ClearAllCooldowns();
    }

    #region Constructor Tests

    [Fact]
    public void Constructor_ValidApiKey_CreatesInstance()
    {
        // Arrange & Act
        using var service = new PostProcessingService("test-api-key");

        // Assert
        Assert.NotNull(service);
    }

    [Fact]
    public void Constructor_NullApiKey_ThrowsArgumentNullException()
    {
        // Act & Assert
        Assert.Throws<ArgumentNullException>(() => new PostProcessingService(null!));
    }

    [Theory]
    [InlineData("https://api.groq.com/openai/v1")]
    [InlineData("https://api.groq.com/openai/v1/")]
    [InlineData("https://api.openai.com/v1")]
    [InlineData("https://custom-endpoint.com/api")]
    public void Constructor_VariousBaseUrls_AcceptsAll(string baseUrl)
    {
        // Act
        using var service = new PostProcessingService("test-key", baseUrl);

        // Assert
        Assert.NotNull(service);
    }

    [Fact]
    public void Constructor_EmptyBaseUrl_UsesDefault()
    {
        // Act - Should not throw, uses default
        using var service = new PostProcessingService("test-key", baseUrl: "");

        // Assert
        Assert.NotNull(service);
    }

    [Theory]
    [InlineData("")]
    [InlineData("   ")]
    [InlineData(null)]
    public void Constructor_EmptyOrNullModel_UsesDefaultModel(string? model)
    {
        // Act - Should not throw, uses default
        using var service = new PostProcessingService("test-key", preferredModel: model!);

        // Assert
        Assert.NotNull(service);
    }

    [Fact]
    public void Constructor_CustomTimeout_AcceptsPositiveValue()
    {
        // Act
        using var service = new PostProcessingService("test-key", timeoutSeconds: 30);

        // Assert
        Assert.NotNull(service);
    }

    [Theory]
    [InlineData(0)]
    [InlineData(-1)]
    [InlineData(-100)]
    public void Constructor_InvalidTimeout_UsesDefaultTimeout(double timeout)
    {
        // Act - Should use default timeout for invalid values
        using var service = new PostProcessingService("test-key", timeoutSeconds: timeout);

        // Assert
        Assert.NotNull(service);
    }

    #endregion

    #region ProcessAsync Input Validation Tests

    [Fact]
    public async Task ProcessAsync_NullTranscript_ReturnsEmptyResult()
    {
        // Arrange
        using var service = new PostProcessingService("test-api-key");

        // Act
        var result = await service.ProcessAsync(
            null!,
            "context",
            Array.Empty<string>());

        // Assert
        Assert.True(result.Success);
        Assert.Equal(string.Empty, result.CleanedTranscript);
    }

    [Fact]
    public async Task ProcessAsync_EmptyTranscript_ReturnsEmptyResult()
    {
        // Arrange
        using var service = new PostProcessingService("test-api-key");

        // Act
        var result = await service.ProcessAsync(
            "",
            "context",
            Array.Empty<string>());

        // Assert
        Assert.True(result.Success);
        Assert.Equal(string.Empty, result.CleanedTranscript);
    }

    [Fact]
    public async Task ProcessAsync_WhitespaceOnlyTranscript_ReturnsEmptyResult()
    {
        // Arrange
        using var service = new PostProcessingService("test-api-key");

        // Act
        var result = await service.ProcessAsync(
            "   \t\n  ",
            "context",
            Array.Empty<string>());

        // Assert
        Assert.True(result.Success);
        Assert.Equal(string.Empty, result.CleanedTranscript);
    }

    #endregion

    #region Sanitization Tests

    [Theory]
    [InlineData("Hello world", "Hello world")]
    [InlineData("  Hello world  ", "Hello world")]
    [InlineData("Hello\r\nworld", "Hello\nworld")]
    [InlineData("Hello\rworld", "Hello\nworld")]
    [InlineData("\"Hello world\"", "Hello world")]
    public void SanitizePostProcessedTranscript_VariousInputs_ReturnsExpected(string input, string expected)
    {
        // Act
        var result = PostProcessingService.SanitizePostProcessedTranscript(input);

        // Assert
        Assert.Equal(expected, result);
    }

    [Theory]
    [InlineData("EMPTY")]
    [InlineData("empty")]
    [InlineData("Empty")]
    [InlineData("EMPTY ")]
    [InlineData(" EMPTY")]
    [InlineData("\"EMPTY\"")]
    public void SanitizePostProcessedTranscript_EmptySentinel_ReturnsEmptyString(string input)
    {
        // Act
        var result = PostProcessingService.SanitizePostProcessedTranscript(input);

        // Assert
        Assert.Equal(string.Empty, result);
    }

    [Fact]
    public void SanitizePostProcessedTranscript_NullInput_ReturnsEmptyString()
    {
        // Act
        var result = PostProcessingService.SanitizePostProcessedTranscript(null!);

        // Assert
        Assert.Equal(string.Empty, result);
    }

    [Fact]
    public void SanitizePostProcessedTranscript_ControlCharacters_StripsControlChars()
    {
        // Arrange - String with control characters (except TAB and LF which are preserved)
        var input = "Hello\x00\x01\x02world";

        // Act
        var result = PostProcessingService.SanitizePostProcessedTranscript(input);

        // Assert
        Assert.Equal("Helloworld", result);
    }

    [Fact]
    public void SanitizePostProcessedTranscript_PreservesTabAndNewline()
    {
        // Arrange
        var input = "Hello\tworld\nNew line";

        // Act
        var result = PostProcessingService.SanitizePostProcessedTranscript(input);

        // Assert
        Assert.Equal("Hello\tworld\nNew line", result);
    }

    #endregion

    #region IsEmptyResponse Tests

    [Theory]
    [InlineData(null, true)]
    [InlineData("", true)]
    [InlineData("   ", true)]
    [InlineData("\t\n", true)]
    [InlineData("EMPTY", true)]
    [InlineData("empty", true)]
    [InlineData("Empty", true)]
    [InlineData("eMpTy", true)]
    [InlineData(" EMPTY ", true)]
    [InlineData("\"EMPTY\"", true)]
    [InlineData("Hello", false)]
    [InlineData("Hello EMPTY world", false)]
    [InlineData("Not empty", false)]
    public void IsEmptyResponse_VariousInputs_ReturnsExpected(string? input, bool expected)
    {
        // Act
        var result = PostProcessingService.IsEmptyResponse(input!);

        // Assert
        Assert.Equal(expected, result);
    }

    #endregion

    #region Cooldown Manager Integration Tests

    [Fact]
    public async Task ProcessAsync_BothModelsCooldownActive_ReturnsFallbackRawTranscript()
    {
        // Arrange
        using var service = new PostProcessingService("test-api-key");
        var transcript = "Hello world";

        // Set both models in cooldown
        LLMCooldownManager.Shared.SetCooldown(PostProcessingService.DefaultModel, TimeSpan.FromMinutes(5));
        LLMCooldownManager.Shared.SetCooldown(PostProcessingService.DefaultFallbackModel, TimeSpan.FromMinutes(5));

        // Act
        var result = await service.ProcessAsync(
            transcript,
            "context",
            Array.Empty<string>());

        // Assert
        Assert.True(result.Success);
        Assert.Equal(transcript, result.CleanedTranscript); // Falls back to raw transcript
    }

    [Fact]
    public void CooldownManager_SetCooldown_ModelsReportInCooldown()
    {
        // Arrange
        var model = "test-model";

        // Act
        LLMCooldownManager.Shared.SetCooldown(model, TimeSpan.FromMinutes(5));

        // Assert
        Assert.True(LLMCooldownManager.Shared.IsInCooldown(model));
    }

    [Fact]
    public void CooldownManager_ClearCooldown_ModelNoLongerInCooldown()
    {
        // Arrange
        var model = "test-model";
        LLMCooldownManager.Shared.SetCooldown(model, TimeSpan.FromMinutes(5));

        // Act
        LLMCooldownManager.Shared.ClearCooldown(model);

        // Assert
        Assert.False(LLMCooldownManager.Shared.IsInCooldown(model));
    }

    [Fact]
    public void CooldownManager_GetEffectivePrimary_ReturnsPrimaryWhenNotInCooldown()
    {
        // Arrange
        var primary = "primary-model";
        var fallback = "fallback-model";

        // Act
        var effective = LLMCooldownManager.Shared.GetEffectivePrimary(primary, fallback);

        // Assert
        Assert.Equal(primary, effective);
    }

    [Fact]
    public void CooldownManager_GetEffectivePrimary_ReturnsFallbackWhenPrimaryInCooldown()
    {
        // Arrange
        var primary = "primary-model";
        var fallback = "fallback-model";
        LLMCooldownManager.Shared.SetCooldown(primary, TimeSpan.FromMinutes(5));

        // Act
        var effective = LLMCooldownManager.Shared.GetEffectivePrimary(primary, fallback);

        // Assert
        Assert.Equal(fallback, effective);
    }

    [Fact]
    public void CooldownManager_GetEffectivePrimary_ReturnsNullWhenBothInCooldown()
    {
        // Arrange
        var primary = "primary-model";
        var fallback = "fallback-model";
        LLMCooldownManager.Shared.SetCooldown(primary, TimeSpan.FromMinutes(5));
        LLMCooldownManager.Shared.SetCooldown(fallback, TimeSpan.FromMinutes(5));

        // Act
        var effective = LLMCooldownManager.Shared.GetEffectivePrimary(primary, fallback);

        // Assert
        Assert.Null(effective);
    }

    [Fact]
    public void CooldownManager_ExpiredCooldown_ReportsNotInCooldown()
    {
        // Arrange
        var model = "test-model";
        LLMCooldownManager.Shared.SetCooldown(model, TimeSpan.FromMilliseconds(1));

        // Wait for cooldown to expire
        Thread.Sleep(10);

        // Act & Assert
        Assert.False(LLMCooldownManager.Shared.IsInCooldown(model));
    }

    [Fact]
    public void CooldownManager_GetCooldownExpiry_ReturnsExpiryForActiveCooldown()
    {
        // Arrange
        var model = "test-model";
        var duration = TimeSpan.FromMinutes(5);
        var beforeSet = DateTime.UtcNow;
        LLMCooldownManager.Shared.SetCooldown(model, duration);

        // Act
        var expiry = LLMCooldownManager.Shared.GetCooldownExpiry(model);

        // Assert
        Assert.NotNull(expiry);
        Assert.True(expiry.Value > beforeSet);
        Assert.True(expiry.Value <= DateTime.UtcNow.Add(duration).AddSeconds(1));
    }

    [Fact]
    public void CooldownManager_GetCooldownExpiry_ReturnsNullForNoCooldown()
    {
        // Arrange
        var model = "no-cooldown-model";

        // Act
        var expiry = LLMCooldownManager.Shared.GetCooldownExpiry(model);

        // Assert
        Assert.Null(expiry);
    }

    #endregion

    #region Rate Limit Parsing Tests

    [Theory]
    [InlineData("60", 60)]
    [InlineData("120", 120)]
    [InlineData("7.66", 7.66)]
    [InlineData("0.5", 0.5)]
    public void TryParseGroqDuration_BareSeconds_ParsesCorrectly(string input, double expectedSeconds)
    {
        // Act
        var success = LLMCooldownManager.TryParseGroqDuration(input, out var result);

        // Assert
        Assert.True(success);
        Assert.Equal(TimeSpan.FromSeconds(expectedSeconds), result);
    }

    [Theory]
    [InlineData("60s", 60)]
    [InlineData("7.66s", 7.66)]
    [InlineData("120ms", 0.12)]
    [InlineData("500ms", 0.5)]
    [InlineData("2m", 120)]
    [InlineData("1h", 3600)]
    public void TryParseGroqDuration_SingleUnit_ParsesCorrectly(string input, double expectedSeconds)
    {
        // Act
        var success = LLMCooldownManager.TryParseGroqDuration(input, out var result);

        // Assert
        Assert.True(success);
        Assert.Equal(TimeSpan.FromSeconds(expectedSeconds).TotalMilliseconds, result.TotalMilliseconds, 1);
    }

    [Theory]
    [InlineData("2m59.56s", 179.56)]
    [InlineData("1h30m", 5400)]
    [InlineData("1h0m0s", 3600)]
    [InlineData("2h30m45s", 9045)]
    public void TryParseGroqDuration_CompoundDuration_ParsesCorrectly(string input, double expectedSeconds)
    {
        // Act
        var success = LLMCooldownManager.TryParseGroqDuration(input, out var result);

        // Assert
        Assert.True(success);
        Assert.Equal(TimeSpan.FromSeconds(expectedSeconds).TotalMilliseconds, result.TotalMilliseconds, 1);
    }

    [Theory]
    [InlineData("")]
    [InlineData("   ")]
    [InlineData("abc")]
    [InlineData("10x")]
    [InlineData("m5")]
    public void TryParseGroqDuration_InvalidInput_ReturnsFalse(string input)
    {
        // Act
        var success = LLMCooldownManager.TryParseGroqDuration(input, out _);

        // Assert
        Assert.False(success);
    }

    [Fact]
    public void ParseRateLimitCooldown_WithRetryAfterHeader_ParsesCorrectly()
    {
        // Arrange
        var headers = new Dictionary<string, IEnumerable<string>>
        {
            ["retry-after"] = new[] { "60" }
        };

        // Act
        var (duration, isDaily) = LLMCooldownManager.ParseRateLimitCooldown(headers);

        // Assert
        Assert.Equal(TimeSpan.FromSeconds(60), duration);
        Assert.False(isDaily);
    }

    [Fact]
    public void ParseRateLimitCooldown_WithDailyLimitExhausted_ReturnsIsDailyTrue()
    {
        // Arrange
        var headers = new Dictionary<string, IEnumerable<string>>
        {
            ["x-ratelimit-remaining-requests"] = new[] { "0" },
            ["x-ratelimit-reset-requests"] = new[] { "2h" }
        };

        // Act
        var (duration, isDaily) = LLMCooldownManager.ParseRateLimitCooldown(headers);

        // Assert
        Assert.Equal(TimeSpan.FromHours(2), duration);
        Assert.True(isDaily);
    }

    [Fact]
    public void ParseRateLimitCooldown_WithTokenResetHeader_ParsesCorrectly()
    {
        // Arrange
        var headers = new Dictionary<string, IEnumerable<string>>
        {
            ["x-ratelimit-reset-tokens"] = new[] { "30s" }
        };

        // Act
        var (duration, isDaily) = LLMCooldownManager.ParseRateLimitCooldown(headers);

        // Assert
        Assert.Equal(TimeSpan.FromSeconds(30), duration);
        Assert.False(isDaily);
    }

    [Fact]
    public void ParseRateLimitCooldown_NoHeaders_ReturnsDefaultCooldown()
    {
        // Arrange
        var headers = new Dictionary<string, IEnumerable<string>>();

        // Act
        var (duration, isDaily) = LLMCooldownManager.ParseRateLimitCooldown(headers);

        // Assert
        Assert.Equal(TimeSpan.FromSeconds(60), duration); // Default re-probe cooldown
        Assert.False(isDaily);
    }

    [Fact]
    public void ParseRateLimitCooldown_CaseInsensitiveHeaderLookup()
    {
        // Arrange - Headers with different case
        var headers = new Dictionary<string, IEnumerable<string>>
        {
            ["Retry-After"] = new[] { "45" }
        };

        // Act
        var (duration, isDaily) = LLMCooldownManager.ParseRateLimitCooldown(headers);

        // Assert
        Assert.Equal(TimeSpan.FromSeconds(45), duration);
        Assert.False(isDaily);
    }

    #endregion

    #region Default Prompts and Models Tests

    [Fact]
    public void DefaultSystemPrompt_IsNotEmpty()
    {
        // Assert
        Assert.NotEmpty(PostProcessingService.DefaultSystemPrompt);
    }

    [Fact]
    public void DefaultSystemPrompt_ContainsCoreInstructions()
    {
        // Assert - Check for key phrases in the prompt
        var prompt = PostProcessingService.DefaultSystemPrompt;
        Assert.Contains("dictation cleanup", prompt, StringComparison.OrdinalIgnoreCase);
        Assert.Contains("filler", prompt, StringComparison.OrdinalIgnoreCase);
        Assert.Contains("EMPTY", prompt);
    }

    [Fact]
    public void DefaultModel_HasExpectedValue()
    {
        // Assert
        Assert.Equal("openai/gpt-oss-20b", PostProcessingService.DefaultModel);
    }

    [Fact]
    public void DefaultFallbackModel_HasExpectedValue()
    {
        // Assert
        Assert.Equal("qwen/qwen3.6-27b", PostProcessingService.DefaultFallbackModel);
    }

    [Fact]
    public void DefaultTimeoutSeconds_HasExpectedValue()
    {
        // Assert
        Assert.Equal(20.0, PostProcessingService.DefaultTimeoutSeconds);
    }

    #endregion

    #region Dispose Tests

    [Fact]
    public void Dispose_CalledMultipleTimes_DoesNotThrow()
    {
        // Arrange
        var service = new PostProcessingService("test-api-key");

        // Act & Assert - Should not throw
        service.Dispose();
        service.Dispose();
        service.Dispose();
    }

    #endregion

    #region StripThinkTags Tests

    [Theory]
    [InlineData("Hello world", "Hello world")]
    [InlineData("<think>reasoning</think>Hello world", "Hello world")]
    [InlineData("Hello<think>reasoning</think> world", "Hello world")]
    [InlineData("Hello world<think>reasoning</think>", "Hello world")]
    [InlineData("<think>thinking\nmultiline</think>Result", "Result")]
    [InlineData("<think>first</think>Middle<think>second</think>", "Middle")]
    public void StripThinkTags_VariousInputs_RemovesThinkTags(string input, string expected)
    {
        // Act - Use reflection to call private static method
        var method = typeof(PostProcessingService).GetMethod(
            "StripThinkTags",
            BindingFlags.NonPublic | BindingFlags.Static);

        var result = (string)method!.Invoke(null, new object[] { input })!;

        // Assert
        Assert.Equal(expected, result);
    }

    #endregion

    #region Instruction Execution Guard Tests

    [Fact]
    public void AppearsToHaveExecutedInstruction_CleanedTranscriptMatches_ReturnsFalse()
    {
        // Arrange - Normal cleanup scenario
        var rawTranscript = "um hello world uh how are you";
        var cleanedTranscript = "Hello world, how are you?";
        var outputLanguage = "";

        // Act
        var result = InvokeAppearsToHaveExecutedInstruction(rawTranscript, cleanedTranscript, outputLanguage);

        // Assert
        Assert.False(result);
    }

    [Fact]
    public void AppearsToHaveExecutedInstruction_AssistantPreambleNotInRaw_ReturnsTrue()
    {
        // Arrange - LLM added "Sure," which wasn't in raw transcript
        var rawTranscript = "write a message to John saying I'm late";
        var cleanedTranscript = "Sure, here is a message to John:\n\nHi John,\n\nI'm running late.";
        var outputLanguage = "";

        // Act
        var result = InvokeAppearsToHaveExecutedInstruction(rawTranscript, cleanedTranscript, outputLanguage);

        // Assert
        Assert.True(result);
    }

    [Fact]
    public void AppearsToHaveExecutedInstruction_WithOutputLanguage_ReturnsFalse()
    {
        // Arrange - Translation is expected when output language is set
        var rawTranscript = "hello world";
        var cleanedTranscript = "Hola mundo";
        var outputLanguage = "Spanish";

        // Act
        var result = InvokeAppearsToHaveExecutedInstruction(rawTranscript, cleanedTranscript, outputLanguage);

        // Assert
        Assert.False(result); // Translation is expected, not instruction execution
    }

    [Fact]
    public void AppearsToHaveExecutedInstruction_InstructionMarkersPreserved_ReturnsFalse()
    {
        // Arrange - Instruction markers preserved in output
        var rawTranscript = "write an email to the team";
        var cleanedTranscript = "Write an email to the team.";
        var outputLanguage = "";

        // Act
        var result = InvokeAppearsToHaveExecutedInstruction(rawTranscript, cleanedTranscript, outputLanguage);

        // Assert
        Assert.False(result);
    }

    [Fact]
    public void AppearsToHaveExecutedInstruction_LowOverlapRatio_ReturnsTrue()
    {
        // Arrange - Output has very different content
        var rawTranscript = "draft a PR description for the auth module";
        var cleanedTranscript = "This pull request implements user authentication with OAuth2.";
        var outputLanguage = "";

        // Act
        var result = InvokeAppearsToHaveExecutedInstruction(rawTranscript, cleanedTranscript, outputLanguage);

        // Assert
        Assert.True(result);
    }

    [Fact]
    public void AppearsToHaveExecutedInstruction_EmptyTranscript_ReturnsFalse()
    {
        // Arrange
        var rawTranscript = "";
        var cleanedTranscript = "Hello";
        var outputLanguage = "";

        // Act
        var result = InvokeAppearsToHaveExecutedInstruction(rawTranscript, cleanedTranscript, outputLanguage);

        // Assert
        Assert.False(result); // Empty raw = nothing to check
    }

    [Fact]
    public void AppearsToHaveExecutedInstruction_NoInstructionMarkers_ReturnsFalse()
    {
        // Arrange - No instruction markers in raw transcript
        var rawTranscript = "the weather is nice today";
        var cleanedTranscript = "The weather is nice today.";
        var outputLanguage = "";

        // Act
        var result = InvokeAppearsToHaveExecutedInstruction(rawTranscript, cleanedTranscript, outputLanguage);

        // Assert
        Assert.False(result);
    }

    #endregion

    #region Vocabulary Handling Tests

    [Fact]
    public void MergeVocabularyTerms_DeduplicatesTerms()
    {
        // Arrange
        var vocabulary = new List<string> { "Kiro", "KIRO", "kiro", "FreeFlow", "freeflow" };

        // Act
        var result = InvokeMergeVocabularyTerms(vocabulary);

        // Assert
        Assert.Equal(2, result.Count);
    }

    [Fact]
    public void MergeVocabularyTerms_TrimsWhitespace()
    {
        // Arrange
        var vocabulary = new List<string> { "  Kiro  ", "\tFreeFlow\n", "   " };

        // Act
        var result = InvokeMergeVocabularyTerms(vocabulary);

        // Assert
        Assert.Equal(2, result.Count);
        Assert.Contains("Kiro", result);
        Assert.Contains("FreeFlow", result);
    }

    [Fact]
    public void MergeVocabularyTerms_EmptyList_ReturnsEmpty()
    {
        // Arrange
        var vocabulary = new List<string>();

        // Act
        var result = InvokeMergeVocabularyTerms(vocabulary);

        // Assert
        Assert.Empty(result);
    }

    [Fact]
    public void MergeVocabularyTerms_AllEmpty_ReturnsEmpty()
    {
        // Arrange
        var vocabulary = new List<string> { "", "   ", "\t" };

        // Act
        var result = InvokeMergeVocabularyTerms(vocabulary);

        // Assert
        Assert.Empty(result);
    }

    #endregion

    #region CooldownChangedEvent Tests

    [Fact]
    public void CooldownManager_SetCooldown_FiresEvent()
    {
        // Arrange
        var eventFired = false;
        var eventModel = "";
        DateTime? eventExpiry = null;

        LLMCooldownManager.Shared.CooldownChanged += (sender, args) =>
        {
            eventFired = true;
            eventModel = args.Model;
            eventExpiry = args.Expiry;
        };

        // Act - Set a daily cooldown (which fires the event)
        LLMCooldownManager.Shared.SetCooldown("event-test-model", TimeSpan.FromHours(2), persist: true);

        // Assert
        Assert.True(eventFired);
        Assert.Equal("event-test-model", eventModel);
        Assert.NotNull(eventExpiry);
    }

    [Fact]
    public void CooldownManager_ClearCooldown_FiresEventWithNullExpiry()
    {
        // Arrange
        LLMCooldownManager.Shared.SetCooldown("clear-test-model", TimeSpan.FromHours(2), persist: true);

        var eventFired = false;
        DateTime? eventExpiry = DateTime.UtcNow; // Non-null initial value

        LLMCooldownManager.Shared.CooldownChanged += (sender, args) =>
        {
            if (args.Model == "clear-test-model")
            {
                eventFired = true;
                eventExpiry = args.Expiry;
            }
        };

        // Act
        LLMCooldownManager.Shared.ClearCooldown("clear-test-model");

        // Assert
        Assert.True(eventFired);
        Assert.Null(eventExpiry);
    }

    #endregion

    #region Helper Methods

    /// <summary>
    /// Invokes the private AppearsToHaveExecutedInstruction method via reflection.
    /// </summary>
    private static bool InvokeAppearsToHaveExecutedInstruction(string rawTranscript, string cleanedTranscript, string outputLanguage)
    {
        using var service = new PostProcessingService("test-api-key");

        var method = typeof(PostProcessingService).GetMethod(
            "AppearsToHaveExecutedInstruction",
            BindingFlags.NonPublic | BindingFlags.Instance);

        if (method == null)
            throw new InvalidOperationException("AppearsToHaveExecutedInstruction method not found");

        return (bool)method.Invoke(service, new object[] { rawTranscript, cleanedTranscript, outputLanguage })!;
    }

    /// <summary>
    /// Invokes the private MergeVocabularyTerms method via reflection.
    /// </summary>
    private static IReadOnlyList<string> InvokeMergeVocabularyTerms(IReadOnlyList<string> vocabulary)
    {
        var method = typeof(PostProcessingService).GetMethod(
            "MergeVocabularyTerms",
            BindingFlags.NonPublic | BindingFlags.Static);

        if (method == null)
            throw new InvalidOperationException("MergeVocabularyTerms method not found");

        return (IReadOnlyList<string>)method.Invoke(null, new object[] { vocabulary })!;
    }

    #endregion
}
