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
    func setCooldown(_ model: String, retryAfterSeconds: TimeInterval) {
        let expiryDate = Date().addingTimeInterval(retryAfterSeconds)
        if retryAfterSeconds >= dailyLimitThreshold {
            // Daily limit: persist to UserDefaults so it survives app restarts.
            persistExpiry(expiryDate, for: model)
        } else {
            // Minute-level limit: keep in memory only; it will expire within minutes.
            cooldowns[model] = expiryDate
        }
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
}
