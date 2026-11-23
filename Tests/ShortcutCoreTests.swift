import Foundation

enum ShortcutCoreTests {
    static func run() {
        testBareFnHoldLifecycle()
        testBareFnToggleStillConsumes()
        testFnHoldPassthroughUnlessToggleComboActive()
        testSnapshotRepairFnHoldDoesNotConsume()
        testDefaultShortcutSpecificityOrdering()
        testRightOptionPresetIsSideSpecific()
        testExactModifierMatching()
        testReducerHonorsExactModifierMatching()
        testRepeatedKeyDownDoesNotReactivate()
        testPasteAgainFiresOnLeadingEdgeOnly()
        testBackendResetClearsActiveBindings()
        testBindingMigrationAndIdentity()
        testConflictDetection()
        testHoldSessionControllerLifecycle()
        testToggleSessionControllerLifecycle()
        testHoldToToggleSessionControllerLifecycle()
        testDoubleTapIsOffByDefault()
        testDoubleTapLatchesAndHoldShortcutStops()
        testDoubleTapLatchedSessionStopsOnFirstToggleShortcutPress()
        testSingleTapStopsWhenDoubleTapWindowExpires()
        testLongHoldStopsImmediatelyWithDoubleTapEnabled()
        testToggleStartedSessionIgnoresHoldShortcut()
        testDoubleTapModifierChordThroughMatcher()
        testFnHoldStartDelayPolicy()
        testQuickFnTapCancelsPendingStart()
        testClaimedFnPressDecisionIsStickyPerPress()
        testBackendResetClearsFnClaim()
        testFnDoubleTapLockClaimsOnlyFollowUpPresses()
        testFnQuickTapPassesThroughWithDoubleTapEnabled()
    }

    private static func testBareFnHoldLifecycle() {
        let configuration = ShortcutConfiguration(hold: .defaultHold, toggle: .disabled)
        let down = ShortcutMatcher.reduce(
            state: ShortcutInputState(),
            event: .modifierChanged(keyCode: 63, isDown: true),
            configuration: configuration
        )
        let up = ShortcutMatcher.reduce(
            state: down.state,
            event: .modifierChanged(keyCode: 63, isDown: false),
            configuration: configuration
        )

        TestSupport.expectEqual(down.emittedEvents, [.holdActivated])
        // Fn hold-to-talk must not consume the key: macOS needs to see Fn
        // events for the system Globe action (e.g. Change Input Source).
        TestSupport.expectEqual(down.consumeDecision, .passthrough)
        TestSupport.expectEqual(up.emittedEvents, [.holdDeactivated])
        TestSupport.expectEqual(up.consumeDecision, .passthrough)
    }

    private static func testBareFnToggleStillConsumes() {
        let configuration = ShortcutConfiguration(
            hold: .disabled,
            toggle: ShortcutPreset.fnKey.binding
        )
        let down = ShortcutMatcher.reduce(
            state: ShortcutInputState(),
            event: .modifierChanged(keyCode: 63, isDown: true),
            configuration: configuration
        )

        // A Fn tap is meaningful to both FreeFlow (toggle dictation) and
        // macOS (Globe action); the user chose Fn for the toggle binding, so
        // FreeFlow keeps consuming it.
        TestSupport.expectEqual(down.emittedEvents, [.toggleActivated])
        TestSupport.expectEqual(down.consumeDecision, .consume)
    }

    private static func testFnHoldPassthroughUnlessToggleComboActive() {
        let configuration = ShortcutConfiguration(
            hold: .defaultHold,
            toggle: .defaultToggle
        )
        // Bare Fn: hold binding is excluded from consume decisions, and the
        // Cmd+Fn toggle is not active without Cmd, so the tap passes through.
        let fnDown = ShortcutMatcher.reduce(
            state: ShortcutInputState(),
            event: .modifierChanged(keyCode: 63, isDown: true),
            configuration: configuration
        )
        TestSupport.expectEqual(fnDown.emittedEvents, [.holdActivated])
        TestSupport.expectEqual(fnDown.consumeDecision, .passthrough)

        // With Cmd held, the Fn-down event activates the Cmd+Fn toggle and
        // Fn is consumed. Cmd down alone activates nothing and passes through.
        let cmdDown = ShortcutMatcher.reduce(
            state: ShortcutInputState(),
            event: .modifierChanged(keyCode: 55, isDown: true),
            configuration: configuration
        )
        TestSupport.expectEqual(cmdDown.emittedEvents, [])
        TestSupport.expectEqual(cmdDown.consumeDecision, .passthrough)

        let fnDownWithCmd = ShortcutMatcher.reduce(
            state: cmdDown.state,
            event: .modifierChanged(keyCode: 63, isDown: true),
            configuration: configuration
        )
        TestSupport.expectEqual(fnDownWithCmd.emittedEvents, [.toggleActivated, .holdActivated])
        TestSupport.expectEqual(fnDownWithCmd.consumeDecision, .consume)
    }

