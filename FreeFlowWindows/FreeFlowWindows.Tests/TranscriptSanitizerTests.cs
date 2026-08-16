using FreeFlowWindows.Core.Services;

namespace FreeFlowWindows.Tests;

/// <summary>
/// Unit tests for TranscriptSanitizer.
/// Tests whitespace removal, line ending normalization, and control character stripping.
/// Validates: Requirements 5.3, 5.4, 5.5
/// </summary>
public class TranscriptSanitizerTests
{
    #region Basic Sanitization Tests

    [Fact]
    public void Sanitize_NullInput_ReturnsEmptyString()
    {
        // Act
        var result = TranscriptSanitizer.Sanitize(null);

        // Assert
        Assert.Equal(string.Empty, result);
    }

    [Fact]
    public void Sanitize_EmptyString_ReturnsEmptyString()
    {
        // Act
        var result = TranscriptSanitizer.Sanitize("");

        // Assert
        Assert.Equal(string.Empty, result);
    }

    [Theory]
    [InlineData(" ")]
    [InlineData("  ")]
    [InlineData("\t")]
    [InlineData("\n")]
    [InlineData("\r\n")]
    [InlineData("   \t\n   ")]
    public void Sanitize_WhitespaceOnly_ReturnsEmptyString(string input)
    {
        // Act
        var result = TranscriptSanitizer.Sanitize(input);

        // Assert
        Assert.Equal(string.Empty, result);
    }

    [Fact]
    public void Sanitize_SimpleText_ReturnsTrimmed()
    {
        // Arrange
        var input = "Hello, World!";

        // Act
        var result = TranscriptSanitizer.Sanitize(input);

        // Assert
        Assert.Equal("Hello, World!", result);
    }

    #endregion

    #region Whitespace Trimming Tests

    [Fact]
    public void Sanitize_LeadingWhitespace_Trimmed()
    {
        // Arrange
        var input = "   Hello";

        // Act
        var result = TranscriptSanitizer.Sanitize(input);

        // Assert
        Assert.Equal("Hello", result);
    }

    [Fact]
    public void Sanitize_TrailingWhitespace_Trimmed()
    {
        // Arrange
        var input = "Hello   ";

        // Act
        var result = TranscriptSanitizer.Sanitize(input);

        // Assert
        Assert.Equal("Hello", result);
    }

    [Fact]
    public void Sanitize_BothLeadingAndTrailingWhitespace_Trimmed()
    {
        // Arrange
        var input = "   Hello World   ";

        // Act
        var result = TranscriptSanitizer.Sanitize(input);

        // Assert
        Assert.Equal("Hello World", result);
    }

    [Fact]
    public void Sanitize_MixedWhitespaceTypes_Trimmed()
    {
        // Arrange
        var input = " \t\n  Hello World  \t\n ";

        // Act
        var result = TranscriptSanitizer.Sanitize(input);

        // Assert
        Assert.Equal("Hello World", result);
    }

    #endregion

    #region Line Ending Normalization Tests

    [Fact]
    public void Sanitize_WindowsCRLF_NormalizedToLF()
    {
        // Arrange
        var input = "Line 1\r\nLine 2\r\nLine 3";

        // Act
        var result = TranscriptSanitizer.Sanitize(input);

        // Assert
        Assert.Equal("Line 1\nLine 2\nLine 3", result);
        Assert.DoesNotContain("\r", result);
    }

    [Fact]
    public void Sanitize_OldMacCR_NormalizedToLF()
    {
        // Arrange
        var input = "Line 1\rLine 2\rLine 3";

        // Act
        var result = TranscriptSanitizer.Sanitize(input);

        // Assert
        Assert.Equal("Line 1\nLine 2\nLine 3", result);
        Assert.DoesNotContain("\r", result);
    }

    [Fact]
    public void Sanitize_MixedLineEndings_AllNormalizedToLF()
    {
        // Arrange
        var input = "Line 1\r\nLine 2\rLine 3\nLine 4";

        // Act
        var result = TranscriptSanitizer.Sanitize(input);

        // Assert
        Assert.Equal("Line 1\nLine 2\nLine 3\nLine 4", result);
        Assert.DoesNotContain("\r", result);
    }

    [Fact]
    public void Sanitize_UnixLF_Preserved()
    {
        // Arrange
        var input = "Line 1\nLine 2\nLine 3";

        // Act
        var result = TranscriptSanitizer.Sanitize(input);

        // Assert
        Assert.Equal("Line 1\nLine 2\nLine 3", result);
    }

