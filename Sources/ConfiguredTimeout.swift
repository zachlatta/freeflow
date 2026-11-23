import Foundation

/// Resolves the user-overridable request timeouts read from UserDefaults
/// (for example `transcription_timeout_seconds`) into values that are safe to
/// hand to `URLRequest`, `Task.sleep`, and `Int(_:)`.
///
/// Converting a very large or non-finite `Double` to `UInt64` or `Int` traps at
/// runtime, so an override such as `1e12` (a natural way to ask for "no
/// timeout") used to crash the app when the timeout task started.
enum ConfiguredTimeout {
    /// Upper bound for any override. One day is far longer than any dictation
    /// request should take, so it behaves like "no timeout" in practice while
    /// staying well inside the range `Task.sleep(nanoseconds:)` accepts.
    static let maximumSeconds: TimeInterval = 86_400

    static func seconds(override: Double, defaultSeconds: TimeInterval) -> TimeInterval {
        guard override.isFinite, override > 0 else { return defaultSeconds }
        return min(override, maximumSeconds)
    }

    static func seconds(forKey key: String, defaultSeconds: TimeInterval, defaults: UserDefaults = .standard) -> TimeInterval {
        seconds(override: defaults.double(forKey: key), defaultSeconds: defaultSeconds)
    }

    /// Saturating conversion for `Task.sleep(nanoseconds:)`.
    static func nanoseconds(for seconds: TimeInterval) -> UInt64 {
        guard !seconds.isNaN, seconds > 0 else { return 0 }
        let nanoseconds = seconds * 1_000_000_000
        guard nanoseconds < Double(UInt64.max) else { return UInt64.max }
        return UInt64(nanoseconds)
    }
}
