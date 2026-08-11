import Foundation
import OSLog

/// Logger for this formatter. Records only metadata (character counts, rule names) — never the user's actual text.
private let fmtLog = Logger(subsystem: "com.zachlatta.freeflow", category: "ContextFormatting")

// MARK: - ContextualFormattingService

/// Applies deterministic post-LLM formatting using the surrounding cursor context.
/// The algorithm is split into four independent phases:
///   1. Normalization (trim spaces, standardize ellipsis)
///   2. Punctuation cleanup (remove conflicting trailing punctuation)
///   3. Capitalization resolution (upper/lower based on preceding context)
///   4. Spacing (leading & trailing)
public enum ContextualFormattingService {

    /// Result of deterministic contextual formatting: the text to insert plus a debug rule trace.
    public struct ContextFormatResult {
        /// The fully formatted text ready to be inserted at the cursor.
        public let formattedText: String
        /// A short human-readable summary of which formatting tweaks were applied
        /// (e.g. "sp:L | +repl" = added a leading space, replaced the selection). Debugging/display only.
        public let ruleApplied: String
    }

    // MARK: - Public API

    /// Applies deterministic post-LLM formatting to `insertedText` using the surrounding cursor context.
    /// - Parameters:
    ///   - insertedText: The cleaned transcript to format and insert.
    ///   - precedingText: Text immediately before the cursor (nil means no Accessibility context — casing is left untouched).
    ///   - followingText: Text immediately after the cursor (nil means none available).
    ///   - selectedText: Text being replaced, if any; a non-empty value marks this as a replacement.
    ///   - cursorPosition: Semantic caret position raw value supplied by the caller (e.g. "start"/"middle"/"end"/"unknown"); nil defaults to "unknown".
    ///   - vocabulary: Custom-vocabulary string used to restore the user's canonical spelling/casing.
    /// - Returns: A `ContextFormatResult` with the formatted text and a debug rule trace.
    public static func format(
        _ insertedText: String,
        precedingText: String?,
        followingText: String?,
        selectedText: String? = nil,
        cursorPosition: String? = nil,
        vocabulary: String = ""
    ) -> ContextFormatResult {
        // Normalize line/paragraph/page breaks to "\n" so every break is recognized below
        // (AX reads can deliver \r, \r\n, \u{2028}, \u{2029}, \u{0085}, \u{000C}).
        let precedingText = precedingText.map(normalizeLineBreaks)
        let followingText = followingText.map(normalizeLineBreaks)

        // Log inputs (character counts only — never log raw transcript text).
        fmtLog.info("format: prec=\(precedingText?.count ?? -1)ch foll=\(followingText?.count ?? -1)ch cursor=\(cursorPosition ?? "nil", privacy: .public) sel=\(selectedText?.count ?? 0)ch input=\(insertedText.count)ch")

        // Phase 1: Normalization — trim whitespace, standardize ellipsis.
        let trimmed = normalize(insertedText)

        guard !trimmed.isEmpty else {
            fmtLog.info("format: empty string — skipped")
            return ContextFormatResult(formattedText: "", ruleApplied: "empty-input")
        }

        let prec          = precedingText ?? ""
        let fol           = followingText ?? ""
        let sel           = selectedText ?? ""
        let isReplacement = !sel.isEmpty
        var ruleParts     = [String]()

        // Phase 2: Punctuation — remove trailing punctuation that conflicts with following text.
        let punctuated = resolvePunctuation(text: trimmed, following: fol)
        if punctuated != trimmed {
            let removed = trimmed.last.map(String.init) ?? "?"
            ruleParts.append("punct:\(removed)→∅")
            // Metadata only — never log the raw transcript or surrounding text (file policy).
            fmtLog.debug("format: removed 1 trailing punctuation char before following text")
        } else {
            ruleParts.append("no-punct")
        }

        // Parse the custom vocabulary once; reused by capitalization and the casing pass below.
        let vocab = parseVocabulary(vocabulary)

        // Phase 3: Capitalization — decide upper/lower for the first letter.
        let capitalized = resolveCapitalization(
            text: punctuated,
            preceding: precedingText,
            vocabulary: vocab
        )
        // Detect what capitalization phase decided by comparing first letters.
        if let origFirst = punctuated.first(where: { $0.isLetter }),
           let capFirst  = capitalized.first(where: { $0.isLetter }) {
            if capFirst.isUppercase && origFirst.isLowercase {
                ruleParts.append("cap:↑")
                fmtLog.debug("format: capitalized first letter")
            } else if capFirst.isLowercase && origFirst.isUppercase {
                ruleParts.append("cap:↓")
                fmtLog.debug("format: lowercased first letter")
            } else {
                ruleParts.append("cap:–")
            }
        } else {
            // preceding was nil (no Accessibility context, e.g. Electron apps) — keep LLM casing.
            ruleParts.append(precedingText == nil ? "cap:blind" : "cap:–")
        }

        // Phase 3.5: Custom-vocabulary casing — restore the user's spelling for ANY matching
        // word (e.g. "api"→"API", "github"→"GitHub"), not just the first one.
        let vocabCased = applyVocabularyCasing(capitalized, vocabulary: vocab)
        if vocabCased != capitalized { ruleParts.append("+vocab") }

        // Phase 4: Spacing — compute leading and trailing spaces.
        var spaced = resolveSpacing(
            text: vocabCased,
            preceding: prec,
            following: fol,
            selected: sel,
            isReplacement: isReplacement
        )
        // Blind apps (no readable context on either side): keep upstream's trailing space after a
        // sentence-ending mark, so consecutive dictations don't jam together ("one.Two").
        if precedingText == nil, followingText == nil,
           let last = spaced.last, ".!?…".contains(last) {
            spaced += " "
        }
        let leadAdded  = spaced.hasPrefix(" ") && !vocabCased.hasPrefix(" ")
        let trailAdded = spaced.hasSuffix(" ")  && !vocabCased.hasSuffix(" ")
        switch (leadAdded, trailAdded) {
        case (true,  true):  ruleParts.append("sp:LT")
        case (true,  false): ruleParts.append("sp:L")
        case (false, true):  ruleParts.append("sp:T")
        case (false, false): ruleParts.append("sp:0")
        }
        if isReplacement { ruleParts.append("+repl") }

        let ruleApplied = ruleParts.joined(separator: " | ")
        fmtLog.info("format: done — rule='\(ruleApplied, privacy: .public)' output=\(spaced.count)ch")
        return ContextFormatResult(formattedText: spaced, ruleApplied: ruleApplied)
    }

