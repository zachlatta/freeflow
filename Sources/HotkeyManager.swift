import Cocoa

final class HotkeyManager {
    private var globalFlagsMonitor: Any?
    private var localFlagsMonitor: Any?
    private var globalKeyDownMonitor: Any?
    private var globalKeyUpMonitor: Any?
    private var localKeyDownMonitor: Any?
    private var localKeyUpMonitor: Any?

    private var configuration = ShortcutConfiguration(
        hold: .defaultHold,
        toggle: .defaultToggle
    )
    private var pressedKeyCodes: Set<UInt16> = []
    private var pressedModifierKeyCodes: Set<UInt16> = []
    private var holdIsActive = false
    private var toggleIsActive = false

    var onShortcutEvent: ((ShortcutEvent) -> Void)?

    func start(configuration: ShortcutConfiguration) {
        stop()
        self.configuration = configuration
        installMonitors()
    }

    func stop() {
        if let monitor = globalFlagsMonitor { NSEvent.removeMonitor(monitor) }
        if let monitor = localFlagsMonitor { NSEvent.removeMonitor(monitor) }
        if let monitor = globalKeyDownMonitor { NSEvent.removeMonitor(monitor) }
        if let monitor = globalKeyUpMonitor { NSEvent.removeMonitor(monitor) }
        if let monitor = localKeyDownMonitor { NSEvent.removeMonitor(monitor) }
        if let monitor = localKeyUpMonitor { NSEvent.removeMonitor(monitor) }
        globalFlagsMonitor = nil
        localFlagsMonitor = nil
        globalKeyDownMonitor = nil
        globalKeyUpMonitor = nil
        localKeyDownMonitor = nil
        localKeyUpMonitor = nil
        pressedKeyCodes.removeAll()
        pressedModifierKeyCodes.removeAll()
        holdIsActive = false
        toggleIsActive = false
    }

    deinit {
        stop()
    }

    private func installMonitors() {
        globalFlagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            _ = self?.handleFlagsChanged(event)
        }
        localFlagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            let shouldConsume = self?.handleFlagsChanged(event) ?? false
            return shouldConsume ? nil : event
        }
        globalKeyDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            _ = self?.handleKeyDown(event)
        }
        globalKeyUpMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyUp) { [weak self] event in
            _ = self?.handleKeyUp(event)
        }
        localKeyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let shouldConsume = self?.handleKeyDown(event) ?? false
            return shouldConsume ? nil : event
        }
        localKeyUpMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyUp) { [weak self] event in
            let shouldConsume = self?.handleKeyUp(event) ?? false
            return shouldConsume ? nil : event
        }
    }

    private func handleFlagsChanged(_ event: NSEvent) -> Bool {
        let shouldConsume = shortcutReferencesModifierKeyCode(event.keyCode)
        if ShortcutBinding.modifierKeyCodes.contains(event.keyCode) {
            if pressedModifierKeyCodes.contains(event.keyCode) {
                pressedModifierKeyCodes.remove(event.keyCode)
            } else {
                pressedModifierKeyCodes.insert(event.keyCode)
            }
        }
        evaluateActiveBindings()
        return shouldConsume
    }

    private func handleKeyDown(_ event: NSEvent) -> Bool {
        guard !event.isARepeat else { return false }
        guard !ShortcutBinding.modifierKeyCodes.contains(event.keyCode) else { return false }
        let shouldConsume = shortcutReferencesKeyCode(event.keyCode)
        pressedKeyCodes.insert(event.keyCode)
        evaluateActiveBindings()
        return shouldConsume
    }

    private func handleKeyUp(_ event: NSEvent) -> Bool {
        guard !ShortcutBinding.modifierKeyCodes.contains(event.keyCode) else { return false }
        let shouldConsume = shortcutReferencesKeyCode(event.keyCode)
        pressedKeyCodes.remove(event.keyCode)
        evaluateActiveBindings()
        return shouldConsume
    }

    private func evaluateActiveBindings() {
        let previousHold = holdIsActive
        let previousToggle = toggleIsActive

        holdIsActive = bindingIsActive(configuration.hold)
        toggleIsActive = bindingIsActive(configuration.toggle)

        emitChanges(
            previousHold: previousHold,
            previousToggle: previousToggle,
            currentHold: holdIsActive,
            currentToggle: toggleIsActive
        )
    }

    private func emitChanges(
        previousHold: Bool,
        previousToggle: Bool,
        currentHold: Bool,
        currentToggle: Bool
    ) {
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

        for (event, _) in activations.sorted(by: { $0.1 > $1.1 }) {
            onShortcutEvent?(event)
        }
        for (event, _) in deactivations.sorted(by: { $0.1 < $1.1 }) {
            onShortcutEvent?(event)
        }
    }

    private func bindingIsActive(_ binding: ShortcutBinding) -> Bool {
        let activeModifiers = currentModifiers
        guard activeModifiers.isSuperset(of: binding.modifiers) else {
            return false
        }

        switch binding.kind {
        case .key:
            return pressedKeyCodes.contains(binding.keyCode)
        case .modifierKey:
            return pressedModifierKeyCodes.contains(binding.keyCode)
        }
    }

    private var currentModifiers: ShortcutModifiers {
        var modifiers: ShortcutModifiers = []
        if pressedModifierKeyCodes.contains(54) || pressedModifierKeyCodes.contains(55) {
            modifiers.insert(.command)
        }
        if pressedModifierKeyCodes.contains(59) || pressedModifierKeyCodes.contains(62) {
            modifiers.insert(.control)
        }
        if pressedModifierKeyCodes.contains(58) || pressedModifierKeyCodes.contains(61) {
            modifiers.insert(.option)
        }
        if pressedModifierKeyCodes.contains(56) || pressedModifierKeyCodes.contains(60) {
            modifiers.insert(.shift)
        }
        if pressedModifierKeyCodes.contains(63) {
            modifiers.insert(.function)
        }
        return modifiers
    }

    private func shortcutReferencesKeyCode(_ keyCode: UInt16) -> Bool {
        configuration.hold.kind == .key && configuration.hold.keyCode == keyCode
            || configuration.toggle.kind == .key && configuration.toggle.keyCode == keyCode
    }

    private func shortcutReferencesModifierKeyCode(_ keyCode: UInt16) -> Bool {
        configuration.hold.kind == .modifierKey && configuration.hold.keyCode == keyCode
            || configuration.toggle.kind == .modifierKey && configuration.toggle.keyCode == keyCode
            || modifierFlagsForKeyCode(keyCode).map { configuration.hold.modifiers.contains($0) || configuration.toggle.modifiers.contains($0) } == true
    }

    private func modifierFlagsForKeyCode(_ keyCode: UInt16) -> ShortcutModifiers? {
        switch keyCode {
        case 54, 55:
            return .command
        case 59, 62:
            return .control
        case 58, 61:
            return .option
        case 56, 60:
            return .shift
        case 63:
            return .function
        default:
            return nil
        }
    }
}
