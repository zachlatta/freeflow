namespace FreeFlowWindows.Core.Interfaces;

/// <summary>
/// Interface for managing clipboard operations and paste simulation.
/// Handles clipboard preservation, text insertion, and "Paste Again" functionality.
/// </summary>
public interface IClipboardManager
{
    /// <summary>
    /// Pastes text into the active application by copying to clipboard and simulating Ctrl+V.
    /// </summary>
    /// <param name="text">The text to paste.</param>
    /// <param name="preserveClipboard">
    /// When true, saves the current clipboard contents before pasting and restores them after a delay.
    /// When false, the pasted text remains on the clipboard.
    /// </param>
    /// <param name="cancellationToken">Cancellation token.</param>
    /// <returns>A task that completes when the paste operation is done (including clipboard restore if enabled).</returns>
    Task PasteTextAsync(string text, bool preserveClipboard = true, CancellationToken cancellationToken = default);

    /// <summary>
    /// Pastes the most recently dictated transcript.
    /// Does nothing if no transcript has been dictated yet.
    /// </summary>
    /// <param name="cancellationToken">Cancellation token.</param>
    /// <returns>A task that completes when the paste operation is done.</returns>
    Task PasteLastTranscriptAsync(CancellationToken cancellationToken = default);

    /// <summary>
    /// Gets the most recently dictated transcript for "Paste Again" functionality.
    /// </summary>
    /// <returns>The last transcript, or null if no transcript has been dictated.</returns>
    string? GetLastTranscript();

    /// <summary>
    /// Gets text from the clipboard.
    /// </summary>
    /// <param name="cancellationToken">Cancellation token.</param>
    /// <returns>The clipboard text, or null if the clipboard doesn't contain text.</returns>
    Task<string?> GetTextAsync(CancellationToken cancellationToken = default);

    /// <summary>
    /// Sets text on the clipboard.
    /// </summary>
    /// <param name="text">The text to set.</param>
    /// <param name="cancellationToken">Cancellation token.</param>
    /// <returns>A task that completes when the text has been set.</returns>
    Task SetTextAsync(string text, CancellationToken cancellationToken = default);

    /// <summary>
    /// Gets or sets the delay after pasting before restoring the original clipboard contents.
    /// Default is 1 second.
    /// </summary>
    TimeSpan ClipboardRestoreDelay { get; set; }
}
