using System.Linq;
using FreeFlowWindows.Core.Services;
using FsCheck;
using FsCheck.Xunit;

namespace FreeFlowWindows.Tests.PropertyTests;

/// <summary>
/// Property-based tests for TranscriptSanitizer.
/// </summary>
public class TranscriptSanitizerPropertyTests
{
    /// <summary>
    /// **Validates: Requirements 5.3, 5.4, 5.5**
    /// 
    /// Property 6: Transcript Sanitization Idempotence
    /// 
    /// For any string that has been processed through the transcript sanitization function 
    /// (which removes leading/trailing whitespace, normalizes line endings, and strips 
    /// control characters), applying the same sanitization function a second time should 
    /// produce an identical result. Formally: sanitize(sanitize(s)) == sanitize(s) for all strings s.
    /// </summary>
    [Property(MaxTest = 100, Verbose = true)]
    public Property Sanitize_IsIdempotent_ForAnyString()
    {
        return Prop.ForAll(
            TranscriptArbitrary.GenerateArbitraryStrings(),
            input =>
            {
                // Act
                var firstResult = TranscriptSanitizer.Sanitize(input);
                var secondResult = TranscriptSanitizer.Sanitize(firstResult);

                // Assert: sanitize(sanitize(s)) == sanitize(s)
                return firstResult == secondResult;
            });
    }

    /// <summary>
    /// **Validates: Requirements 5.3, 5.4, 5.5**
    /// 
    /// Property 6 extended: SanitizePostProcessed is also idempotent.
    /// 
    /// For strings that don't match the EMPTY sentinel, applying SanitizePostProcessed 
    /// twice should produce the same result as applying it once.
    /// </summary>
    [Property(MaxTest = 100, Verbose = true)]
    public Property SanitizePostProcessed_IsIdempotent_ForNonEmptyResults()
    {
        return Prop.ForAll(
            TranscriptArbitrary.GenerateArbitraryStrings(),
            input =>
            {
                // Act
                var firstResult = TranscriptSanitizer.SanitizePostProcessed(input);
                
                // Skip empty results as they're special (EMPTY sentinel handled)
                if (string.IsNullOrEmpty(firstResult))
                {
                    return true; // Trivially idempotent
                }

                var secondResult = TranscriptSanitizer.SanitizePostProcessed(firstResult);

                // Assert: sanitize(sanitize(s)) == sanitize(s)
                return firstResult == secondResult;
            });
    }

    /// <summary>
    /// **Validates: Requirements 5.3, 5.4, 5.5**
    /// 
    /// Property 6 extended: Sanitized output never contains carriage return.
    /// 
    /// Line endings should be normalized to LF only (no CR characters).
    /// </summary>
    [Property(MaxTest = 100, Verbose = true)]
    public Property Sanitize_NeverContainsCarriageReturn()
    {
        return Prop.ForAll(
            TranscriptArbitrary.GenerateStringsWithMixedLineEndings(),
            input =>
            {
                // Act
                var result = TranscriptSanitizer.Sanitize(input);

                // Assert: No CR characters in output
                return !result.Contains('\r');
            });
    }

    /// <summary>
    /// **Validates: Requirements 5.3, 5.4, 5.5**
    /// 
    /// Property 6 extended: Sanitized output never contains unwanted control characters.
    /// 
    /// Control characters (except TAB and LF) should be stripped.
    /// </summary>
    [Property(MaxTest = 100, Verbose = true)]
    public Property Sanitize_NeverContainsUnwantedControlCharacters()
    {
        return Prop.ForAll(
            TranscriptArbitrary.GenerateStringsWithControlCharacters(),
            input =>
            {
                // Act
                var result = TranscriptSanitizer.Sanitize(input);

                // Assert: No unwanted control characters in output
                foreach (var c in result)
                {
                    // Only TAB (0x09) and LF (0x0A) are allowed from control range
                    if (c < 0x20 && c != '\t' && c != '\n')
                    {
                        return false;
                    }
                    // DEL character
                    if (c == 0x7F)
                    {
                        return false;
                    }
                    // C1 control characters
                    if (c >= 0x80 && c <= 0x9F)
                    {
                        return false;
                    }
                }

                return true;
            });
    }

