import AppKit

final class LocalShortcutCaptureBackend {
    private var localFlagsMonitor: Any?
    private var localKeyDownMonitor: Any?
    private var pressedModifierKeyCodes: Set<UInt16> = []

    var onInputEvent: ((ShortcutInputEvent) -> Void)?
    var onKeyDownEvent: ((NSEvent) -> Void)?

    func start() {
        stop()

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
        guard ShortcutBinding.modifierKeyCodes.contains(event.keyCode) else { return }

        let isDown: Bool
        if pressedModifierKeyCodes.contains(event.keyCode) {
            pressedModifierKeyCodes.remove(event.keyCode)
            isDown = false
        } else {
            pressedModifierKeyCodes.insert(event.keyCode)
            isDown = true
        }

        onInputEvent?(.modifierChanged(keyCode: event.keyCode, isDown: isDown))
    }

    private func handleKeyDown(_ event: NSEvent) {
        if !ShortcutBinding.modifierKeyCodes.contains(event.keyCode) {
            onInputEvent?(.keyChanged(keyCode: event.keyCode, isDown: true, isRepeat: event.isARepeat))
        }
        onKeyDownEvent?(event)
    }
}