    #endregion

    #region Control Character Stripping Tests

    [Fact]
    public void Sanitize_NullCharacter_Removed()
    {
        // Arrange
        var input = "Hello\0World";

        // Act
        var result = TranscriptSanitizer.Sanitize(input);

        // Assert
        Assert.Equal("HelloWorld", result);
        // Check length - if null char was removed, length should be 10
        Assert.Equal(10, result.Length);
        Assert.False(result.Contains('\0'), "Result should not contain null character");
    }

    [Fact]
    public void Sanitize_BellCharacter_Removed()
    {
        // Arrange
        var input = "Hello\aWorld";

        // Act
        var result = TranscriptSanitizer.Sanitize(input);

        // Assert
        Assert.Equal("HelloWorld", result);
    }

    [Fact]
    public void Sanitize_BackspaceCharacter_Removed()
    {
        // Arrange
        var input = "Hello\bWorld";

        // Act
        var result = TranscriptSanitizer.Sanitize(input);

        // Assert
        Assert.Equal("HelloWorld", result);
    }

    [Fact]
    public void Sanitize_FormFeedCharacter_Removed()
    {
        // Arrange
        var input = "Hello\fWorld";

        // Act
        var result = TranscriptSanitizer.Sanitize(input);

        // Assert
        Assert.Equal("HelloWorld", result);
    }

    [Fact]
    public void Sanitize_VerticalTabCharacter_Removed()
    {
        // Arrange
        var input = "Hello\vWorld";

        // Act
        var result = TranscriptSanitizer.Sanitize(input);

        // Assert
        Assert.Equal("HelloWorld", result);
    }

    [Fact]
    public void Sanitize_EscapeCharacter_Removed()
    {
        // Arrange
        var input = "Hello\x1BWorld"; // ESC character

        // Act
        var result = TranscriptSanitizer.Sanitize(input);

        // Assert
        Assert.Equal("HelloWorld", result);
    }

    [Fact]
    public void Sanitize_DELCharacter_Removed()
    {
        // Arrange
        var input = "Hello\x7FWorld"; // DEL character

        // Act
        var result = TranscriptSanitizer.Sanitize(input);

        // Assert
        Assert.Equal("HelloWorld", result);
    }

    [Fact]
    public void Sanitize_C1ControlCharacters_Removed()
    {
        // Arrange - C1 control characters (0x80-0x9F)
        var input = "Hello\x80\x8F\x9FWorld";

        // Act
        var result = TranscriptSanitizer.Sanitize(input);

        // Assert
        Assert.Equal("HelloWorld", result);
    }

    [Fact]
    public void Sanitize_TabCharacter_Preserved()
    {
        // Arrange
        var input = "Hello\tWorld";

        // Act
        var result = TranscriptSanitizer.Sanitize(input);

        // Assert
        Assert.Equal("Hello\tWorld", result);
        Assert.Contains("\t", result);
    }

    [Fact]
    public void Sanitize_LineFeedCharacter_Preserved()
    {
        // Arrange
        var input = "Hello\nWorld";

        // Act
        var result = TranscriptSanitizer.Sanitize(input);

        // Assert
        Assert.Equal("Hello\nWorld", result);
        Assert.Contains("\n", result);
    }

    [Fact]
    public void Sanitize_MultipleControlCharacters_AllRemoved()
    {
        // Arrange
        var input = "\0Hello\a\b\fWorld\v\x1B\x7F";

        // Act
        var result = TranscriptSanitizer.Sanitize(input);

        // Assert
        Assert.Equal("HelloWorld", result);
    }

    [Fact]
    public void Sanitize_StringWithNoControlChars_NoAllocation()
    {
        // Arrange - Clean string should pass through efficiently
        var input = "Hello World! This is a clean string with no control characters.";

        // Act
        var result = TranscriptSanitizer.Sanitize(input);

        // Assert
        Assert.Equal(input, result);
    }

    #endregion

    #region SanitizePostProcessed Tests

    [Fact]
    public void SanitizePostProcessed_QuotedString_QuotesRemoved()
    {
        // Arrange
        var input = "\"Hello World\"";

        // Act
        var result = TranscriptSanitizer.SanitizePostProcessed(input);

        // Assert
        Assert.Equal("Hello World", result);
    }

