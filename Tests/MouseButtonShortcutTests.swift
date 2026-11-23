import Foundation

/// Mouse-button shortcut rules. Button numbers are zero-based (0 = left,
/// 1 = right, 2 = middle, 3+ = side buttons). All inputs are synthetic.
enum MouseButtonShortcutTests {
    private static let leftCommand: UInt16 = 55
    private static let leftShift: UInt16 = 56
    private static let backButton = 3
    private static let forwardButton = 4

    static func run() {
        testOnlyMiddleAndSideButtonsCanBeCaptured()
        testBareMouseHoldLifecycleConsumesPressAndRelease()
        testUnboundMouseButtonsPassThrough()
        testUnsupportedStoredMouseBindingNeverFires()
        testMouseBindingWithModifiersRequiresExactModifiers()
        testBareMouseBindingDoesNotFireWithModifiersHeld()
        testReleaseIsConsumedOnlyWhenPressWasConsumed()
        testMouseBindingNeverConsumesModifierEvents()
        testHoldAndToggleOnDistinctMouseButtons()
        testBackendResetReleasesMouseHold()
        testHasPressedShortcutInputsIncludesBoundMouseButton()
        testMouseConflictRule()
        testUsesFnKeyIgnoresMouseButtonNumber()
        testDecodesLegacyStoredBindings()
        testMouseBindingRoundTripsThroughCodable()
        testDoubleTapMouseHoldLatchesToggle()
    }

    private static func mouse(_ button: Int, modifiers: Set<UInt16> = []) -> ShortcutBinding {
        guard let binding = ShortcutBinding.fromMouseButton(button, pressedModifierKeyCodes: modifiers) else {
            fatalError("Expected a supported mouse button")
        }
        return binding
    }

    private static func run(
        _ inputs: [ShortcutInputEvent],
        configuration: ShortcutConfiguration,
        from state: ShortcutInputState = ShortcutInputState()
    ) -> [ShortcutMatchResult] {
        var state = state
        return inputs.map { input in
            let result = ShortcutMatcher.reduce(state: state, event: input, configuration: configuration)
            state = result.state
            return result
        }
    }

    private static func testOnlyMiddleAndSideButtonsCanBeCaptured() {
        TestSupport.expect(ShortcutBinding.fromMouseButton(0, pressedModifierKeyCodes: []) == nil, "Left click must not be capturable")
        TestSupport.expect(ShortcutBinding.fromMouseButton(1, pressedModifierKeyCodes: []) == nil, "Right click must not be capturable")
        TestSupport.expect(ShortcutBinding.fromMouseButton(-1, pressedModifierKeyCodes: []) == nil, "Negative buttons are invalid")
        TestSupport.expect(ShortcutBinding.fromMouseButton(32, pressedModifierKeyCodes: []) == nil, "Out-of-range buttons are invalid")

        let middle = mouse(2)
        TestSupport.expectEqual(middle.kind, .mouseButton)
        TestSupport.expectEqual(middle.displayName, "Middle Click")
        TestSupport.expectEqual(mouse(backButton).displayName, "Mouse Button 4")
        TestSupport.expectEqual(mouse(backButton, modifiers: [leftCommand]).displayName, "Cmd ⌘ + Mouse Button 4")
        TestSupport.expect(mouse(backButton).isCustom, "Captured mouse bindings are custom")
        TestSupport.expect(mouse(backButton).requiresExactModifierMatch, "Mouse bindings always match modifiers exactly")
    }

    private static func testBareMouseHoldLifecycleConsumesPressAndRelease() {
        let configuration = ShortcutConfiguration(hold: mouse(backButton), toggle: .disabled)
        let results = run([
            .mouseButtonChanged(button: backButton, isDown: true),
            .mouseButtonChanged(button: backButton, isDown: false),
        ], configuration: configuration)

        TestSupport.expectEqual(results[0].emittedEvents, [.holdActivated])
        TestSupport.expectEqual(results[0].consumeDecision, .consume)
        TestSupport.expectEqual(results[1].emittedEvents, [.holdDeactivated])
        TestSupport.expectEqual(results[1].consumeDecision, .consume)
        TestSupport.expectEqual(results[1].state.consumedMouseButtons, [])
    }

