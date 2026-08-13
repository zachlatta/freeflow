using FreeFlowWindows.Core.Models;
using FreeFlowWindows.Core.Services;
using FsCheck;
using FsCheck.Xunit;
using System.Text.Json;

namespace FreeFlowWindows.Tests.PropertyTests;

/// <summary>
/// Property-based tests for settings serialization and persistence.
/// </summary>
public class SettingsManagerPropertyTests
{
    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        WriteIndented = true,
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase
    };

    /// <summary>
    /// **Validates: Requirements 7.1, 7.2, 7.3**
    /// 
    /// Property 1: Settings Serialization Round-Trip
    /// 
    /// For any valid AppSettings object with arbitrary values for all fields 
    /// (API URLs, model names, hotkey configurations, microphone IDs, vocabulary strings, 
    /// boolean flags, and timeout values), serializing to JSON and then deserializing 
    /// should produce an AppSettings object where all fields are equivalent to the original.
    /// </summary>
    [Property(MaxTest = 100, Verbose = true)]
    public Property SettingsRoundTrip_PreservesAllFields()
    {
        return Prop.ForAll(
            AppSettingsArbitrary.Generate(),
            settings =>
            {
                // Act: Serialize to JSON and deserialize back
                var json = JsonSerializer.Serialize(settings, JsonOptions);
                var restored = JsonSerializer.Deserialize<AppSettings>(json, JsonOptions);

                // Assert: All fields should be equivalent
                return restored != null && settings.Equals(restored);
            });
    }

    /// <summary>
    /// **Validates: Requirements 7.1, 7.2, 7.3**
    /// 
    /// Additional property test: SettingsManager file round-trip.
    /// Settings saved to a file and loaded back should be equivalent to the original.
    /// </summary>
    [Property(MaxTest = 100, Verbose = true)]
    public Property SettingsManager_SaveAndLoad_PreservesAllFields()
    {
        return Prop.ForAll(
            AppSettingsArbitrary.Generate(),
            settings =>
            {
                // Arrange: Create a temp file for testing
                var tempPath = Path.Combine(Path.GetTempPath(), $"freeflow_test_{Guid.NewGuid():N}.json");
                var manager = new SettingsManager(tempPath, enforcePermissions: false);

                try
                {
                    // Act: Save and load
                    manager.Save(settings);
                    var loaded = manager.Load();

                    // Assert: All fields should be equivalent
                    return settings.Equals(loaded);
                }
                finally
                {
                    // Cleanup
                    try { File.Delete(tempPath); } catch { }
                }
            });
    }
}

/// <summary>
/// Custom FsCheck arbitrary generators for AppSettings and related types.
/// </summary>
public static class AppSettingsArbitrary
{
    /// <summary>
    /// Generates arbitrary AppSettings instances with valid values for all fields.
    /// </summary>
    public static Arbitrary<AppSettings> Generate()
    {
        return Arb.From(GenerateAppSettings());
    }

    private static Gen<AppSettings> GenerateAppSettings()
    {
        return from apiBaseUrl in GenerateUrl()
               from transcriptionModel in GenerateModelName()
               from transcriptionApiUrl in GenerateOptionalUrl()
               from postProcessingModel in GenerateModelName()
               from postProcessingFallbackModel in GenerateModelName()
               from holdHotkey in GenerateHotkeyBinding()
               from toggleHotkey in GenerateHotkeyBinding()
               from selectedMicrophoneId in GenerateOptionalDeviceId()
               from customVocabulary in GenerateVocabulary()
               from preserveClipboard in Arb.Generate<bool>()
               from startWithWindows in Arb.Generate<bool>()
               from transcriptionTimeoutSeconds in GeneratePositiveTimeout()
               from postProcessingTimeoutSeconds in GeneratePositiveTimeout()
               select new AppSettings
               {
                   ApiBaseUrl = apiBaseUrl,
                   TranscriptionModel = transcriptionModel,
                   TranscriptionApiUrl = transcriptionApiUrl,
                   PostProcessingModel = postProcessingModel,
                   PostProcessingFallbackModel = postProcessingFallbackModel,
                   HoldHotkey = holdHotkey,
                   ToggleHotkey = toggleHotkey,
                   SelectedMicrophoneId = selectedMicrophoneId,
                   CustomVocabulary = customVocabulary,
                   PreserveClipboard = preserveClipboard,
                   StartWithWindows = startWithWindows,
                   TranscriptionTimeoutSeconds = transcriptionTimeoutSeconds,
                   PostProcessingTimeoutSeconds = postProcessingTimeoutSeconds
               };
    }

