import Foundation

enum ShortcutInputEvent: Equatable {
    case modifierChanged(keyCode: UInt16, isDown: Bool)
    case modifierSnapshot(Set<UInt16>)
    case keyChanged(keyCode: UInt16, isDown: Bool, isRepeat: Bool)
    case backendReset
}

enum ShortcutConsumeDecision: Equatable {
    case consume
    case passthrough
}

struct ShortcutInputState: Equatable {
    var pressedKeyCodes: Set<UInt16> = []
    var pressedModifierKeyCodes: Set<UInt16> = []
    var holdIsActive = false
    var toggleIsActive = false
    /// True while any key or modifier belonging to the toggle shortcut is currently pressed.
    var toggleComponentIsActive = false
    var copyAgainIsActive = false

    var currentModifiers: ShortcutModifiers {
        ShortcutBinding.modifiers(for: pressedModifierKeyCodes)
    }

    func hasPressedShortcutInputs(configuration: ShortcutConfiguration) -> Bool {
        let currentModifiers = currentModifiers
        let keyReferenceHeld = pressedKeyCodes.contains { keyCode in
            let isHoldKey = configuration.hold.kind == .key && configuration.hold.keyCode == keyCode
            let isToggleKey = configuration.toggle.kind == .key && configuration.toggle.keyCode == keyCode
            let isCopyAgainKey = configuration.copyAgain.kind == .key && configuration.copyAgain.keyCode == keyCode
            return isHoldKey || isToggleKey || isCopyAgainKey
        }
        if keyReferenceHeld {
            return true
        }

        if configuration.hold.referencesPressedModifiers(
            pressedModifierKeyCodes: pressedModifierKeyCodes,
            currentModifiers: currentModifiers,
            permittedAdditionalExactMatchModifiers: configuration.permittedAdditionalExactMatchModifiers
        ) {
            return true
        }

        if configuration.toggle.referencesPressedModifiers(
            pressedModifierKeyCodes: pressedModifierKeyCodes,
            currentModifiers: currentModifiers,
            permittedAdditionalExactMatchModifiers: configuration.permittedAdditionalExactMatchModifiers
        ) {
            return true
        }

        if configuration.copyAgain.referencesPressedModifiers(
            pressedModifierKeyCodes: pressedModifierKeyCodes,
            currentModifiers: currentModifiers,
            permittedAdditionalExactMatchModifiers: configuration.permittedAdditionalExactMatchModifiers
        ) {
            return true
        }

        return false
    }

    /// Returns true if the given key code belongs to a component of the toggle shortcut.
    /// - Parameters:
    ///   - keyCode: The raw key code of the input event.
    ///   - kind: Whether the input is a regular key or a modifier key.
    ///   - configuration: The active shortcut configuration to match against.
    static func isToggleComponentInput(
        keyCode: UInt16,
        kind: ShortcutBindingKind,
        configuration: ShortcutConfiguration
    ) -> Bool {
        let binding = configuration.toggle
        guard !binding.isDisabled else { return false }

        if kind == .key {
            return binding.kind == .key && binding.keyCode == keyCode
        } else if kind == .modifierKey {
            if binding.kind == .modifierKey {
                return binding.keyCode == keyCode
            } else {
                if let exactModifiers = binding.exactModifierKeyCodes {
                    return exactModifiers.contains(keyCode)
                } else if let modifier = ShortcutBinding.modifier(forKeyCode: keyCode) {
                    // Safely extract the modifier and check intersection to prevent force-unwrap crashes
                    return !binding.modifiers.isDisjoint(with: [modifier])
                }
            }
        }
        return false
    }
}

struct ShortcutMatchResult: Equatable {
    let state: ShortcutInputState
    let emittedEvents: [ShortcutEvent]
    let consumeDecision: ShortcutConsumeDecision
}

