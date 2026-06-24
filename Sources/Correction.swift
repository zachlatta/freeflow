import Foundation

/// A single deterministic find-and-replace rule for the dictation Dictionary.
/// `heard` is the phrase the transcription tends to produce; `replacement` is
/// what the speaker actually meant. Applied as the last step before paste,
/// after the LLM cleanup pass, so a correction can never be undone by
/// post-processing.
struct Correction: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var heard: String
    var replacement: String
    var wholeWord: Bool = true
    var caseSensitive: Bool = false
    var enabled: Bool = true
}

/// Pure, isolation-free engine that applies a list of corrections to a string.
/// Kept free of AppState so it can run on the background transcription task.
enum DictionaryEngine {
    static func apply(_ text: String, corrections: [Correction]) -> String {
        guard !text.isEmpty, !corrections.isEmpty else { return text }

        var result = text
        for correction in corrections {
            let heard = correction.heard.trimmingCharacters(in: .whitespacesAndNewlines)
            guard correction.enabled, !heard.isEmpty else { continue }

            var options: NSRegularExpression.Options = []
            if !correction.caseSensitive { options.insert(.caseInsensitive) }

            var pattern = NSRegularExpression.escapedPattern(for: heard)
            if correction.wholeWord {
                // Unicode-aware word boundary: only match when the phrase is not
                // flanked by a letter or digit. Keeps "cat" from rewriting the
                // "cat" inside "category".
                pattern = "(?<![\\p{L}\\p{N}])" + pattern + "(?![\\p{L}\\p{N}])"
            }

            guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else {
                continue
            }
            let fullRange = NSRange(result.startIndex..., in: result)
            let template = NSRegularExpression.escapedTemplate(for: correction.replacement)
            result = regex.stringByReplacingMatches(
                in: result,
                options: [],
                range: fullRange,
                withTemplate: template
            )
        }
        return result
    }
}
