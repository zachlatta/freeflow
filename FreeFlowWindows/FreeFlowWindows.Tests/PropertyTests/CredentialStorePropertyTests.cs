using FreeFlowWindows.Core.Interfaces;
using FreeFlowWindows.Core.Services;

namespace FreeFlowWindows.Tests.PropertyTests;

/// <summary>
/// Property-based tests for CredentialStore using FsCheck.
/// Tests the credential store round-trip property: storing an API key and retrieving it
/// should return the exact same value.
/// </summary>
public class CredentialStorePropertyTests : IDisposable
{
    private readonly ICredentialStore _credentialStore;
    private readonly List<string> _testAccountNames = new();

    public CredentialStorePropertyTests()
    {
        _credentialStore = new CredentialStore();
    }

    /// <summary>
    /// Property 2: Credential Store Round-Trip
    /// For any valid API key string (non-empty, containing printable ASCII characters 
    /// including special characters like hyphens and underscores), storing it in the 
    /// credential store with an account name and then retrieving it with the same 
    /// account name should return the exact same string.
    /// 
    /// **Validates: Requirements 7.4, 7.5**
    /// </summary>
    [Property(MaxTest = 100)]
    public Property CredentialStoreRoundTrip_PreservesApiKey()
    {
        // Custom generator for valid API keys: non-empty, printable ASCII with special chars
        var apiKeyGen = GenerateValidApiKey();
        
        // Custom generator for account names: simple alphanumeric identifiers
        var accountNameGen = GenerateAccountName();

        return Prop.ForAll(
            apiKeyGen.ToArbitrary(),
            accountNameGen.ToArbitrary(),
            (apiKey, accountName) =>
            {
                // Skip null/empty inputs (shouldn't happen but defensive check)
                if (string.IsNullOrEmpty(apiKey) || string.IsNullOrEmpty(accountName))
                    return true; // Trivially passes - we only test valid inputs
                
                // Track for cleanup
                var fullAccountName = $"test_{accountName}_{Guid.NewGuid():N}";
                _testAccountNames.Add(fullAccountName);

                try
                {
                    // Act: Store the API key
                    _credentialStore.SetApiKey(fullAccountName, apiKey);

                    // Act: Retrieve the API key
                    var retrieved = _credentialStore.GetApiKey(fullAccountName);

                    // Assert: Retrieved value must exactly match stored value
                    return retrieved == apiKey;
                }
                finally
                {
                    // Cleanup: Remove the test credential
                    _credentialStore.DeleteApiKey(fullAccountName);
                }
            });
    }

    /// <summary>
    /// Property test verifying that overwriting an existing credential preserves the new value.
    /// 
    /// **Validates: Requirements 7.4, 7.5**
    /// </summary>
    [Property(MaxTest = 100)]
    public Property CredentialStoreOverwrite_PreservesLatestValue()
    {
        var apiKeyGen = GenerateValidApiKey();
        var accountNameGen = GenerateAccountName();

        return Prop.ForAll(
            apiKeyGen.ToArbitrary(),
            apiKeyGen.ToArbitrary(),
            accountNameGen.ToArbitrary(),
            (firstApiKey, secondApiKey, accountName) =>
            {
                // Skip null/empty inputs (shouldn't happen but defensive check)
                if (string.IsNullOrEmpty(firstApiKey) || string.IsNullOrEmpty(secondApiKey) || string.IsNullOrEmpty(accountName))
                    return true; // Trivially passes - we only test valid inputs
                
                var fullAccountName = $"test_overwrite_{accountName}_{Guid.NewGuid():N}";
                _testAccountNames.Add(fullAccountName);

                try
                {
                    // Store first value
                    _credentialStore.SetApiKey(fullAccountName, firstApiKey);

                    // Overwrite with second value
                    _credentialStore.SetApiKey(fullAccountName, secondApiKey);

                    // Retrieve should return the second (latest) value
                    var retrieved = _credentialStore.GetApiKey(fullAccountName);

                    return retrieved == secondApiKey;
                }
                finally
                {
                    _credentialStore.DeleteApiKey(fullAccountName);
                }
            });
    }

    /// <summary>
    /// Property test verifying that API keys with special characters are handled correctly.
    /// API keys often contain characters like hyphens, underscores, and alphanumeric strings.
    /// 
    /// **Validates: Requirements 7.4, 7.5**
    /// </summary>
    [Property(MaxTest = 100)]
    public Property CredentialStoreRoundTrip_HandlesSpecialCharacters()
    {
        // Generator specifically for API keys with special characters common in real API keys
        var specialApiKeyGen = GenerateApiKeyWithSpecialChars();
        var accountNameGen = GenerateAccountName();

        return Prop.ForAll(
            specialApiKeyGen.ToArbitrary(),
            accountNameGen.ToArbitrary(),
            (apiKey, accountName) =>
            {
                // Skip null/empty inputs (shouldn't happen but defensive check)
                if (string.IsNullOrEmpty(apiKey) || string.IsNullOrEmpty(accountName))
                    return true; // Trivially passes - we only test valid inputs
                
                var fullAccountName = $"test_special_{accountName}_{Guid.NewGuid():N}";
                _testAccountNames.Add(fullAccountName);

                try
                {
                    _credentialStore.SetApiKey(fullAccountName, apiKey);
                    var retrieved = _credentialStore.GetApiKey(fullAccountName);

                    return retrieved == apiKey;
                }
                finally
                {
                    _credentialStore.DeleteApiKey(fullAccountName);
                }
            });
    }

    /// <summary>
    /// Generates valid API key strings: non-empty, printable ASCII characters.
    /// Includes letters, digits, and common special characters found in API keys.
    /// </summary>
    private static Gen<string> GenerateValidApiKey()
    {
        // Printable ASCII range (32-126) excluding control characters
        // Focus on characters commonly found in API keys
        var printableChars = Enumerable.Range(33, 94) // '!' (33) to '~' (126)
            .Select(i => (char)i)
            .ToArray();

        return Gen.ArrayOf(Gen.Elements(printableChars))
            .Where(chars => chars.Length > 0 && chars.Length <= 256)
            .Select(chars => new string(chars));
    }

    /// <summary>
    /// Generates API keys with special characters commonly found in real API keys.
    /// Examples: sk-proj-abc123, gsk_abc123-def456, etc.
    /// </summary>
    private static Gen<string> GenerateApiKeyWithSpecialChars()
    {
        // Characters commonly found in API keys
        var apiKeyChars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_".ToCharArray();
        
        // Common API key prefixes
        var prefixes = new[] { "sk-", "gsk_", "api_", "key-", "" };

        return from prefix in Gen.Elements(prefixes)
               from chars in Gen.ArrayOf(Gen.Elements(apiKeyChars))
                   .Where(c => c.Length >= 8 && c.Length <= 128)
               select prefix + new string(chars);
    }

    /// <summary>
    /// Generates valid account names for credential storage.
    /// Account names should be simple identifiers.
    /// </summary>
    private static Gen<string> GenerateAccountName()
    {
        var validChars = "abcdefghijklmnopqrstuvwxyz0123456789_".ToCharArray();

        return Gen.ArrayOf(Gen.Elements(validChars))
            .Where(chars => chars.Length >= 3 && chars.Length <= 32)
            .Select(chars => new string(chars));
    }

    public void Dispose()
    {
        // Clean up any remaining test credentials
        foreach (var accountName in _testAccountNames)
        {
            try
            {
                _credentialStore.DeleteApiKey(accountName);
            }
            catch
            {
                // Ignore cleanup errors
            }
        }
    }
}