    private static func testSnapshotRepairFnHoldDoesNotConsume() {
        // A snapshot that suddenly reports Fn as pressed (e.g. the event tap
        // missed the Fn flagsChanged while disabled) repairs hold state; the
        // ordinary key event carrying the snapshot must not be swallowed.
        let configuration = ShortcutConfiguration(hold: .defaultHold, toggle: .disabled)
        let repaired = ShortcutMatcher.reduce(
            state: ShortcutInputState(),
            event: .modifierSnapshot([63]),
            configuration: configuration
        )
        TestSupport.expectEqual(repaired.emittedEvents, [.holdActivated])
        TestSupport.expectEqual(repaired.consumeDecision, .passthrough)

        // Non-Fn hold bindings keep their existing edge-consumption behavior.
        let optionConfiguration = ShortcutConfiguration(
            hold: ShortcutPreset.rightOption.binding,
            toggle: .disabled
        )
        let optionRepaired = ShortcutMatcher.reduce(
            state: ShortcutInputState(),
            event: .modifierSnapshot([61]),
            configuration: optionConfiguration
        )
        TestSupport.expectEqual(optionRepaired.emittedEvents, [.holdActivated])
        TestSupport.expectEqual(optionRepaired.consumeDecision, .consume)
    }

    private static func testDefaultShortcutSpecificityOrdering() {
        let configuration = ShortcutConfiguration(
            hold: .defaultHold,
            toggle: .defaultToggle
        )
        let commandDown = ShortcutMatcher.reduce(
            state: ShortcutInputState(),
            event: .modifierChanged(keyCode: 55, isDown: true),
            configuration: configuration
        )
        let fnDown = ShortcutMatcher.reduce(
            state: commandDown.state,
            event: .modifierChanged(keyCode: 63, isDown: true),
            configuration: configuration
        )
        let fnUp = ShortcutMatcher.reduce(
            state: fnDown.state,
            event: .modifierChanged(keyCode: 63, isDown: false),
            configuration: configuration
        )

        TestSupport.expectEqual(fnDown.emittedEvents, [.toggleActivated, .holdActivated])
        TestSupport.expectEqual(fnUp.emittedEvents, [.holdDeactivated, .toggleDeactivated])
    }

    private static func testRightOptionPresetIsSideSpecific() {
        let configuration = ShortcutConfiguration(
            hold: ShortcutPreset.rightOption.binding,
            toggle: .disabled
        )
        let leftOption = ShortcutMatcher.reduce(
            state: ShortcutInputState(),
            event: .modifierChanged(keyCode: 58, isDown: true),
            configuration: configuration
        )
        let rightOption = ShortcutMatcher.reduce(
            state: ShortcutInputState(),
            event: .modifierChanged(keyCode: 61, isDown: true),
            configuration: configuration
        )

        TestSupport.expectEqual(leftOption.emittedEvents, [])
        TestSupport.expectEqual(rightOption.emittedEvents, [.holdActivated])
    }

    private static func testExactModifierMatching() {
        TestSupport.expect(
            ShortcutBinding.exactModifierKeyCodesMatch([54], exactModifierKeyCodes: [54, 55]),
            "A generic Command binding should accept Right Command"
        )
        TestSupport.expect(
            ShortcutBinding.exactModifierKeyCodesMatch([55], exactModifierKeyCodes: [54, 55]),
            "A generic Command binding should accept Left Command"
        )
        TestSupport.expect(
            !ShortcutBinding.exactModifierKeyCodesMatch([55, 56], exactModifierKeyCodes: [55]),
            "Unexpected Shift should invalidate an exact Command binding"
        )
        TestSupport.expect(
            ShortcutBinding.exactModifierKeyCodesMatch(
                [55, 56],
                exactModifierKeyCodes: [55],
                permittedAdditionalExactMatchModifiers: [.shift]
            ),
            "Explicitly permitted Shift should not invalidate an exact Command binding"
        )
    }

