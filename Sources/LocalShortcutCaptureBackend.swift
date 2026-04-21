import AppKit

final class LocalShortcutCaptureBackend {
    private var localFlagsMonitor: Any?
    private var localKeyDownMonitor: Any?
    private var pressedModifierKeyCodes: Set<UInt16> = []

    var onInputEvent: ((ShortcutInputEvent) -> Void)?
    var onKeyDownEvent: ((NSEvent) -> Void)?

    func start() {
        stop()

        if ModifierKeyEventState.currentFunctionKeyIsDown() {
            pressedModifierKeyCodes.insert(ModifierKeyEventState.fnKeyCode)
        }

        localFlagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlagsChanged(event)
            return nil
        }

        localKeyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKeyDown(event)
            return nil
        }
    }

    func stop() {
        if let monitor = localKeyDownMonitor {
            NSEvent.removeMonitor(monitor)
        }
        if let monitor = localFlagsMonitor {
            NSEvent.removeMonitor(monitor)
        }
        localKeyDownMonitor = nil
        localFlagsMonitor = nil
        pressedModifierKeyCodes.removeAll()
    }

    deinit {
        stop()
    }

    private func handleFlagsChanged(_ event: NSEvent) {
        guard ShortcutBinding.modifierKeyCodes.contains(event.keyCode),
              let isDown = ModifierKeyEventState.isKeyDown(for: event) else { return }

        if isDown {
            pressedModifierKeyCodes.insert(event.keyCode)
        } else {
            pressedModifierKeyCodes.remove(event.keyCode)
        }

        onInputEvent?(.modifierChanged(keyCode: event.keyCode, isDown: isDown))
    }

    private func handleKeyDown(_ event: NSEvent) {
        if !ShortcutBinding.modifierKeyCodes.contains(event.keyCode) {
            let trustedFn = pressedModifierKeyCodes.contains(ModifierKeyEventState.fnKeyCode)
            onInputEvent?(.modifierSnapshot(ModifierKeyEventState.pressedModifierKeyCodes(
                for: event,
                trustedFunctionKeyIsDown: trustedFn
            )))
            onInputEvent?(.keyChanged(keyCode: event.keyCode, isDown: true, isRepeat: event.isARepeat))
        }
        onKeyDownEvent?(event)
    }
}
