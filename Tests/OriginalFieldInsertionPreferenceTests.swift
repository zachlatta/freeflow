import Foundation

enum OriginalFieldInsertionPreferenceTests {
    static func run() {
        let suite = "FreeFlowTests.OriginalFieldInsertion.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        TestSupport.expect(!OriginalFieldInsertionPreference.defaultEnabled, "Original-field insertion must default to off")
        TestSupport.expect(!OriginalFieldInsertionPreference.load(from: defaults), "A missing preference must keep original-field insertion off")
        TestSupport.expect(defaults.object(forKey: OriginalFieldInsertionPreference.storageKey) == nil, "Loading the default must not persist a choice")

        for enabled in [true, false] {
            defaults.set(enabled, forKey: OriginalFieldInsertionPreference.storageKey)
            let reloaded = UserDefaults(suiteName: suite)!
            TestSupport.expectEqual(OriginalFieldInsertionPreference.load(from: reloaded), enabled)
            TestSupport.expectEqual(reloaded.object(forKey: OriginalFieldInsertionPreference.storageKey) as? Bool, enabled)
        }

        defaults.set("invalid", forKey: OriginalFieldInsertionPreference.storageKey)
        TestSupport.expect(!OriginalFieldInsertionPreference.load(from: defaults), "An invalid saved value must default to off")

        defaults.removeObject(forKey: OriginalFieldInsertionPreference.storageKey)
        TestSupport.expect(!OriginalFieldInsertionPreference.load(from: defaults), "Removing a saved choice must restore off")
    }
}
