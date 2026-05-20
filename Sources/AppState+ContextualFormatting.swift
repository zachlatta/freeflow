import Foundation
import AppKit

// MARK: - Contextual Formatting
// Deterministic (non-LLM) rules that adjust the transcript before pasting,
// based on the text surrounding the cursor. Extracted from AppState to keep
// the main file closer to the upstream structure.

extension AppState {

    // MARK: - List Marker Detection

    /// Characters used as unordered list bullets in plain text and Markdown.
    private static let listBullets: Set<Character> = ["-", "*", "•", "‣", "◦", "▸", "▹"]

    /// Characters that act as closing delimiters. If transcript ends with punctuation
    /// immediately preceding these, the punctuation is stripped to avoid formatting
    /// errors like ".)" or ".]".
    private static let closingDelimiters: Set<Character> = [
        ")", "]", "}",
        "\"", "\u{201D}",  // ASCII and Unicode right double-quote
        "'", "\u{2019}",   // ASCII and Unicode right single-quote / apostrophe
        ">", "»", "\u{203A}"
    ]

    /// Returns true if the trimmed preceding text ends with a list marker pattern.
    ///
    /// Recognized patterns (case-insensitive):
    /// - Unordered: `- `, `* `, `• `, etc.
    /// - Ordered: `1. `, `2) `, `a. `, `A) `, etc.
    /// - Nested: `  - `, `    * ` (indentation + bullet)
    private static func endsWithListMarker(_ trimmed: String) -> Bool {
        guard !trimmed.isEmpty else { return false }

        // The raw precedingText ends with what's right before the cursor.
        // For a list item the pattern is: <bullet><space> or <number><punct><space>
        // Since we receive the trimmed version (no trailing whitespace), the
        // cursor sits right after the trailing space that was stripped. So we
        // check the last non-whitespace character of the *untrimmed* preceding
        // — but here we already have trimmed. The raw preceding ends with
        // "<marker> " so trimmed ends with the marker character itself.

        let last = trimmed.last!

        // Unordered bullet: trimmed ends with - * • etc.
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
        guard !text.isEmpty else { return text }
        var result = text

        // --- Rule 1: Capitalization of the first character ---
        let shouldCapitalize: Bool
        if let preceding = precedingText, !preceding.isEmpty {
            // Check the raw text (before trimming) for trailing newlines.
            // The AX API may return "text\n" or "text\n  " (newline + indentation).
            // We look for the last non-space char to detect newlines even with
            // trailing spaces/tabs from indentation.
            let lastNonSpace = preceding.last(where: { $0 != " " && $0 != "\t" })
            let rawEndsWithNewline = lastNonSpace == "\n" || lastNonSpace == "\r"
            let trimmed = preceding.trimmingCharacters(in: .whitespacesAndNewlines)
            let endsWithTerminalPunct = trimmed.last.map { ".!?:".contains($0) } ?? false
            let endsWithListItem = Self.endsWithListMarker(trimmed)
            // Capitalize when: sentence boundary, start of field, after newline, or list item
            shouldCapitalize = rawEndsWithNewline || endsWithTerminalPunct
                || endsWithListItem
                || cursorPosition == "start" || trimmed.isEmpty
        } else {
            // No preceding context or empty string: field is empty or inaccessible
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

        // --- Rule 2: Remove trailing punctuation for mechanical conflicts ---
        //
        // We rely on the LLM post-processing service (which sees PRECEDING_TEXT and FOLLOWING_TEXT)
        // to make smart grammatical decisions about whether the transcript needs terminal
        // punctuation (. ! ?). We trust its decisions for complete sentences, interjections, etc.
        //
        // However, we apply deterministic overrides for mechanical formatting conflicts:
        //
        //   A) Duplicate/Conflicting punctuation: Transcript ends with punctuation AND
        //      followingText starts with punctuation -> remove transcript's punctuation
        //      so the existing punctuation on screen takes precedence (avoiding ".." or ".?").
        //   B) Inside parentheses/quotes: Transcript ends with punctuation AND the immediate
        //      following non-whitespace character is a closing delimiter (like ")", "]", "}",
        //      or quotes) -> remove transcript's punctuation to avoid formatting errors like ".)".
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
                    // Case A: Transcript ends with punctuation AND following starts with punctuation
                    //         -> avoid duplicate/conflicting punctuation (e.g. "..", ".,", ".?")
                    if allPunctuation.contains(lastChar) && allPunctuation.contains(firstFollowingNonSpace) {
                        result.removeLast()
                    }
                    // Case B: Transcript ends with punctuation AND following starts with a closing delimiter
                    //         -> avoid punctuation inside brackets/quotes (e.g. ".)", ".]", ".\"")
                    else if allPunctuation.contains(lastChar) && Self.closingDelimiters.contains(firstFollowingNonSpace) {
                        result.removeLast()
                    }
                }
            }
        }

        // --- Rule 3: Strip trailing whitespace and zero-width characters ---
        // Always strip ALL trailing whitespace (including Unicode variants like
        // non-breaking space \u{00A0} and zero-width formatting characters) from
        // the formatted result. The downstream applySmartTrailingSpace will re-add
        // a space ONLY when followingText exists and requires word separation.
        while let last = result.last,
              last.isWhitespace || Self.zeroWidthChars.contains(last) {
            result.removeLast()
        }

        return result
    }

    // MARK: - Zero-Width Characters

    /// Unicode characters that are invisible but can break spacing logic if left
    /// at the end of the formatted text. These are stripped alongside whitespace
    /// in Rule 3.
    private static let zeroWidthChars: Set<Character> = [
        "\u{00A0}",  // NBSP (non-breaking space)
        "\u{200B}",  // zero-width space
        "\u{200C}",  // zero-width non-joiner
        "\u{200D}",  // zero-width joiner
        "\u{2060}",  // word joiner
        "\u{FEFF}",  // zero-width no-break space / BOM
    ]
}
