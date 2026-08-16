using Xunit;
using FreeFlowWindows.Core.Services;

namespace FreeFlowWindows.Tests;

/// <summary>
/// Unit tests for CredentialStore.
/// Tests storing, retrieving, overwriting, and deleting API keys.
/// Validates: Requirements 7.4, 7.5
/// </summary>
public class CredentialStoreTests : IDisposable
{
    private readonly CredentialStore _credentialStore;
    private readonly List<string> _createdAccounts;
    private readonly string _testPrefix;

    public CredentialStoreTests()
    {
        _credentialStore = new CredentialStore();
        _createdAccounts = new List<string>();
        // Use a unique prefix for each test run to avoid conflicts
        _testPrefix = $"test_{Guid.NewGuid():N}_";
    }

    public void Dispose()
    {
        // Cleanup: delete all credentials created during tests
        foreach (var accountName in _createdAccounts)
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

    private string GetUniqueAccountName(string baseName)
    {
        var accountName = _testPrefix + baseName;
        _createdAccounts.Add(accountName);
        return accountName;
    }

    [Fact]
    public void SetApiKey_ThenGetApiKey_ReturnsStoredKey()
    {
        // Arrange
        var accountName = GetUniqueAccountName("api_key");
        var apiKey = "sk-test-key-12345";

        // Act
        _credentialStore.SetApiKey(accountName, apiKey);
        var retrieved = _credentialStore.GetApiKey(accountName);

        // Assert
        Assert.Equal(apiKey, retrieved);
    }

    [Fact]
    public void SetApiKey_WithSpecialCharacters_ReturnsStoredKey()
    {
        // Arrange
        var accountName = GetUniqueAccountName("api_key_special");
        var apiKey = "sk-test_key-with-special_chars!@#$%^&*()";

        // Act
        _credentialStore.SetApiKey(accountName, apiKey);
        var retrieved = _credentialStore.GetApiKey(accountName);

        // Assert
        Assert.Equal(apiKey, retrieved);
    }

    [Fact]
    public void SetApiKey_OverwriteExistingKey_ReturnsNewKey()
    {
        // Arrange
        var accountName = GetUniqueAccountName("api_key_overwrite");
        var originalKey = "sk-original-key";
        var newKey = "sk-new-key-67890";

        // Act
        _credentialStore.SetApiKey(accountName, originalKey);
        _credentialStore.SetApiKey(accountName, newKey);
        var retrieved = _credentialStore.GetApiKey(accountName);

        // Assert
        Assert.Equal(newKey, retrieved);
    }

    [Fact]
    public void DeleteApiKey_ThenGetApiKey_ReturnsNull()
    {
        // Arrange
        var accountName = GetUniqueAccountName("api_key_delete");
        var apiKey = "sk-key-to-delete";

        // Act
        _credentialStore.SetApiKey(accountName, apiKey);
        _credentialStore.DeleteApiKey(accountName);
        var retrieved = _credentialStore.GetApiKey(accountName);

        // Assert
        Assert.Null(retrieved);
    }

    [Fact]
    public void GetApiKey_NonExistentKey_ReturnsNull()
    {
        // Arrange
        var accountName = GetUniqueAccountName("non_existent_key");

        // Act
        var retrieved = _credentialStore.GetApiKey(accountName);

        // Assert
        Assert.Null(retrieved);
    }

    [Fact]
    public void DeleteApiKey_NonExistentKey_DoesNotThrow()
    {
        // Arrange
        var accountName = GetUniqueAccountName("non_existent_delete");

        // Act & Assert - should not throw
        var exception = Record.Exception(() => _credentialStore.DeleteApiKey(accountName));
        Assert.Null(exception);
    }

    [Fact]
    public void SetApiKey_MultipleAccounts_StoresIndependently()
    {
        // Arrange
        var accountName1 = GetUniqueAccountName("api_key");
        var accountName2 = GetUniqueAccountName("transcription_api_key");
        var apiKey1 = "sk-primary-key";
        var apiKey2 = "sk-transcription-key";

        // Act
        _credentialStore.SetApiKey(accountName1, apiKey1);
        _credentialStore.SetApiKey(accountName2, apiKey2);
        var retrieved1 = _credentialStore.GetApiKey(accountName1);
        var retrieved2 = _credentialStore.GetApiKey(accountName2);

        // Assert
        Assert.Equal(apiKey1, retrieved1);
        Assert.Equal(apiKey2, retrieved2);
    }

    [Fact(Skip = "Windows Credential Manager may return null for empty credentials")]
    public void SetApiKey_EmptyString_StoresAndRetrievesCorrectly()
    {
        // Arrange
        var accountName = GetUniqueAccountName("api_key_empty");
        var apiKey = "";

        // Act
        _credentialStore.SetApiKey(accountName, apiKey);
        var retrieved = _credentialStore.GetApiKey(accountName);

        // Assert
        Assert.Equal(apiKey, retrieved);
    }

    [Fact]
    public void SetApiKey_LongKey_StoresAndRetrievesCorrectly()
    {
        // Arrange
        var accountName = GetUniqueAccountName("api_key_long");
        var apiKey = new string('x', 1000); // 1000 character key

        // Act
        _credentialStore.SetApiKey(accountName, apiKey);
        var retrieved = _credentialStore.GetApiKey(accountName);

        // Assert
        Assert.Equal(apiKey, retrieved);
    }

    [Fact]
    public void SetApiKey_UnicodeCharacters_StoresAndRetrievesCorrectly()
    {
        // Arrange
        var accountName = GetUniqueAccountName("api_key_unicode");
        var apiKey = "sk-test-키-κλειδί-钥匙-🔑";

        // Act
        _credentialStore.SetApiKey(accountName, apiKey);
        var retrieved = _credentialStore.GetApiKey(accountName);

        // Assert
        Assert.Equal(apiKey, retrieved);
    }
}
