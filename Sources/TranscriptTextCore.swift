import Foundation
import os.log

private let transcriptTextLog = OSLog(
    subsystem: "com.zachlatta.freeflow",
    category: "Transcription"
)

enum TranscriptionResponseParsingError: Error, Equatable {
    case invalidResponse
}

enum TranscriptionResponseParser {
    // Whisper can emit these stock phrases for silence or background noise.
    // Only suppress them when segment metadata independently reports a high
    // probability of no speech, which protects genuine short dictations.
    private static let hallucinationPhrases: Set<String> = [
        "thank you",
        "thank you for watching",
        "thank you very much",
        "thank you so much",
        "thanks for watching",
        "please subscribe",
        "like and subscribe",
        "subtitles by",
        "subtitles by the amara.org community",
        "you"
    ]

    // Tuned conservatively against roughly 500 quiet, noisy, and real-speech
    // samples to minimize the chance of filtering genuine short dictations.
    private static let hallucinationNoSpeechThreshold = 0.1

    static func parse(_ data: Data) throws -> String {
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw TranscriptionResponseParsingError.invalidResponse
        }

        if let json = object as? [String: Any],
           let text = json["text"] as? String {
            if isHallucination(text: text, json: json) {
                return ""
            }
            return strippingEdgeSubtitleCredits(from: text, json: json)
        }

