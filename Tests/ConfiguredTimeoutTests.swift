import Foundation

enum ConfiguredTimeoutTests {
    static func run() {
        // Unset, zero, negative, and non-finite overrides fall back to the default.
        TestSupport.expectEqual(ConfiguredTimeout.seconds(override: 0, defaultSeconds: 20), 20)
        TestSupport.expectEqual(ConfiguredTimeout.seconds(override: -1, defaultSeconds: 20), 20)
        TestSupport.expectEqual(ConfiguredTimeout.seconds(override: .infinity, defaultSeconds: 20), 20)
        TestSupport.expectEqual(ConfiguredTimeout.seconds(override: .nan, defaultSeconds: 20), 20)

        // Ordinary overrides are honored unchanged.
        TestSupport.expectEqual(ConfiguredTimeout.seconds(override: 60, defaultSeconds: 20), 60)
        TestSupport.expectEqual(ConfiguredTimeout.seconds(override: 0.5, defaultSeconds: 20), 0.5)

        // Regression for #318: an override this large used to trap in
        // UInt64(timeoutSeconds * 1_000_000_000) when the timeout task started.
        let huge = ConfiguredTimeout.seconds(override: 1e12, defaultSeconds: 20)
        TestSupport.expectEqual(huge, ConfiguredTimeout.maximumSeconds)
        TestSupport.expectEqual(ConfiguredTimeout.nanoseconds(for: huge), UInt64(ConfiguredTimeout.maximumSeconds) * 1_000_000_000)
        TestSupport.expectEqual(Int(huge), 86_400)

        // The sleep conversion itself saturates instead of trapping.
        TestSupport.expectEqual(ConfiguredTimeout.nanoseconds(for: 1e30), UInt64.max)
        TestSupport.expectEqual(ConfiguredTimeout.nanoseconds(for: .infinity), UInt64.max)
        TestSupport.expectEqual(ConfiguredTimeout.nanoseconds(for: .nan), 0)
        TestSupport.expectEqual(ConfiguredTimeout.nanoseconds(for: -5), 0)
        TestSupport.expectEqual(ConfiguredTimeout.nanoseconds(for: 20), 20_000_000_000)

        // The UserDefaults-backed lookup goes through the same sanitizing path.
        let suite = "configured-timeout-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        TestSupport.expectEqual(ConfiguredTimeout.seconds(forKey: "transcription_timeout_seconds", defaultSeconds: 20, defaults: defaults), 20)
        defaults.set(45.0, forKey: "transcription_timeout_seconds")
        TestSupport.expectEqual(ConfiguredTimeout.seconds(forKey: "transcription_timeout_seconds", defaultSeconds: 20, defaults: defaults), 45)
        defaults.set(99_999_999_999.0, forKey: "transcription_timeout_seconds")
        TestSupport.expectEqual(ConfiguredTimeout.seconds(forKey: "transcription_timeout_seconds", defaultSeconds: 20, defaults: defaults), ConfiguredTimeout.maximumSeconds)
    }
}
