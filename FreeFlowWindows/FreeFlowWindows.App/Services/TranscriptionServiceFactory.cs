using FreeFlowWindows.Core.Interfaces;
using FreeFlowWindows.Core.Services;

namespace FreeFlowWindows.App.Services;

/// <summary>
/// Factory that creates TranscriptionService instances with current settings.
/// This ensures the API key is fetched fresh each time transcription is needed,
/// allowing settings changes to take effect immediately without app restart.
/// </summary>
public class TranscriptionServiceFactory : ITranscriptionService
{
    private readonly ISettingsManager _settingsManager;
    private readonly ICredentialStore _credentialStore;

    public TranscriptionServiceFactory(ISettingsManager settingsManager, ICredentialStore credentialStore)
    {
        _settingsManager = settingsManager ?? throw new ArgumentNullException(nameof(settingsManager));
        _credentialStore = credentialStore ?? throw new ArgumentNullException(nameof(credentialStore));
    }

    public async Task<TranscriptionResult> TranscribeAsync(string audioFilePath, CancellationToken cancellationToken = default)
    {
        // Get current settings and credentials
        var settings = _settingsManager.Load();
        var apiKey = _credentialStore.GetApiKey("api_key") ?? "";

        var logPath = System.IO.Path.Combine(System.IO.Path.GetTempPath(), "freeflow_debug.log");
        System.IO.File.AppendAllText(logPath, $"[{DateTime.Now:HH:mm:ss}] TranscribeAsync called\n");
        System.IO.File.AppendAllText(logPath, $"  API Key length: {apiKey?.Length ?? 0}\n");
        System.IO.File.AppendAllText(logPath, $"  Audio file: {audioFilePath}\n");
        System.IO.File.AppendAllText(logPath, $"  File exists: {System.IO.File.Exists(audioFilePath)}\n");

        // Check for missing API key
        if (string.IsNullOrWhiteSpace(apiKey))
        {
            System.IO.File.AppendAllText(logPath, "  ERROR: API key is empty!\n");
            return TranscriptionResult.Fail(
                TranscriptionError.AuthenticationError("API key not configured. Please add your API key in Settings."));
        }

        var baseUrl = settings.TranscriptionApiUrl ?? settings.ApiBaseUrl ?? "https://api.groq.com/openai/v1";
        var model = settings.TranscriptionModel ?? "whisper-large-v3";

        System.IO.File.AppendAllText(logPath, $"  Base URL: {baseUrl}\n");
        System.IO.File.AppendAllText(logPath, $"  Model: {model}\n");

        // Create a fresh transcription service with current settings
        using var service = new TranscriptionService(
            apiKey,
            baseUrl,
            model,
            settings.TranscriptionTimeoutSeconds,
            null);  // language hint

        try
        {
            var result = await service.TranscribeAsync(audioFilePath, cancellationToken);
            
            System.IO.File.AppendAllText(logPath, $"  Result success: {result.Success}\n");
            if (result.Success)
            {
                System.IO.File.AppendAllText(logPath, $"  Transcript: {result.Transcript}\n");
            }
            else
            {
                System.IO.File.AppendAllText(logPath, $"  Error: {result.Error?.Type} - {result.Error?.Message}\n");
            }
            
            return result;
        }
        catch (Exception ex)
        {
            System.IO.File.AppendAllText(logPath, $"  Exception: {ex.Message}\n");
            System.IO.File.AppendAllText(logPath, $"  Stack: {ex.StackTrace}\n");
            throw;
        }
    }
}
