using System.Collections.Concurrent;
using System.Text.RegularExpressions;

namespace FreeFlowWindows.Core.Services;

/// <summary>
/// Tracks per-model rate-limit cooldowns so subsequent requests skip a rate-limited model
/// instead of sending a doomed request and paying an extra round-trip.
/// 
/// Two storage tiers:
///   - Minute-level limits (retry-after &lt; 1 hour): stored in memory, cleared on app restart.
///   - Daily limits (retry-after &gt;= 1 hour): persisted to app settings so the cooldown
///     survives app restarts and is visible in the Settings UI.
///     
/// Ports the macOS LLMCooldownManager actor to C# using thread-safe concurrent collections.
/// </summary>
public sealed class LLMCooldownManager
{
    /// <summary>
    /// Shared instance used by all PostProcessingService instances across the app.
    /// Rate limits apply at the Groq organization level, so one shared state is correct.
    /// </summary>
    public static LLMCooldownManager Shared { get; } = new();

    /// <summary>
    /// Cooldowns at or above this threshold are treated as daily limits and persisted.
    /// </summary>
    private static readonly TimeSpan DailyLimitThreshold = TimeSpan.FromHours(1);

    /// <summary>
    /// Fallback cooldown used when a 429 carries no parseable timing header. Kept well below
    /// DailyLimitThreshold so it stays in memory and lets the next call re-probe soon.
    /// </summary>
    private static readonly TimeSpan DefaultReprobeCooldown = TimeSpan.FromSeconds(60);

    /// <summary>
    /// In-memory store for short-lived minute-level cooldowns.
    /// Maps model name to expiration DateTime (UTC).
    /// </summary>
    private readonly ConcurrentDictionary<string, DateTime> _cooldowns = new();

    /// <summary>
    /// Persistent store for daily-level cooldowns.
    /// Maps model name to expiration DateTime (UTC).
    /// In a full implementation, this would use SettingsManager or similar.
    /// For now, uses a concurrent dictionary that survives within the app session.
    /// </summary>
    private readonly ConcurrentDictionary<string, DateTime> _persistedCooldowns = new();

    /// <summary>
    /// Event raised when a cooldown changes (for Settings UI binding).
    /// </summary>
    public event EventHandler<CooldownChangedEventArgs>? CooldownChanged;

    /// <summary>
    /// Private constructor to enforce singleton pattern.
    /// </summary>
    private LLMCooldownManager()
    {
    }

    /// <summary>
    /// Returns true if the given model is currently blocked by a rate-limit cooldown.
    /// Checks both in-memory (minute-level) and persisted (daily-level) stores.
    /// </summary>
    /// <param name="model">The model identifier.</param>
    /// <returns>True if the model is in cooldown, false otherwise.</returns>
    public bool IsInCooldown(string model)
    {
        var now = DateTime.UtcNow;

        // Check in-memory store first — minute-level limits live here.
        if (_cooldowns.TryGetValue(model, out var until))
        {
            if (now < until)
            {
                return true;
            }
            // Entry expired; remove it to keep the dictionary clean.
            _cooldowns.TryRemove(model, out _);
        }

        // Check persisted store for daily-limit entries.
        if (_persistedCooldowns.TryGetValue(model, out var persistedUntil))
        {
            if (now < persistedUntil)
            {
                return true;
            }
            // Entry expired; remove it.
            _persistedCooldowns.TryRemove(model, out _);
            CooldownChanged?.Invoke(this, new CooldownChangedEventArgs(model, null));
        }

        return false;
    }

    /// <summary>
    /// Gets the cooldown expiry time for a model, or null if not in cooldown.
    /// </summary>
    /// <param name="model">The model identifier.</param>
    /// <returns>The expiry time (UTC) or null if no active cooldown.</returns>
    public DateTime? GetCooldownExpiry(string model)
    {
        var now = DateTime.UtcNow;

        // Check persisted first (daily limits take precedence)
        if (_persistedCooldowns.TryGetValue(model, out var persistedUntil) && now < persistedUntil)
        {
            return persistedUntil;
        }

        // Check in-memory
        if (_cooldowns.TryGetValue(model, out var until) && now < until)
        {
            return until;
        }

        return null;
    }

