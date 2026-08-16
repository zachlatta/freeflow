using FreeFlowWindows.Core.Interfaces;
using FreeFlowWindows.Core.Models;
using FreeFlowWindows.Core.Services;

namespace FreeFlowWindows.App.Services;

/// <summary>
/// Factory that creates PostProcessingService instances with current settings.
/// This ensures the API key is fetched fresh each time processing is needed,
/// allowing settings changes to take effect immediately without app restart.
/// </summary>
public class PostProcessingServiceFactory : IPostProcessingService
{
    private readonly ISettingsManager _settingsManager;
    private readonly ICredentialStore _credentialStore;

    public PostProcessingServiceFactory(ISettingsManager settingsManager, ICredentialStore credentialStore)
    {
        _settingsManager = settingsManager ?? throw new ArgumentNullException(nameof(settingsManager));
        _credentialStore = credentialStore ?? throw new ArgumentNullException(nameof(credentialStore));
    }

    public async Task<PostProcessingResult> ProcessAsync(
        string transcript,
        string contextSummary,
        IReadOnlyList<string> customVocabulary,
        string? customSystemPrompt = null,
        string? outputLanguage = null,
        CancellationToken cancellationToken = default)
    {
        // Get current settings and credentials
        var settings = _settingsManager.Load();
        var apiKey = _credentialStore.GetApiKey("api_key") ?? "";

        // If no API key, just return the transcript as-is (fallback)
        if (string.IsNullOrWhiteSpace(apiKey))
        {
            return PostProcessingResult.Fallback(transcript);
        }

        var baseUrl = settings.ApiBaseUrl ?? "https://api.groq.com/openai/v1";
        var model = settings.PostProcessingModel ?? "";
        var fallbackModel = settings.PostProcessingFallbackModel ?? "";

        // If no model configured, skip post-processing
        if (string.IsNullOrWhiteSpace(model))
        {
            return PostProcessingResult.Fallback(transcript);
        }

        // Create a fresh post-processing service with current settings
        using var service = new PostProcessingService(
            apiKey,
            baseUrl,
            model,
            fallbackModel,
            true,  // enableCaching
            settings.PostProcessingTimeoutSeconds);

        return await service.ProcessAsync(
            transcript,
            contextSummary,
            customVocabulary,
            customSystemPrompt,
            outputLanguage,
            cancellationToken);
    }
}
