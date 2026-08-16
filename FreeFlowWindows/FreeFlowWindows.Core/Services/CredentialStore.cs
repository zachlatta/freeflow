using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Text;
using FreeFlowWindows.Core.Interfaces;

namespace FreeFlowWindows.Core.Services;

/// <summary>
/// Secure storage for API keys using Windows Credential Manager.
/// Also supports loading from .env file for development.
/// Uses P/Invoke to Advapi32.dll for credential management.
/// </summary>
public class CredentialStore : ICredentialStore
{
    private const string CredentialPrefix = "FreeFlow:";
    private static Dictionary<string, string>? _envVars;

    public string? GetApiKey(string accountName)
    {
        // First, check .env file (for development convenience)
        var envKey = GetEnvApiKey(accountName);
        if (!string.IsNullOrEmpty(envKey))
        {
            return envKey;
        }

        // Fall back to Windows Credential Manager
        var targetName = CredentialPrefix + accountName;

        if (!CredRead(targetName, CredentialType.Generic, 0, out var credentialPtr))
        {
            return null;
        }

        try
        {
            var credential = Marshal.PtrToStructure<CREDENTIAL>(credentialPtr);
            if (credential.CredentialBlob == IntPtr.Zero || credential.CredentialBlobSize == 0)
            {
                return null;
            }

            var passwordBytes = new byte[credential.CredentialBlobSize];
            Marshal.Copy(credential.CredentialBlob, passwordBytes, 0, (int)credential.CredentialBlobSize);
            return Encoding.Unicode.GetString(passwordBytes);
        }
        finally
        {
            CredFree(credentialPtr);
        }
    }

    private static string? GetEnvApiKey(string accountName)
    {
        // Load .env file if not already loaded
        if (_envVars == null)
        {
            _envVars = LoadEnvFile();
        }

        // Map account names to env var names
        var envVarName = accountName switch
        {
            "api_key" => "GROQ_API_KEY",
            _ => accountName.ToUpperInvariant().Replace(" ", "_")
        };

        return _envVars.TryGetValue(envVarName, out var value) ? value : null;
    }

    private static Dictionary<string, string> LoadEnvFile()
    {
        var result = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        
        // Look for .env in the app directory and parent directories
        var dir = AppDomain.CurrentDomain.BaseDirectory;
        
        for (int i = 0; i < 10; i++) // Check up to 10 parent directories
        {
            var envPath = Path.Combine(dir, ".env");
            
            if (File.Exists(envPath))
            {
                try
                {
                    foreach (var line in File.ReadAllLines(envPath))
                    {
                        var trimmed = line.Trim();
                        if (string.IsNullOrEmpty(trimmed) || trimmed.StartsWith("#"))
                            continue;

                        var eqIndex = trimmed.IndexOf('=');
                        if (eqIndex > 0)
                        {
                            var key = trimmed.Substring(0, eqIndex).Trim();
                            var value = trimmed.Substring(eqIndex + 1).Trim();
                            // Remove surrounding quotes if present
                            if (value.Length >= 2 && 
                                ((value.StartsWith("\"") && value.EndsWith("\"")) ||
                                 (value.StartsWith("'") && value.EndsWith("'"))))
                            {
                                value = value.Substring(1, value.Length - 2);
                            }
                            result[key] = value;
                        }
                    }
                }
                catch
                {
                    // Silently ignore errors reading .env file
                }
                break;
            }
            
            var parent = Directory.GetParent(dir);
            if (parent == null)
            {
                break;
            }
            dir = parent.FullName;
        }

        return result;
    }

    public void SetApiKey(string accountName, string apiKey)
    {
        var targetName = CredentialPrefix + accountName;
        var credentialBlob = Encoding.Unicode.GetBytes(apiKey);

        var credential = new CREDENTIAL
        {
            Type = CredentialType.Generic,
            TargetName = targetName,
            CredentialBlobSize = (uint)credentialBlob.Length,
            CredentialBlob = Marshal.AllocHGlobal(credentialBlob.Length),
            Persist = CredentialPersistence.LocalMachine,
            UserName = accountName
        };

        try
        {
            Marshal.Copy(credentialBlob, 0, credential.CredentialBlob, credentialBlob.Length);

            if (!CredWrite(ref credential, 0))
            {
                throw new Win32Exception(Marshal.GetLastWin32Error());
            }
        }
        finally
        {
            if (credential.CredentialBlob != IntPtr.Zero)
            {
                Marshal.FreeHGlobal(credential.CredentialBlob);
            }
        }
    }

    public void DeleteApiKey(string accountName)
    {
        var targetName = CredentialPrefix + accountName;
        CredDelete(targetName, CredentialType.Generic, 0);
        // Ignore errors - the credential may not exist
    }

    #region Win32 P/Invoke

    private enum CredentialType : uint
    {
        Generic = 1
    }

    private enum CredentialPersistence : uint
    {
        Session = 1,
        LocalMachine = 2,
        Enterprise = 3
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct CREDENTIAL
    {
        public uint Flags;
        public CredentialType Type;
        public string TargetName;
        public string Comment;
        public System.Runtime.InteropServices.ComTypes.FILETIME LastWritten;
        public uint CredentialBlobSize;
        public IntPtr CredentialBlob;
        public CredentialPersistence Persist;
        public uint AttributeCount;
        public IntPtr Attributes;
        public string TargetAlias;
        public string UserName;
    }

    [DllImport("advapi32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    private static extern bool CredRead(
        string targetName,
        CredentialType type,
        uint flags,
        out IntPtr credential);

    [DllImport("advapi32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    private static extern bool CredWrite(
        ref CREDENTIAL credential,
        uint flags);

    [DllImport("advapi32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    private static extern bool CredDelete(
        string targetName,
        CredentialType type,
        uint flags);

    [DllImport("advapi32.dll", SetLastError = true)]
    private static extern void CredFree(IntPtr credential);

    #endregion
}
