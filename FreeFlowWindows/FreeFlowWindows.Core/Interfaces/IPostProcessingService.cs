using FreeFlowWindows.Core.Models;

namespace FreeFlowWindows.Core.Interfaces;

/// <summary>
/// Service for cleaning up transcripts using an LLM.
/// </summary>
public interface IPostProcessingService
{
    /// <summary>
    /// Processes a raw transcript using an LLM to clean up filler words,
    /// fix punctuation, and improve formatting while preserving the speaker's intent.
    /// </summary>
    /// <param name="rawTranscript">The raw transcript from the Whisper API.</param>
    /// <param name="contextSummary">Context summary from the active application (for spelling hints).</param>
    /// <param name="customVocabulary">User-defined vocabulary terms (one per line).</param>
    /// <param name="customSystemPrompt">Optional custom system prompt (uses default if empty).</param>
    /// <param name="outputLanguage">Optional target language for translation (empty = no translation).</param>
    /// <param name="cancellationToken">Cancellation token.</param>
    /// <returns>The post-processing result containing the cleaned transcript or error information.</returns>
    Task<PostProcessingResult> ProcessAsync(
        string rawTranscript,
        string contextSummary,
        IReadOnlyList<string> customVocabulary,
        string? customSystemPrompt = null,
        string? outputLanguage = null,
        CancellationToken cancellationToken = default);
}