    [Fact]
    public void SanitizePostProcessed_QuotedStringWithWhitespace_BothHandled()
    {
        // Arrange
        var input = "  \"Hello World\"  ";

        // Act
        var result = TranscriptSanitizer.SanitizePostProcessed(input);

        // Assert
        Assert.Equal("Hello World", result);
    }

    [Fact]
    public void SanitizePostProcessed_UnbalancedQuotes_NotRemoved()
    {
        // Arrange - Only leading quote
        var input = "\"Hello World";

        // Act
        var result = TranscriptSanitizer.SanitizePostProcessed(input);

        // Assert
        Assert.Equal("\"Hello World", result);
    }

    [Fact]
    public void SanitizePostProcessed_SingleQuote_NotRemoved()
    {
        // Arrange - Just a single quote character
        var input = "\"";

        // Act
        var result = TranscriptSanitizer.SanitizePostProcessed(input);

        // Assert
        Assert.Equal("\"", result);
    }

    [Theory]
    [InlineData("EMPTY")]
    [InlineData("empty")]
    [InlineData("Empty")]
    [InlineData("eMpTy")]
    public void SanitizePostProcessed_EMPTYSentinel_ReturnsEmptyString(string input)
    {
        // Act
        var result = TranscriptSanitizer.SanitizePostProcessed(input);

        // Assert
        Assert.Equal(string.Empty, result);
    }

    [Fact]
    public void SanitizePostProcessed_QuotedEMPTY_ReturnsEmptyString()
    {
        // Arrange
        var input = "\"EMPTY\"";

        // Act
        var result = TranscriptSanitizer.SanitizePostProcessed(input);

        // Assert
        Assert.Equal(string.Empty, result);
    }

    [Fact]
    public void SanitizePostProcessed_EMPTYWithWhitespace_ReturnsEmptyString()
    {
        // Arrange
        var input = "  EMPTY  ";

        // Act
        var result = TranscriptSanitizer.SanitizePostProcessed(input);

        // Assert
        Assert.Equal(string.Empty, result);
    }

    [Fact]
    public void SanitizePostProcessed_EMPTYAsPartOfWord_NotTreatedAsEmpty()
    {
        // Arrange - "EMPTY" within other text should not be treated as empty
        var input = "The room is EMPTY today";

        // Act
        var result = TranscriptSanitizer.SanitizePostProcessed(input);

        // Assert
        Assert.Equal("The room is EMPTY today", result);
    }

    [Fact]
    public void SanitizePostProcessed_ControlCharsAndQuotes_AllHandled()
    {
        // Arrange
        var input = "  \"\0Hello\aWorld\"  ";

        // Act
        var result = TranscriptSanitizer.SanitizePostProcessed(input);

        // Assert
        Assert.Equal("HelloWorld", result);
    }

    #endregion