    /// <summary>
    /// **Validates: Requirements 5.3, 5.4, 5.5**
    /// 
    /// Property 6 extended: Sanitized output never has leading/trailing whitespace.
    /// 
    /// The output should be trimmed on both ends.
    /// </summary>
    [Property(MaxTest = 100, Verbose = true)]
    public Property Sanitize_NeverHasLeadingOrTrailingWhitespace()
    {
        return Prop.ForAll(
            TranscriptArbitrary.GenerateArbitraryStrings(),
            input =>
            {
                // Act
                var result = TranscriptSanitizer.Sanitize(input);

                // Empty results are trivially valid
                if (string.IsNullOrEmpty(result))
                {
                    return true;
                }

                // Assert: result == result.Trim()
                return result == result.Trim();
            });
    }

    /// <summary>
    /// **Validates: Requirements 5.3, 5.4, 5.5**
    /// 
    /// Property 6 extended: Sanitization preserves non-control printable content.
    /// 
    /// If the input contains printable characters (not control chars), those characters
    /// should appear in the output (in order), except for trimmed whitespace at ends.
    /// </summary>
    [Property(MaxTest = 100, Verbose = true)]
    public Property Sanitize_PreservesPrintableContent()
    {
        return Prop.ForAll(
            TranscriptArbitrary.GeneratePrintableStrings(),
            input =>
            {
                // Act
                var result = TranscriptSanitizer.Sanitize(input);

                // The result should be the trimmed version of the input
                // (with line endings normalized and control chars stripped)
                var expected = input.Trim();

                // Result should equal the trimmed input for pure printable strings
                return result == expected;
            });
    }

    /// <summary>
    /// **Validates: Requirements 5.9**
    /// 
    /// Property 7: Empty Response Detection Consistency
    /// 
    /// For any LLM response string that is empty, contains only whitespace, or equals 
    /// the literal text "EMPTY" (case-insensitive), the post-processing service should 
    /// consistently classify it as an empty result and return a signal to skip pasting.
    /// 
    /// This test verifies: If IsEmptyResponse(s) returns true, then SanitizePostProcessed(s)
    /// returns an empty string.
    /// </summary>
    [Property(MaxTest = 100, Verbose = true)]
    public Property IsEmptyResponse_True_ImpliesSanitizePostProcessed_ReturnsEmpty()
    {
        return Prop.ForAll(
            TranscriptArbitrary.GenerateArbitraryStrings(),
            input =>
            {
                // If IsEmptyResponse returns true, SanitizePostProcessed must return empty
                if (TranscriptSanitizer.IsEmptyResponse(input))
                {
                    var sanitized = TranscriptSanitizer.SanitizePostProcessed(input);
                    return string.IsNullOrEmpty(sanitized);
                }
                
                // If not empty, the property trivially holds
                return true;
            });
    }

    /// <summary>
    /// **Validates: Requirements 5.9**
    /// 
    /// Property 7 extended: Non-empty sanitized result implies not an empty response.
    /// 
    /// If SanitizePostProcessed(s) returns a non-empty string, then IsEmptyResponse(s) 
    /// must return false. This is the contrapositive of the consistency property.
    /// </summary>
    [Property(MaxTest = 100, Verbose = true)]
    public Property SanitizePostProcessed_NonEmpty_ImpliesIsEmptyResponse_False()
    {
        return Prop.ForAll(
            TranscriptArbitrary.GenerateArbitraryStrings(),
            input =>
            {
                var sanitized = TranscriptSanitizer.SanitizePostProcessed(input);
                
                // If SanitizePostProcessed returns non-empty, IsEmptyResponse must be false
                if (!string.IsNullOrEmpty(sanitized))
                {
                    return !TranscriptSanitizer.IsEmptyResponse(input);
                }
                
                // If sanitized is empty, the property trivially holds
                return true;
            });
    }

