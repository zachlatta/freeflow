import Foundation
import AppKit

// MARK: - Contextual Formatting
// Deterministic (non-LLM) rules that adjust the transcript before pasting,
// based on the text surrounding the cursor. Extracted from AppState to keep
// the main file closer to the upstream structure.

extension AppState {

    // MARK: - List Marker Detection

    /// Characters used as unordered list bullets in plain text and Markdown.
    private static let listBullets: Set<Character> = ["-", "*", "\u{2022}", "\u{2023}", "\u{25E6}", "\u{25B8}", "\u{25B9}"]

    /// Returns true if the trimmed preceding text ends with a list marker pattern.
    ///
    /// Recognized patterns (case-insensitive):
    /// - Unordered: `- `, `* `, `\u{2022} `, etc.
    /// - Ordered: `1. `, `2) `, `a. `, `A) `, etc.
    /// - Nested: `  - `, `    * ` (indentation + bullet)
    private static func endsWithListMarker(_ trimmed: String) -> Bool {
        guard !trimmed.isEmpty else { return false }

        // The raw precedingText ends with what's right before the cursor.
        // For a list item the pattern is: <bullet><space> or <number><punct><space>
        // Since we receive the trimmed version (no trailing whitespace), the
        // cursor sits right after the trailing space that was stripped. So we
        // check the last non-whitespace character of the *untrimmed* preceding
        // \u2014 but here we already have trimmed. The raw preceding ends with
        // "<marker> " so trimmed ends with the marker character itself.

        let last = trimmed.last!

        // Unordered bullet: trimmed ends with - * \u{2022} etc.
        if listBullets.contains(last) {
            // Make sure it's actually a bullet (line-start or after whitespace),
            // not a hyphenated word like "well-"
            if trimmed.count == 1 { return true }
            let lastIdx = trimmed.index(before: trimmed.endIndex)
            let beforeLast = trimmed[trimmed.index(before: lastIdx)]
            return beforeLast.isWhitespace || beforeLast.isNewline
        }

        // Ordered list: trimmed ends with "1." or "1)" or "a." or "a)" etc.
        if last == "." || last == ")" {
            let withoutLast = trimmed.dropLast()
            guard let penultimate = withoutLast.last else { return false }
            // Must be a digit or a single letter (a-z / A-Z)
            if penultimate.isNumber { return true }
            if penultimate.isLetter {
                // Single letter followed by . or ) at line start or after whitespace
                if withoutLast.count == 1 { return true }
                let penIdx = withoutLast.index(before: withoutLast.endIndex)
                let beforePenultimate = withoutLast[withoutLast.index(before: penIdx)]
                return beforePenultimate.isWhitespace || beforePenultimate.isNewline
            }
        }

        return false
    }

    // MARK: - Formatting Entry Point

    /// Applies deterministic formatting rules to the transcript using surrounding text context.
    ///
    /// Rules applied (in order):
    /// 1. **Capitalization**: uppercase at sentence start, empty field, after newline,
    ///    or after a list marker (`- `, `1. `, `* `, etc.); lowercase mid-sentence.
    /// 2. **Terminal punctuation removal**: strips `.!?` when followingText continues
    ///    the sentence, or removes duplicate/conflicting punctuation.
    /// 3. **Trailing whitespace cleanup**: strips all trailing whitespace characters
    ///    (including Unicode variants like non-breaking spaces) so that
    ///    `applySmartTrailingSpace` can make the correct spacing decision downstream.
    func applyContextualFormatting(
        _ text: String,
        precedingText: String?,
        followingText: String?,
        cursorPosition: String?
    ) -> String {
        // Strip any leading/trailing whitespace the LLM may have added before
        // applying any formatting rules. This prevents phantom spaces from
        // leaking into the pasted output regardless of their source.
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return text }
        var result = trimmedText