    private static func testReducerHonorsExactModifierMatching() {
        let binding = ShortcutBinding(
            keyCode: 96,
            keyDisplay: "F5",
            modifiers: [.command],
            kind: .key,
            preset: nil,
            exactModifierKeyCodes: [55]
        )

        let rightCommandState = ShortcutMatcher.reduce(
            state: ShortcutInputState(),
            event: .modifierChanged(keyCode: 54, isDown: true),
            configuration: ShortcutConfiguration(hold: binding, toggle: .disabled)
        ).state
        let rightCommandKey = ShortcutMatcher.reduce(
            state: rightCommandState,
            event: .keyChanged(keyCode: 96, isDown: true, isRepeat: false),
            configuration: ShortcutConfiguration(hold: binding, toggle: .disabled)
        )
        TestSupport.expectEqual(rightCommandKey.emittedEvents, [])

        let leftCommandState = ShortcutMatcher.reduce(
            state: ShortcutInputState(),
            event: .modifierChanged(keyCode: 55, isDown: true),
            configuration: ShortcutConfiguration(hold: binding, toggle: .disabled)
        ).state
        let leftCommandKey = ShortcutMatcher.reduce(
            state: leftCommandState,
            event: .keyChanged(keyCode: 96, isDown: true, isRepeat: false),
            configuration: ShortcutConfiguration(hold: binding, toggle: .disabled)
        )
        TestSupport.expectEqual(leftCommandKey.emittedEvents, [.holdActivated])

        let shiftedState = ShortcutMatcher.reduce(
            state: leftCommandState,
            event: .modifierChanged(keyCode: 56, isDown: true),
            configuration: ShortcutConfiguration(hold: binding, toggle: .disabled)
        ).state
        let shiftedKey = ShortcutMatcher.reduce(
            state: shiftedState,
            event: .keyChanged(keyCode: 96, isDown: true, isRepeat: false),
            configuration: ShortcutConfiguration(hold: binding, toggle: .disabled)
        )
        TestSupport.expectEqual(shiftedKey.emittedEvents, [])

        let permittedConfiguration = ShortcutConfiguration(
            hold: binding,
            toggle: .disabled,
            permittedAdditionalExactMatchModifiers: [.shift]
        )
        let permittedKey = ShortcutMatcher.reduce(
            state: shiftedState,
            event: .keyChanged(keyCode: 96, isDown: true, isRepeat: false),
            configuration: permittedConfiguration
        )
        TestSupport.expectEqual(permittedKey.emittedEvents, [.holdActivated])
    }

    private static func testRepeatedKeyDownDoesNotReactivate() {
        let binding = ShortcutBinding(
            keyCode: 96,
            keyDisplay: "F5",
            modifiers: [],
            kind: .key,
            preset: nil
        )
        let configuration = ShortcutConfiguration(hold: binding, toggle: .disabled)
        let first = ShortcutMatcher.reduce(
            state: ShortcutInputState(),
            event: .keyChanged(keyCode: 96, isDown: true, isRepeat: false),
            configuration: configuration
        )
        let repeated = ShortcutMatcher.reduce(
            state: first.state,
            event: .keyChanged(keyCode: 96, isDown: true, isRepeat: true),
            configuration: configuration
        )

        TestSupport.expectEqual(first.emittedEvents, [.holdActivated])
        TestSupport.expectEqual(repeated.emittedEvents, [])
        TestSupport.expectEqual(repeated.state, first.state)
        TestSupport.expectEqual(repeated.consumeDecision, .consume)
    }

    private static func testPasteAgainFiresOnLeadingEdgeOnly() {
        let binding = ShortcutBinding(
            keyCode: 96,
            keyDisplay: "F5",
            modifiers: [],
            kind: .key,
            preset: nil
        )
        let configuration = ShortcutConfiguration(hold: .disabled, toggle: .disabled, copyAgain: binding)
        let firstDown = ShortcutMatcher.reduce(
            state: ShortcutInputState(),
            event: .keyChanged(keyCode: 96, isDown: true, isRepeat: false),
            configuration: configuration
        )
        let repeated = ShortcutMatcher.reduce(
            state: firstDown.state,
            event: .keyChanged(keyCode: 96, isDown: true, isRepeat: true),
            configuration: configuration
        )
        let up = ShortcutMatcher.reduce(
            state: repeated.state,
            event: .keyChanged(keyCode: 96, isDown: false, isRepeat: false),
            configuration: configuration
        )
        let secondDown = ShortcutMatcher.reduce(
            state: up.state,
            event: .keyChanged(keyCode: 96, isDown: true, isRepeat: false),
            configuration: configuration
        )

        TestSupport.expectEqual(firstDown.emittedEvents, [.copyAgainTriggered])
        TestSupport.expectEqual(repeated.emittedEvents, [])
        TestSupport.expectEqual(up.emittedEvents, [])
        TestSupport.expectEqual(secondDown.emittedEvents, [.copyAgainTriggered])
    }