    // MARK: - Phase 1: Normalization

    /// Canonicalizes every line/paragraph/page break to "\n" so the capitalization phase
    /// recognizes them all. AX reads can deliver CRLF, CR, line/paragraph separators, NEL,
    /// or form feed; without this only "\n" would count as a line start.
    static func normalizeLineBreaks(_ text: String) -> String {
        // CRLF first so it collapses to a single "\n"; then the single-codepoint breaks.
        return text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\u{2028}", with: "\n")  // line separator
            .replacingOccurrences(of: "\u{2029}", with: "\n")  // paragraph separator
            .replacingOccurrences(of: "\u{0085}", with: "\n")  // next line (NEL)
            .replacingOccurrences(of: "\u{000C}", with: "\n")  // form feed (page break)
    }

    /// Phase 1: trims surrounding whitespace and collapses non-standard dot runs to a single "." (keeping only exact "...").
    private static func normalize(_ text: String) -> String {
        var normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Standardize ellipsis: only exactly "..." is kept. Other dot runs → ".".
        // Process longer runs first to avoid partial matches.
        normalized = normalized.replacingOccurrences(
            of: "(?<!\\.)\\.{4,}(?!\\.)", with: ".", options: .regularExpression
        )
        normalized = normalized.replacingOccurrences(
            of: "(?<!\\.)\\.{2}(?!\\.)", with: ".", options: .regularExpression
        )

        return normalized
    }

