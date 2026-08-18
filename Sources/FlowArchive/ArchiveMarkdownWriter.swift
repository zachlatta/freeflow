import Foundation

struct ArchiveFrontMatter: Equatable {
    var title: String
    var date: Date
    var durationSeconds: Int
    var tags: [String]
    var audio: String
    var hash: String
    var sourceVolume: String?
}

struct ParsedArchiveMarkdown: Equatable {
    var frontMatter: ArchiveFrontMatter
    var summary: [String]
    var transcript: String
}

enum ArchiveMarkdownWriter {
    static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static func kebabCase(_ raw: String) -> String {
        let lowered = raw.lowercased()
        var scalars: [Character] = []
        var lastDash = false
        for character in lowered {
            if character.isLetter || character.isNumber {
                scalars.append(character)
                lastDash = false
            } else if !lastDash && !scalars.isEmpty {
                scalars.append("-")
                lastDash = true
            }
        }
        while scalars.last == "-" { scalars.removeLast() }
        let slug = String(scalars)
        return slug.isEmpty ? "untitled-recording" : slug
    }

    static func stem(date: Date, kebabName: String) -> String {
        "\(dateFormatter.string(from: date))_\(kebabCase(kebabName))"
    }

    static func formatTimestamp(_ time: TimeInterval) -> String {
        let total = max(0, Int(time.rounded()))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "[%d:%02d:%02d]", hours, minutes, seconds)
        }
        return String(format: "[%02d:%02d]", minutes, seconds)
    }

    static func transcriptBody(segments: [(start: TimeInterval, text: String)], fallback: String) -> String {
        if segments.isEmpty {
            return fallback.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return segments.map { segment in
            let text = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
            return "\(formatTimestamp(segment.start)) \(text)"
        }.joined(separator: "\n")
    }

    static func render(
        frontMatter: ArchiveFrontMatter,
        summary: [String],
        transcript: String
    ) -> String {
        let tags = frontMatter.tags.map { yamlQuote($0) }.joined(separator: ", ")
        var lines: [String] = [
            "---",
            "title: \(yamlQuote(frontMatter.title))",
            "date: \(dateFormatter.string(from: frontMatter.date))",
            "duration_seconds: \(frontMatter.durationSeconds)",
            "tags: [\(tags)]",
            "audio: \(yamlQuote(frontMatter.audio))",
            "hash: \(yamlQuote(frontMatter.hash))"
        ]
        if let source = frontMatter.sourceVolume, !source.isEmpty {
            lines.append("source_volume: \(yamlQuote(source))")
        }
        lines.append("---")
        lines.append("")
        lines.append("## Summary")
        let bullets = summary.isEmpty ? ["(no summary)"] : summary
        for bullet in bullets {
            lines.append("- \(bullet)")
        }
        lines.append("")
        lines.append("## Transcript")
        lines.append(transcript)
        lines.append("")
        return lines.joined(separator: "\n")
    }

    static func parse(_ markdown: String) -> ParsedArchiveMarkdown? {
        let normalized = markdown.replacingOccurrences(of: "\r\n", with: "\n")
        guard normalized.hasPrefix("---") else { return nil }
        let rest = normalized.dropFirst(3)
        guard let endRange = rest.range(of: "\n---") else { return nil }
        let yaml = String(rest[..<endRange.lowerBound])
        let body = String(rest[endRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)

        var fields: [String: String] = [:]
        for rawLine in yaml.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = String(line[..<colon]).trimmingCharacters(in: .whitespaces)
            let value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            fields[key] = value
        }

        guard let title = fields["title"].map(unquote),
              let dateString = fields["date"],
              let date = dateFormatter.date(from: dateString),
              let audio = fields["audio"].map(unquote),
              let hash = fields["hash"].map(unquote)
        else { return nil }

        let duration = Int(fields["duration_seconds"] ?? "0") ?? 0
        let tags = parseTagList(fields["tags"] ?? "")
        let source = fields["source_volume"].map(unquote)

        let summary = parseSummary(from: body)
        let transcript = parseTranscript(from: body)

        return ParsedArchiveMarkdown(
            frontMatter: ArchiveFrontMatter(
                title: title,
                date: date,
                durationSeconds: duration,
                tags: tags,
                audio: audio,
                hash: hash,
                sourceVolume: source?.isEmpty == true ? nil : source
            ),
            summary: summary,
            transcript: transcript
        )
    }

    private static func parseSummary(from body: String) -> [String] {
        guard let summaryRange = body.range(of: "## Summary") else { return [] }
        let after = body[summaryRange.upperBound...]
        let section: Substring
        if let next = after.range(of: "\n## ") {
            section = after[..<next.lowerBound]
        } else {
            section = after
        }
        return section
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .compactMap { line -> String? in
                guard line.hasPrefix("- ") else { return nil }
                let value = String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                return value.isEmpty ? nil : value
            }
    }

    private static func parseTranscript(from body: String) -> String {
        guard let range = body.range(of: "## Transcript") else { return "" }
        return String(body[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func parseTagList(_ raw: String) -> [String] {
        var value = raw.trimmingCharacters(in: .whitespaces)
        if value.hasPrefix("[") && value.hasSuffix("]") {
            value.removeFirst()
            value.removeLast()
        }
        return value
            .split(separator: ",")
            .map { unquote(String($0).trimmingCharacters(in: .whitespaces)) }
            .filter { !$0.isEmpty }
    }

    private static func yamlQuote(_ value: String) -> String {
        if value.contains(":") || value.contains("#") || value.contains("\"") || value.contains("'") {
            let escaped = value.replacingOccurrences(of: "\"", with: "\\\"")
            return "\"\(escaped)\""
        }
        return value
    }

    private static func unquote(_ value: String) -> String {
        var result = value.trimmingCharacters(in: .whitespaces)
        if result.hasPrefix("\"") && result.hasSuffix("\"") && result.count >= 2 {
            result.removeFirst()
            result.removeLast()
            result = result.replacingOccurrences(of: "\\\"", with: "\"")
        }
        return result
    }
}