    private static func testBackendResetClearsActiveBindings() {
        let configuration = ShortcutConfiguration(hold: .defaultHold, toggle: .defaultToggle)
        let commandDown = ShortcutMatcher.reduce(
            state: ShortcutInputState(),
            event: .modifierChanged(keyCode: 55, isDown: true),
            configuration: configuration
        )
        let fnDown = ShortcutMatcher.reduce(
            state: commandDown.state,
            event: .modifierChanged(keyCode: 63, isDown: true),
            configuration: configuration
        )
        let reset = ShortcutMatcher.reduce(
            state: fnDown.state,
            event: .backendReset,
            configuration: configuration
        )

        TestSupport.expectEqual(reset.emittedEvents, [.holdDeactivated, .toggleDeactivated])
        TestSupport.expectEqual(reset.consumeDecision, .passthrough)
        TestSupport.expect(reset.state.pressedKeyCodes.isEmpty, "Backend reset should clear pressed keys")
        TestSupport.expect(reset.state.pressedModifierKeyCodes.isEmpty, "Backend reset should clear modifiers")
        TestSupport.expect(!reset.state.holdIsActive && !reset.state.toggleIsActive, "Backend reset should clear active bindings")
    }

    private static func testBindingMigrationAndIdentity() {
        let stored = ShortcutBinding(
            keyCode: 96,
            keyDisplay: "F5",
            modifiers: [],
            kind: .key,
            preset: nil,
            exactModifierKeyCodes: [999, 61]
        )
        let normalized = stored.normalizedForStorageMigration()
        TestSupport.expectEqual(normalized.exactModifierKeyCodes, [61])
        TestSupport.expectEqual(normalized.modifiers, [.option])

        let first = ShortcutBinding(
            keyCode: 96,
            keyDisplay: "F5",
            modifiers: [.command, .option],
            kind: .key,
            preset: nil,
            exactModifierKeyCodes: [55, 58]
        )
        let second = ShortcutBinding(
            keyCode: 96,
            keyDisplay: "F5",
            modifiers: [.option, .command],
            kind: .key,
            preset: nil,
            exactModifierKeyCodes: [58, 55]
        )
        TestSupport.expectEqual(first.id, second.id)
    }

    private static func testConflictDetection() {
        let first = ShortcutBinding(
            keyCode: 96,
            keyDisplay: "F5",
            modifiers: [.command],
            kind: .key,
            preset: nil
        )
        let same = ShortcutBinding(
            keyCode: 96,
            keyDisplay: "F5",
            modifiers: [.command],
            kind: .key,
            preset: nil
        )
        let different = ShortcutBinding(
            keyCode: 97,
            keyDisplay: "F6",
            modifiers: [.command],
            kind: .key,
            preset: nil
        )

        TestSupport.expect(first.conflicts(with: same), "Equivalent bindings should conflict")
        TestSupport.expect(same.conflicts(with: first), "Conflict detection should be symmetric")
        TestSupport.expect(!first.conflicts(with: different), "Different primary keys should not conflict")
        TestSupport.expect(!first.conflicts(with: .disabled), "Disabled bindings should not conflict")
    }

    private static func testHoldSessionControllerLifecycle() {
        let controller = DictationShortcutSessionController()
        TestSupport.expectEqual(controller.handle(event: .holdActivated, isTranscribing: true), nil)
        TestSupport.expectEqual(controller.handle(event: .holdActivated, isTranscribing: false), .start(.hold))
        TestSupport.expectEqual(controller.handle(event: .holdDeactivated, isTranscribing: false), .stop)
        TestSupport.expectEqual(controller.activeMode, nil)
    }

    private static func testToggleSessionControllerLifecycle() {
        let controller = DictationShortcutSessionController()
        TestSupport.expectEqual(controller.handle(event: .toggleActivated, isTranscribing: false), .start(.toggle))
        TestSupport.expectEqual(controller.handle(event: .toggleActivated, isTranscribing: false), nil)
        TestSupport.expectEqual(controller.handle(event: .toggleDeactivated, isTranscribing: false), nil)
        TestSupport.expectEqual(controller.toggleStopArmed, true)
        TestSupport.expectEqual(controller.handle(event: .toggleActivated, isTranscribing: false), .stop)
        TestSupport.expectEqual(controller.activeMode, nil)
    }

