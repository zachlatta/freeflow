import Cocoa
import Carbon

enum HotkeyOption: String, CaseIterable, Identifiable {
    case fnKey = "fn"
    case rightOption = "rightOption"
    case f5 = "f5"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .fnKey: return "Fn (Globe) Key"
        case .rightOption: return "Right Option Key"
        case .f5: return "F5 Key"
        }
    }

    var keyCode: UInt16 {
        switch self {
        case .fnKey: return 63       // Fn/Globe key
        case .rightOption: return 61 // Right Option
        case .f5: return 96          // F5
        }
    }

    var isModifier: Bool {
        switch self {
        case .fnKey, .rightOption: return true
        case .f5: return false
        }
    }
}

class HotkeyManager {
    private var globalFlagsMonitor: Any?
    private var localFlagsMonitor: Any?
    private var globalKeyDownMonitor: Any?
    private var globalKeyUpMonitor: Any?
    private var localKeyDownMonitor: Any?
    private var localKeyUpMonitor: Any?
    private var isKeyDown = false
    private var currentOption: HotkeyOption = .fnKey

    var onKeyDown: (() -> Void)?
    var onKeyUp: (() -> Void)?

    func start(option: HotkeyOption) {
        stop()
        currentOption = option
        isKeyDown = false

        if option.isModifier {
            globalFlagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
                self?.handleFlagsChanged(event: event)
            }
            localFlagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
                self?.handleFlagsChanged(event: event)
                return event
            }
        } else {
            // For regular keys like F5, monitor keyDown/keyUp
            globalKeyDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
                self?.handleKeyDown(event: event)
            }
            globalKeyUpMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyUp) { [weak self] event in
                self?.handleKeyUp(event: event)
            }
            localKeyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                self?.handleKeyDown(event: event)
                return event
            }
            localKeyUpMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyUp) { [weak self] event in
                self?.handleKeyUp(event: event)
                return event
            }
        }
    }

    private func handleFlagsChanged(event: NSEvent) {
        guard event.keyCode == currentOption.keyCode else { return }

        let flagIsSet: Bool
        switch currentOption {
        case .fnKey:
            flagIsSet = event.modifierFlags.contains(.function)
        case .rightOption:
            flagIsSet = event.modifierFlags.contains(.option)
        default:
            return
        }

        if flagIsSet && !isKeyDown {
            isKeyDown = true
            onKeyDown?()
        } else if !flagIsSet && isKeyDown {
            isKeyDown = false
            onKeyUp?()
        }
    }

    private func handleKeyDown(event: NSEvent) {
        guard event.keyCode == currentOption.keyCode else { return }
        guard !event.isARepeat else { return } // Ignore key repeat
        if !isKeyDown {
            isKeyDown = true
            onKeyDown?()
        }
    }

    private func handleKeyUp(event: NSEvent) {
        guard event.keyCode == currentOption.keyCode else { return }
        if isKeyDown {
            isKeyDown = false
            onKeyUp?()
        }
    }

    func stop() {
        if let m = globalFlagsMonitor { NSEvent.removeMonitor(m) }
        if let m = localFlagsMonitor { NSEvent.removeMonitor(m) }
        if let m = globalKeyDownMonitor { NSEvent.removeMonitor(m) }
        if let m = globalKeyUpMonitor { NSEvent.removeMonitor(m) }
        if let m = localKeyDownMonitor { NSEvent.removeMonitor(m) }
        if let m = localKeyUpMonitor { NSEvent.removeMonitor(m) }
        globalFlagsMonitor = nil
        localFlagsMonitor = nil
        globalKeyDownMonitor = nil
        globalKeyUpMonitor = nil
        localKeyDownMonitor = nil
        localKeyUpMonitor = nil
        isKeyDown = false
    }

    deinit {
        stop()
    }
}

class ToggleHotkeyManager {
    private var globalKeyDownMonitor: Any?
    private var localKeyDownMonitor: Any?

    var onToggle: (() -> Void)?

    func start() {
        stop()

        globalKeyDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKeyDown(event: event)
        }
        localKeyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKeyDown(event: event)
            return event
        }
    }

    private func handleKeyDown(event: NSEvent) {
        // Space = keyCode 49, must have Fn/Globe modifier active
        guard event.keyCode == 49,
              event.modifierFlags.contains(.function),
              !event.isARepeat else { return }
        onToggle?()
    }

    func stop() {
        if let m = globalKeyDownMonitor { NSEvent.removeMonitor(m) }
        if let m = localKeyDownMonitor { NSEvent.removeMonitor(m) }
        globalKeyDownMonitor = nil
        localKeyDownMonitor = nil
    }

    deinit {
        stop()
    }
}
