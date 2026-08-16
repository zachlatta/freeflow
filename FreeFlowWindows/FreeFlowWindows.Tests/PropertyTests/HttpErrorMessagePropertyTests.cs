using FreeFlowWindows.Core.Http;
using FsCheck;
using FsCheck.Xunit;

namespace FreeFlowWindows.Tests.PropertyTests;

/// <summary>
/// Property-based tests for HTTP error message friendliness.
/// Tests the HttpTransport.FriendlyHttpMessage static method.
/// </summary>
public class HttpErrorMessagePropertyTests
{
    /// <summary>
    /// **Validates: Requirements 4.5, 4.6, 10.1, 10.2**
    /// 
    /// Property 10: HTTP Error Message Friendliness - Non-empty message
    /// 
    /// For any HTTP status code returned by the Whisper API or LLM API, the friendly 
    /// error message function should produce a non-empty, user-readable string.
    /// </summary>
    [Property(MaxTest = 100, Verbose = true)]
    public Property FriendlyHttpMessage_ReturnsNonEmptyMessage_ForAnyStatusCode()
    {
        return Prop.ForAll(
            HttpStatusCodeArbitrary.GenerateAllHttpStatusCodes(),
            HttpStatusCodeArbitrary.GenerateHostNames(),
            (statusCode, host) =>
            {
                // Act
                var message = HttpTransport.FriendlyHttpMessage(statusCode, host);

                // Assert: Message must be non-empty
                return !string.IsNullOrWhiteSpace(message);
            });
    }

    /// <summary>
    /// **Validates: Requirements 4.5, 4.6, 10.1, 10.2**
    /// 
    /// Property 10: HTTP Error Message Friendliness - User-readable, no raw JSON
    /// 
    /// For any HTTP status code, the friendly error message should not contain raw JSON
    /// structures, technical exception details, or stack traces.
    /// </summary>
    [Property(MaxTest = 100, Verbose = true)]
    public Property FriendlyHttpMessage_DoesNotExposeRawJson_ForAnyStatusCode()
    {
        return Prop.ForAll(
            HttpStatusCodeArbitrary.GenerateAllHttpStatusCodes(),
            HttpStatusCodeArbitrary.GenerateHostNames(),
            (statusCode, host) =>
            {
                // Act
                var message = HttpTransport.FriendlyHttpMessage(statusCode, host);

                // Assert: Message must not contain JSON indicators or technical details
                var containsJson = message.Contains("{") && message.Contains("}");
                var containsStackTrace = message.Contains("   at ") || message.Contains("StackTrace");
                var containsException = message.Contains("Exception:") || message.Contains("exception:");
                var containsNullPointer = message.Contains("NullReference") || message.Contains("null reference");

                return !containsJson && !containsStackTrace && !containsException && !containsNullPointer;
            });
    }

    /// <summary>
    /// **Validates: Requirements 4.5, 4.6, 10.1, 10.2**
    /// 
    /// Property 10: HTTP Error Message Friendliness - Consistency
    /// 
    /// For the same HTTP status code, the message should be consistent regardless
    /// of the response body content (which is not passed to FriendlyHttpMessage).
    /// Calling the function multiple times with the same inputs should produce the same result.
    /// </summary>
    [Property(MaxTest = 100, Verbose = true)]
    public Property FriendlyHttpMessage_ReturnsConsistentMessage_ForSameStatusCode()
    {
        return Prop.ForAll(
            HttpStatusCodeArbitrary.GenerateAllHttpStatusCodes(),
            HttpStatusCodeArbitrary.GenerateHostNames(),
            (statusCode, host) =>
            {
                // Act: Call multiple times with same inputs
                var message1 = HttpTransport.FriendlyHttpMessage(statusCode, host);
                var message2 = HttpTransport.FriendlyHttpMessage(statusCode, host);
                var message3 = HttpTransport.FriendlyHttpMessage(statusCode, host);

                // Assert: All messages should be identical
                return message1 == message2 && message2 == message3;
            });
    }