enum ShortcutMatcher {
    static func reduce(
        state: ShortcutInputState,
        event: ShortcutInputEvent,
        configuration: ShortcutConfiguration
    ) -> ShortcutMatchResult {
        switch event {
        case .backendReset:
            return reduceBackendReset(state: state, configuration: configuration)

        case .modifierSnapshot(let pressedModifierKeyCodes):
            var nextState = state
            nextState.pressedModifierKeyCodes = pressedModifierKeyCodes

            let emittedEvents = updateActiveBindings(in: &nextState, configuration: configuration)
            return ShortcutMatchResult(
                state: nextState,
                emittedEvents: emittedEvents,
                consumeDecision: emittedEvents.isEmpty ? .passthrough : .consume
            )

        case .modifierChanged(let keyCode, let isDown):
            let shouldConsumeBefore = shouldConsumeModifierEvent(
                for: keyCode,
                state: state,
                configuration: configuration
            )

            var nextState = state
            if isDown {
                nextState.pressedModifierKeyCodes.insert(keyCode)
            } else {
                nextState.pressedModifierKeyCodes.remove(keyCode)
            }

            // Emit stateless event on pressed modifier if it is a toggle component
            var statelessEvents: [ShortcutEvent] = []
            if isDown {
                if ShortcutInputState.isToggleComponentInput(keyCode: keyCode, kind: .modifierKey, configuration: configuration) {
                    statelessEvents.append(.toggleComponentInputReceived)
                }
            }

            let shouldConsumeAfter = shouldConsumeModifierEvent(
                for: keyCode,
                state: nextState,
                configuration: configuration
            )
            let emittedEvents = updateActiveBindings(in: &nextState, configuration: configuration)
            return ShortcutMatchResult(
                state: nextState,
                emittedEvents: emittedEvents + statelessEvents,
                consumeDecision: (shouldConsumeBefore || shouldConsumeAfter) ? .consume : .passthrough
            )

        case .keyChanged(let keyCode, let isDown, let isRepeat):
            let shouldConsumeBefore = shouldConsumeKeyEvent(
                for: keyCode,
                state: state,
                configuration: configuration
            )

            var nextState = state
            if isRepeat {
                // Key repeats don't change state but might need consumption
                return ShortcutMatchResult(
                    state: state,
                    emittedEvents: [],
                    consumeDecision: shouldConsumeBefore ? .consume : .passthrough
                )
            }

            if isDown {
                nextState.pressedKeyCodes.insert(keyCode)
            } else {
                nextState.pressedKeyCodes.remove(keyCode)
            }

            // Emit stateless event on pressed key if it is a toggle component
            var statelessEvents: [ShortcutEvent] = []
            if isDown {
                if ShortcutInputState.isToggleComponentInput(keyCode: keyCode, kind: .key, configuration: configuration) {
                    statelessEvents.append(.toggleComponentInputReceived)
                }
            }

            let shouldConsumeAfter = shouldConsumeKeyEvent(
                for: keyCode,
                state: nextState,
                configuration: configuration
            )
            let emittedEvents = updateActiveBindings(in: &nextState, configuration: configuration)
            return ShortcutMatchResult(
                state: nextState,
                emittedEvents: emittedEvents + statelessEvents,
                consumeDecision: (shouldConsumeBefore || shouldConsumeAfter) ? .consume : .passthrough
            )
        }
    }

    private static func reduceBackendReset(
        state: ShortcutInputState,
        configuration: ShortcutConfiguration
    ) -> ShortcutMatchResult {
        var nextState = state
        nextState.pressedKeyCodes.removeAll()
        nextState.pressedModifierKeyCodes.removeAll()
        let emittedEvents = updateActiveBindings(in: &nextState, configuration: configuration)
        return ShortcutMatchResult(
            state: nextState,
            emittedEvents: emittedEvents,
            consumeDecision: .passthrough
        )
    }

