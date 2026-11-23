import Foundation

enum FeedbackSoundPreferenceTests {
    static func run() {
        let suite = "FreeFlowTests.FeedbackSound.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        // Absent preferences keep today's sounds and persist nothing.
        TestSupport.expectEqual(FeedbackSoundPreference.load(.recordingStart, from: defaults), "Tink")
        TestSupport.expectEqual(FeedbackSoundPreference.load(.recordingStop, from: defaults), "Pop")
        TestSupport.expectEqual(FeedbackSoundPreference.load(.error, from: defaults), "Basso")
        for event in FeedbackSoundEvent.allCases {
            TestSupport.expect(defaults.object(forKey: event.storageKey) == nil, "Loading defaults must not persist a choice")
            TestSupport.expect(
                FeedbackSoundPreference.builtInSoundNames.contains(event.defaultSoundName),
                "Every default must be offered in the picker"
            )
        }
        TestSupport.expectEqual(
            Set(FeedbackSoundEvent.allCases.map(\.storageKey)).count,
            FeedbackSoundEvent.allCases.count
        )

        // Choices persist per event, including None.
        FeedbackSoundPreference.save("Glass", for: .recordingStart, to: defaults)
        FeedbackSoundPreference.save(FeedbackSoundPreference.noneValue, for: .recordingStop, to: defaults)
        let reloaded = UserDefaults(suiteName: suite)!
        TestSupport.expectEqual(FeedbackSoundPreference.load(.recordingStart, from: reloaded), "Glass")
        TestSupport.expectEqual(FeedbackSoundPreference.load(.recordingStop, from: reloaded), FeedbackSoundPreference.noneValue)
        TestSupport.expectEqual(FeedbackSoundPreference.load(.error, from: reloaded), "Basso")

        // Unrecognized stored values load as the default.
        defaults.set("Synthetic Missing Chime", forKey: FeedbackSoundEvent.error.storageKey)
        TestSupport.expectEqual(FeedbackSoundPreference.load(.error, from: defaults), "Basso")
        defaults.set(42, forKey: FeedbackSoundEvent.recordingStart.storageKey)
        TestSupport.expectEqual(FeedbackSoundPreference.load(.recordingStart, from: defaults), "Tink")
        FeedbackSoundPreference.save("Synthetic Missing Chime", for: .error, to: defaults)
        TestSupport.expect(defaults.object(forKey: FeedbackSoundEvent.error.storageKey) == nil, "Saving an unknown value must clear the choice")

        // Resolution: the selected sound when loadable.
        let everything: (String) -> String? = { $0 }
        TestSupport.expectEqual(FeedbackSoundPreference.resolve("Glass", for: .recordingStart, loader: everything), "Glass")
        TestSupport.expectEqual(FeedbackSoundPreference.resolve("Tink", for: .recordingStart, loader: everything), "Tink")

        // None is silent and never touches the loader.
        var loaderCalls = 0
        let counting: (String) -> String? = { loaderCalls += 1; return $0 }
        TestSupport.expect(
            FeedbackSoundPreference.resolve(FeedbackSoundPreference.noneValue, for: .error, loader: counting) == nil,
            "None must be silent"
        )
        TestSupport.expectEqual(loaderCalls, 0)

        // A selected sound macOS cannot load falls back to the default, not silence.
        let onlyDefaults: (String) -> String? = { name in
            FeedbackSoundEvent.allCases.contains { $0.defaultSoundName == name } ? name : nil
        }
        TestSupport.expectEqual(FeedbackSoundPreference.resolve("Glass", for: .recordingStart, loader: onlyDefaults), "Tink")
        TestSupport.expectEqual(FeedbackSoundPreference.resolve("Hero", for: .recordingStop, loader: onlyDefaults), "Pop")
        TestSupport.expectEqual(FeedbackSoundPreference.resolve("Frog", for: .error, loader: onlyDefaults), "Basso")

        // Off-catalog values are never handed to the loader.
        var requested: [String] = []
        let recording: (String) -> String? = { requested.append($0); return $0 }
        TestSupport.expectEqual(
            FeedbackSoundPreference.resolve("../Synthetic Path", for: .error, loader: recording),
            "Basso"
        )
        TestSupport.expectEqual(requested, ["Basso"])

        // If nothing can load, playback is skipped instead of crashing.
        let nothing: (String) -> String? = { _ in nil }
        TestSupport.expect(
            FeedbackSoundPreference.resolve("Glass", for: .recordingStart, loader: nothing) == nil,
            "Unloadable selection and default must resolve to nil"
        )

        TestSupport.expectEqual(FeedbackSoundPreference.displayName(for: FeedbackSoundPreference.noneValue), "None")
        TestSupport.expectEqual(FeedbackSoundPreference.displayName(for: "Purr"), "Purr")
    }
}