    /// <summary>
    /// **Validates: Requirements 4.5, 4.6, 10.1, 10.2**
    /// 
    /// Property 10: HTTP Error Message Friendliness - Readable English
    /// 
    /// For any HTTP status code, the message should be human-readable English text
    /// with proper sentence structure (starts with capital, ends with punctuation).
    /// </summary>
    [Property(MaxTest = 100, Verbose = true)]
    public Property FriendlyHttpMessage_IsUserReadable_ForAnyStatusCode()
    {
        return Prop.ForAll(
            HttpStatusCodeArbitrary.GenerateAllHttpStatusCodes(),
            HttpStatusCodeArbitrary.GenerateHostNames(),
            (statusCode, host) =>
            {
                // Act
                var message = HttpTransport.FriendlyHttpMessage(statusCode, host);

                // Assert: Basic readability checks
                // - Starts with a capital letter or digit
                var startsWithCapital = char.IsUpper(message[0]) || char.IsDigit(message[0]);

                // - Ends with punctuation (period, question mark, or exclamation)
                var endsWithPunctuation = message.EndsWith('.') || message.EndsWith('?') || message.EndsWith('!');

                // - Has reasonable length (not too short, not too long)
                var reasonableLength = message.Length >= 10 && message.Length <= 500;

                // - Contains at least one space (is a proper sentence, not just a code)
                var hasSentenceStructure = message.Contains(' ');

                return startsWithCapital && endsWithPunctuation && reasonableLength && hasSentenceStructure;
            });
    }

    /// <summary>
    /// **Validates: Requirements 4.5, 4.6, 10.1, 10.2**
    /// 
    /// Property 10: HTTP Error Message Friendliness - Includes HTTP code for context
    /// 
    /// For status codes that aren't common (like 401, 429), the message should include
    /// the status code to help with troubleshooting, unless it's a well-known error.
    /// </summary>
    [Property(MaxTest = 100, Verbose = true)]
    public Property FriendlyHttpMessage_IncludesStatusCodeWhenAppropriate_ForUncommonCodes()
    {
        return Prop.ForAll(
            HttpStatusCodeArbitrary.GenerateUncommonStatusCodes(),
            HttpStatusCodeArbitrary.GenerateHostNames(),
            (statusCode, host) =>
            {
                // Act
                var message = HttpTransport.FriendlyHttpMessage(statusCode, host);

                // Assert: For uncommon status codes (403, 404, 413, 400, 5xx), 
                // the message should mention HTTP or the status code number
                var mentionsHttp = message.Contains("HTTP", StringComparison.OrdinalIgnoreCase);
                var mentionsStatusCode = message.Contains(statusCode.ToString());

                // Either HTTP is mentioned or the status code is mentioned
                return mentionsHttp || mentionsStatusCode;
            });
    }

    /// <summary>
    /// **Validates: Requirements 4.5, 4.6, 10.1, 10.2**
    /// 
    /// Property 10: HTTP Error Message Friendliness - Null host handling
    /// 
    /// When host is null, the message should still be valid and use a placeholder.
    /// </summary>
    [Property(MaxTest = 100, Verbose = true)]
    public Property FriendlyHttpMessage_HandlesNullHost_Gracefully()
    {
        return Prop.ForAll(
            HttpStatusCodeArbitrary.GenerateAllHttpStatusCodes(),
            statusCode =>
            {
                // Act
                var message = HttpTransport.FriendlyHttpMessage(statusCode, null);

                // Assert: Message is still valid
                var isNonEmpty = !string.IsNullOrWhiteSpace(message);
                var containsProvider = message.Contains("provider", StringComparison.OrdinalIgnoreCase);

                return isNonEmpty && containsProvider;
            });
    }