    private static func testHoldToToggleSessionControllerLifecycle() {
        let controller = DictationShortcutSessionController()
        TestSupport.expectEqual(controller.handle(event: .holdActivated, isTranscribing: false), .start(.hold))
        TestSupport.expectEqual(controller.handle(event: .toggleActivated, isTranscribing: false), .switchedToToggle)
        TestSupport.expectEqual(controller.handle(event: .holdDeactivated, isTranscribing: false), nil)
        TestSupport.expectEqual(controller.activeMode, .toggle)
        TestSupport.expectEqual(controller.handle(event: .copyAgainTriggered, isTranscribing: false), nil)
        controller.beginManual(mode: .hold)
        TestSupport.expectEqual(controller.activeMode, .hold)
        controller.forceToggleMode()
        TestSupport.expectEqual(controller.activeMode, .toggle)
        controller.reset()
        TestSupport.expectEqual(controller.activeMode, nil)
        TestSupport.expectEqual(controller.toggleStopArmed, false)
    }

    private static func doubleTapHandle(
        _ controller: DictationShortcutSessionController,
        _ event: ShortcutEvent,
        at now: TimeInterval
    ) -> DictationShortcutAction? {
        controller.handle(event: event, isTranscribing: false, doubleTapToToggleEnabled: true, now: now)
    }

    private static func testDoubleTapIsOffByDefault() {
        let controller = DictationShortcutSessionController()
        TestSupport.expectEqual(controller.handle(event: .holdActivated, isTranscribing: false, now: 0), .start(.hold))
        TestSupport.expectEqual(controller.handle(event: .holdDeactivated, isTranscribing: false, now: 0.1), .stop)
        TestSupport.expectEqual(controller.handle(event: .holdActivated, isTranscribing: false, now: 0.2), .start(.hold))
    }

    private static func testDoubleTapLatchesAndHoldShortcutStops() {
        let controller = DictationShortcutSessionController()
        TestSupport.expectEqual(doubleTapHandle(controller, .holdActivated, at: 0), .start(.hold))
        TestSupport.expectEqual(
            doubleTapHandle(controller, .holdDeactivated, at: 0.1),
            .awaitDoubleTap(DictationShortcutSessionController.doubleTapWindow)
        )
        TestSupport.expectEqual(controller.activeMode, .hold)
        TestSupport.expectEqual(doubleTapHandle(controller, .holdActivated, at: 0.2), .switchedToToggle)
        TestSupport.expectEqual(controller.activeMode, .toggle)
        TestSupport.expectEqual(controller.handleDoubleTapTimeout(), nil)
        TestSupport.expectEqual(doubleTapHandle(controller, .holdDeactivated, at: 0.3), nil)
        TestSupport.expectEqual(controller.activeMode, .toggle)
        TestSupport.expectEqual(doubleTapHandle(controller, .holdActivated, at: 5), .stop)
        TestSupport.expectEqual(controller.activeMode, nil)
        TestSupport.expectEqual(doubleTapHandle(controller, .holdDeactivated, at: 5.1), nil)
    }

    private static func testDoubleTapLatchedSessionStopsOnFirstToggleShortcutPress() {
        let controller = DictationShortcutSessionController()
        _ = doubleTapHandle(controller, .holdActivated, at: 0)
        _ = doubleTapHandle(controller, .holdDeactivated, at: 0.1)
        _ = doubleTapHandle(controller, .holdActivated, at: 0.2)
        _ = doubleTapHandle(controller, .holdDeactivated, at: 0.3)
        TestSupport.expectEqual(doubleTapHandle(controller, .toggleActivated, at: 5), .stop)
    }

    private static func testSingleTapStopsWhenDoubleTapWindowExpires() {
        let controller = DictationShortcutSessionController()
        _ = doubleTapHandle(controller, .holdActivated, at: 0)
        _ = doubleTapHandle(controller, .holdDeactivated, at: 0.1)
        TestSupport.expectEqual(controller.handleDoubleTapTimeout(), .stop)
        TestSupport.expectEqual(controller.activeMode, nil)
        TestSupport.expectEqual(controller.handleDoubleTapTimeout(), nil)
    }

