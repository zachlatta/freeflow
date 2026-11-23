import Foundation

/// Decides how long a shortcut press must last before recording starts.
enum ShortcutStartDelayPolicy {
    /// Minimum hold time before an Fn/Globe hold-to-talk press starts
    /// dictation. Fn events pass through to macOS (see `ShortcutMatcher`), so a
    /// quick tap can perform the system Globe action (for example Change Input
    /// Source). The floor keeps that tap from also starting a recording;
    /// releasing before it cancels the pending start.
    static let minimumFnHoldStartDelay: TimeInterval = 0.2

    static func effectiveDelay(
        for mode: RecordingTriggerMode,
        holdBinding: ShortcutBinding,
        configuredDelay: TimeInterval
    ) -> TimeInterval {
        let configuredDelay = max(0, configuredDelay)
        guard mode == .hold, holdBinding.usesFnKey else {
            return configuredDelay
        }
        return max(configuredDelay, minimumFnHoldStartDelay)
    }
}
