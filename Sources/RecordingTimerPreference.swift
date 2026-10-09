import Foundation

/// A missing preference keeps the timer hidden without changing saved choices.
enum RecordingTimerPreference {
    static let storageKey = "show_recording_timer"
    static let defaultEnabled = false

    static func load(from defaults: UserDefaults) -> Bool {
        (defaults.object(forKey: storageKey) as? Bool) ?? defaultEnabled
    }
}