    private static func testLongHoldStopsImmediatelyWithDoubleTapEnabled() {
        let controller = DictationShortcutSessionController()
        _ = doubleTapHandle(controller, .holdActivated, at: 0)
        TestSupport.expectEqual(doubleTapHandle(controller, .holdDeactivated, at: 1), .stop)
    }

    private static func testToggleStartedSessionIgnoresHoldShortcut() {
        let controller = DictationShortcutSessionController()
        _ = doubleTapHandle(controller, .toggleActivated, at: 0)
        TestSupport.expectEqual(doubleTapHandle(controller, .holdActivated, at: 1), nil)
        TestSupport.expectEqual(doubleTapHandle(controller, .holdDeactivated, at: 1.1), nil)
        TestSupport.expectEqual(doubleTapHandle(controller, .holdActivated, at: 2), nil)
        TestSupport.expectEqual(controller.activeMode, .toggle)
    }

    /// Option stays down while only the grave key is tapped twice.
    private static func testDoubleTapModifierChordThroughMatcher() {
        let optionKeyCode: UInt16 = 58
        let graveKeyCode: UInt16 = 50
        let configuration = ShortcutConfiguration(
            hold: ShortcutBinding(keyCode: graveKeyCode, keyDisplay: "`", modifiers: [.option], kind: .key, preset: nil),
            toggle: .disabled
        )
        let controller = DictationShortcutSessionController()
        var state = ShortcutInputState()
        var actions: [DictationShortcutAction] = []
        var now: TimeInterval = 0

        let inputs: [ShortcutInputEvent] = [
            .modifierChanged(keyCode: optionKeyCode, isDown: true),
            .keyChanged(keyCode: graveKeyCode, isDown: true, isRepeat: false),
            .keyChanged(keyCode: graveKeyCode, isDown: false, isRepeat: false),
            .keyChanged(keyCode: graveKeyCode, isDown: true, isRepeat: false),
            .keyChanged(keyCode: graveKeyCode, isDown: false, isRepeat: false),
            .modifierChanged(keyCode: optionKeyCode, isDown: false),
        ]
        for input in inputs {
            let result = ShortcutMatcher.reduce(state: state, event: input, configuration: configuration)
            state = result.state
            for event in result.emittedEvents {
                if let action = doubleTapHandle(controller, event, at: now) {
                    actions.append(action)
                }
            }
            now += 0.1
        }

        TestSupport.expectEqual(actions, [
            .start(.hold),
            .awaitDoubleTap(DictationShortcutSessionController.doubleTapWindow),
            .switchedToToggle,
        ])
        TestSupport.expectEqual(controller.activeMode, .toggle)
    }

    private static func testFnHoldStartDelayPolicy() {
        let floor = ShortcutStartDelayPolicy.minimumFnHoldStartDelay
        TestSupport.expectApproximatelyEqual(floor, 0.2)

        // Fn hold gets the 200 ms floor when the configured delay is shorter.
        TestSupport.expectApproximatelyEqual(
            ShortcutStartDelayPolicy.effectiveDelay(for: .hold, holdBinding: .defaultHold, configuredDelay: 0),
            floor
        )
        TestSupport.expectApproximatelyEqual(
            ShortcutStartDelayPolicy.effectiveDelay(for: .hold, holdBinding: .defaultHold, configuredDelay: 0.1),
            floor
        )
        // A longer user delay is kept.
        TestSupport.expectApproximatelyEqual(
            ShortcutStartDelayPolicy.effectiveDelay(for: .hold, holdBinding: .defaultHold, configuredDelay: 0.5),
            0.5
        )
        // A hold binding that only uses Fn as a modifier also gets the floor.
        let fnSpace = ShortcutBinding(keyCode: 49, keyDisplay: "Space", modifiers: [.function], kind: .key, preset: nil)
        TestSupport.expectApproximatelyEqual(
            ShortcutStartDelayPolicy.effectiveDelay(for: .hold, holdBinding: fnSpace, configuredDelay: 0),
            floor
        )
        // Non-Fn hold bindings keep their configured delay.
        let rightOption = ShortcutPreset.rightOption.binding
        TestSupport.expectApproximatelyEqual(
            ShortcutStartDelayPolicy.effectiveDelay(for: .hold, holdBinding: rightOption, configuredDelay: 0),
            0
        )
        TestSupport.expectApproximatelyEqual(
            ShortcutStartDelayPolicy.effectiveDelay(for: .hold, holdBinding: rightOption, configuredDelay: 0.15),
            0.15
        )
        // Toggle starts are not affected by the Fn hold floor.
        TestSupport.expectApproximatelyEqual(
            ShortcutStartDelayPolicy.effectiveDelay(for: .toggle, holdBinding: .defaultHold, configuredDelay: 0),
            0
        )
        TestSupport.expectApproximatelyEqual(
            ShortcutStartDelayPolicy.effectiveDelay(for: .toggle, holdBinding: .defaultHold, configuredDelay: 0.3),
            0.3
        )
        // A disabled hold binding does not count as Fn.
        TestSupport.expectApproximatelyEqual(
            ShortcutStartDelayPolicy.effectiveDelay(for: .hold, holdBinding: .disabled, configuredDelay: 0),
            0
        )
    }

