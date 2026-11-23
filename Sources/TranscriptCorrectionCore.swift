import Foundation

/// Deterministic, on-device "heard -> replacement" corrections for dictated
/// transcripts (issue #125).
///
/// Rules are written one per line:
///
///     cloud code | clod code -> Claude Code
///     next message => nextMessage
///
/// Semantics:
/// - `->` or `=>` (whichever appears first) separates heard forms from the
///   replacement. Multiple heard forms share one replacement with `|`.
/// - Blank lines and lines starting with `#` are ignored. Lines without an
///   arrow, without a heard form containing a letter or digit, or with an
///   empty replacement are ignored and counted as invalid.
/// - Matching is whole-word and case-insensitive. A heard form that starts
///   (ends) with a letter, digit or combining mark only matches when the
///   preceding (following) character is not a letter, digit or combining
///   mark, so "cat" never rewrites "category" or the decomposed "caté".
///   Apostrophes, hyphens and underscores count as boundaries, so possessives
///   such as "cloud code's" are still corrected.
/// - Whitespace inside a heard form matches any run of whitespace.
/// - Text is compared in Unicode NFC, so precomposed and decomposed accents
///   match each other.
/// - The transcript is scanned once, left to right. At each position the
///   longest heard form wins. Replacement text is inserted literally and is
///   never scanned again, so rules cannot cascade into each other.
/// - When the same heard form appears in several rules, the first rule wins.
/// - A replacement containing an uppercase letter is inserted verbatim
///   ("Claude Code", "nextMessage"). An all-lowercase replacement follows the
///   casing of the matched text: ALL CAPS stays all caps and a capitalized
///   match (for example at the start of a sentence) capitalizes the first
///   letter.
struct TranscriptCorrectionRule: Equatable {
    var heardForms: [String]
    var replacement: String
}

struct TranscriptCorrectionParseResult: Equatable {
    var rules: [TranscriptCorrectionRule]
    var invalidLineCount: Int
}

enum TranscriptCorrectionParser {
    static func parse(_ text: String) -> TranscriptCorrectionParseResult {
        var rules: [TranscriptCorrectionRule] = []
        var invalidLineCount = 0

        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }

            guard let arrow = firstArrowRange(in: line) else {
                invalidLineCount += 1
                continue
            }

            let replacement = line[arrow.upperBound...]
                .trimmingCharacters(in: .whitespaces)
            let heardForms = line[..<arrow.lowerBound]
                .split(separator: "|")
                .map { collapseWhitespace(String($0)) }
                .filter { containsWordCharacter($0) }

            guard !replacement.isEmpty, !heardForms.isEmpty else {
                invalidLineCount += 1
                continue
            }
            rules.append(TranscriptCorrectionRule(heardForms: heardForms, replacement: replacement))
        }

        return TranscriptCorrectionParseResult(rules: rules, invalidLineCount: invalidLineCount)
    }

    private static func firstArrowRange(in line: String) -> Range<String.Index>? {
        let candidates = [line.range(of: "->"), line.range(of: "=>")].compactMap { $0 }
        return candidates.min { $0.lowerBound < $1.lowerBound }
    }

    private static func collapseWhitespace(_ text: String) -> String {
        text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    static func containsWordCharacter(_ text: String) -> Bool {
        text.unicodeScalars.contains(where: TranscriptCorrector.isWordScalar)
    }
}

struct TranscriptCorrector {
    private struct Entry {
        var heard: String
        var replacement: String
    }

    private let entries: [Entry]
    private let regex: NSRegularExpression?

    var isEmpty: Bool { entries.isEmpty }

    init(rulesText: String) {
        self.init(rules: TranscriptCorrectionParser.parse(rulesText).rules)
    }