    // MARK: - Phase 2: Punctuation Cleanup

    /// Phase 2: strips trailing punctuation on the inserted text that would collide with the following
    /// text (returns unchanged when the following text starts on a new line or is empty).
    private static func resolvePunctuation(text: String, following: String) -> String {
        var result = text

        // Find the first non-whitespace character in following text.
        let firstNonSpace = following.first(where: { !$0.isWhitespace })

        // Check whether the following text starts with a newline (skip spaces/tabs only).
        let followingAfterSpaces = following.drop(while: { $0 == " " || $0 == "\t" })
        let followingStartsWithNewline = followingAfterSpaces.first == "\n"
            || followingAfterSpaces.first == "\r"

        guard let f = firstNonSpace, !followingStartsWithNewline else {
            return result
        }

        // Rule P1: A trailing ellipsis ("…" or "...") is an unwanted LLM artifact when the
        // following text continues with a word/number (mid-sentence) OR begins with its own
        // sentence punctuation (the following mark is the real terminator) — drop the ellipsis.
        // So "wait…" before "." / ";" / "!" / "?" / ":" / "," keeps only the following mark.
        // (Ellipsis before a line break or end-of-text is intentional and is preserved above.)
        if f.isLetter || f.isNumber || ".,;:!?".contains(f) {
            if result.hasSuffix("…") { result.removeLast() }
            else if result.hasSuffix("...") { result.removeLast(3) }
        }

        // Rule P2: Collapse a duplicate trailing mark when the following text starts with the
        // same one (e.g. "!!" or ",,") — keep the mark already in the document, drop ours.
        if let last = result.last,
           ".?!,".contains(last),
           last == f {
            result.removeLast()
        }
        
        // Rule P3: Punctuation Collision (e.g. ".)", ".,", ".:", ".?", ".!")
        // If the LLM generates a period but the following character is a closing/terminal
        // punctuation, remove the period (that following mark is the real terminator).
        if let last = result.last, last == ".", "),:;]?!".contains(f) {
            // Only remove if it's not an abbreviation like "etc."
            if !isLikelyAbbreviation(result) {
                result.removeLast()
            }
        }

        // Rule P4: Mid-sentence continuation. Drop a trailing period when the following
        // text continues in lowercase (e.g. "Normal." inserted before " of text.").
        if let last = result.last, last == ".", f.isLetter, f.isLowercase, !isLikelyAbbreviation(result) {
            result.removeLast()
        }

        // Rule P5: Insertion right before an existing comma. The document already supplies the
        // separator, so any terminal mark the model appended is redundant and must go — keep
        // the document's comma. Covers "," ";" ":" "!" "?" "." and ellipsis. Self-contained
        // (P2/P3 above may strip "," or "." first; this then no-ops). Abbreviation periods
        // (e.g. "etc.") are preserved, matching P3/P4.
        if f == "," {
            if result.hasSuffix("…") {
                result.removeLast()
            } else if result.hasSuffix("...") {
                result.removeLast(3)
            } else if let last = result.last, ",.;:!?".contains(last),
                      last != "." || !isLikelyAbbreviation(result) {
                result.removeLast()
            }
        }

        return result
    }

    /// Latin + common accented vowels. Hoisted to a type-level constant so the 28-element
    /// `Set<Character>` is allocated once rather than rebuilt on every isLikelyAbbreviation() call.
    private static let abbreviationVowels: Set<Character> = ["a","e","i","o","u","y","à","á","â","ã","ä","è","é","ê","ë","ì","í","î","ï","ò","ó","ô","õ","ö","ù","ú","û","ü"]

