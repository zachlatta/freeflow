import Foundation

enum ShortcutCleanupPreferenceTests {
    static func run() {
        let suite = "FreeFlowTests.ShortcutCleanup.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        for mode in [RecordingTriggerMode.hold, .toggle] {
            let key = ShortcutCleanupPreference.storageKey(for: mode)
            TestSupport.expectEqual(ShortcutCleanupPreference.load(from: defaults, key: key), .inherit)
            TestSupport.expect(defaults.object(forKey: key) == nil, "A missing shortcut choice must inherit without being saved")

            for preference in ShortcutCleanupPreference.allCases {
                preference.save(to: defaults, key: key)
                let reloaded = UserDefaults(suiteName: suite)!
                TestSupport.expectEqual(ShortcutCleanupPreference.load(from: reloaded, key: key), preference)
            }
        }

        defaults.set("invalid", forKey: ShortcutCleanupPreference.holdStorageKey)
        TestSupport.expectEqual(
            ShortcutCleanupPreference.load(from: defaults, key: ShortcutCleanupPreference.holdStorageKey),
            .inherit
        )

        for global in [false, true] {
            for mode in [RecordingTriggerMode.hold, .toggle] {
                var session = ShortcutCleanupSession()
                let value = session.start(
                    origin: .shortcut(mode),
                    globalPreserveExactWording: global,
                    holdPreference: .inherit,
                    togglePreference: .inherit
                )
                TestSupport.expect(value == global, "Inherited shortcut preference must use the global setting")
                TestSupport.expectEqual(session.preserveExactWording, global)
            }
        }

        for mode in [RecordingTriggerMode.hold, .toggle] {
            let overrideCases: [(ShortcutCleanupPreference, ShortcutCleanupPreference, Bool)] = [
                (ShortcutCleanupPreference.preserveExactWording, .cleanup, true),
                (.cleanup, .preserveExactWording, false)
            ]
            for (selectedPreference, otherPreference, expected) in overrideCases {
                let (holdPreference, togglePreference) = mode == .hold
                    ? (selectedPreference, otherPreference)
                    : (otherPreference, selectedPreference)
                var session = ShortcutCleanupSession()
                let value = session.start(
                    origin: .shortcut(mode),
                    globalPreserveExactWording: !expected,
                    holdPreference: holdPreference,
                    togglePreference: togglePreference
                )
                TestSupport.expect(value == expected, "Shortcut override must win over the global setting")
            }
        }

        for global in [false, true] {
            var menuSession = ShortcutCleanupSession()
            TestSupport.expect(
                menuSession.start(
                    origin: .menu,
                    globalPreserveExactWording: global,
                    holdPreference: .preserveExactWording,
                    togglePreference: .cleanup
                ) == global,
                "Menu-bar dictation must keep using the global setting"
            )
        }

        var session = ShortcutCleanupSession()
        let controller = DictationShortcutSessionController()
        var globalPreference = true
        var holdPreference = ShortcutCleanupPreference.inherit
        var togglePreference = ShortcutCleanupPreference.preserveExactWording

        TestSupport.expectEqual(
            controller.handle(event: .holdActivated, isTranscribing: false),
            .start(.hold)
        )
        let holdChoice = session.start(
            origin: .shortcut(.hold),
            globalPreserveExactWording: globalPreference,
            holdPreference: holdPreference,
            togglePreference: togglePreference
        )

        globalPreference = false
        holdPreference = .preserveExactWording
        togglePreference = .cleanup
        TestSupport.expectEqual(
            controller.handle(event: .toggleActivated, isTranscribing: false),
            .switchedToToggle
        )
        TestSupport.expect(
            session.preserveExactWording == holdChoice,
            "Hold-to-toggle must keep the choice captured at recording start"
        )
        TestSupport.expectEqual(controller.handle(event: .toggleDeactivated, isTranscribing: false), nil)
        TestSupport.expectEqual(
            controller.handle(event: .toggleActivated, isTranscribing: false),
            .stop
        )

        session.reset()
        TestSupport.expect(session.preserveExactWording == nil, "Stopping the session must clear the active choice")
        TestSupport.expectEqual(
            controller.handle(event: .toggleActivated, isTranscribing: false),
            .start(.toggle)
        )
        TestSupport.expect(
            session.start(
                origin: .shortcut(.toggle),
                globalPreserveExactWording: globalPreference,
                holdPreference: holdPreference,
                togglePreference: togglePreference
            ) == false,
            "A new session must use preferences changed after the previous recording started"
        )

        controller.reset()
        session.reset()
        TestSupport.expect(session.preserveExactWording == nil, "Cancellation must clear the active choice")
        TestSupport.expectEqual(controller.handle(event: .holdActivated, isTranscribing: false), .start(.hold))
        TestSupport.expect(
            session.start(
                origin: .shortcut(.hold),
                globalPreserveExactWording: globalPreference,
                holdPreference: holdPreference,
                togglePreference: togglePreference
            ),
            "A session after cancellation must use its own current preference"
        )
    }
}