    private static func testUnboundMouseButtonsPassThrough() {
        let configuration = ShortcutConfiguration(hold: mouse(backButton), toggle: .defaultToggle)
        for button in [0, 1, 2, forwardButton, 9] {
            let results = run([
                .mouseButtonChanged(button: button, isDown: true),
                .mouseButtonChanged(button: button, isDown: false),
            ], configuration: configuration)
            for result in results {
                TestSupport.expectEqual(result.emittedEvents, [])
                TestSupport.expectEqual(result.consumeDecision, .passthrough)
            }
        }

        // Keyboard-only configurations never consume mouse input.
        let keyboardOnly = run([
            .mouseButtonChanged(button: backButton, isDown: true),
            .mouseButtonChanged(button: backButton, isDown: false),
        ], configuration: ShortcutConfiguration(hold: .defaultHold, toggle: .defaultToggle))
        TestSupport.expectEqual(keyboardOnly.map(\.consumeDecision), [.passthrough, .passthrough])
    }

    private static func testUnsupportedStoredMouseBindingNeverFires() {
        for button: UInt16 in [0, 1] {
            let crafted = ShortcutBinding(
                keyCode: button,
                keyDisplay: "Synthetic",
                modifiers: [],
                kind: .mouseButton,
                preset: nil
            )
            TestSupport.expect(!crafted.isSupported, "Left/right mouse bindings are unsupported")
            let results = run([
                .mouseButtonChanged(button: Int(button), isDown: true),
                .mouseButtonChanged(button: Int(button), isDown: false),
            ], configuration: ShortcutConfiguration(hold: crafted, toggle: crafted))
            TestSupport.expectEqual(results.map(\.emittedEvents), [[], []])
            TestSupport.expectEqual(results.map(\.consumeDecision), [.passthrough, .passthrough])
        }
    }

    private static func testMouseBindingWithModifiersRequiresExactModifiers() {
        let configuration = ShortcutConfiguration(
            hold: mouse(backButton, modifiers: [leftCommand]),
            toggle: .disabled
        )

        let bare = run([
            .mouseButtonChanged(button: backButton, isDown: true),
            .mouseButtonChanged(button: backButton, isDown: false),
        ], configuration: configuration)
        TestSupport.expectEqual(bare.map(\.emittedEvents), [[], []])
        TestSupport.expectEqual(bare.map(\.consumeDecision), [.passthrough, .passthrough])

        let exact = run([
            .modifierChanged(keyCode: leftCommand, isDown: true),
            .mouseButtonChanged(button: backButton, isDown: true),
            .mouseButtonChanged(button: backButton, isDown: false),
            .modifierChanged(keyCode: leftCommand, isDown: false),
        ], configuration: configuration)
        TestSupport.expectEqual(exact[1].emittedEvents, [.holdActivated])
        TestSupport.expectEqual(exact[1].consumeDecision, .consume)
        TestSupport.expectEqual(exact[2].emittedEvents, [.holdDeactivated])
        TestSupport.expectEqual(exact[2].consumeDecision, .consume)

        let extraModifier = run([
            .modifierChanged(keyCode: leftCommand, isDown: true),
            .modifierChanged(keyCode: leftShift, isDown: true),
            .mouseButtonChanged(button: backButton, isDown: true),
            .mouseButtonChanged(button: backButton, isDown: false),
        ], configuration: configuration)
        TestSupport.expectEqual(extraModifier[2].emittedEvents, [])
        TestSupport.expectEqual(extraModifier[2].consumeDecision, .passthrough)
        TestSupport.expectEqual(extraModifier[3].consumeDecision, .passthrough)
    }

    private static func testBareMouseBindingDoesNotFireWithModifiersHeld() {
        let configuration = ShortcutConfiguration(hold: mouse(2), toggle: .disabled)
        let results = run([
            .modifierChanged(keyCode: leftCommand, isDown: true),
            .mouseButtonChanged(button: 2, isDown: true),
            .mouseButtonChanged(button: 2, isDown: false),
        ], configuration: configuration)
        // Cmd + middle click (e.g. open link in new tab) stays with the app.
        TestSupport.expectEqual(results[1].emittedEvents, [])
        TestSupport.expectEqual(results[1].consumeDecision, .passthrough)
        TestSupport.expectEqual(results[2].consumeDecision, .passthrough)
    }