        // --- Rule 1: Capitalization of the first character ---
        //
        // Capitalize when: after terminal punctuation, after newline (new paragraph),
        // after list marker, at start of field, or when field is empty.
        // Otherwise, force lowercase (mid-sentence continuation).
        //
        // Newline detection is robust: we check the last NON-SPACE character of
        // precedingText, not just preceding.last, because some accessibility APIs
        // return trailing spaces after the \n (e.g. "Previous text.\n  ").
        let shouldCapitalize: Bool
        if let preceding = precedingText {
            let rawEndsWithNewline = preceding.last == "\n" || preceding.last == "\r"
            // Also detect newline when spaces follow it (e.g. "text.\n  ")
            let lastNonSpace = preceding.reversed().first(where: { !($0 == " " || $0 == "\t") })
            let lastNonSpaceIsNewline = lastNonSpace.map { $0.isNewline } ?? false

            let trimmed = preceding.trimmingCharacters(in: .whitespacesAndNewlines)
            let endsWithTerminalPunct = trimmed.last.map { ".!?:".contains($0) } ?? false
            let endsWithListItem = Self.endsWithListMarker(trimmed)
            // Capitalize when: sentence boundary, start of field, after newline, or list item
            shouldCapitalize = rawEndsWithNewline || lastNonSpaceIsNewline
                || endsWithTerminalPunct
                || endsWithListItem
                || cursorPosition == "start" || trimmed.isEmpty
        } else {
            // No preceding context: field is empty or inaccessible
            shouldCapitalize = true
        }

        if let firstScalar = result.unicodeScalars.first {
            let idx = result.startIndex
            if shouldCapitalize && firstScalar.properties.isLowercase {
                result.replaceSubrange(idx...idx, with: result[idx].uppercased())
            } else if !shouldCapitalize && firstScalar.properties.isUppercase {
                result.replaceSubrange(idx...idx, with: result[idx].lowercased())
            }
        }

        // --- Rule 2: Remove terminal punctuation when it would conflict with followingText ---
        //
        // The LLM does not know what text follows the cursor, so it often adds
        // terminal punctuation (. ! ?) assuming the transcript ends the sentence.
        // When inserting mid-text, this creates duplicates or conflicts with the
        // existing punctuation flow. We remove the transcript's trailing punct
        // in any of these scenarios:
        //
        //   A) Transcript ends with .!? and followingText continues with a
        //      letter/digit \u2192 we are mid-sentence, punct is unwanted.
        //   B) Transcript ends with ANY punctuation and followingText starts
        //      with the SAME punctuation \u2192 duplicate.
        //   C) Transcript ends with ANY punctuation and followingText starts
        //      with DIFFERENT punctuation \u2192 conflicting; the existing text's
        //      punctuation takes precedence over the LLM-generated one.
        //
        // We examine the first *non-whitespace* character of followingText to
        // handle cases where the Accessibility API returns " ." (space before
        // punctuation) depending on cursor position.

        let allPunctuation: Set<Character> = [".", "!", "?", ",", ";", ":"]

        if let following = followingText, !following.isEmpty {
            let followingAfterSpaces = following.drop(while: { $0 == " " || $0 == "\t" })
            let followingStartsWithNewline = followingAfterSpaces.first == "\n"
                || followingAfterSpaces.first == "\r"

            if !followingStartsWithNewline,
               let firstFollowingNonSpace = following.first(where: { !$0.isWhitespace }),
               let lastChar = result.last {

                // Abbreviation guard: don't remove the period from short words like Dr., Sr., etc.
                let lastWord = String(result.split(separator: " ").last ?? Substring(result))
                let isAbbreviation = lastWord.hasSuffix(".") && lastWord.count <= 4

                if !isAbbreviation {
                    // Case A: transcript ends with .!? and following starts with letter/digit
                    //         \u2192 mid-sentence insertion, remove LLM's terminal punct
                    if allPunctuation.contains(lastChar)
                        && (firstFollowingNonSpace.isLetter || firstFollowingNonSpace.isNumber) {
                        // Only remove terminal punct (.!?), not commas/semicolons which are structural
                        if ".!?".contains(lastChar) {
                            result.removeLast()
                        }
                    }
                    // Case B+C unified: transcript ends with punct AND following starts with punct
                    //                   \u2192 the existing text's punctuation takes precedence
                    else if allPunctuation.contains(lastChar)
                                && allPunctuation.contains(firstFollowingNonSpace) {
                        result.removeLast()
                    }
                }
            }
        }

        // --- Rule 3: Strip trailing whitespace ---
        // Always strip ALL trailing whitespace (including Unicode variants like
        // non-breaking space \u{00A0} and zero-width spaces) from the formatted result.
        // The downstream applySmartTrailingSpace will re-add a space ONLY when
        // followingText exists and requires word separation.
        while let last = result.last, last.isWhitespace || last == "\u{00A0}" {
            result.removeLast()
        }

        return result
    }
}