    #region IsEmptyResponse Tests

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData(" ")]
    [InlineData("  ")]
    [InlineData("\t")]
    [InlineData("\n")]
    [InlineData("  \t\n  ")]
    public void IsEmptyResponse_EmptyOrWhitespace_ReturnsTrue(string? input)
    {
        // Act
        var result = TranscriptSanitizer.IsEmptyResponse(input);

        // Assert
        Assert.True(result);
    }

    [Theory]
    [InlineData("EMPTY")]
    [InlineData("empty")]
    [InlineData("Empty")]
    [InlineData("  EMPTY  ")]
    [InlineData("\"EMPTY\"")]
    [InlineData("  \"EMPTY\"  ")]
    [InlineData("\"empty\"")]
    public void IsEmptyResponse_EMPTYVariants_ReturnsTrue(string input)
    {
        // Act
        var result = TranscriptSanitizer.IsEmptyResponse(input);

        // Assert
        Assert.True(result);
    }

    [Theory]
    [InlineData("Hello")]
    [InlineData("Hello World")]
    [InlineData("The room is EMPTY")]
    [InlineData("Not empty at all")]
    public void IsEmptyResponse_NonEmptyContent_ReturnsFalse(string input)
    {
        // Act
        var result = TranscriptSanitizer.IsEmptyResponse(input);

        // Assert
        Assert.False(result);
    }

    #endregion

    #region NormalizeBlankLines Tests

    [Fact]
    public void NormalizeBlankLines_MultipleConsecutiveBlankLines_CollapsedToOne()
    {
        // Arrange
        var input = "Paragraph 1\n\n\n\nParagraph 2";

        // Act
        var result = TranscriptSanitizer.NormalizeBlankLines(input);

        // Assert
        Assert.Equal("Paragraph 1\n\nParagraph 2", result);
    }

    [Fact]
    public void NormalizeBlankLines_SingleBlankLine_Preserved()
    {
        // Arrange
        var input = "Paragraph 1\n\nParagraph 2";

        // Act
        var result = TranscriptSanitizer.NormalizeBlankLines(input);

        // Assert
        Assert.Equal("Paragraph 1\n\nParagraph 2", result);
    }

    [Fact]
    public void NormalizeBlankLines_NoBlankLines_NoChange()
    {
        // Arrange
        var input = "Line 1\nLine 2\nLine 3";

        // Act
        var result = TranscriptSanitizer.NormalizeBlankLines(input);

        // Assert
        Assert.Equal("Line 1\nLine 2\nLine 3", result);
    }

    [Fact]
    public void NormalizeBlankLines_NullInput_ReturnsEmptyString()
    {
        // Act
        var result = TranscriptSanitizer.NormalizeBlankLines(null);

        // Assert
        Assert.Equal(string.Empty, result);
    }

    [Fact]
    public void NormalizeBlankLines_WhitespaceOnlyLines_TreatedAsBlank()
    {
        // Arrange
        var input = "Paragraph 1\n   \n\t\n   \nParagraph 2";

        // Act
        var result = TranscriptSanitizer.NormalizeBlankLines(input);

        // Assert
        Assert.Equal("Paragraph 1\n\nParagraph 2", result);
    }

    #endregion

    #region Idempotence Tests

    [Theory]
    [InlineData("Hello World")]
    [InlineData("  Hello World  ")]
    [InlineData("Line 1\r\nLine 2")]
    [InlineData("Hello\0World")]
    [InlineData("  \"Hello World\"  ")]
    [InlineData("EMPTY")]
    public void Sanitize_Idempotent_SamResultOnSecondCall(string input)
    {
        // Arrange
        var firstResult = TranscriptSanitizer.Sanitize(input);

        // Act
        var secondResult = TranscriptSanitizer.Sanitize(firstResult);

        // Assert
        Assert.Equal(firstResult, secondResult);
    }

    [Theory]
    [InlineData("Hello World")]
    [InlineData("  Hello World  ")]
    [InlineData("Line 1\r\nLine 2")]
    [InlineData("  \"Hello World\"  ")]
    public void SanitizePostProcessed_Idempotent_SameResultOnSecondCall(string input)
    {
        // Arrange
        var firstResult = TranscriptSanitizer.SanitizePostProcessed(input);

        // Act
        var secondResult = TranscriptSanitizer.SanitizePostProcessed(firstResult);

        // Assert
        Assert.Equal(firstResult, secondResult);
    }

    #endregion

    #region Unicode and Special Characters Tests

    [Fact]
    public void Sanitize_UnicodeText_Preserved()
    {
        // Arrange - Various Unicode scripts
        var input = "Hello 世界 مرحبا Привет 🌍";

        // Act
        var result = TranscriptSanitizer.Sanitize(input);

        // Assert
        Assert.Equal("Hello 世界 مرحبا Привет 🌍", result);
    }

    [Fact]
    public void Sanitize_Emojis_Preserved()
    {
        // Arrange
        var input = "Hello 👋 World 🌍 Test 🎉";

        // Act
        var result = TranscriptSanitizer.Sanitize(input);

        // Assert
        Assert.Equal("Hello 👋 World 🌍 Test 🎉", result);
    }

    [Fact]
    public void Sanitize_AccentedCharacters_Preserved()
    {
        // Arrange
        var input = "Café résumé naïve coöperate";

        // Act
        var result = TranscriptSanitizer.Sanitize(input);

        // Assert
        Assert.Equal("Café résumé naïve coöperate", result);
    }

    [Fact]
    public void Sanitize_ExtendedLatinCharacters_Preserved()
    {
        // Arrange - Characters above 0x9F (start of printable extended characters)
        var input = "€ £ ¥ © ® ™ ° ± ² ³";

        // Act
        var result = TranscriptSanitizer.Sanitize(input);

        // Assert
        Assert.Equal("€ £ ¥ © ® ™ ° ± ² ³", result);
    }

    #endregion
}
