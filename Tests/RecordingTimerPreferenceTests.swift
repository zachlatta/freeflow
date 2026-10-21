import Foundation

enum RecordingTimerPreferenceTests {
    static func run() {
        let suite = "FreeFlowTests.RecordingTimer.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        TestSupport.expect(!RecordingTimerPreference.defaultEnabled, "Timer must default to off")
        TestSupport.expect(!RecordingTimerPreference.load(from: defaults), "New and existing installs without a preference must keep the timer off")
        TestSupport.expect(defaults.object(forKey: RecordingTimerPreference.storageKey) == nil, "Loading the default must not persist a choice")

        for enabled in [true, false] {
            defaults.set(enabled, forKey: RecordingTimerPreference.storageKey)
            let reloaded = UserDefaults(suiteName: suite)!
            TestSupport.expectEqual(RecordingTimerPreference.load(from: reloaded), enabled)
            TestSupport.expectEqual(reloaded.object(forKey: RecordingTimerPreference.storageKey) as? Bool, enabled)
        }
        defaults.removeObject(forKey: RecordingTimerPreference.storageKey)
        TestSupport.expect(!RecordingTimerPreference.load(from: defaults), "Removing a saved choice must restore off")
    }
}