    /// <summary>
    /// **Validates: Requirements 5.9**
    /// 
    /// Property 7 extended: The "EMPTY" sentinel (case-insensitive) should always be 
    /// detected as an empty response.
    /// 
    /// This tests all common case variations of the EMPTY sentinel.
    /// </summary>
    [Property(MaxTest = 100, Verbose = true)]
    public Property EmptySentinel_AlwaysDetectedAsEmpty()
    {
        return Prop.ForAll(
            TranscriptArbitrary.GenerateEmptySentinelVariations(),
            input =>
            {
                // All EMPTY sentinel variations should be detected as empty
                return TranscriptSanitizer.IsEmptyResponse(input);
            });
    }

    /// <summary>
    /// **Validates: Requirements 5.9**
    /// 
    /// Property 7 extended: Empty, null, and whitespace-only strings are always
    /// detected as empty responses.
    /// </summary>
    [Property(MaxTest = 100, Verbose = true)]
    public Property EmptyWhitespaceOrNull_AlwaysDetectedAsEmpty()
    {
        return Prop.ForAll(
            TranscriptArbitrary.GenerateEmptyOrWhitespaceStrings(),
            input =>
            {
                // Null, empty, and whitespace-only should all be detected as empty
                return TranscriptSanitizer.IsEmptyResponse(input);
            });
    }

    /// <summary>
    /// **Validates: Requirements 5.9**
    /// 
    /// Property 7 extended: Non-empty, non-EMPTY strings with actual content
    /// should not be detected as empty responses.
    /// </summary>
    [Property(MaxTest = 100, Verbose = true)]
    public Property NonEmptyContent_NotDetectedAsEmpty()
    {
        return Prop.ForAll(
            TranscriptArbitrary.GenerateNonEmptyContentStrings(),
            input =>
            {
                // Real content should not be detected as empty
                return !TranscriptSanitizer.IsEmptyResponse(input);
            });
    }
}

/// <summary>
/// Custom FsCheck arbitrary generators for transcript sanitizer tests.
/// </summary>
public static class TranscriptArbitrary
{
    /// <summary>
    /// Generates arbitrary strings including null, empty, whitespace, control chars, and Unicode.
    /// </summary>
    public static Arbitrary<string> GenerateArbitraryStrings()
    {
        return Arb.From(
            Gen.Frequency(
                // Null
                Tuple.Create(1, Gen.Constant<string>(null!)),
                // Empty string
                Tuple.Create(1, Gen.Constant("")),
                // Whitespace only
                Tuple.Create(2, GenerateWhitespaceOnlyString()),
                // Normal ASCII strings
                Tuple.Create(4, Arb.Generate<string>()),
                // Strings with control characters
                Tuple.Create(2, GenerateStringWithControlChars()),
                // Strings with mixed line endings
                Tuple.Create(2, GenerateStringWithMixedLineEndings()),
                // Unicode strings
                Tuple.Create(2, GenerateUnicodeString()),
                // Strings with quotes
                Tuple.Create(1, GenerateQuotedString()),
                // EMPTY sentinel variations
                Tuple.Create(1, GenerateEmptySentinel())
            ));
    }

    /// <summary>
    /// Generates strings that may contain various line ending styles.
    /// </summary>
    public static Arbitrary<string> GenerateStringsWithMixedLineEndings()
    {
        return Arb.From(
            Gen.Frequency(
                // Windows CRLF
                Tuple.Create(2, GenerateStringWithLineEnding("\r\n")),
                // Old Mac CR
                Tuple.Create(1, GenerateStringWithLineEnding("\r")),
                // Unix LF
                Tuple.Create(2, GenerateStringWithLineEnding("\n")),
                // Mixed
                Tuple.Create(1, GenerateStringWithMixedLineEndings())
            ));
    }

    /// <summary>
    /// Generates strings that contain control characters.
    /// </summary>
    public static Arbitrary<string> GenerateStringsWithControlCharacters()
    {
        return Arb.From(GenerateStringWithControlChars());
    }