    /// A terminal period is likely an abbreviation when the last token is short (≤4 letters)
    /// AND carries an abbreviation marker: an internal dot ("i.e."), all-caps ("API"), or all
    /// consonants ("Dr", "Sr", "vs"). Plain short words that contain a vowel ("sea", "ok",
    /// "ten") are NOT abbreviations, so their undue terminal period is cleaned by P3/P4.
    /// Language-agnostic: keys on letter shape, not an enumerated list. Abbreviations or terms
    /// the user adds to the custom vocabulary are preserved — their canonical spelling/casing is
    /// restored in Phase 3.5 — so user-specific terms are kept regardless of this heuristic.
    private static func isLikelyAbbreviation(_ text: String) -> Bool {
        guard text.hasSuffix(".") else { return false }
        let word = String(text.dropLast().reversed().prefix(while: { !$0.isWhitespace }).reversed())
        // A token containing a digit ("17h59", "v2", "5km") is a time/version/measure — its
        // trailing period ends the sentence; it is never an abbreviation like "Dr." or "etc.".
        guard !word.contains(where: { $0.isNumber }) else { return false }
        let letters = word.filter { $0.isLetter }
        guard !letters.isEmpty, letters.count <= 4 else { return false }
        let allUppercase = letters.allSatisfy { $0.isUppercase }
        let allConsonants = letters.lowercased().allSatisfy { !abbreviationVowels.contains($0) }
        let hasInternalDot = word.contains(".")
        return allUppercase || allConsonants || hasInternalDot
    }

    /// Parses the custom-vocabulary string (comma/semicolon/newline-separated terms, possibly
    /// multi-word) into a lookup of lowercased word → its canonical casing. Used to restore the
    /// user's intended casing on the first dictated word (e.g. "silva" → "Silva").
    private static func parseVocabulary(_ raw: String) -> [String: String] {
        guard !raw.isEmpty else { return [:] }
        var map: [String: String] = [:]
        for entry in raw.split(whereSeparator: { $0 == "," || $0 == ";" || $0 == "\n" || $0 == "\r" }) {
            for word in entry.split(whereSeparator: { $0 == " " || $0 == "\t" }) {
                let canonical = String(word)
                let key = canonical.lowercased()
                if map[key] == nil { map[key] = canonical }
            }
        }
        return map
    }

    /// Restores the user's canonical casing for ANY vocabulary term appearing in the text,
    /// not just the first word. Matches whole alphanumeric words case-insensitively, so a term
    /// like "API" fixes "api"/"Api" → "API" wherever it occurs without touching substrings
    /// inside larger words ("rapid" stays "rapid"). Non-letter/number chars are word boundaries.
    private static func applyVocabularyCasing(_ text: String, vocabulary: [String: String]) -> String {
        guard !vocabulary.isEmpty else { return text }
        var result = ""
        var word = ""
        // Emit the accumulated word, swapped for its canonical casing when it is a vocab term.
        func flushWord() {
            guard !word.isEmpty else { return }
            result += vocabulary[word.lowercased()] ?? word
            word = ""
        }
        for ch in text {
            if ch.isLetter || ch.isNumber {
                word.append(ch)
            } else {
                flushWord()
                result.append(ch)
            }
        }
        flushWord()
        return result
    }

    // MARK: - Phase 3: Capitalization