    /// A Fn tap released before the start-delay floor ends the session
    /// before recording can start, so AppState cancels the pending start.
    private static func testQuickFnTapCancelsPendingStart() {
        let delay = ShortcutStartDelayPolicy.effectiveDelay(
            for: .hold,
            holdBinding: .defaultHold,
            configuredDelay: 0
        )
        let releaseAt: TimeInterval = 0.1
        TestSupport.expect(releaseAt < delay, "Quick tap must release before the Fn start floor")

        let controller = DictationShortcutSessionController()
        TestSupport.expectEqual(controller.handle(event: .holdActivated, isTranscribing: false, now: 0), .start(.hold))
        TestSupport.expectEqual(
            controller.handle(event: .holdDeactivated, isTranscribing: false, now: releaseAt),
            .stop
        )
        TestSupport.expectEqual(controller.activeMode, nil)
        TestSupport.expectEqual(controller.claimsHoldShortcutPresses, false)
    }

    private static func testClaimedFnPressDecisionIsStickyPerPress() {
        let configuration = ShortcutConfiguration(hold: .defaultHold, toggle: .disabled)

        // Unclaimed on down: the matching up passes through even if the
        // caller starts claiming mid-press.
        let down = ShortcutMatcher.reduce(
            state: ShortcutInputState(),
            event: .modifierChanged(keyCode: 63, isDown: true),
            configuration: configuration,
            claimFnHoldPress: false
        )
        let up = ShortcutMatcher.reduce(
            state: down.state,
            event: .modifierChanged(keyCode: 63, isDown: false),
            configuration: configuration,
            claimFnHoldPress: true
        )
        TestSupport.expectEqual(down.consumeDecision, .passthrough)
        TestSupport.expectEqual(up.emittedEvents, [.holdDeactivated])
        TestSupport.expectEqual(up.consumeDecision, .passthrough)

        // Claimed on down: the matching up is consumed even if the claim
        // ends mid-press, so macOS never sees half a Fn press.
        let claimedDown = ShortcutMatcher.reduce(
            state: ShortcutInputState(),
            event: .modifierChanged(keyCode: 63, isDown: true),
            configuration: configuration,
            claimFnHoldPress: true
        )
        TestSupport.expectEqual(claimedDown.emittedEvents, [.holdActivated])
        TestSupport.expectEqual(claimedDown.consumeDecision, .consume)
        let claimedUp = ShortcutMatcher.reduce(
            state: claimedDown.state,
            event: .modifierChanged(keyCode: 63, isDown: false),
            configuration: configuration,
            claimFnHoldPress: false
        )
        TestSupport.expectEqual(claimedUp.emittedEvents, [.holdDeactivated])
        TestSupport.expectEqual(claimedUp.consumeDecision, .consume)
        TestSupport.expectEqual(claimedUp.state.fnPressIsClaimedByHold, false)

        // The claim only affects Fn; other hold keys are unchanged.
        let optionConfiguration = ShortcutConfiguration(hold: ShortcutPreset.rightOption.binding, toggle: .disabled)
        let optionDown = ShortcutMatcher.reduce(
            state: ShortcutInputState(),
            event: .modifierChanged(keyCode: 61, isDown: true),
            configuration: optionConfiguration,
            claimFnHoldPress: false
        )
        TestSupport.expectEqual(optionDown.consumeDecision, .consume)
    }

    private static func testBackendResetClearsFnClaim() {
        let configuration = ShortcutConfiguration(hold: .defaultHold, toggle: .disabled)
        let claimedDown = ShortcutMatcher.reduce(
            state: ShortcutInputState(),
            event: .modifierChanged(keyCode: 63, isDown: true),
            configuration: configuration,
            claimFnHoldPress: true
        )
        let reset = ShortcutMatcher.reduce(
            state: claimedDown.state,
            event: .backendReset,
            configuration: configuration
        )
        TestSupport.expectEqual(reset.state.fnPressIsClaimedByHold, false)
        TestSupport.expectEqual(reset.emittedEvents, [.holdDeactivated])
    }