    private static func testReleaseIsConsumedOnlyWhenPressWasConsumed() {
        let configuration = ShortcutConfiguration(
            hold: mouse(backButton, modifiers: [leftCommand]),
            toggle: .disabled
        )

        // Modifier released before the button: the binding ends, but the
        // release is still swallowed because its press was.
        let modifierFirst = run([
            .modifierChanged(keyCode: leftCommand, isDown: true),
            .mouseButtonChanged(button: backButton, isDown: true),
            .modifierChanged(keyCode: leftCommand, isDown: false),
            .mouseButtonChanged(button: backButton, isDown: false),
        ], configuration: configuration)
        TestSupport.expectEqual(modifierFirst[1].consumeDecision, .consume)
        TestSupport.expectEqual(modifierFirst[2].emittedEvents, [.holdDeactivated])
        TestSupport.expectEqual(modifierFirst[3].emittedEvents, [])
        TestSupport.expectEqual(modifierFirst[3].consumeDecision, .consume)

        // Button pressed (delivered to the app) before the modifier: the
        // release must also be delivered so the app sees a matched pair.
        let buttonFirst = run([
            .mouseButtonChanged(button: backButton, isDown: true),
            .modifierChanged(keyCode: leftCommand, isDown: true),
            .mouseButtonChanged(button: backButton, isDown: false),
            .modifierChanged(keyCode: leftCommand, isDown: false),
        ], configuration: configuration)
        TestSupport.expectEqual(buttonFirst[0].consumeDecision, .passthrough)
        TestSupport.expectEqual(buttonFirst[2].consumeDecision, .passthrough)
    }

    private static func testMouseBindingNeverConsumesModifierEvents() {
        let configuration = ShortcutConfiguration(
            hold: mouse(backButton, modifiers: [leftCommand]),
            toggle: .disabled
        )
        let results = run([
            .modifierChanged(keyCode: leftCommand, isDown: true),
            .mouseButtonChanged(button: backButton, isDown: true),
            .modifierChanged(keyCode: leftCommand, isDown: false),
            .mouseButtonChanged(button: backButton, isDown: false),
        ], configuration: configuration)
        TestSupport.expectEqual(results[0].consumeDecision, .passthrough)
        TestSupport.expectEqual(results[2].consumeDecision, .passthrough)
    }

    private static func testHoldAndToggleOnDistinctMouseButtons() {
        let configuration = ShortcutConfiguration(hold: mouse(backButton), toggle: mouse(forwardButton))
        let results = run([
            .mouseButtonChanged(button: forwardButton, isDown: true),
            .mouseButtonChanged(button: forwardButton, isDown: false),
            .mouseButtonChanged(button: backButton, isDown: true),
            .mouseButtonChanged(button: backButton, isDown: false),
        ], configuration: configuration)
        TestSupport.expectEqual(results.map(\.emittedEvents), [
            [.toggleActivated], [.toggleDeactivated], [.holdActivated], [.holdDeactivated],
        ])
        TestSupport.expectEqual(results.map(\.consumeDecision), [.consume, .consume, .consume, .consume])
    }

    private static func testBackendResetReleasesMouseHold() {
        let configuration = ShortcutConfiguration(hold: mouse(backButton), toggle: .disabled)
        let results = run([
            .mouseButtonChanged(button: backButton, isDown: true),
            .backendReset,
            .mouseButtonChanged(button: backButton, isDown: false),
        ], configuration: configuration)
        TestSupport.expectEqual(results[1].emittedEvents, [.holdDeactivated])
        TestSupport.expectEqual(results[1].state.pressedMouseButtons, [])
        TestSupport.expectEqual(results[1].state.consumedMouseButtons, [])
        // A release after the reset has no recorded press, so it passes through.
        TestSupport.expectEqual(results[2].emittedEvents, [])
        TestSupport.expectEqual(results[2].consumeDecision, .passthrough)
    }

    private static func testHasPressedShortcutInputsIncludesBoundMouseButton() {
        let configuration = ShortcutConfiguration(hold: mouse(backButton), toggle: .disabled)
        var state = ShortcutInputState()
        state.pressedMouseButtons = [forwardButton]
        TestSupport.expect(!state.hasPressedShortcutInputs(configuration: configuration), "Unbound buttons are not shortcut inputs")
        state.pressedMouseButtons = [backButton]
        TestSupport.expect(state.hasPressedShortcutInputs(configuration: configuration), "Bound button is a shortcut input")
    }