    /// Phase 3: decides the first letter's case from the preceding context (sentence boundaries,
    /// bullets, line/paragraph starts) — custom-vocabulary casing on the first word wins.
    private static func resolveCapitalization(
        text: String,
        preceding: String?,
        vocabulary: [String: String]
    ) -> String {

        // Custom-vocabulary casing wins for the first word: a term the user defined (e.g. a
        // name "Silva") keeps its exact casing even when the rule would upper/lowercase it.
        if !vocabulary.isEmpty, let firstAlphaIdx = text.firstIndex(where: { $0.isLetter }) {
            let firstWordEnd = text[firstAlphaIdx...].firstIndex(where: { $0.isWhitespace }) ?? text.endIndex
            let firstWord = String(text[firstAlphaIdx..<firstWordEnd])
            if let canonical = vocabulary[firstWord.lowercased()] {
                var mutable = text
                mutable.replaceSubrange(firstAlphaIdx..<firstWordEnd, with: canonical)
                return mutable
            }
        }

        guard let preceding = preceding else {
            // No Accessibility (AX) context available, so do not force case.
            return text
        }

        // Find the last non-whitespace character in preceding text.
        // IMPORTANT: We use `last(where:)` instead of `drop { }.last` because
        // `drop` removes from the BEGINNING, which gives wrong results when
        // the string doesn't start with whitespace but ends with it.
        let precLastNonSpace = preceding.last(where: { !$0.isWhitespace })

        // Trim only spaces and tabs to preserve newlines for the newline check.
        let precTrimmedSpacesAndTabs = preceding.trimmingCharacters(
            in: CharacterSet(charactersIn: " \t")
        )


        // Priority-ordered rules. First match wins.
        let mustUppercase: Bool = {
            if precTrimmedSpacesAndTabs.isEmpty { return true } // Force uppercase if field is completely empty
            if precTrimmedSpacesAndTabs.hasSuffix("\n") { return true }
            if let last = precLastNonSpace, ".?!…".contains(last) {
                // A period that ends an abbreviation ("Dr.") is NOT a sentence boundary, so it
                // must not force uppercase on the next word. ? ! … are always boundaries.
                if last != "." || !isLikelyAbbreviation(precTrimmedSpacesAndTabs) { return true }
            }

            // Standalone bullet (•, ◦, ‣, ▪) right before the cursor → list item start.
            // Bullets are unambiguous markers even when an app serializes list items inline
            // (no newline before the bullet), unlike "-"/"*" which can occur mid-text.
            if let last = precLastNonSpace, "•◦‣▪".contains(last) { return true }

            // Opening "(" or '"' that starts a sentence → capitalize the first word.
            // "Starts a sentence" = at a line/paragraph start, or right after .?!…
            if let opener = precTrimmedSpacesAndTabs.last, opener == "(" || opener == "\"" {
                let beforeOpener = precTrimmedSpacesAndTabs.dropLast()
                    .trimmingCharacters(in: CharacterSet(charactersIn: " \t"))
                if beforeOpener.isEmpty || beforeOpener.hasSuffix("\n") { return true }
                if let b = beforeOpener.last, ".?!…".contains(b) { return true }
            }

            // Rule C4: After bullet/numbered list marker ("- ", "* ", "1. ", "a) ")
            // Limit alphanumeric enumerators to 1-3 chars to avoid false positives
            // like "value)" being treated as a list marker.
            if preceding.range(
                of: #"(?:^|\n)\s*(?:[-*•–]|[a-zA-Z0-9]{1,3}[\.)])\s*$"#,
                options: .regularExpression
            ) != nil { return true }

            return false
        }()

        // Resolve: if we must uppercase, do it. Otherwise, force lowercase.
        // Default-lowercase unless a sentence boundary was detected.
        let decision = mustUppercase
        guard let firstAlphaIdx = text.firstIndex(where: { $0.isLetter }) else { return text }

        // EXCEPTION: If the system decided to lowercase, but the inserted text
        // starts with an abbreviation (like "Dr."), preserve its original casing.
        if decision == false {
            let firstWordEnd = text[firstAlphaIdx...].firstIndex(where: { $0.isWhitespace }) ?? text.endIndex
            let firstWord = String(text[firstAlphaIdx..<firstWordEnd])
            if isLikelyAbbreviation(firstWord) {
                return text
            }
            // Preserve all-caps acronyms (API, NASA, HTTP): a run of 2+ letters that is entirely
            // uppercase is an acronym, not a sentence start the LLM over-capitalized.
            let firstWordLetters = firstWord.filter { $0.isLetter }
            if firstWordLetters.count >= 2, firstWordLetters.allSatisfy({ $0.isUppercase }) {
                return text
            }
            // Preserve the English pronoun "I" and its contractions (I'm, I'll, I've, I'd):
            // a standalone uppercase "I" followed by whitespace, an apostrophe, or end of text.
            if text[firstAlphaIdx] == "I" {
                let after = text.index(after: firstAlphaIdx)
                if after == text.endIndex || text[after].isWhitespace
                    || text[after] == "'" || text[after] == "\u{2019}" {
                    return text
                }
            }
        }

        let firstLetter = text[firstAlphaIdx]
        let replaced = decision ? firstLetter.uppercased() : firstLetter.lowercased()
        var mutable = text
        mutable.replaceSubrange(firstAlphaIdx...firstAlphaIdx, with: replaced)
        return mutable
    }

