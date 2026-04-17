import Cocoa
import os.log

private let shortcutLog = OSLog(subsystem: "com.zachlatta.freeflow", category: "Shortcuts")

enum GlobalShortcutBackendError: LocalizedError {
    case eventTapUnavailable

    var errorDescription: String? {
        switch self {
        case .eventTapUnavailable:
            return "Global shortcut monitoring could not start. FreeFlow requires keyboard monitoring permission for global shortcuts."
        }
    }
}

final class GlobalShortcutBackend {
    private var eventTap: CFMachPort?
    private var eventTapRunLoopSource: CFRunLoopSource?
    private var pressedModifierKeyCodes: Set<UInt16> = []

    var onInputEvent: ((ShortcutInputEvent) -> ShortcutConsumeDecision)?
    var onEscapeKeyPressed: (() -> Bool)?

    func start() throws {
        stop()
        try installEventTap()
    }

    func stop() {
        if let source = eventTapRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        eventTapRunLoopSource = nil
        if let tap = eventTap {
            CFMachPortInvalidate(tap)
        }
        eventTap = nil
        pressedModifierKeyCodes.removeAll()
    }

    deinit {
        stop()
    }

    private func installEventTap() throws {
        let eventMask = [
            CGEventType.flagsChanged,
            CGEventType.keyDown,
            CGEventType.keyUp
        ].reduce(CGEventMask(0)) { partialResult, eventType in
            partialResult | (CGEventMask(1) << eventType.rawValue)
        }

        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo else {
                return Unmanaged.passUnretained(event)
            }

            let backend = Unmanaged<GlobalShortcutBackend>.fromOpaque(userInfo).takeUnretainedValue()
            return backend.handleEventTap(type: type, event: event)
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            os_log(.error, log: shortcutLog, "Failed to install global shortcut event tap")
            throw GlobalShortcutBackendError.eventTapUnavailable
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        eventTap = tap
        eventTapRunLoopSource = source
    }

    private func handleEventTap(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            pressedModifierKeyCodes.removeAll()
            _ = onInputEvent?(.backendReset)
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)

        case .flagsChanged, .keyDown, .keyUp:
            guard let nsEvent = NSEvent(cgEvent: event) else {
                return Unmanaged.passUnretained(event)
            }

            let shouldConsume: Bool
            switch type {
            case .flagsChanged:
                shouldConsume = handleFlagsChanged(nsEvent)
            case .keyDown:
                shouldConsume = handleKeyDown(nsEvent)
            case .keyUp:
                shouldConsume = handleKeyUp(nsEvent)
            default:
                shouldConsume = false
            }

            return shouldConsume ? nil : Unmanaged.passUnretained(event)

        default:
            return Unmanaged.passUnretained(event)
        }
    }

    private func handleFlagsChanged(_ event: NSEvent) -> Bool {
        guard ShortcutBinding.modifierKeyCodes.contains(event.keyCode),
              let isDown = ModifierKeyEventState.isKeyDown(for: event) else {
            return false
        }

        if isDown {
            pressedModifierKeyCodes.insert(event.keyCode)
        } else {
            pressedModifierKeyCodes.remove(event.keyCode)
        }

        return onInputEvent?(.modifierChanged(keyCode: event.keyCode, isDown: isDown)) == .consume
    }

    private func handleKeyDown(_ event: NSEvent) -> Bool {
        if event.keyCode == 53 {
            guard !event.isARepeat else { return false }
            return onEscapeKeyPressed?() ?? false
        }

        guard !ShortcutBinding.modifierKeyCodes.contains(event.keyCode) else { return false }
        return onInputEvent?(.keyChanged(keyCode: event.keyCode, isDown: true, isRepeat: event.isARepeat)) == .consume
    }

    private func handleKeyUp(_ event: NSEvent) -> Bool {
        guard !ShortcutBinding.modifierKeyCodes.contains(event.keyCode) else { return false }
        return onInputEvent?(.keyChanged(keyCode: event.keyCode, isDown: false, isRepeat: false)) == .consume
    }
}