    private struct FnPressStep: Equatable {
        let isDown: Bool
        let consumeDecision: ShortcutConsumeDecision
        let actions: [DictationShortcutAction]
    }

    /// Runs bare Fn presses through the matcher and the session controller the
    /// way AppState wires them: the claim is read from the controller at each
    /// Fn event, and emitted events feed the controller.
    private static func runFnPresses(
        _ presses: [(down: TimeInterval, up: TimeInterval)],
        controller: DictationShortcutSessionController
    ) -> [FnPressStep] {
        let configuration = ShortcutConfiguration(hold: .defaultHold, toggle: .defaultToggle)
        var state = ShortcutInputState()
        var steps: [FnPressStep] = []
        for press in presses {
            for (isDown, now) in [(true, press.down), (false, press.up)] {
                let result = ShortcutMatcher.reduce(
                    state: state,
                    event: .modifierChanged(keyCode: 63, isDown: isDown),
                    configuration: configuration,
                    claimFnHoldPress: controller.claimsHoldShortcutPresses
                )
                state = result.state
                let actions = result.emittedEvents.compactMap { doubleTapHandle(controller, $0, at: now) }
                steps.append(FnPressStep(isDown: isDown, consumeDecision: result.consumeDecision, actions: actions))
            }
        }
        return steps
    }

    /// Double tap on Fn locks recording. The first tap is indistinguishable
    /// from a Globe tap and reaches macOS; the latching press and the press
    /// that stops the locked recording belong to FreeFlow and are consumed.
    private static func testFnDoubleTapLockClaimsOnlyFollowUpPresses() {
        let controller = DictationShortcutSessionController()
        let steps = runFnPresses(
            [(down: 0, up: 0.1), (down: 0.25, up: 0.35), (down: 5, up: 5.1), (down: 8, up: 8.1)],
            controller: controller
        )

        TestSupport.expectEqual(steps, [
            // First tap: passes through to macOS.
            FnPressStep(isDown: true, consumeDecision: .passthrough, actions: [.start(.hold)]),
            FnPressStep(
                isDown: false,
                consumeDecision: .passthrough,
                actions: [.awaitDoubleTap(DictationShortcutSessionController.doubleTapWindow)]
            ),
            // Second press latches and is claimed for its whole down/up pair.
            FnPressStep(isDown: true, consumeDecision: .consume, actions: [.switchedToToggle]),
            FnPressStep(isDown: false, consumeDecision: .consume, actions: []),
            // Stop press is claimed, including the release after the session ends.
            FnPressStep(isDown: true, consumeDecision: .consume, actions: [.stop]),
            FnPressStep(isDown: false, consumeDecision: .consume, actions: []),
            // Next ordinary tap passes through again.
            FnPressStep(isDown: true, consumeDecision: .passthrough, actions: [.start(.hold)]),
            FnPressStep(
                isDown: false,
                consumeDecision: .passthrough,
                actions: [.awaitDoubleTap(DictationShortcutSessionController.doubleTapWindow)]
            ),
        ])
        TestSupport.expectEqual(controller.claimsHoldShortcutPresses, true)
        TestSupport.expectEqual(controller.handleDoubleTapTimeout(), .stop)
        TestSupport.expectEqual(controller.claimsHoldShortcutPresses, false)
    }

    /// With double tap enabled, a single quick Fn tap still reaches macOS and
    /// ends without recording once the double-tap window expires. A long hold
    /// also passes through and stops on release.
    private static func testFnQuickTapPassesThroughWithDoubleTapEnabled() {
        let controller = DictationShortcutSessionController()
        let tap = runFnPresses([(down: 0, up: 0.1)], controller: controller)
        TestSupport.expectEqual(tap.map(\.consumeDecision), [.passthrough, .passthrough])
        TestSupport.expectEqual(controller.handleDoubleTapTimeout(), .stop)
        TestSupport.expectEqual(controller.claimsHoldShortcutPresses, false)

        let hold = runFnPresses([(down: 1, up: 3)], controller: controller)
        TestSupport.expectEqual(hold, [
            FnPressStep(isDown: true, consumeDecision: .passthrough, actions: [.start(.hold)]),
            FnPressStep(isDown: false, consumeDecision: .passthrough, actions: [.stop]),
        ])
        TestSupport.expectEqual(controller.claimsHoldShortcutPresses, false)
    }
}
