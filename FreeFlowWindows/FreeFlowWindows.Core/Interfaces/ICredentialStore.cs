namespace FreeFlowWindows.Core.Interfaces;

/// <summary>
/// Secure storage for API keys using Windows Credential Manager.
/// </summary>
public interface ICredentialStore
{
    /// <summary>
    /// Retrieves the API key for the specified account name.
    /// </summary>
    /// <param name="accountName">The account name (e.g., "api_key", "transcription_api_key")</param>
    /// <returns>The API key, or null if not found.</returns>
    string? GetApiKey(string accountName);

    /// <summary>
    /// Stores the API key for the specified account name.
    /// </summary>
    /// <param name="accountName">The account name (e.g., "api_key", "transcription_api_key")</param>
    /// <param name="apiKey">The API key to store.</param>
    void SetApiKey(string accountName, string apiKey);

    /// <summary>
    /// Deletes the API key for the specified account name.
    /// </summary>
    /// <param name="accountName">The account name to delete.</param>
    void DeleteApiKey(string accountName);
}