    /// <summary>
    /// **Validates: Requirements 4.5, 4.6, 10.1, 10.2**
    /// 
    /// Property 10: HTTP Error Message Friendliness - Host is included when provided
    /// 
    /// When a host is provided, the message should include it for context.
    /// </summary>
    [Property(MaxTest = 100, Verbose = true)]
    public Property FriendlyHttpMessage_IncludesHost_WhenProvided()
    {
        return Prop.ForAll(
            HttpStatusCodeArbitrary.GenerateAllHttpStatusCodes(),
            HttpStatusCodeArbitrary.GenerateNonEmptyHostNames(),
            (statusCode, host) =>
            {
                // Skip the case where the error message pattern doesn't include host
                // (e.g., 400 error which just says "Provider rejected")
                if (statusCode == 400)
                {
                    // 400 error doesn't include host in the message pattern
                    var msg = HttpTransport.FriendlyHttpMessage(statusCode, host);
                    return !string.IsNullOrWhiteSpace(msg);
                }

                // Act
                var message = HttpTransport.FriendlyHttpMessage(statusCode, host);

                // Assert: Host should be included in the message
                return message.Contains(host);
            });
    }
}

/// <summary>
/// Custom FsCheck arbitrary generators for HTTP status codes and hostnames.
/// </summary>
public static class HttpStatusCodeArbitrary
{
    /// <summary>
    /// Common HTTP status codes returned by APIs.
    /// </summary>
    private static readonly int[] CommonStatusCodes = new[]
    {
        // Client errors
        400, // Bad Request
        401, // Unauthorized
        403, // Forbidden
        404, // Not Found
        405, // Method Not Allowed
        408, // Request Timeout
        409, // Conflict
        410, // Gone
        413, // Payload Too Large
        415, // Unsupported Media Type
        422, // Unprocessable Entity
        429, // Too Many Requests
        
        // Server errors
        500, // Internal Server Error
        501, // Not Implemented
        502, // Bad Gateway
        503, // Service Unavailable
        504, // Gateway Timeout
    };

    /// <summary>
    /// Status codes that are less common and should include the status code in the message.
    /// </summary>
    private static readonly int[] UncommonStatusCodes = new[]
    {
        403, // Forbidden
        404, // Not Found
        413, // Payload Too Large
        400, // Bad Request
        500, // Server Error
        501, // Not Implemented
        502, // Bad Gateway
        503, // Service Unavailable
        504, // Gateway Timeout
    };

    /// <summary>
    /// Generates all common HTTP status codes.
    /// </summary>
    public static Arbitrary<int> GenerateAllHttpStatusCodes()
    {
        return Arb.From(
            Gen.Frequency(
                // Common status codes (weighted higher)
                Tuple.Create(8, Gen.Elements(CommonStatusCodes)),
                // Any 4xx error code
                Tuple.Create(1, Gen.Choose(400, 499)),
                // Any 5xx error code
                Tuple.Create(1, Gen.Choose(500, 599)),
                // Edge case: unusual status codes
                Tuple.Create(1, Gen.Choose(100, 199)),
                Tuple.Create(1, Gen.Choose(200, 299)),
                Tuple.Create(1, Gen.Choose(300, 399))
            ));
    }

    /// <summary>
    /// Generates uncommon status codes that should include the code in the message.
    /// </summary>
    public static Arbitrary<int> GenerateUncommonStatusCodes()
    {
        return Arb.From(Gen.Elements(UncommonStatusCodes));
    }

    /// <summary>
    /// Generates realistic API host names, including null.
    /// </summary>
    public static Arbitrary<string?> GenerateHostNames()
    {
        return Arb.From(
            Gen.Frequency(
                // null host (should use placeholder)
                Tuple.Create(1, Gen.Constant<string?>(null)),
                // Real API hosts
                Tuple.Create(3, Gen.Elements<string?>(
                    "api.groq.com",
                    "api.openai.com",
                    "api.anthropic.com",
                    "localhost",
                    "192.168.1.1",
                    "my-custom-api.example.com"
                ))
            ));
    }

    /// <summary>
    /// Generates only non-empty host names.
    /// </summary>
    public static Arbitrary<string> GenerateNonEmptyHostNames()
    {
        return Arb.From(
            Gen.Elements(
                "api.groq.com",
                "api.openai.com",
                "api.anthropic.com",
                "localhost",
                "192.168.1.1",
                "my-custom-api.example.com"
            ));
    }
}
