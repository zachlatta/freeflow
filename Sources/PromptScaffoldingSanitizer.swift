import Foundation

/// Defensive cleanup of prompt-scaffolding tokens that a post-processing model occasionally
/// leaks into its output.
///
/// The post-processing prompts label their sections with uppercase tokens
/// (`RAW_TRANSCRIPTION`, `PRECEDING_TEXT`, `FOLLOWING_TEXT`, `SELECTED_TEXT`, `VOICE_COMMAND`).
/// When a section is unusual (for example empty), a model sometimes emits a stray line ABOUT
/// the label instead of just cleaning the text — e.g. "FOLLOWING_TEXT is not relevant…". Such
/// a line must never reach the user's document. This is a hard backstop on top of omitting
/// empty sections from the prompt in the first place.
enum PromptScaffoldingSanitizer {

    /// The structural labels used by the post-processing prompts. Uppercase snake_case; these
    /// never occur as a leading label in genuine dictation.
    private static let scaffoldingTokens = [
        "RAW_TRANSCRIPTION", "PRECEDING_TEXT", "FOLLOWING_TEXT",
        "SELECTED_TEXT", "VOICE_COMMAND"
    ]

    /// Removes any LINE that starts with a scaffolding token (the leak pattern: the model
    /// echoing a label), then trims surrounding blank lines.
    ///
    /// Only leading-token lines are dropped, so an inline mention inside legitimate dictation
    /// (e.g. "the variable FOLLOWING_TEXT in the code") is preserved — a leak always appears as
    /// a label at the start of its own line. If stripping would remove everything, the original
    /// is kept: a lone token line is more likely the user's real content than a leak, since a
    /// genuine leak is appended to real text.
    static func strip(_ text: String) -> String {
        // Fast path: no token present at all.
        guard scaffoldingTokens.contains(where: { text.contains($0) }) else { return text }

        let kept = text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !lineIsLeakedLabel(String($0)) }

        let result = kept.joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Never nuke the user's only content: if everything was stripped, the token line was
        // most likely genuine dictation, so fall back to the trimmed original.
        return result.isEmpty ? text.trimmingCharacters(in: .whitespacesAndNewlines) : result
    }

    /// True when a line begins with a scaffolding token used as a label (bare, `TOKEN:`, or
    /// `TOKEN ` followed by commentary) — i.e. the model parroting the prompt's structure.
    private static func lineIsLeakedLabel(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return scaffoldingTokens.contains { token in
            trimmed == token
                || trimmed.hasPrefix(token + ":")
                || trimmed.hasPrefix(token + " ")
        }
    }
}