    /// <summary>
    /// Generates valid URL strings for API endpoints.
    /// </summary>
    private static Gen<string> GenerateUrl()
    {
        var protocols = new[] { "https://", "http://" };
        var domains = new[] { "api.groq.com", "api.openai.com", "localhost:8080", "192.168.1.100:3000", "custom-api.example.com" };
        var paths = new[] { "/openai/v1", "/v1", "/api", "", "/whisper/v1" };

        return from protocol in Gen.Elements(protocols)
               from domain in Gen.Elements(domains)
               from path in Gen.Elements(paths)
               select protocol + domain + path;
    }

    /// <summary>
    /// Generates optional URL strings (null or valid URL).
    /// </summary>
    private static Gen<string?> GenerateOptionalUrl()
    {
        return Gen.Frequency(
            Tuple.Create(1, Gen.Constant<string?>(null)),
            Tuple.Create(2, GenerateUrl().Select(url => (string?)url)));
    }

    /// <summary>
    /// Generates valid model name strings.
    /// </summary>
    private static Gen<string> GenerateModelName()
    {
        var models = new[]
        {
            "whisper-large-v3",
            "whisper-large-v3-turbo",
            "openai/gpt-oss-20b",
            "qwen/qwen3.6-27b",
            "gpt-4o-mini",
            "gpt-4-turbo",
            "claude-3-sonnet",
            "llama-3.2-90b-text-preview",
            "custom-model-v1"
        };

        return Gen.Elements(models);
    }

    /// <summary>
    /// Generates arbitrary HotkeyBinding instances.
    /// </summary>
    private static Gen<HotkeyBinding> GenerateHotkeyBinding()
    {
        return from modifiers in GenerateModifierKeys()
               from key in GenerateVirtualKey()
               select new HotkeyBinding
               {
                   Modifiers = modifiers,
                   Key = key
               };
    }

    /// <summary>
    /// Generates arbitrary ModifierKeys combinations.
    /// </summary>
    private static Gen<ModifierKeys> GenerateModifierKeys()
    {
        // Generate combinations of modifier keys
        return from useCtrl in Arb.Generate<bool>()
               from useAlt in Arb.Generate<bool>()
               from useShift in Arb.Generate<bool>()
               from useWin in Arb.Generate<bool>()
               select (useCtrl ? ModifierKeys.Ctrl : ModifierKeys.None) |
                      (useAlt ? ModifierKeys.Alt : ModifierKeys.None) |
                      (useShift ? ModifierKeys.Shift : ModifierKeys.None) |
                      (useWin ? ModifierKeys.Win : ModifierKeys.None);
    }

    /// <summary>
    /// Generates arbitrary VirtualKey values.
    /// </summary>
    private static Gen<VirtualKey> GenerateVirtualKey()
    {
        var keys = Enum.GetValues<VirtualKey>();
        return Gen.Elements(keys);
    }

    /// <summary>
    /// Generates optional device ID strings (null or GUID-like strings).
    /// </summary>
    private static Gen<string?> GenerateOptionalDeviceId()
    {
        var deviceIds = new Gen<string>[]
        {
            Gen.Constant("{0.0.0.00000000}.{aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee}"),
            Gen.Constant("{0.0.1.00000000}.{11111111-2222-3333-4444-555555555555}"),
            from guid in Arb.Generate<Guid>()
            select $"{{0.0.0.00000000}}.{{{guid}}}",
            Gen.Constant("default"),
            Gen.Constant("Microphone (Realtek High Definition Audio)")
        };

        return Gen.Frequency(
            Tuple.Create(1, Gen.Constant<string?>(null)),
            Tuple.Create(3, Gen.OneOf(deviceIds).Select(id => (string?)id)));
    }

    /// <summary>
    /// Generates custom vocabulary strings (newline-separated terms).
    /// </summary>
    private static Gen<string> GenerateVocabulary()
    {
        var terms = new[]
        {
            "FreeFlow", "Whisper", "OpenAI", "Groq", "API", "JSON",
            "John Smith", "Jane Doe", "ACME Corp", "TypeScript",
            "Kubernetes", "PostgreSQL", "React.js", "dotnet",
            "München", "São Paulo", "日本語", "北京"
        };

        return Gen.Frequency(
            Tuple.Create(1, Gen.Constant("")),
            Tuple.Create(1, Gen.Elements(terms)),
            Tuple.Create(2, from count in Gen.Choose(1, 5)
                            from selectedTerms in Gen.ArrayOf(count, Gen.Elements(terms))
                            select string.Join("\n", selectedTerms.Distinct())));
    }

    /// <summary>
    /// Generates positive timeout values in a reasonable range.
    /// </summary>
    private static Gen<int> GeneratePositiveTimeout()
    {
        return Gen.Choose(1, 120); // 1 second to 2 minutes
    }
}
