import Foundation

enum ShortcutInputEvent: Equatable {
    case modifierChanged(keyCode: UInt16, isDown: Bool)
    case modifierSnapshot(Set<UInt16>)
    case keyChanged(keyCode: UInt16, isDown: Bool, isRepeat: Bool)
    case mouseChanged(button: Int, isDown: Bool)
    case backendReset
}

enum ShortcutConsumeDecision: Equatable {
    case consume
    case passthrough
}

struct ShortcutInputState: Equatable {
    var pressedKeyCodes: Set<UInt16> = []
    var pressedModifierKeyCodes: Set<UInt16> = []
    var pressedMouseButtons: Set<Int> = []
    var holdIsActive = false
    var toggleIsActive = false

    var currentModifiers: ShortcutModifiers {
        ShortcutBinding.modifiers(for: pressedModifierKeyCodes)
    }

    func hasPressedShortcutInputs(configuration: ShortcutConfiguration) -> Bool {
        let currentModifiers = currentModifiers
        let keyReferenceHeld = pressedKeyCodes.contains { keyCode in
            configuration.hold.kind == .key && configuration.hold.keyCode == keyCode
                || configuration.toggle.kind == .key && configuration.toggle.keyCode == keyCode
                || configuration.hold.chordKeyCode == keyCode
                || configuration.toggle.chordKeyCode == keyCode
        }
        let mouseReferenceHeld = pressedMouseButtons.contains { button in
            let buttonCode = UInt16(button)
            return configuration.hold.kind == .mouseButton && configuration.hold.keyCode == buttonCode
                || configuration.toggle.kind == .mouseButton && configuration.toggle.keyCode == buttonCode
        }
        if keyReferenceHeld || mouseReferenceHeld {
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

            let shouldConsumeAfter = shouldConsumeModifierEvent(
                for: keyCode,
                state: nextState,
                configuration: configuration
            )
            let emittedEvents = updateActiveBindings(in: &nextState, configuration: configuration)
            return ShortcutMatchResult(
                state: nextState,
                emittedEvents: emittedEvents,
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
                return ShortcutMatchResult(
                    state: nextState,
                    emittedEvents: [],
                    consumeDecision: shouldConsumeBefore ? .consume : .passthrough
                )
            }

            if isDown {
                nextState.pressedKeyCodes.insert(keyCode)
            } else {
                nextState.pressedKeyCodes.remove(keyCode)
            }

            let shouldConsumeAfter = shouldConsumeKeyEvent(
                for: keyCode,
                state: nextState,
                configuration: configuration
            )
            let emittedEvents = updateActiveBindings(in: &nextState, configuration: configuration)
            return ShortcutMatchResult(
                state: nextState,
                emittedEvents: emittedEvents,
                consumeDecision: (shouldConsumeBefore || shouldConsumeAfter) ? .consume : .passthrough
            )
        case .mouseChanged(let button, let isDown):
            let shouldConsumeBefore = shouldConsumeMouseEvent(
                for: button,
                state: state,
                configuration: configuration
            )
            var nextState = state
            if isDown {
                nextState.pressedMouseButtons.insert(button)
            } else {
                nextState.pressedMouseButtons.remove(button)
            }
            let shouldConsumeAfter = shouldConsumeMouseEvent(
                for: button,
                state: nextState,
                configuration: configuration
            )
            let emittedEvents = updateActiveBindings(in: &nextState, configuration: configuration)
            return ShortcutMatchResult(
                state: nextState,
                emittedEvents: emittedEvents,
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
        nextState.pressedMouseButtons.removeAll()
        let emittedEvents = updateActiveBindings(in: &nextState, configuration: configuration)
        return ShortcutMatchResult(
            state: nextState,
            emittedEvents: emittedEvents,
            consumeDecision: .passthrough
        )
    }

    private static func updateActiveBindings(
        in state: inout ShortcutInputState,
        configuration: ShortcutConfiguration
    ) -> [ShortcutEvent] {
        let previousHold = state.holdIsActive
        let previousToggle = state.toggleIsActive

        state.holdIsActive = bindingIsActive(configuration.hold, state: state, configuration: configuration)
        state.toggleIsActive = bindingIsActive(configuration.toggle, state: state, configuration: configuration)

        return emitChanges(
            previousHold: previousHold,
            previousToggle: previousToggle,
            currentHold: state.holdIsActive,
            currentToggle: state.toggleIsActive,
            configuration: configuration
        )
    }

    private static func emitChanges(
        previousHold: Bool,
        previousToggle: Bool,
        currentHold: Bool,
        currentToggle: Bool,
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
        if previousHold && !currentHold {
            deactivations.append((.holdDeactivated, configuration.hold.specificityScore))
        }
        if previousToggle && !currentToggle {
            deactivations.append((.toggleDeactivated, configuration.toggle.specificityScore))
        }

        let orderedActivations = activations.sorted(by: { $0.1 > $1.1 }).map(\.0)
        let orderedDeactivations = deactivations.sorted(by: { $0.1 < $1.1 }).map(\.0)
        return orderedActivations + orderedDeactivations
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
            guard state.pressedKeyCodes.contains(binding.keyCode) else { return false }
            if let chordKeyCode = binding.chordKeyCode,
               !state.pressedKeyCodes.contains(chordKeyCode) {
                return false
            }
            return true
        case .modifierKey:
            return state.pressedModifierKeyCodes.contains(binding.keyCode)
        case .mouseButton:
            guard binding.keyCode != 0,
                  state.pressedMouseButtons.contains(Int(binding.keyCode)) else {
                return false
            }
            if let chordKeyCode = binding.chordKeyCode,
               !state.pressedKeyCodes.contains(chordKeyCode) {
                return false
            }
            return true
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

    private static func shouldConsumeMouseEvent(
        for button: Int,
        state: ShortcutInputState,
        configuration: ShortcutConfiguration
    ) -> Bool {
        relevantMouseBindings(for: button, configuration: configuration).contains {
            bindingIsActive($0, state: state, configuration: configuration)
        }
    }

    private static func relevantKeyBindings(
        for keyCode: UInt16,
        configuration: ShortcutConfiguration
    ) -> [ShortcutBinding] {
        [configuration.hold, configuration.toggle].filter { binding in
            if binding.kind == .key {
                return binding.keyCode == keyCode || binding.chordKeyCode == keyCode
            }
            if binding.kind == .mouseButton, let chordKeyCode = binding.chordKeyCode {
                return chordKeyCode == keyCode
            }
            return false
        }
    }

    private static func relevantMouseBindings(
        for button: Int,
        configuration: ShortcutConfiguration
    ) -> [ShortcutBinding] {
        let buttonCode = UInt16(button)
        return [configuration.hold, configuration.toggle].filter { binding in
            binding.kind == .mouseButton && binding.keyCode == buttonCode
        }
    }

    private static func relevantModifierBindings(
        for keyCode: UInt16,
        configuration: ShortcutConfiguration
    ) -> [ShortcutBinding] {
        [configuration.hold, configuration.toggle].filter { binding in
            switch binding.kind {
            case .key, .modifierKey, .mouseButton:
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
