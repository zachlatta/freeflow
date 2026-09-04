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

            // GlobalShortcutBackend attaches this decision to the ordinary
            // key event that carried the snapshot. If the snapshot merely
            // repairs a missed Fn state (e.g. after the event tap was
            // re-enabled), flipping Fn hold state must not swallow that key;
            // macOS still needs unobstructed Fn handling for Globe actions.
            // Toggle and non-Fn hold transitions keep consuming as before.
            let onlyFnHoldTransitions =
                configuration.hold.usesFnKey
                && emittedEvents.allSatisfy { $0 == .holdActivated || $0 == .holdDeactivated }
            let consumeDecision: ShortcutConsumeDecision =
                emittedEvents.isEmpty || onlyFnHoldTransitions ? .passthrough : .consume

            return ShortcutMatchResult(
                state: nextState,
                emittedEvents: emittedEvents,
                consumeDecision: consumeDecision
            )

        case .modifierChanged(let keyCode, let isDown):
            // Fn/Globe is the only modifier with a system-level tap action
            // (e.g. "Press globe to: Change Input Source"). If a hold-to-talk
            // binding consumes Fn events, macOS never sees the key at all and
            // the Globe action can never fire, even for quick taps. macOS
            // itself ignores long Fn holds, so hold bindings can safely
            // observe Fn passively: quick taps reach the system Globe action,
            // sustained holds still drive hold-to-talk. Toggle bindings keep
            // consuming because a Fn tap is meaningful on both sides and the
            // user chose Fn for it.
            let consumeConfiguration =
                keyCode == ShortcutBinding.fnKeyCode
                ? configuration.withHoldBindingDisabled
                : configuration

            let shouldConsumeBefore = shouldConsumeModifierEvent(
                for: keyCode,
                state: state,
                configuration: consumeConfiguration
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
                configuration: consumeConfiguration
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

    private static func updateActiveBindings(
        in state: inout ShortcutInputState,
        configuration: ShortcutConfiguration
    ) -> [ShortcutEvent] {
        let previousHold = state.holdIsActive
        let previousToggle = state.toggleIsActive
        let previousCopyAgain = state.copyAgainIsActive

        state.holdIsActive = bindingIsActive(configuration.hold, state: state, configuration: configuration)
        state.toggleIsActive = bindingIsActive(configuration.toggle, state: state, configuration: configuration)
        state.copyAgainIsActive = bindingIsActive(configuration.copyAgain, state: state, configuration: configuration)

        return emitChanges(
            previousHold: previousHold,
            previousToggle: previousToggle,
            previousCopyAgain: previousCopyAgain,
            currentHold: state.holdIsActive,
            currentToggle: state.toggleIsActive,
            currentCopyAgain: state.copyAgainIsActive,
            configuration: configuration
        )
    }

    private static func emitChanges(
        previousHold: Bool,
        previousToggle: Bool,
        previousCopyAgain: Bool,
        currentHold: Bool,
        currentToggle: Bool,
        currentCopyAgain: Bool,
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