    // Update the active states of all configured bindings and return triggered events
    private static func updateActiveBindings(
        in state: inout ShortcutInputState,
        configuration: ShortcutConfiguration
    ) -> [ShortcutEvent] {
        let previousHold = state.holdIsActive
        let previousToggle = state.toggleIsActive
        let previousCopyAgain = state.copyAgainIsActive
        let previousToggleComponent = state.toggleComponentIsActive

        state.holdIsActive = bindingIsActive(configuration.hold, state: state, configuration: configuration)
        state.toggleIsActive = bindingIsActive(configuration.toggle, state: state, configuration: configuration)
        state.copyAgainIsActive = bindingIsActive(configuration.copyAgain, state: state, configuration: configuration)
        state.toggleComponentIsActive = bindingHasAnyInputActive(configuration.toggle, state: state)

        return emitChanges(
            previousHold: previousHold,
            previousToggle: previousToggle,
            previousCopyAgain: previousCopyAgain,
            previousToggleComponent: previousToggleComponent,
            currentHold: state.holdIsActive,
            currentToggle: state.toggleIsActive,
            currentCopyAgain: state.copyAgainIsActive,
            currentToggleComponent: state.toggleComponentIsActive,
            configuration: configuration
        )
    }

    // Determine the state transitions and emit corresponding shortcut events
    private static func emitChanges(
        previousHold: Bool,
        previousToggle: Bool,
        previousCopyAgain: Bool,
        previousToggleComponent: Bool,
        currentHold: Bool,
        currentToggle: Bool,
        currentCopyAgain: Bool,
        currentToggleComponent: Bool,
        configuration: ShortcutConfiguration
    ) -> [ShortcutEvent] {
        var activations: [(ShortcutEvent, Int)] = []
        var deactivations: [(ShortcutEvent, Int)] = []

        if !previousHold && currentHold {
            activations.append((.holdActivated, configuration.hold.specificityScore))
        }
        if !previousToggle && currentToggle {
            activations.append((.toggleActivated, configuration.toggle.specificityScore))
        }
        // Emit event when any part of the toggle shortcut is pressed
        if !previousToggleComponent && currentToggleComponent {
            activations.append((.toggleComponentActivated, configuration.toggle.specificityScore))
        }
        // Paste Again is a one-shot: fire on the leading edge only.
        if !previousCopyAgain && currentCopyAgain {
            activations.append((.copyAgainTriggered, configuration.copyAgain.specificityScore))
        }
        if previousHold && !currentHold {
            deactivations.append((.holdDeactivated, configuration.hold.specificityScore))
        }
        if previousToggle && !currentToggle {
            deactivations.append((.toggleDeactivated, configuration.toggle.specificityScore))
        }
        // Emit event when all parts of the toggle shortcut are released
        if previousToggleComponent && !currentToggleComponent {
            deactivations.append((.toggleComponentDeactivated, configuration.toggle.specificityScore))
        }

        let orderedActivations = activations.sorted(by: { $0.1 > $1.1 }).map(\.0)
        let orderedDeactivations = deactivations.sorted(by: { $0.1 < $1.1 }).map(\.0)
        return orderedActivations + orderedDeactivations
    }

    /// Returns true if any key or modifier belonging to the binding is currently pressed.
    /// Unlike `bindingIsActive`, this matches a partial press of the shortcut, not the full combo.
    /// - Parameters:
    ///   - binding: The shortcut binding to test for partial activation.
    ///   - state: The current pressed-input state.
    private static func bindingHasAnyInputActive(
        _ binding: ShortcutBinding,
        state: ShortcutInputState
    ) -> Bool {
        guard !binding.isDisabled else { return false }
        switch binding.kind {
        case .disabled:
            return false
        case .key:
            if state.pressedKeyCodes.contains(binding.keyCode) { return true }
        case .modifierKey:
            if state.pressedModifierKeyCodes.contains(binding.keyCode) { return true }
        }
        if let exactModifiers = binding.exactModifierKeyCodes {
            if !exactModifiers.isDisjoint(with: state.pressedModifierKeyCodes) {
                return true
            }
        } else {
            let activeModifiers = state.currentModifiers
            if !binding.modifiers.isDisjoint(with: activeModifiers) {
                return true
            }
        }
        return false
    }

