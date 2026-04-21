import AppKit
import Carbon.HIToolbox

enum ModifierKeyEventState {
    static func isKeyDown(for event: NSEvent) -> Bool? {
        guard let mappedFlag = mappedFlag(for: event.keyCode) else {
            return nil
        }
        return event.modifierFlags.contains(mappedFlag)
    }

    static func pressedModifierKeyCodes(
        for event: NSEvent,
        trustedFunctionKeyIsDown: Bool? = nil
    ) -> Set<UInt16> {
        ShortcutBinding.modifierKeyCodes.filter { keyCode in
            // macOS sets NSEvent.ModifierFlags.function for arrow keys, F-keys,
            // and navigation keys (Home/End/Page Up/Page Down/Forward Delete)
            // regardless of whether the physical Fn key is held. When the caller
            // can provide an authoritative Fn-down state (tracked from
            // flagsChanged events), prefer it over the unreliable event flag.
            if keyCode == fnKeyCode, let trustedFunctionKeyIsDown {
                return trustedFunctionKeyIsDown
            }
            guard let mappedFlag = mappedFlag(for: keyCode) else {
                return false
            }
            return event.modifierFlags.contains(mappedFlag)
        }
    }

    static let fnKeyCode: UInt16 = 63

    /// Reads the current system-wide Fn state. Useful for seeding a backend's
    /// tracked Fn state at start or after a tap reset, since flagsChanged events
    /// don't fire for keys already held when a monitor begins.
    static func currentFunctionKeyIsDown() -> Bool {
        NSEvent.modifierFlags.contains(.function)
    }

    private static func mappedFlag(for keyCode: UInt16) -> NSEvent.ModifierFlags? {
        switch keyCode {
        case 54:
            return .rightCommand
        case 55:
            return .leftCommand
        case 56:
            return .leftShift
        case 58:
            return .leftOption
        case 59:
            return .leftControl
        case 60:
            return .rightShift
        case 61:
            return .rightOption
        case 62:
            return .rightControl
        case 63:
            return .function
        default:
            return nil
        }
    }
}

private extension NSEvent.ModifierFlags {
    static let leftControl = Self(rawValue: UInt(NX_DEVICELCTLKEYMASK))
    static let leftShift = Self(rawValue: UInt(NX_DEVICELSHIFTKEYMASK))
    static let rightShift = Self(rawValue: UInt(NX_DEVICERSHIFTKEYMASK))
    static let leftCommand = Self(rawValue: UInt(NX_DEVICELCMDKEYMASK))
    static let rightCommand = Self(rawValue: UInt(NX_DEVICERCMDKEYMASK))
    static let leftOption = Self(rawValue: UInt(NX_DEVICELALTKEYMASK))
    static let rightOption = Self(rawValue: UInt(NX_DEVICERALTKEYMASK))
    static let rightControl = Self(rawValue: UInt(NX_DEVICERCTLKEYMASK))
}