    // MARK: - Phase 4: Spacing

    // Quote characters split by typographic role. Curly and guillemet quotes are unambiguous by
    // Unicode; straight quotes (" ' `) are ambiguous and decided by the neighbouring character.
    /// Unambiguous OPENING quotes (glue to the next word): guillemets and left curly quotes.
    private static let openingQuotes: Set<Character> = ["\u{00AB}", "\u{2039}", "\u{201C}", "\u{2018}"]  // «  ‹  “  ‘
    /// Unambiguous CLOSING quotes (take a space before the next word): right guillemets/curly quotes.
    private static let closingQuotes: Set<Character> = ["\u{00BB}", "\u{203A}", "\u{201D}", "\u{2019}"]  // »  ›  ”  ’
    /// Ambiguous straight quotes — opening vs closing is decided by the neighbouring character.
    private static let straightQuotes: Set<Character> = ["\"", "'", "`"]
    /// Every character the spacing rules treat as a quote.
    private static let allQuotes: Set<Character> = openingQuotes.union(closingQuotes).union(straightQuotes)

    /// True when a quote immediately before the cursor is a CLOSING quote (which should get a
    /// leading space — `"hello" today`) rather than an OPENING quote (glued — `"hello`). Curly and
    /// guillemet quotes are unambiguous; a straight quote (`"` `'` `` ` ``) is closing when the
    /// character right before it is a letter, number, or closing bracket/punctuation (covers
    /// `"hello"|` and `users'|`), and opening otherwise (a true opening like `… "|`).
    private static func precedingQuoteIsClosing(_ quote: Character, in preceding: String, closing: Set<Character>) -> Bool {
        if closingQuotes.contains(quote) { return true }
        if openingQuotes.contains(quote) { return false }
        // Ambiguous straight quote: look at the character immediately before it (no whitespace skip past the quote).
        guard let n = preceding.reversed().drop(while: { $0.isWhitespace }).dropFirst().first else { return false }
        return n.isLetter || n.isNumber || closing.contains(n)
    }

    /// Mirror of `precedingQuoteIsClosing` for a quote at the START of the following text: true when
    /// it is an OPENING quote (a space belongs before it — `word "hello"`) rather than a closing
    /// quote (glued). A straight quote looks at the character immediately after it.
    private static func followingQuoteIsOpening(_ quote: Character, in following: String, opening: Set<Character>) -> Bool {
        if openingQuotes.contains(quote) { return true }
        if closingQuotes.contains(quote) { return false }
        guard let n = following.drop(while: { $0.isWhitespace }).dropFirst().first else { return true }
        return n.isLetter || n.isNumber || opening.contains(n)
    }

