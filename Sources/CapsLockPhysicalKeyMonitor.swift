import Foundation
import IOKit.hid
import os.log

private let capsLockPhysicalKeyLog = OSLog(subsystem: "com.zachlatta.freeflow", category: "Shortcuts")

enum CapsLockPhysicalKeyMonitorError: LocalizedError {
    case openFailed(IOReturn)

    var errorDescription: String? {
        switch self {
        case .openFailed(let result):
            return "Caps Lock shortcut monitoring could not start because the HID keyboard monitor failed with code \(result)."
        }
    }
}

final class CapsLockPhysicalKeyMonitor {
    private var manager: IOHIDManager?
    private let runLoopMode = CFRunLoopMode.commonModes.rawValue
    private var capsLockIsDown = false

    var onStateChanged: ((Bool) -> Void)?

    func start() throws {
        stop()

        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let matching: CFDictionary = [
            kIOHIDElementTypeKey: NSNumber(value: kIOHIDElementTypeInput_Button.rawValue),
            kIOHIDElementUsagePageKey: NSNumber(value: kHIDPage_KeyboardOrKeypad),
            kIOHIDElementUsageKey: NSNumber(value: kHIDUsage_KeyboardCapsLock)
        ] as CFDictionary

        IOHIDManagerSetInputValueMatching(manager, matching)
        IOHIDManagerRegisterInputValueCallback(
            manager,
            { context, _, _, value in
                guard let context else { return }
                let monitor = Unmanaged<CapsLockPhysicalKeyMonitor>
                    .fromOpaque(context)
                    .takeUnretainedValue()
                monitor.handleInputValue(value)
            },
            Unmanaged.passUnretained(self).toOpaque()
        )
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), runLoopMode)

        let openResult = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        guard openResult == kIOReturnSuccess else {
            IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), runLoopMode)
            IOHIDManagerRegisterInputValueCallback(manager, nil, nil)
            capsLockIsDown = false
            os_log(.error, log: capsLockPhysicalKeyLog, "Caps Lock HID monitor failed to open: %{public}d", openResult)
            throw CapsLockPhysicalKeyMonitorError.openFailed(openResult)
        }

        self.manager = manager
    }

    func stop() {
        guard let manager else { return }

        IOHIDManagerRegisterInputValueCallback(manager, nil, nil)
        IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), runLoopMode)
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        self.manager = nil
        capsLockIsDown = false
    }

    deinit {
        stop()
    }

    private func handleInputValue(_ value: IOHIDValue) {
        let element = IOHIDValueGetElement(value)
        guard IOHIDElementGetType(element) == kIOHIDElementTypeInput_Button,
              IOHIDElementGetUsagePage(element) == kHIDPage_KeyboardOrKeypad,
              IOHIDElementGetUsage(element) == kHIDUsage_KeyboardCapsLock else {
            return
        }

        let isDown = IOHIDValueGetIntegerValue(value) != 0
        guard isDown != capsLockIsDown else { return }

        capsLockIsDown = isDown
        onStateChanged?(isDown)
    }
}