    private static func bindingIsActive(
        _ binding: ShortcutBinding,
        state: ShortcutInputState,
        configuration: ShortcutConfiguration
    ) -> Bool {
        guard !binding.isDisabled else { return false }
        let activeModifiers = state.currentModifiers
        guard binding.modifiersAreActive(
            pressedModifierKeyCodes: state.pressedModifierKeyCodes,
            currentModifiers: activeModifiers,
            permittedAdditionalExactMatchModifiers: configuration.permittedAdditionalExactMatchModifiers
        ) else {
            return false
        }

        switch binding.kind {
        case .disabled:
            return false
        case .key:
            return state.pressedKeyCodes.contains(binding.keyCode)
        case .modifierKey:
            return state.pressedModifierKeyCodes.contains(binding.keyCode)
        }
    }

    private static func shouldConsumeKeyEvent(
        for keyCode: UInt16,
        state: ShortcutInputState,
        configuration: ShortcutConfiguration
    ) -> Bool {
        relevantKeyBindings(for: keyCode, configuration: configuration).contains {
            bindingIsActive($0, state: state, configuration: configuration)
        }
    }

    private static func shouldConsumeModifierEvent(
        for keyCode: UInt16,
        state: ShortcutInputState,
        configuration: ShortcutConfiguration
    ) -> Bool {
        relevantModifierBindings(for: keyCode, configuration: configuration).contains {
            bindingIsActive($0, state: state, configuration: configuration)
        }
    }

    private static func relevantKeyBindings(
        for keyCode: UInt16,
        configuration: ShortcutConfiguration
    ) -> [ShortcutBinding] {
        [configuration.hold, configuration.toggle, configuration.copyAgain].filter { binding in
            binding.kind == .key && binding.keyCode == keyCode
        }
    }

    private static func relevantModifierBindings(
        for keyCode: UInt16,
        configuration: ShortcutConfiguration
    ) -> [ShortcutBinding] {
        [configuration.hold, configuration.toggle, configuration.copyAgain].filter { binding in
            switch binding.kind {
            case .key, .modifierKey:
                return modifierEvent(for: keyCode, affects: binding)
            case .disabled:
                return false
            }
        }
    }

    private static func modifierEvent(for keyCode: UInt16, affects binding: ShortcutBinding) -> Bool {
        if binding.keyCode == keyCode {
            return true
        }

        if binding.exactModifierKeyCodes != nil {
            return ShortcutBinding.modifierKeyCodes.contains(keyCode)
        }

        return ShortcutBinding.modifierKeyCodes.contains(keyCode)
            && ShortcutBinding.logicalModifier(forKeyCode: keyCode).map(binding.modifiers.contains) == true
    }
}

private extension ShortcutBinding {
    func modifiersAreActive(
        pressedModifierKeyCodes: Set<UInt16>,
        currentModifiers: ShortcutModifiers,
        permittedAdditionalExactMatchModifiers: ShortcutModifiers
    ) -> Bool {
        guard currentModifiers.isSuperset(of: modifiers) else {
            return false
        }

        guard let exactModifierKeyCodes = exactModifierKeyCodes else {
            return true
        }

        if ShortcutBinding.exactModifierKeyCodesMatch(
            pressedModifierKeyCodes,
            exactModifierKeyCodes: exactModifierKeyCodes,
            permittedAdditionalExactMatchModifiers: permittedAdditionalExactMatchModifiers
        ) {
            return true
        }
        return false
    }

    func referencesPressedModifiers(
        pressedModifierKeyCodes: Set<UInt16>,
        currentModifiers: ShortcutModifiers,
        permittedAdditionalExactMatchModifiers: ShortcutModifiers
    ) -> Bool {
        if let exactModifierKeyCodes = exactModifierKeyCodes {
            if !exactModifierKeyCodes.isDisjoint(with: pressedModifierKeyCodes) {
                return true
            }
            if !permittedAdditionalExactMatchModifiers.isEmpty {
                let additionalModifierKeyCodes = ShortcutBinding.matchingModifierKeyCodes(
                    for: permittedAdditionalExactMatchModifiers
                )
                if !additionalModifierKeyCodes.isDisjoint(with: pressedModifierKeyCodes) {
                    return true
                }
            }
        } else if !modifiers.isDisjoint(with: currentModifiers) {
            return true
        }

        guard kind == .modifierKey else { return false }
        return pressedModifierKeyCodes.contains(keyCode)
    }
}