    /// <summary>
    /// Generates strings containing only printable characters (no control chars).
    /// </summary>
    public static Arbitrary<string> GeneratePrintableStrings()
    {
        return Arb.From(
            from length in Gen.Choose(0, 50)
            from chars in Gen.ArrayOf(length, GeneratePrintableChar())
            select new string(chars));
    }

    private static Gen<string> GenerateWhitespaceOnlyString()
    {
        var whitespaceChars = new[] { ' ', '\t', '\n', '\r' };
        return from length in Gen.Choose(1, 10)
               from chars in Gen.ArrayOf(length, Gen.Elements(whitespaceChars))
               select new string(chars);
    }

    private static Gen<string> GenerateStringWithControlChars()
    {
        var controlChars = new[] { '\0', '\a', '\b', '\f', '\v', '\x1B', '\x7F' };
        return from prefix in Arb.Generate<string>().Where(s => s != null)
               from ctrl in Gen.Elements(controlChars)
               from suffix in Arb.Generate<string>().Where(s => s != null)
               select prefix + ctrl + suffix;
    }

    private static Gen<string> GenerateStringWithLineEnding(string lineEnding)
    {
        return from part1 in GenerateSimpleWord()
               from part2 in GenerateSimpleWord()
               select part1 + lineEnding + part2;
    }

    private static Gen<string> GenerateStringWithMixedLineEndings()
    {
        return from parts in Gen.ArrayOf(4, GenerateSimpleWord())
               select parts[0] + "\r\n" + parts[1] + "\r" + parts[2] + "\n" + parts[3];
    }

    private static Gen<string> GenerateSimpleWord()
    {
        return from length in Gen.Choose(1, 10)
               from chars in Gen.ArrayOf(length, Gen.Choose('a', 'z').Select(i => (char)i))
               select new string(chars);
    }

    private static Gen<string> GenerateUnicodeString()
    {
        var unicodeSamples = new[]
        {
            "Hello 世界",
            "مرحبا",
            "Привет",
            "🌍🎉👋",
            "Café résumé naïve",
            "€ £ ¥"
        };
        return Gen.Elements(unicodeSamples);
    }

    private static Gen<string> GenerateQuotedString()
    {
        return from content in GenerateSimpleWord()
               from leadingSpace in Gen.Choose(0, 3).Select(n => new string(' ', n))
               from trailingSpace in Gen.Choose(0, 3).Select(n => new string(' ', n))
               select leadingSpace + "\"" + content + "\"" + trailingSpace;
    }

    private static Gen<string> GenerateEmptySentinel()
    {
        var variants = new[] { "EMPTY", "empty", "Empty", "eMpTy", "  EMPTY  ", "\"EMPTY\"" };
        return Gen.Elements(variants);
    }

    private static Gen<char> GeneratePrintableChar()
    {
        // Printable ASCII range (space to tilde)
        return Gen.Choose(0x20, 0x7E).Select(i => (char)i);
    }

    /// <summary>
    /// Generates EMPTY sentinel variations with different cases, whitespace, and quotes.
    /// </summary>
    public static Arbitrary<string> GenerateEmptySentinelVariations()
    {
        return Arb.From(
            Gen.Frequency(
                // Case variations
                Tuple.Create(2, Gen.Constant("EMPTY")),
                Tuple.Create(2, Gen.Constant("empty")),
                Tuple.Create(2, Gen.Constant("Empty")),
                Tuple.Create(1, Gen.Constant("eMpTy")),
                Tuple.Create(1, Gen.Constant("EMPTY ")),
                Tuple.Create(1, Gen.Constant(" EMPTY")),
                Tuple.Create(1, Gen.Constant("  EMPTY  ")),
                // With quotes
                Tuple.Create(1, Gen.Constant("\"EMPTY\"")),
                Tuple.Create(1, Gen.Constant("\"empty\"")),
                Tuple.Create(1, Gen.Constant(" \"EMPTY\" ")),
                // With mixed whitespace
                Tuple.Create(1, Gen.Constant("\tEMPTY\t")),
                Tuple.Create(1, Gen.Constant("\nEMPTY\n")),
                // Random case variations
                Tuple.Create(2, GenerateRandomCaseEmpty())
            ));
    }

