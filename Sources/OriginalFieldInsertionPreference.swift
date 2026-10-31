import Foundation

/// A missing preference keeps original-field insertion disabled.
enum OriginalFieldInsertionPreference {
    static let storageKey = "original_field_insertion_enabled"
    static let defaultEnabled = false

    /// Returns the default-off choice for missing/invalid values without persisting a default.
    static func load(from defaults: UserDefaults) -> Bool {
        (defaults.object(forKey: storageKey) as? Bool) ?? defaultEnabled
    }
}
