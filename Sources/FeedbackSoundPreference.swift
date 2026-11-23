import Foundation

/// The three moments where FreeFlow plays an audible cue.
enum FeedbackSoundEvent: String, CaseIterable {
    case recordingStart
    case recordingStop
    case error

    var storageKey: String {
        switch self {
        case .recordingStart: return "feedback_sound_recording_start"
        case .recordingStop: return "feedback_sound_recording_stop"
        case .error: return "feedback_sound_error"
        }
    }

    /// The sound FreeFlow has always played for this event.
    var defaultSoundName: String {
        switch self {
        case .recordingStart: return "Tink"
        case .recordingStop: return "Pop"
        case .error: return "Basso"
        }
    }

    var displayName: String {
        switch self {
        case .recordingStart: return "Recording start"
        case .recordingStop: return "Recording stop"
        case .error: return "Error"
        }
    }
}

/// Stores a per-event choice among the built-in macOS alert sounds or "None".
///
/// Safe-fallback policy: a missing or unrecognized stored value loads as the
/// event's default, and a recognized sound that macOS cannot load at play time
/// falls back to the default sound. Only an explicit "None" choice is silent.
enum FeedbackSoundPreference {
    /// Stored value for an event the user chose to silence.
    static let noneValue = "none"

    /// Stock alert sounds in /System/Library/Sounds, loadable by name with
    /// `NSSound(named:)`.
    static let builtInSoundNames = [
        "Basso", "Blow", "Bottle", "Frog", "Funk", "Glass", "Hero",
        "Morse", "Ping", "Pop", "Purr", "Sosumi", "Submarine", "Tink",
    ]

    /// Values the Settings picker offers, in display order.
    static let selectableValues = [noneValue] + builtInSoundNames

    static func displayName(for value: String) -> String {
        value == noneValue ? "None" : value
    }

    static func isSelectable(_ value: String) -> Bool {
        selectableValues.contains(value)
    }

    static func load(_ event: FeedbackSoundEvent, from defaults: UserDefaults) -> String {
        guard let stored = defaults.string(forKey: event.storageKey),
              isSelectable(stored) else {
            return event.defaultSoundName
        }
        return stored
    }

    static func save(_ value: String, for event: FeedbackSoundEvent, to defaults: UserDefaults) {
        if isSelectable(value) {
            defaults.set(value, forKey: event.storageKey)
        } else {
            defaults.removeObject(forKey: event.storageKey)
        }
    }

    /// Resolves a selection to a playable sound. Returns nil for "None", or
    /// when neither the selected sound nor the default can be loaded.
    static func resolve<Sound>(
        _ value: String,
        for event: FeedbackSoundEvent,
        loader: (String) -> Sound?
    ) -> Sound? {
        if value == noneValue { return nil }
        if isSelectable(value), let sound = loader(value) {
            return sound
        }
        return loader(event.defaultSoundName)
    }
}
