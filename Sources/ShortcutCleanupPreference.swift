import Foundation

enum ShortcutCleanupPreference: String, CaseIterable, Hashable {
    case inherit
    case preserveExactWording
    case cleanup

    static let holdStorageKey = "hold_shortcut_cleanup_preference"
    static let toggleStorageKey = "toggle_shortcut_cleanup_preference"

    static func storageKey(for mode: RecordingTriggerMode) -> String {
        switch mode {
        case .hold: return holdStorageKey
        case .toggle: return toggleStorageKey
        }
    }

    static func load(from defaults: UserDefaults, key: String) -> Self {
        guard let rawValue = defaults.string(forKey: key), let preference = Self(rawValue: rawValue) else {
            return .inherit
        }
        return preference
    }

    func save(to defaults: UserDefaults, key: String) {
        defaults.set(rawValue, forKey: key)
    }

    fileprivate func resolve(globalPreserveExactWording: Bool) -> Bool {
        switch self {
        case .inherit: return globalPreserveExactWording
        case .preserveExactWording: return true
        case .cleanup: return false
        }
    }
}

enum ShortcutCleanupSessionOrigin {
    case menu
    case shortcut(RecordingTriggerMode)
}

struct ShortcutCleanupSession {
    private(set) var preserveExactWording: Bool?

    @discardableResult
    mutating func start(
        origin: ShortcutCleanupSessionOrigin,
        globalPreserveExactWording: Bool,
        holdPreference: ShortcutCleanupPreference,
        togglePreference: ShortcutCleanupPreference
    ) -> Bool {
        let preference: ShortcutCleanupPreference?
        switch origin {
        case .menu:
            preference = nil
        case .shortcut(.hold):
            preference = holdPreference
        case .shortcut(.toggle):
            preference = togglePreference
        }

        let effectiveValue = preference?.resolve(globalPreserveExactWording: globalPreserveExactWording)
            ?? globalPreserveExactWording
        preserveExactWording = effectiveValue
        return effectiveValue
    }

    mutating func reset() {
        preserveExactWording = nil
    }
}
