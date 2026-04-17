import AppKit

enum CommandModeStyle: String, CaseIterable, Codable, Identifiable {
    case automatic
    case manual

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic: return "Automatic"
        case .manual: return "Manual"
        }
    }
}

enum CommandModeManualModifier: String, CaseIterable, Codable, Identifiable {
    case command
    case control
    case option
    case shift

    var id: String { rawValue }

    var title: String {
        switch self {
        case .command: return "Command"
        case .control: return "Control"
        case .option: return "Option"
        case .shift: return "Shift"
        }
    }

    var shortcutModifier: ShortcutModifiers {
        switch self {
        case .command: return .command
        case .control: return .control
        case .option: return .option
        case .shift: return .shift
        }
    }
}

extension ShortcutModifiers {
    init(eventFlags: NSEvent.ModifierFlags) {
        var value: ShortcutModifiers = []
        if eventFlags.contains(.command) { value.insert(.command) }
        if eventFlags.contains(.control) { value.insert(.control) }
        if eventFlags.contains(.option) { value.insert(.option) }
        if eventFlags.contains(.shift) { value.insert(.shift) }
        if eventFlags.contains(.function) { value.insert(.function) }
        self = value
    }
}

extension ShortcutBinding {
    static func from(event: NSEvent, pressedModifierKeyCodes: Set<UInt16>) -> ShortcutBinding? {
        guard !event.isARepeat else { return nil }
        guard !Self.modifierKeyCodes.contains(event.keyCode) else { return nil }

        let label = Self.displayLabel(for: event.keyCode, event: event)
        guard !label.isEmpty else { return nil }

        let exactModifierKeyCodes = Self.normalizedExactModifierKeyCodes(pressedModifierKeyCodes)

        return ShortcutBinding(
            keyCode: event.keyCode,
            keyDisplay: label,
            modifiers: Self.modifiers(for: pressedModifierKeyCodes),
            kind: .key,
            preset: nil,
            exactModifierKeyCodes: exactModifierKeyCodes
        )
    }

    static func fromModifierKeyCode(
        _ keyCode: UInt16,
        pressedModifierKeyCodes: Set<UInt16>,
        allowBareModifier: Bool = false
    ) -> ShortcutBinding? {
        guard modifierKeyCodes.contains(keyCode),
              let primaryModifier = logicalModifier(forKeyCode: keyCode) else {
            return nil
        }

        let activeModifiers = modifiers(for: pressedModifierKeyCodes)
        guard activeModifiers.contains(primaryModifier) else {
            return nil
        }

        var extraModifiers = activeModifiers
        extraModifiers.remove(primaryModifier)
        guard allowBareModifier || !extraModifiers.isEmpty else {
            return nil
        }

        return ShortcutBinding(
            keyCode: keyCode,
            keyDisplay: displayLabel(for: keyCode),
            modifiers: extraModifiers,
            kind: .modifierKey,
            preset: nil,
            exactModifierKeyCodes: normalizedExactModifierKeyCodes(pressedModifierKeyCodes)
        )
    }

    static func displayLabel(for keyCode: UInt16, event: NSEvent? = nil) -> String {
        if let modifierName = modifierKeyNames[keyCode] {
            return modifierName
        }

        if let special = specialKeyNames[keyCode] {
            return special
        }

        if let functionKey = functionKeyNames[keyCode] {
            return functionKey
        }

        let candidate = event?.charactersIgnoringModifiers ?? ""
        let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count == 1 {
            return trimmed.uppercased()
        }
        return trimmed
    }

    private static let modifierKeyNames: [UInt16: String] = [
        54: "Right Command",
        55: "Command",
        56: "Shift",
        58: "Option",
        59: "Control",
        60: "Right Shift",
        61: "Right Option",
        62: "Right Control",
        63: "Fn"
    ]

    private static let specialKeyNames: [UInt16: String] = [
        18: "1",
        19: "2",
        20: "3",
        21: "4",
        23: "5",
        22: "6",
        26: "7",
        28: "8",
        25: "9",
        29: "0",
        27: "-",
        24: "=",
        33: "[",
        30: "]",
        42: "\\",
        41: ";",
        39: "'",
        43: ",",
        47: ".",
        44: "/",
        50: "`",
        36: "↩",
        48: "⇥",
        49: "Space",
        51: "⌫",
        53: "Esc",
        117: "Del",
        123: "←",
        124: "→",
        125: "↓",
        126: "↑",
        115: "Home",
        119: "End",
        116: "Pg Up",
        121: "Pg Down"
    ]

    private static let functionKeyNames: [UInt16: String] = [
        122: "F1",
        120: "F2",
        99: "F3",
        118: "F4",
        96: "F5",
        97: "F6",
        98: "F7",
        100: "F8",
        101: "F9",
        109: "F10",
        103: "F11",
        111: "F12",
        105: "F13",
        107: "F14",
        113: "F15",
        106: "F16",
        64: "F17",
        79: "F18",
        80: "F19",
        90: "F20"
    ]
}
