import AppKit

final class LocalShortcutCaptureBackend {
    private var localFlagsMonitor: Any?
    private var localKeyDownMonitor: Any?
    private var localKeyUpMonitor: Any?
    private var localMouseDownMonitor: Any?
    private var localMouseUpMonitor: Any?
    private var pressedModifierKeyCodes: Set<UInt16> = []
    private var pressedKeyCodes: Set<UInt16> = []
    private var pressedMouseButtons: Set<Int> = []

    var onInputEvent: ((ShortcutInputEvent) -> Void)?
    var onKeyDownEvent: ((NSEvent) -> Void)?
    var onKeyUpEvent: ((NSEvent) -> Void)?
    var onMouseDownEvent: ((NSEvent) -> Void)?
    var onMouseUpEvent: ((NSEvent) -> Void)?

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

        localKeyUpMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyUp) { [weak self] event in
            self?.handleKeyUp(event)
            return nil
        }

        let mouseDownMask = NSEvent.EventTypeMask.leftMouseDown
            .union(.rightMouseDown)
            .union(.otherMouseDown)
        localMouseDownMonitor = NSEvent.addLocalMonitorForEvents(matching: mouseDownMask) { [weak self] event in
            self?.handleMouseDown(event)
            return event.buttonNumber == 0 ? event : nil
        }

        let mouseUpMask = NSEvent.EventTypeMask.leftMouseUp
            .union(.rightMouseUp)
            .union(.otherMouseUp)
        localMouseUpMonitor = NSEvent.addLocalMonitorForEvents(matching: mouseUpMask) { [weak self] event in
            self?.handleMouseUp(event)
            return event.buttonNumber == 0 ? event : nil
        }
    }

    func stop() {
        if let monitor = localKeyDownMonitor {
            NSEvent.removeMonitor(monitor)
        }
        if let monitor = localFlagsMonitor {
            NSEvent.removeMonitor(monitor)
        }
        if let monitor = localKeyUpMonitor {
            NSEvent.removeMonitor(monitor)
        }
        if let monitor = localMouseDownMonitor {
            NSEvent.removeMonitor(monitor)
        }
        if let monitor = localMouseUpMonitor {
            NSEvent.removeMonitor(monitor)
        }
        localKeyDownMonitor = nil
        localFlagsMonitor = nil
        localKeyUpMonitor = nil
        localMouseDownMonitor = nil
        localMouseUpMonitor = nil
        pressedModifierKeyCodes.removeAll()
        pressedKeyCodes.removeAll()
        pressedMouseButtons.removeAll()
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
            if !event.isARepeat {
                pressedKeyCodes.insert(event.keyCode)
            }
            let trustedFn = pressedModifierKeyCodes.contains(ModifierKeyEventState.fnKeyCode)
            onInputEvent?(.modifierSnapshot(ModifierKeyEventState.pressedModifierKeyCodes(
                for: event,
                trustedFunctionKeyIsDown: trustedFn
            )))
            onInputEvent?(.keyChanged(keyCode: event.keyCode, isDown: true, isRepeat: event.isARepeat))
        }
        onKeyDownEvent?(event)
    }

    private func handleKeyUp(_ event: NSEvent) {
        guard !ShortcutBinding.modifierKeyCodes.contains(event.keyCode) else { return }
        pressedKeyCodes.remove(event.keyCode)
        let trustedFn = pressedModifierKeyCodes.contains(ModifierKeyEventState.fnKeyCode)
        onInputEvent?(.modifierSnapshot(ModifierKeyEventState.pressedModifierKeyCodes(
            for: event,
            trustedFunctionKeyIsDown: trustedFn
        )))
        onInputEvent?(.keyChanged(keyCode: event.keyCode, isDown: false, isRepeat: false))
        onKeyUpEvent?(event)
    }

    private func handleMouseDown(_ event: NSEvent) {
        pressedMouseButtons.insert(event.buttonNumber)
        onInputEvent?(.mouseChanged(button: event.buttonNumber, isDown: true))
        onMouseDownEvent?(event)
    }

    private func handleMouseUp(_ event: NSEvent) {
        pressedMouseButtons.remove(event.buttonNumber)
        onInputEvent?(.mouseChanged(button: event.buttonNumber, isDown: false))
        onMouseUpEvent?(event)
    }
}