    private static func testMouseConflictRule() {
        let back = mouse(backButton)
        TestSupport.expect(back.conflicts(with: mouse(backButton)), "Identical mouse bindings conflict")
        TestSupport.expect(
            mouse(backButton, modifiers: [leftCommand]).conflicts(with: mouse(backButton, modifiers: [leftCommand])),
            "Identical modified mouse bindings conflict"
        )
        TestSupport.expect(!back.conflicts(with: mouse(forwardButton)), "Different buttons do not conflict")
        TestSupport.expect(
            !back.conflicts(with: mouse(backButton, modifiers: [leftCommand])),
            "Exact modifier matching keeps bare and modified bindings distinct"
        )
        let keyWithSameCode = ShortcutBinding(
            keyCode: UInt16(backButton),
            keyDisplay: "F",
            modifiers: [],
            kind: .key,
            preset: nil
        )
        TestSupport.expect(!back.conflicts(with: keyWithSameCode), "Mouse and key bindings never conflict")
        TestSupport.expect(!back.conflicts(with: .disabled), "Disabled bindings never conflict")
        TestSupport.expect(back.id != keyWithSameCode.id, "Mouse and key bindings have distinct identities")
    }

    private static func testUsesFnKeyIgnoresMouseButtonNumber() {
        let button63 = ShortcutBinding(
            keyCode: 63,
            keyDisplay: "Mouse Button 64",
            modifiers: [],
            kind: .mouseButton,
            preset: nil
        )
        TestSupport.expect(!button63.usesFnKey, "A mouse button number is not the Fn key code")
        TestSupport.expect(mouse(2, modifiers: [63]).usesFnKey, "Fn + mouse binding uses Fn")
    }

    private static func testDecodesLegacyStoredBindings() {
        let decoder = JSONDecoder()
        let legacyPreset = Data(#"{"keyCode":96,"keyDisplay":"F5","modifiers":0,"kind":"key","preset":"f5"}"#.utf8)
        let legacyModifier = Data(
            #"{"keyCode":61,"keyDisplay":"Right Option","modifiers":1,"kind":"modifierKey","exactModifierKeyCodes":[61,55]}"#.utf8
        )

        guard let preset = try? decoder.decode(ShortcutBinding.self, from: legacyPreset),
              let modifier = try? decoder.decode(ShortcutBinding.self, from: legacyModifier) else {
            fatalError("Legacy stored shortcuts must still decode")
        }
        TestSupport.expectEqual(preset, ShortcutPreset.f5.binding)
        TestSupport.expect(preset.isSupported, "Legacy key bindings stay supported")
        TestSupport.expectEqual(modifier.kind, .modifierKey)
        TestSupport.expectEqual(modifier.exactModifierKeyCodes, [61, 55])
        TestSupport.expectEqual(modifier.modifiers, [.command])
        TestSupport.expect(modifier.isSupported, "Legacy modifier bindings stay supported")
    }

    private static func testMouseBindingRoundTripsThroughCodable() {
        let binding = mouse(backButton, modifiers: [leftCommand])
        guard let data = try? JSONEncoder().encode(binding),
              let decoded = try? JSONDecoder().decode(ShortcutBinding.self, from: data) else {
            fatalError("Mouse binding must round-trip")
        }
        TestSupport.expectEqual(decoded, binding)
        TestSupport.expectEqual(decoded.normalizedForStorageMigration(), binding)

        let storedLeftClick = Data(#"{"keyCode":0,"keyDisplay":"Synthetic","modifiers":0,"kind":"mouseButton"}"#.utf8)
        guard let leftClick = try? JSONDecoder().decode(ShortcutBinding.self, from: storedLeftClick) else {
            fatalError("Stored mouse binding must decode")
        }
        TestSupport.expect(!leftClick.isSupported, "A stored left-click binding is rejected")
    }

    private static func testDoubleTapMouseHoldLatchesToggle() {
        let configuration = ShortcutConfiguration(hold: mouse(backButton), toggle: .disabled)
        let controller = DictationShortcutSessionController()
        var state = ShortcutInputState()
        var actions: [DictationShortcutAction] = []
        var now: TimeInterval = 0
        let inputs: [ShortcutInputEvent] = [
            .mouseButtonChanged(button: backButton, isDown: true),
            .mouseButtonChanged(button: backButton, isDown: false),
            .mouseButtonChanged(button: backButton, isDown: true),
            .mouseButtonChanged(button: backButton, isDown: false),
        ]
        for input in inputs {
            let result = ShortcutMatcher.reduce(state: state, event: input, configuration: configuration)
            state = result.state
            for event in result.emittedEvents {
                if let action = controller.handle(
                    event: event,
                    isTranscribing: false,
                    doubleTapToToggleEnabled: true,
                    now: now
                ) {
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
    }
}