    /// Phase 4: computes and applies the leading/trailing space around the inserted text, and restores
    /// spaces eaten when replacing a selection (Phase 4C).
    private static func resolveSpacing(
        text: String,
        preceding: String,
        following: String,
        selected: String,
        isReplacement: Bool
    ) -> String {

        let openingPunctuation: Set<Character> = ["(", "[", "{", "\"", "'", "`", "<", "\u{00AB}", "\u{201C}", "\u{2018}"]
        let closingPunctuation: Set<Character> = [")", "]", "}", ",", ".", "!", "?", ";", ":", "…", ">", "\u{00BB}"]

        // ── Phase 4A: Leading space ──

        let precLastNonSpace = preceding.last(where: { !$0.isWhitespace })
        let insertedFirstNonSpace = text.first(where: { !$0.isWhitespace })

        var leadingSpace = ""

        if let p = precLastNonSpace {
            // Default: add space after words, numbers, and closing punctuation.
            if p.isLetter || p.isNumber || closingPunctuation.contains(p) {
                leadingSpace = " "
            }

            // No space after opening punctuation.
            if openingPunctuation.contains(p) {
                leadingSpace = ""
            }

            // Quote-aware override: a closing quote gets a leading space ("hello" today),
            // an opening quote is glued ("hello). Covers EN straight/curly and PT « » / curly.
            if allQuotes.contains(p) {
                leadingSpace = precedingQuoteIsClosing(p, in: preceding, closing: closingPunctuation) ? " " : ""
            }
        }

        // No space before closing punctuation (text starts with it).
        if let i = insertedFirstNonSpace, closingPunctuation.contains(i) {
            leadingSpace = ""
        }

        // If preceding already ends with whitespace, no extra space needed.
        if preceding.last?.isWhitespace == true {
            leadingSpace = ""
        }

        // ── Phase 4B: Trailing space ──

        var trailingSpace = ""
        let followingFirstNonSpace = following.first(where: { !$0.isWhitespace })

        if let f = followingFirstNonSpace {
            // Add space before words, numbers, and opening punctuation.
            if f.isLetter || f.isNumber || openingPunctuation.contains(f) {
                trailingSpace = " "
            }

            // No space before closing punctuation.
            if closingPunctuation.contains(f) {
                trailingSpace = ""
            }

            // Quote-aware override: a space belongs before an opening quote (word "hello"),
            // none before a closing quote.
            if allQuotes.contains(f) {
                trailingSpace = followingQuoteIsOpening(f, in: following, opening: openingPunctuation) ? " " : ""
            }
        }

        // If following already starts with whitespace, no extra space needed.
        if following.first?.isWhitespace == true {
            trailingSpace = ""
        }

        // ── Phase 4C: Selected text space restoration ──
        // When the system replaces selected text, spaces that were part of the
        // selection get eaten. Restore them if the selected text had them.
        if isReplacement {
            if selected.hasSuffix(" ") && following.first?.isWhitespace != true {
                // Do NOT restore space if the following text starts with closing punctuation
                // (prevents adding space before a comma/period).
                if let f = followingFirstNonSpace, closingPunctuation.contains(f) {
                    trailingSpace = ""
                } else {
                    trailingSpace = " "
                }
            }
            if selected.hasPrefix(" ") && preceding.last?.isWhitespace != true {
                leadingSpace = " "
            }
        }

        // ── Phase 4D: Assemble and clean up ──

        var result = leadingSpace + text + trailingSpace

        // Prevent double-space at boundary with preceding.
        if preceding.hasSuffix(" ") && result.hasPrefix(" ") {
            result.removeFirst()
        }

        // Prevent double-space at boundary with following.
        if following.hasPrefix(" ") && result.hasSuffix(" ") {
            result.removeLast()
        }

        // Collapse any run of spaces WITHIN the inserted text to one (e.g. leadingSpace + a text that
        // itself begins with a space). This normalizes only the inserted string — it cannot touch the
        // field's own preceding/following, so a double space against existing field whitespace survives.
        result = result.replacingOccurrences(of: " {2,}", with: " ", options: .regularExpression)

        return result
    }
}
