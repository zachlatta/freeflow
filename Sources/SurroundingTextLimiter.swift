import Foundation

/// Bounds the surrounding text (the text before/after the cursor) that is sent to the
/// post-processing model, so the model cannot echo a large block of already-typed text
/// back into the cleaned transcript. It caps sentences, enforces a character budget with
/// tolerance via word-safe truncation, and flattens whitespace.
///
/// LLM-only: the deterministic formatter (`ContextualFormattingService`) still receives the
/// full text with its real line/paragraph breaks — this type never touches that path.
enum SurroundingTextLimiter {

    // MARK: - Tunable constants

    /// Max sentences kept from the text before the cursor.
    static let precedingMaxSentences = 2
    /// Soft character budget for the text before the cursor.
    static let precedingCharBudget = 200
    /// Max sentences kept from the text after the cursor.
    static let followingMaxSentences = 1
    /// Soft character budget for the text after the cursor.
    static let followingCharBudget = 160
    /// Slack above a budget before anything is cut, so a slightly-long sentence is sent whole.
    static let tolerance = 40

    // MARK: - Anchor

    /// Which side of the cursor the text sits on (drives keep-end vs keep-start).
    enum Anchor {
        /// Text before the cursor: keep the last sentences / the end on truncation.
        case preceding
        /// Text after the cursor: keep the first sentences / the start on truncation.
        case following
    }

    // MARK: - Entry points (the only API PostProcessingService calls)

    /// Bounds the text before the cursor for the prompt.
    static func boundedPreceding(_ text: String) -> String {
        boundedSurrounding(text, maxSentences: precedingMaxSentences,
                           charBudget: precedingCharBudget, tolerance: tolerance, anchor: .preceding)
    }

    /// Bounds the text after the cursor for the prompt.
    static func boundedFollowing(_ text: String) -> String {
        boundedSurrounding(text, maxSentences: followingMaxSentences,
                           charBudget: followingCharBudget, tolerance: tolerance, anchor: .following)
    }

    // MARK: - Generic bounding

    /// Bounds `text` to the portion nearest the cursor in three stages, then flattens it.
    static func boundedSurrounding(_ text: String, maxSentences: Int, charBudget: Int,
                                   tolerance: Int, anchor: Anchor) -> String {
        // Single ceiling: anything at or below it is sent whole (this is what tolerance buys).
        let hardMax = charBudget + tolerance
        // Flatten first so sentence joins and word boundaries are plain single spaces.
        let pieces = splitIntoSentences(collapseWhitespace(text))
        guard !pieces.isEmpty else { return "" }
        // Stage 1+2: start at maxSentences and drop one at a time until it fits the ceiling.
        var n = min(maxSentences, pieces.count)
        while n >= 1 {
            // preceding keeps the sentences nearest the cursor (the end); following the start.
            let slice = anchor == .preceding ? pieces.suffix(n) : pieces.prefix(n)
            let candidate = slice.joined(separator: " ")
            if candidate.count <= hardMax { return candidate }
            n -= 1
        }
        // Stage 3: a single sentence is still over the ceiling — word-safe truncate to it.
        // `pieces` is non-empty (guarded above), so this branch always binds.
        guard let single = (anchor == .preceding ? pieces.last : pieces.first) else { return "" }
        return truncateAtWordBoundary(single, limit: hardMax, anchor: anchor)
    }

    // MARK: - Primitives

    /// Splits text into sentences at `.`/`!`/`?`/`…` followed by whitespace or end-of-text.
    /// An internal dot inside a token (e.g. the dot after "U" in "U.S.") stays attached because it is
    /// not followed by whitespace; the TERMINAL dot of an abbreviation followed by a space ("U.S. ",
    /// "etc. ") IS treated as a boundary, so abbreviations in running text can over-split. That is
    /// acceptable: this only bounds the LLM context window (the char budget still applies).
    static func splitIntoSentences(_ text: String) -> [String] {
        // Sentence-ending punctuation.
        let enders: Set<Character> = [".", "!", "?", "…"]
        let chars = Array(text)
        var pieces: [String] = []
        var current = ""
        var i = 0
        while i < chars.count {
            let c = chars[i]
            current.append(c)
            // A boundary is an ender whose next character is whitespace or end-of-text.
            if enders.contains(c) {
                let next: Character? = i + 1 < chars.count ? chars[i + 1] : nil
                if next?.isWhitespace ?? true {
                    let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty { pieces.append(trimmed) }
                    current = ""
                }
            }
            i += 1
        }
        // Trailing fragment with no ender (the in-progress sentence) is still a piece.
        let tail = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !tail.isEmpty { pieces.append(tail) }
        return pieces
    }

    /// Collapses every whitespace run (spaces, tabs, and any line/paragraph/page break) into
    /// a single space, then trims. LLM-only — the formatter keeps the real breaks.
    static func collapseWhitespace(_ text: String) -> String {
        var out = ""
        var lastWasSpace = false
        // Map any whitespace scalar to one space and squeeze repeats.
        for ch in text {
            if ch.isWhitespace {
                if !lastWasSpace { out.append(" ") }
                lastWasSpace = true
            } else {
                out.append(ch)
                lastWasSpace = false
            }
        }
        return out.trimmingCharacters(in: .whitespaces)
    }

    /// Truncates `text` to `limit` characters without splitting a word: preceding keeps the
    /// end, following keeps the start. Falls back to a hard cut when there is no inner space,
    /// so a single over-long word (e.g. a URL) never becomes an empty string.
    static func truncateAtWordBoundary(_ text: String, limit: Int, anchor: Anchor) -> String {
        guard text.count > limit else { return text }
        if anchor == .following {
            // Keep the first `limit` chars, then drop back to the last whole word.
            let slice = String(text.prefix(limit))
            if let sp = slice.lastIndex(of: " ") {
                let cut = String(slice[..<sp])
                if !cut.isEmpty { return cut }   // guard: never collapse to empty
            }
            return slice   // no inner space: hard cut rather than split a word
        } else {
            // Keep the last `limit` chars, then drop the leading partial word.
            let slice = String(text.suffix(limit))
            if let sp = slice.firstIndex(of: " ") {
                let cut = String(slice[slice.index(after: sp)...])
                if !cut.isEmpty { return cut }
            }
            return slice
        }
    }
}
