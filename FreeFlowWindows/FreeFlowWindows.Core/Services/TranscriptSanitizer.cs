using System.Text;

namespace FreeFlowWindows.Core.Services;

/// <summary>
/// Sanitizes transcript text by removing leading/trailing whitespace,
/// normalizing line endings, and stripping control characters.
/// </summary>
/// <remarks>
/// This sanitizer guarantees idempotence: calling Sanitize() on an already-sanitized
/// string produces the same result. This is important for consistent processing
/// throughout the dictation pipeline.
/// 
/// Validates: Requirements 5.3, 5.4, 5.5
/// </remarks>
public static class TranscriptSanitizer
{
    /// <summary>
    /// Sanitizes a transcript string by:
    /// 1. Removing leading and trailing whitespace
    /// 2. Normalizing line endings (CRLF and CR to LF)
    /// 3. Stripping control characters (except LF and TAB)
    /// </summary>
    /// <param name="input">The raw transcript text to sanitize.</param>
    /// <returns>The sanitized transcript, or empty string if input is null/whitespace.</returns>
    /// <remarks>
    /// This method is idempotent: Sanitize(Sanitize(s)) == Sanitize(s) for all strings s.
    /// </remarks>
    public static string Sanitize(string? input)
    {
        if (string.IsNullOrWhiteSpace(input))
        {
            return string.Empty;
        }

        // First pass: normalize line endings (CRLF -> LF, CR -> LF)
        var normalized = NormalizeLineEndings(input);

        // Second pass: strip control characters (except LF and TAB)
        var stripped = StripControlCharacters(normalized);

        // Final pass: trim leading and trailing whitespace
        return stripped.Trim();
    }

    /// <summary>
    /// Sanitizes a post-processed transcript by applying the standard sanitization
    /// plus LLM-specific cleanup (outer quote removal, EMPTY sentinel detection).
    /// </summary>
    /// <param name="input">The raw LLM output to sanitize.</param>
    /// <returns>The sanitized transcript, or empty string for null/whitespace/EMPTY values.</returns>
    public static string SanitizePostProcessed(string? input)
    {
        // Apply standard sanitization first
        var sanitized = Sanitize(input);

        if (string.IsNullOrEmpty(sanitized))
        {
            return string.Empty;
        }

        // Strip outer quotes if the LLM wrapped the entire response
        if (sanitized.Length > 1 && sanitized.StartsWith('"') && sanitized.EndsWith('"'))
        {
            sanitized = sanitized[1..^1].Trim();
        }

        // Treat the sentinel value as empty
        if (sanitized.Equals("EMPTY", StringComparison.OrdinalIgnoreCase))
        {
            return string.Empty;
        }

        return sanitized;
    }

    /// <summary>
    /// Checks if a string is considered an "empty" response that should skip pasting.
    /// Returns true for null, empty strings, whitespace-only, or the "EMPTY" sentinel.
    /// </summary>
    public static bool IsEmptyResponse(string? response)
    {
        if (string.IsNullOrWhiteSpace(response))
        {
            return true;
        }

        var trimmed = response.Trim();

        // Handle quoted "EMPTY"
        if (trimmed.Length > 1 && trimmed.StartsWith('"') && trimmed.EndsWith('"'))
        {
            trimmed = trimmed[1..^1].Trim();
        }

        return trimmed.Equals("EMPTY", StringComparison.OrdinalIgnoreCase);
    }

    /// <summary>
    /// Normalizes line endings to Unix-style LF.
    /// Converts Windows CRLF and old Mac CR to LF.
    /// </summary>
    private static string NormalizeLineEndings(string input)
    {
        if (string.IsNullOrEmpty(input))
        {
            return string.Empty;
        }

        // Replace CRLF first (order matters), then standalone CR
        return input
            .Replace("\r\n", "\n")
            .Replace("\r", "\n");
    }

    /// <summary>
    /// Strips control characters from the string, preserving only:
    /// - Regular printable characters (code point >= 32)
    /// - Line feed (LF, code point 10) for line breaks
    /// - Horizontal tab (TAB, code point 9) for indentation
    /// </summary>
    private static string StripControlCharacters(string input)
    {
        if (string.IsNullOrEmpty(input))
        {
            return string.Empty;
        }

        // Check if any control characters exist (optimization to avoid allocation)
        var hasControlChars = false;
        foreach (var c in input)
        {
            if (IsUnwantedControlCharacter(c))
            {
                hasControlChars = true;
                break;
            }
        }

        if (!hasControlChars)
        {
            return input;
        }

        // Build new string without unwanted control characters
        var sb = new StringBuilder(input.Length);
        foreach (var c in input)
        {
            if (!IsUnwantedControlCharacter(c))
            {
                sb.Append(c);
            }
        }

        return sb.ToString();
    }

    /// <summary>
    /// Determines if a character is an unwanted control character.
    /// Returns true for control characters except LF (10) and TAB (9).
    /// </summary>
    private static bool IsUnwantedControlCharacter(char c)
    {
        // Control characters are in ranges:
        // - 0x00-0x1F (C0 controls)
        // - 0x7F (DEL)
        // - 0x80-0x9F (C1 controls)
        //
        // We preserve:
        // - 0x09 (TAB) for indentation
        // - 0x0A (LF) for line breaks

        if (c == '\t' || c == '\n')
        {
            return false; // Preserve TAB and LF
        }

        // C0 controls (excluding TAB and LF which are already handled)
        if (c < 0x20)
        {
            return true;
        }

        // DEL character
        if (c == 0x7F)
        {
            return true;
        }

        // C1 controls
        if (c >= 0x80 && c <= 0x9F)
        {
            return true;
        }

        return false;
    }

    /// <summary>
    /// Normalizes a multi-line transcript by collapsing multiple consecutive
    /// blank lines into a single blank line.
    /// </summary>
    /// <param name="input">The input text with potentially excessive blank lines.</param>
    /// <returns>The text with normalized blank lines.</returns>
    public static string NormalizeBlankLines(string? input)
    {
        if (string.IsNullOrWhiteSpace(input))
        {
            return string.Empty;
        }

        var sanitized = Sanitize(input);
        if (string.IsNullOrEmpty(sanitized))
        {
            return string.Empty;
        }

        // Split into lines, then reconstruct with max one blank line between paragraphs
        var lines = sanitized.Split('\n');
        var result = new StringBuilder();
        var previousWasBlank = false;
        var firstLine = true;

        foreach (var line in lines)
        {
            var trimmedLine = line.TrimEnd();
            var isBlank = string.IsNullOrWhiteSpace(trimmedLine);

            if (isBlank)
            {
                // Only mark as blank, don't add yet - we'll add a blank line when we see the next non-blank
                previousWasBlank = true;
            }
            else
            {
                if (!firstLine)
                {
                    // Add a single newline, plus another if previous line(s) were blank
                    result.Append('\n');
                    if (previousWasBlank)
                    {
                        result.Append('\n');
                    }
                }
                result.Append(trimmedLine);
                previousWasBlank = false;
                firstLine = false;
            }
        }

        return result.ToString();
    }
}