    /// <summary>
    /// Generates null, empty strings, and whitespace-only strings.
    /// </summary>
    public static Arbitrary<string> GenerateEmptyOrWhitespaceStrings()
    {
        return Arb.From(
            Gen.Frequency(
                // Null
                Tuple.Create(2, Gen.Constant<string>(null!)),
                // Empty string
                Tuple.Create(2, Gen.Constant("")),
                // Single space
                Tuple.Create(1, Gen.Constant(" ")),
                // Multiple spaces
                Tuple.Create(1, Gen.Constant("   ")),
                // Tab only
                Tuple.Create(1, Gen.Constant("\t")),
                // Newline only
                Tuple.Create(1, Gen.Constant("\n")),
                // Mixed whitespace
                Tuple.Create(1, Gen.Constant(" \t \n ")),
                // Random whitespace-only strings
                Tuple.Create(2, GenerateWhitespaceOnlyString())
            ));
    }

    /// <summary>
    /// Generates strings with actual content that should NOT be considered empty.
    /// </summary>
    public static Arbitrary<string> GenerateNonEmptyContentStrings()
    {
        return Arb.From(
            Gen.Frequency(
                // Simple words
                Tuple.Create(3, GenerateSimpleWord()),
                // Sentences
                Tuple.Create(2, GenerateSentence()),
                // Words with surrounding whitespace (content preserved after trim)
                Tuple.Create(1, GenerateWordWithWhitespace()),
                // Unicode content
                Tuple.Create(1, GenerateUnicodeString()),
                // Quoted content (not EMPTY)
                Tuple.Create(1, GenerateQuotedNonEmpty()),
                // Numbers
                Tuple.Create(1, GenerateNumberString()),
                // Strings that look similar to EMPTY but aren't
                Tuple.Create(1, GenerateNearEmptyStrings())
            ));
    }

    private static Gen<string> GenerateRandomCaseEmpty()
    {
        return from chars in Gen.ArrayOf(5, Gen.Elements('E', 'e', 'M', 'm', 'P', 'p', 'T', 't', 'Y', 'y'))
               let baseStr = "EMPTY"
               from indices in Gen.Shuffle(new[] { 0, 1, 2, 3, 4 })
               let indexArray = indices.ToArray()
               select new string(baseStr.ToLower().ToCharArray()
                   .Select((c, i) => indexArray.Take(3).Contains(i) ? char.ToUpper(c) : c).ToArray());
    }

    private static Gen<string> GenerateSentence()
    {
        return from wordCount in Gen.Choose(3, 8)
               from words in Gen.ArrayOf(wordCount, GenerateSimpleWord())
               select string.Join(" ", (IEnumerable<string>)words) + ".";
    }

    private static Gen<string> GenerateWordWithWhitespace()
    {
        return from leadingSpaces in Gen.Choose(0, 3).Select(n => new string(' ', n))
               from word in GenerateSimpleWord()
               from trailingSpaces in Gen.Choose(0, 3).Select(n => new string(' ', n))
               select leadingSpaces + word + trailingSpaces;
    }

    private static Gen<string> GenerateQuotedNonEmpty()
    {
        return from word in GenerateSimpleWord()
               select "\"" + word + "\"";
    }

    private static Gen<string> GenerateNumberString()
    {
        return from num in Arb.Generate<int>()
               select num.ToString();
    }

    private static Gen<string> GenerateNearEmptyStrings()
    {
        // Strings that look similar to "EMPTY" but aren't
        var nearEmpties = new[]
        {
            "EMPT",
            "MPTY", 
            "EMPTYX",
            "XEMPTY",
            "E M P T Y",
            "EM PTY",
            "NOT EMPTY",
            "EMPTYISH",
            "FEMPTY",
            "EMPTY1"
        };
        return Gen.Elements(nearEmpties);
    }
}