    init(rules: [TranscriptCorrectionRule]) {
        var seen = Set<String>()
        var ordered: [(index: Int, entry: Entry)] = []
        for rule in rules {
            let replacement = rule.replacement.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !replacement.isEmpty else { continue }
            for form in rule.heardForms {
                let heard = form
                    .split(whereSeparator: { $0.isWhitespace })
                    .joined(separator: " ")
                    .precomposedStringWithCanonicalMapping
                guard TranscriptCorrectionParser.containsWordCharacter(heard),
                      seen.insert(heard.lowercased()).inserted else { continue }
                ordered.append((ordered.count, Entry(heard: heard, replacement: replacement)))
            }
        }

        // Longest heard form first so the alternation prefers it at any
        // given position; ties keep rule order.
        ordered.sort {
            let lhs = $0.entry.heard.count
            let rhs = $1.entry.heard.count
            return lhs != rhs ? lhs > rhs : $0.index < $1.index
        }
        entries = ordered.map(\.entry)

        guard !entries.isEmpty else {
            regex = nil
            return
        }
        let pattern = entries.map { "(" + Self.pattern(forHeard: $0.heard) + ")" }
            .joined(separator: "|")
        regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    }

    func apply(_ text: String) -> String {
        guard let regex, !text.isEmpty else { return text }

        let normalized = text.precomposedStringWithCanonicalMapping
        let source = normalized as NSString
        let matches = regex.matches(
            in: normalized,
            options: [],
            range: NSRange(location: 0, length: source.length)
        )
        guard !matches.isEmpty else { return text }

        var output = ""
        var cursor = 0
        for match in matches {
            guard let entryIndex = (0..<entries.count).first(where: {
                match.range(at: $0 + 1).location != NSNotFound
            }) else { continue }
            let range = match.range
            output += source.substring(with: NSRange(location: cursor, length: range.location - cursor))
            output += Self.adaptCase(
                entries[entryIndex].replacement,
                toMatch: source.substring(with: range)
            )
            cursor = range.location + range.length
        }
        output += source.substring(from: cursor)
        return output
    }

    /// Unique replacement terms, in rule order, to offer the cleanup model as
    /// vocabulary so it keeps the corrected spelling.
    static func vocabularyHints(for rules: [TranscriptCorrectionRule]) -> [String] {
        var seen = Set<String>()
        return rules
            .map { $0.replacement.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
    }

    /// Custom vocabulary with correction replacements appended, one per line.
    static func vocabulary(_ customVocabulary: String, addingHintsFrom rulesText: String) -> String {
        let hints = vocabularyHints(for: TranscriptCorrectionParser.parse(rulesText).rules)
        guard !hints.isEmpty else { return customVocabulary }
        let trimmed = customVocabulary.trimmingCharacters(in: .whitespacesAndNewlines)
        return ([trimmed].filter { !$0.isEmpty } + hints).joined(separator: "\n")
    }

    static func isWordScalar(_ scalar: Unicode.Scalar) -> Bool {
        let properties = scalar.properties
        if properties.isAlphabetic { return true }
        switch properties.generalCategory {
        case .decimalNumber, .letterNumber, .otherNumber,
             .nonspacingMark, .spacingMark, .enclosingMark:
            return true
        default:
            return false
        }
    }

    private static let wordClass = "[\\p{L}\\p{N}\\p{M}]"

    private static func pattern(forHeard heard: String) -> String {
        let body = heard
            .split(separator: " ")
            .map { NSRegularExpression.escapedPattern(for: String($0)) }
            .joined(separator: "\\s+")
        let leading = heard.unicodeScalars.first.map(isWordScalar) ?? false
        let trailing = heard.unicodeScalars.last.map(isWordScalar) ?? false
        return (leading ? "(?<!\(wordClass))" : "")
            + body
            + (trailing ? "(?!\(wordClass))" : "")
    }

    static func adaptCase(_ replacement: String, toMatch matched: String) -> String {
        // Replacements with explicit capitals are the user's chosen spelling.
        guard replacement == replacement.lowercased() else { return replacement }

        let letters = matched.unicodeScalars.filter { $0.properties.isAlphabetic }
        guard let firstLetter = letters.first else { return replacement }

        if letters.count > 1, letters.allSatisfy({ $0.properties.isUppercase }) {
            return replacement.uppercased()
        }
        if firstLetter.properties.isUppercase,
           let first = replacement.first, first.isLetter {
            return first.uppercased() + replacement.dropFirst()
        }
        return replacement
    }
}