    /// <summary>
    /// Registers a cooldown for a model using the retry-after duration from the API 429 response.
    /// Minute-level durations stay in memory; daily-level durations are persisted.
    /// </summary>
    /// <param name="model">The model that was rate-limited.</param>
    /// <param name="retryAfter">Duration until the model can be used again.</param>
    /// <param name="persist">Force persistence even for short durations (for daily quota signals).</param>
    public void SetCooldown(string model, TimeSpan retryAfter, bool persist = false)
    {
        var expiryDate = DateTime.UtcNow.Add(retryAfter);

        if (persist || retryAfter >= DailyLimitThreshold)
        {
            // Daily limit: persist so it survives app restarts.
            _persistedCooldowns[model] = expiryDate;
            CooldownChanged?.Invoke(this, new CooldownChangedEventArgs(model, expiryDate));
        }
        else
        {
            // Minute-level limit: keep in memory only; it will expire within minutes.
            _cooldowns[model] = expiryDate;
        }
    }

    /// <summary>
    /// Returns an available model to use up-front, or null when none is available.
    /// Returns the primary if it is not cooling down; otherwise the fallback if it 
    /// exists and is itself not cooling down; otherwise null, so the caller can 
    /// skip a doomed request when BOTH models are rate-limited.
    /// </summary>
    /// <param name="primary">The primary model to try first.</param>
    /// <param name="fallback">The fallback model to try if primary is in cooldown.</param>
    /// <returns>An available model, or null if both are in cooldown.</returns>
    public string? GetEffectivePrimary(string primary, string? fallback)
    {
        if (!IsInCooldown(primary))
        {
            return primary;
        }

        if (fallback != null && !IsInCooldown(fallback))
        {
            return fallback;
        }

        return null;
    }

    /// <summary>
    /// Clears the cooldown for a specific model (useful for testing or manual reset).
    /// </summary>
    /// <param name="model">The model to clear.</param>
    public void ClearCooldown(string model)
    {
        _cooldowns.TryRemove(model, out _);
        _persistedCooldowns.TryRemove(model, out _);
        CooldownChanged?.Invoke(this, new CooldownChangedEventArgs(model, null));
    }

    /// <summary>
    /// Clears all cooldowns (useful for testing).
    /// </summary>
    public void ClearAllCooldowns()
    {
        var models = _cooldowns.Keys.Concat(_persistedCooldowns.Keys).Distinct().ToList();
        _cooldowns.Clear();
        _persistedCooldowns.Clear();
        foreach (var model in models)
        {
            CooldownChanged?.Invoke(this, new CooldownChangedEventArgs(model, null));
        }
    }

    /// <summary>
    /// Reads from an HTTP 429 response how long the model must cool down AND whether 
    /// the limit is a daily one (so the caller persists it even when the remaining time is short).
    /// 
    /// Priority: 
    /// 1. Exhausted daily request quota (x-ratelimit-remaining-requests &lt;= 0, using x-ratelimit-reset-requests)
    /// 2. retry-after header (delta-seconds)
    /// 3. x-ratelimit-reset-tokens (per-minute TPM reset)
    /// 4. Default short re-probe fallback
    /// </summary>
    /// <param name="headers">HTTP response headers from a 429 response.</param>
    /// <returns>Tuple of (cooldown duration, whether this is a daily limit).</returns>
    public static (TimeSpan Duration, bool IsDaily) ParseRateLimitCooldown(IDictionary<string, IEnumerable<string>> headers)
    {
        // Helper to get a header value
        string? GetHeader(string name)
        {
            if (headers.TryGetValue(name, out var values))
            {
                return values.FirstOrDefault();
            }
            // Try case-insensitive lookup
            var key = headers.Keys.FirstOrDefault(k => k.Equals(name, StringComparison.OrdinalIgnoreCase));
            if (key != null && headers.TryGetValue(key, out values))
            {
                return values.FirstOrDefault();
            }
            return null;
        }

        // Daily (RPD) quota spent: classify as daily and use its reset
        var remainingRequestsStr = GetHeader("x-ratelimit-remaining-requests");
        if (double.TryParse(remainingRequestsStr, out var remainingRequests) && remainingRequests <= 0)
        {
            var dailyResetStr = GetHeader("x-ratelimit-reset-requests");
            if (dailyResetStr != null && TryParseGroqDuration(dailyResetStr, out var dailyReset))
            {
                return (dailyReset, true);
            }
        }

        // retry-after is the authoritative wait header
        var retryAfterStr = GetHeader("retry-after");
        if (retryAfterStr != null && TryParseGroqDuration(retryAfterStr, out var retryAfter))
        {
            return (retryAfter, false);
        }

        // x-ratelimit-reset-tokens carries the per-minute (TPM) reset
        var tokenResetStr = GetHeader("x-ratelimit-reset-tokens");
        if (tokenResetStr != null && TryParseGroqDuration(tokenResetStr, out var tokenReset))
        {
            return (tokenReset, false);
        }

        // No timing header present: cool down briefly so the next call can re-probe
        return (DefaultReprobeCooldown, false);
    }