        let plainText = String(data: data, encoding: .utf8) ?? ""
        let text = plainText
            .components(separatedBy: .newlines)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            throw TranscriptionResponseParsingError.invalidResponse
        }

        return text
    }

    private static func isHallucination(text: String, json: [String: Any]) -> Bool {
        let normalized = text
            .lowercased()
            .trimmingCharacters(in: CharacterSet.punctuationCharacters.union(.whitespacesAndNewlines))
        guard hallucinationPhrases.contains(normalized)
            || SubtitleCreditMatcher.isSubtitleCredit(text) else {
            return false
        }

        // Logs deliberately omit the transcript text.
        guard let segments = json["segments"] as? [[String: Any]] else {
            os_log(
                .info,
                log: transcriptTextLog,
                "Skipping hallucination filter: provider response has no segments/no_speech metadata"
            )
            return false
        }

        guard let noSpeechProb = segments.first?["no_speech_prob"] as? Double else {
            os_log(
                .info,
                log: transcriptTextLog,
                "Skipping hallucination filter: provider response omitted no_speech_prob"
            )
            return false
        }
        return noSpeechProb >= hallucinationNoSpeechThreshold
    }

    // Whisper sometimes appends (or, less often, prepends) a subtitle-credit
    // segment to real speech that is followed by silence. Strip such an edge
    // segment only when that segment's text is, in full, a known credit line
    // and that same segment reports a high no-speech probability. Interior
    // segments are never touched.
    private static func strippingEdgeSubtitleCredits(from text: String, json: [String: Any]) -> String {
        guard let segments = json["segments"] as? [[String: Any]], segments.count > 1 else {
            return text
        }

        var result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var remaining = segments[...]
        var stripped = false

        while let last = remaining.last,
              let creditText = subtitleCreditText(in: last),
              result.hasSuffix(creditText) {
            result = String(result.dropLast(creditText.count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            remaining = remaining.dropLast()
            stripped = true
        }

        while let first = remaining.first,
              let creditText = subtitleCreditText(in: first),
              result.hasPrefix(creditText) {
            result = String(result.dropFirst(creditText.count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            remaining = remaining.dropFirst()
            stripped = true
        }

        return stripped ? result : text
    }

    private static func subtitleCreditText(in segment: [String: Any]) -> String? {
        guard let segmentText = segment["text"] as? String,
              let noSpeechProb = segment["no_speech_prob"] as? Double,
              noSpeechProb >= hallucinationNoSpeechThreshold,
              SubtitleCreditMatcher.isSubtitleCredit(segmentText) else {
            return nil
        }
        let trimmed = segmentText.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

// Whisper is trained on subtitled video, so on silence it can emit the
// subtitle-credit line of whatever language it guessed. Matching is
// deliberately exact: after normalization the *entire* text must equal one of
// these curated credit lines (optionally followed by a year). Merely
// mentioning subtitles, captions, or Amara never matches.
enum SubtitleCreditMatcher {
    private static let knownCredits: [String] = [
        // English
        "Subtitles by the Amara.org community",
        "Subtitles made by the community of Amara.org",
        "Subtitles created by the Amara.org community",
        // German
        "Untertitel im Auftrag des ZDF",
        "Untertitel im Auftrag des ZDF für funk",
        "Untertitelung im Auftrag des ZDF",
        "Untertitelung im Auftrag des ZDF für funk",
        "Untertitelung des ZDF",
        "Untertitelung des ZDF für funk",
        "Untertitel der Amara.org-Community",
        "Untertitelung aufgrund der Amara.org-Community",
        // French
        "Sous-titres réalisés par la communauté d'Amara.org",
        "Sous-titres réalisés para la communauté d'Amara.org",
        "Sous-titrage Société Radio-Canada",
        "Sous-titrage ST' 501",
        // Spanish
        "Subtítulos realizados por la comunidad de Amara.org",
        "Subtítulos por la comunidad de Amara.org",
        "Subtitulado por la comunidad de Amara.org",
        // Italian
        "Sottotitoli creati dalla comunità Amara.org",
        "Sottotitoli e revisione a cura di QTSS",
        "Sottotitoli a cura di QTSS",
        // Portuguese
        "Legendas pela comunidade Amara.org",
        "Legendas pela comunidade de Amara.org",
        // Dutch
        "Ondertitels ingediend door de Amara.org gemeenschap",
        "Ondertiteld door de Amara.org gemeenschap",
        "Ondertiteling door de Amara.org gemeenschap",
        // Polish
        "Napisy stworzone przez społeczność Amara.org",
        "Napisy wykonane przez społeczność Amara.org",
        // Norwegian / Danish
        "Undertekster av Ai-Media",
        "Undertekster af Ai-Media",
        // Turkish
        "Altyazı M.K.",
        // Russian
        "Субтитры сделал DimaTorzok",
        "Субтитры создавал DimaTorzok",
        "Субтитры подготовлены сообществом Amara.org",
        "Редактор субтитров А.Синецкая Корректор А.Егорова",
        // Chinese
        "字幕by索兰娅",
        "字幕由Amara.org社区提供",
        "字幕志愿者 杨茜茜",
        // Arabic
        "ترجمة نانسي قنقر"
    ]

    private static let normalizedCredits: Set<String> = Set(knownCredits.map(normalize))

    static func isSubtitleCredit(_ text: String) -> Bool {
        let normalized = normalize(text)
        guard !normalized.isEmpty else { return false }
        if normalizedCredits.contains(normalized) {
            return true
        }
        // Allow a single trailing year, e.g. "Untertitel im Auftrag des ZDF, 2017".
        guard let lastSpace = normalized.lastIndex(of: " ") else { return false }
        let tail = normalized[normalized.index(after: lastSpace)...]
        guard tail.count == 4,
              tail.allSatisfy({ $0.isASCII && $0.isNumber }),
              tail.hasPrefix("19") || tail.hasPrefix("20") else {
            return false
        }
        return normalizedCredits.contains(String(normalized[..<lastSpace]))
    }

    // Case-, diacritic-, and width-insensitive; every run of punctuation,
    // symbols, or whitespace collapses to a single space.
    static func normalize(_ text: String) -> String {
        let folded = text
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            )
            .precomposedStringWithCanonicalMapping
        var result = ""
        var pendingSpace = false
        for character in folded {
            if character.isLetter || character.isNumber {
                if pendingSpace && !result.isEmpty {
                    result.append(" ")
                }
                pendingSpace = false
                result.append(character)
            } else {
                pendingSpace = true
            }
        }
        return result
    }
}

enum TranscriptOutputSanitizer {
    // Verbatim translation deliberately preserves the cleanup prompt's EMPTY
    // sentinel because "empty" can be legitimate translated speech here.
    static func verbatimTranslation(_ value: String) -> String {
        var result = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !result.isEmpty else { return "" }
        if result.hasPrefix("\"") && result.hasSuffix("\"") && result.count > 1 {
            result.removeFirst()
            result.removeLast()
            result = result.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return result
    }

    static func postProcessedTranscript(_ value: String) -> String {
        var result = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !result.isEmpty else { return "" }

        if result.hasPrefix("\"") && result.hasSuffix("\"") && result.count > 1 {
            result.removeFirst()
            result.removeLast()
            result = result.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if result == "EMPTY" {
            return ""
        }

        return result
    }

    static func commandModeTranscript(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func appearsToHaveExecutedInstruction(
        rawTranscript: String,
        cleanedTranscript: String,
        outputLanguage: String
    ) -> Bool {
        guard outputLanguage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }

        let rawTokens = significantTokens(in: rawTranscript)
        let cleanedTokens = significantTokens(in: cleanedTranscript)
        guard !rawTokens.isEmpty, !cleanedTokens.isEmpty else { return false }

        let instructionMarkers: Set<String> = [
            "ask", "answer", "compose", "create", "draft", "email", "generate", "make",
            "message", "prompt", "reply", "respond", "response", "summarize", "tell",
            "translate", "write", "claude", "chatgpt", "ai", "llm"
        ]
        let rawMarkers = rawTokens.intersection(instructionMarkers)
        guard !rawMarkers.isEmpty else { return false }

        let preservedMarkers = rawMarkers.intersection(cleanedTokens)
        let overlap = rawTokens.intersection(cleanedTokens)
        let overlapRatio = Double(overlap.count) / Double(max(rawTokens.count, 1))
        let assistantPreamblePattern = #"(?i)^\s*(sure|certainly|absolutely|here(?:'s| is)|i(?:'d| would) be happy to|i can)\b"#
        let cleanedHasAssistantPreamble = cleanedTranscript.range(
            of: assistantPreamblePattern,
            options: .regularExpression
        ) != nil
        let rawHasSamePreamble = rawTranscript.range(
            of: assistantPreamblePattern,
            options: .regularExpression
        ) != nil

        return (cleanedHasAssistantPreamble && !rawHasSamePreamble)
            || (preservedMarkers.isEmpty && overlapRatio < 0.35)
    }

    private static func significantTokens(in text: String) -> Set<String> {
        let stopWords: Set<String> = [
            "a", "an", "and", "are", "as", "at", "be", "but", "by", "can", "could",
            "for", "from", "had", "has", "have", "he", "her", "him", "his", "i", "if",
            "in", "into", "is", "it", "its", "just", "me", "my", "of", "on", "or", "our",
            "please", "she", "so", "that", "the", "their", "them", "then", "there", "this",
            "to", "um", "uh", "was", "we", "were", "what", "when", "where", "who", "with",
            "would", "you", "your"
        ]

        let normalized = text.lowercased()
        let parts = normalized.split { character in
            !character.isLetter && !character.isNumber
        }

        return Set(parts.map(String.init).filter { token in
            token.count > 1 && !stopWords.contains(token)
        })
    }
}
