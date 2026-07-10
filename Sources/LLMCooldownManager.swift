import Foundation

/// Tracks per-model rate-limit cooldowns so subsequent requests skip a rate-limited model
/// instead of sending a doomed request and paying an extra round-trip.
///
/// Two storage tiers:
///   - Minute-level limits (retry-after < 1 hour): stored in memory, cleared on app restart.
///   - Daily limits (retry-after >= 1 hour): persisted in UserDefaults so the cooldown
///     survives app restarts and is visible in the Settings UI.
actor LLMCooldownManager {

    /// Shared instance used by all PostProcessingService instances across the app.
    /// Rate limits apply at the Groq organization level, so one shared state is correct.
    static let shared = LLMCooldownManager()

    /// Cooldowns at or above this threshold are treated as daily limits and persisted.
    private let dailyLimitThreshold: TimeInterval = 3600

    /// Fallback cooldown used when a 429 carries no parseable timing header. Kept well below
    /// `dailyLimitThreshold` so it stays in memory and lets the next call re-probe soon.
    private static let defaultReprobeCooldownSeconds: TimeInterval = 60

    /// In-memory store for short-lived minute-level cooldowns.
    private var cooldowns: [String: Date] = [:]

    /// Returns true if the given model is currently blocked by a rate-limit cooldown.
    /// Checks both in-memory (minute-level) and UserDefaults (daily-level) stores.
    func isInCooldown(_ model: String) -> Bool {
        let now = Date()

        // Check in-memory store first — minute-level limits live here.
        if let until = cooldowns[model] {
            if now < until { return true }
            // Entry expired; remove it to keep the dictionary clean.
            cooldowns.removeValue(forKey: model)
        }

        // Check UserDefaults for persisted daily-limit entries.
        if let until = persistedExpiry(for: model) {
            if now < until { return true }
            // Entry expired; remove it from UserDefaults.
            clearPersistedExpiry(for: model)
        }

        return false
    }

    /// Registers a cooldown for a model using the retry-after duration from the API 429 response.
    /// Minute-level durations stay in memory; daily-level durations are also written to UserDefaults.
    /// Pass `persist: true` for a daily-limit signal (the RPD reset header) so a daily quota that
    /// happens to reset in under an hour is still persisted and shown in Settings, not kept in memory.
    func setCooldown(_ model: String, retryAfterSeconds: TimeInterval, persist: Bool = false) {
        let expiryDate = Date().addingTimeInterval(retryAfterSeconds)
        if persist || retryAfterSeconds >= dailyLimitThreshold {
            // Daily limit: persist to UserDefaults so it survives app restarts.
            persistExpiry(expiryDate, for: model)
        } else {
            // Minute-level limit: keep in memory only; it will expire within minutes.
            cooldowns[model] = expiryDate
        }
    }

    /// Returns an available model to use up-front, or nil when none is: the primary if it is not
    /// cooling down; otherwise the fallback if it exists and is itself not cooling down; otherwise
    /// nil, so the caller can skip a doomed request when BOTH models are rate-limited.
    func effectivePrimary(_ primary: String, fallback: String?) -> String? {
        if !isInCooldown(primary) {
            return primary
        }
        guard let fallback, !isInCooldown(fallback) else {
            return nil
        }
        return fallback
    }

    // MARK: - UserDefaults (daily-limit persistence)

    /// Shared key format so SettingsView can read expiry dates without going through the actor.
    /// nonisolated allows this to be called synchronously from SwiftUI view code.
    nonisolated static func udKey(for model: String) -> String {
        "llm_cooldown_expiry_\(model)"
    }

    /// Instance wrapper used internally by the actor methods below.
    private func udKey(_ model: String) -> String {
        Self.udKey(for: model)
    }

    /// Reads the persisted cooldown expiry for a model from UserDefaults.
    /// Returns nil if no entry exists.
    private func persistedExpiry(for model: String) -> Date? {
        let timestamp = UserDefaults.standard.double(forKey: udKey(model))
        guard timestamp > 0 else { return nil }
        return Date(timeIntervalSince1970: timestamp)
    }

    /// Writes a cooldown expiry date for a model to UserDefaults as a Unix timestamp.
    private func persistExpiry(_ date: Date, for model: String) {
        UserDefaults.standard.set(date.timeIntervalSince1970, forKey: udKey(model))
    }

    /// Removes a model's cooldown entry from UserDefaults once it has expired.
    private func clearPersistedExpiry(for model: String) {
        UserDefaults.standard.removeObject(forKey: udKey(model))
    }

    // MARK: - Rate-limit header parsing

    /// Reads from a Groq 429 response how long the model must cool down AND whether the limit is a
    /// daily one (so the caller persists it even when the remaining time is short).
    /// Priority: an exhausted daily request quota (`x-ratelimit-remaining-requests` <= 0, using the
    /// `x-ratelimit-reset-requests` RPD reset) → `retry-after` (delta-seconds) →
    /// `x-ratelimit-reset-tokens` (the per-minute / Tokens-Per-Minute reset) → a short re-probe
    /// fallback. The RPD check runs FIRST because Groq usually also sends `retry-after`; honoring
    /// that first would hide a short, near-reset daily window and stop it from persisting.
    /// nonisolated static so the call site computes it without an actor hop.
    nonisolated static func rateLimitCooldown(from httpResponse: HTTPURLResponse) -> (seconds: TimeInterval, isDaily: Bool) {
        // Daily (RPD) quota spent: classify as daily and use its reset even when retry-after is also
        // present, so a short near-reset daily window still persists and surfaces in Settings.
        let remainingRequests = httpResponse.value(forHTTPHeaderField: "x-ratelimit-remaining-requests")
            .flatMap { Double($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
        if let remainingRequests, remainingRequests <= 0,
           let dailyReset = httpResponse.value(forHTTPHeaderField: "x-ratelimit-reset-requests").flatMap(parseGroqDuration) {
            return (dailyReset, true)
        }
        // retry-after is the authoritative wait Groq sets specifically on a 429.
        if let value = httpResponse.value(forHTTPHeaderField: "retry-after").flatMap(parseGroqDuration) {
            return (value, false)
        }
        // x-ratelimit-reset-tokens carries the per-minute (TPM) reset, e.g. "7.66s".
        if let value = httpResponse.value(forHTTPHeaderField: "x-ratelimit-reset-tokens").flatMap(parseGroqDuration) {
            return (value, false)
        }
        // No timing header present (rare): cool down briefly so the next call can re-probe.
        return (Self.defaultReprobeCooldownSeconds, false)
    }

    /// Parses a Groq duration string into a TimeInterval. Accepts bare seconds ("2", "7.66"),
    /// a single suffixed unit ("7.66s", "120ms"), and compound forms ("2m59.56s", "1h0m0s",
    /// "1h2m3.5s"). Returns nil for empty, unrecognized-unit, negative, or non-finite input —
    /// so a malformed header can never yield a negative/NaN/infinite cooldown.
    private nonisolated static func parseGroqDuration(_ value: String) -> TimeInterval? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        // A bare number is plain seconds — covers the `retry-after` integer form ("2").
        // Reject NaN/infinite/negative (Double() also accepts "nan"/"inf"/"-3"/"0x10").
        if let seconds = Double(trimmed) { return (seconds.isFinite && seconds >= 0) ? seconds : nil }
        // Otherwise accumulate <number><unit> segments left to right (h, m, s, ms).
        var total: TimeInterval = 0
        var numberBuffer = ""
        var matchedAnyUnit = false
        var index = trimmed.startIndex
        while index < trimmed.endIndex {
            let character = trimmed[index]
            if character.isNumber || character == "." {
                numberBuffer.append(character)
                index = trimmed.index(after: index)
                continue
            }
            // Hit a unit: the preceding digits must form a valid number.
            guard let number = Double(numberBuffer) else { return nil }
            numberBuffer = ""
            // "ms" must be checked before the single-letter "m"/"s".
            if trimmed[index...].hasPrefix("ms") {
                total += number / 1000.0
                index = trimmed.index(index, offsetBy: 2)
            } else if character == "h" {
                total += number * 3600.0
                index = trimmed.index(after: index)
            } else if character == "m" {
                total += number * 60.0
                index = trimmed.index(after: index)
            } else if character == "s" {
                total += number
                index = trimmed.index(after: index)
            } else {
                return nil // Unrecognized unit.
            }
            matchedAnyUnit = true
        }
        // Reject a trailing number with no unit (e.g. "1h30") and unit-less input.
        guard numberBuffer.isEmpty, matchedAnyUnit else { return nil }
        // Reject a non-finite/negative accumulated total for the same safety reason.
        return (total.isFinite && total >= 0) ? total : nil
    }
}