    /// <summary>
    /// Parses a Groq duration string into a TimeSpan. Accepts bare seconds ("2", "7.66"),
    /// a single suffixed unit ("7.66s", "120ms"), and compound forms ("2m59.56s", "1h0m0s").
    /// </summary>
    /// <param name="value">The duration string to parse.</param>
    /// <param name="result">The parsed TimeSpan.</param>
    /// <returns>True if parsing succeeded, false otherwise.</returns>
    public static bool TryParseGroqDuration(string value, out TimeSpan result)
    {
        result = TimeSpan.Zero;
        var trimmed = value.Trim();
        if (string.IsNullOrEmpty(trimmed))
        {
            return false;
        }

        // A bare number is plain seconds
        if (double.TryParse(trimmed, out var bareSeconds))
        {
            if (!double.IsFinite(bareSeconds) || bareSeconds < 0)
            {
                return false;
            }
            result = TimeSpan.FromSeconds(bareSeconds);
            return true;
        }

        // Otherwise accumulate <number><unit> segments left to right (h, m, s, ms)
        var total = TimeSpan.Zero;
        var numberBuffer = new System.Text.StringBuilder();
        var matchedAnyUnit = false;
        var index = 0;

        while (index < trimmed.Length)
        {
            var character = trimmed[index];

            if (char.IsDigit(character) || character == '.')
            {
                numberBuffer.Append(character);
                index++;
                continue;
            }

            // Hit a unit: the preceding digits must form a valid number
            if (numberBuffer.Length == 0 || !double.TryParse(numberBuffer.ToString(), out var number))
            {
                return false;
            }
            numberBuffer.Clear();

            // "ms" must be checked before single-letter units
            if (index + 1 < trimmed.Length && trimmed.Substring(index, 2) == "ms")
            {
                total = total.Add(TimeSpan.FromMilliseconds(number));
                index += 2;
            }
            else if (character == 'h')
            {
                total = total.Add(TimeSpan.FromHours(number));
                index++;
            }
            else if (character == 'm')
            {
                total = total.Add(TimeSpan.FromMinutes(number));
                index++;
            }
            else if (character == 's')
            {
                total = total.Add(TimeSpan.FromSeconds(number));
                index++;
            }
            else
            {
                // Unrecognized unit
                return false;
            }
            matchedAnyUnit = true;
        }

        // Reject a trailing number with no unit and unit-less input
        if (numberBuffer.Length > 0 || !matchedAnyUnit)
        {
            return false;
        }

        // Reject non-finite/negative accumulated total
        if (total < TimeSpan.Zero)
        {
            return false;
        }

        result = total;
        return true;
    }
}

/// <summary>
/// Event args for cooldown change notifications.
/// </summary>
public class CooldownChangedEventArgs : EventArgs
{
    /// <summary>
    /// The model whose cooldown changed.
    /// </summary>
    public string Model { get; }

    /// <summary>
    /// The new expiry time, or null if cooldown was cleared.
    /// </summary>
    public DateTime? Expiry { get; }

    /// <summary>
    /// Creates a new cooldown changed event args.
    /// </summary>
    public CooldownChangedEventArgs(string model, DateTime? expiry)
    {
        Model = model;
        Expiry = expiry;
    }
}
