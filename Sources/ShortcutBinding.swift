import AppKit

struct ShortcutModifiers: OptionSet, Hashable, Codable {
    let rawValue: Int

    static let command = ShortcutModifiers(rawValue: 1 << 0)
    static let control = ShortcutModifiers(rawValue: 1 << 1)
    static let option = ShortcutModifiers(rawValue: 1 << 2)
    static let shift = ShortcutModifiers(rawValue: 1 << 3)
    static let function = ShortcutModifiers(rawValue: 1 << 4)

    init(rawValue: Int) {
        self.rawValue = rawValue
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.init(rawValue: try container.decode(Int.self))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    init(eventFlags: NSEvent.ModifierFlags) {
        var value: ShortcutModifiers = []
        if eventFlags.contains(.command) { value.insert(.command) }
        if eventFlags.contains(.control) { value.insert(.control) }
        if eventFlags.contains(.option) { value.insert(.option) }
        if eventFlags.contains(.shift) { value.insert(.shift) }
        if eventFlags.contains(.function) { value.insert(.function) }
        self = value
    }

    var orderedDisplayNames: [String] {
        var names: [String] = []
        if contains(.command) { names.append("⌘") }
        if contains(.control) { names.append("⌃") }
        if contains(.option) { names.append("⌥") }
        if contains(.shift) { names.append("⇧") }
        if contains(.function) { names.append("fn") }
        return names
    }
}

enum ShortcutBindingKind: String, Codable {
    case disabled
    case key
    case modifierKey
}

enum RecordingTriggerMode: String, Codable {
    case hold
    case toggle

    var badgeTitle: String {
        switch self {
        case .hold: return "Hold"
        case .toggle: return "Tap"
        }
    }
}

enum ShortcutRole {
    case hold
    case toggle

    var title: String {
        switch self {
        case .hold: return "Hold to Talk"
        case .toggle: return "Tap to Toggle"
        }
    }
}

enum ShortcutEvent {
    case holdActivated
    case holdDeactivated
    case toggleActivated
    case toggleDeactivated
}

struct ShortcutConfiguration {
    let hold: ShortcutBinding
    let toggle: ShortcutBinding
}

enum ShortcutPreset: String, CaseIterable, Identifiable, Codable {
    case fnKey = "fn"
    case rightOption = "rightOption"
    case f5 = "f5"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fnKey: return "Fn (Globe) Key"
        case .rightOption: return "Right Option Key"
        case .f5: return "F5 Key"
        }
    }

    var binding: ShortcutBinding {
        switch self {
        case .fnKey:
            return ShortcutBinding(
                keyCode: 63,
                keyDisplay: "Fn",
                modifiers: [],
                kind: .modifierKey,
                preset: self
            )
        case .rightOption:
            return ShortcutBinding(
                keyCode: 61,
                keyDisplay: "Right Option",
                modifiers: [],
                kind: .modifierKey,
                preset: self
            )
        case .f5:
            return ShortcutBinding(
                keyCode: 96,
                keyDisplay: "F5",
                modifiers: [],
                kind: .key,
                preset: self
            )
        }
    }
}

struct ShortcutBinding: Codable, Hashable, Identifiable {
    let keyCode: UInt16
    let keyDisplay: String
    let modifiers: ShortcutModifiers
    let kind: ShortcutBindingKind
    let preset: ShortcutPreset?

    var id: String {
        "\(kind.rawValue):\(keyCode):\(modifiers.rawValue):\(preset?.rawValue ?? "custom")"
    }

    var displayName: String {
        if isDisabled { return "Disabled" }
        let parts = modifiers.orderedDisplayNames + [keyDisplay]
        return parts.joined(separator: " + ")
    }

    var selectionTitle: String {
        preset?.title ?? displayName
    }

    var isCustom: Bool {
        preset == nil && !isDisabled
    }

    var isDisabled: Bool {
        kind == .disabled
    }

    var specificityScore: Int {
        modifiers.orderedDisplayNames.count
    }

    var usesFnKey: Bool {
        guard !isDisabled else { return false }
        return keyCode == 63 || modifiers.contains(.function)
    }

    func withAddedModifiers(_ extraModifiers: ShortcutModifiers) -> ShortcutBinding {
        guard !isDisabled else { return self }
        return ShortcutBinding(
            keyCode: keyCode,
            keyDisplay: keyDisplay,
            modifiers: modifiers.union(extraModifiers),
            kind: kind,
            preset: preset
        )
    }

    static let disabled = ShortcutBinding(
        keyCode: 0,
        keyDisplay: "Disabled",
        modifiers: [],
        kind: .disabled,
        preset: nil
    )
    static let defaultHold = ShortcutPreset.fnKey.binding
    static let defaultToggle = ShortcutPreset.fnKey.binding.withAddedModifiers(.command)

    static func from(event: NSEvent) -> ShortcutBinding? {
        guard !event.isARepeat else { return nil }
        guard !Self.modifierKeyCodes.contains(event.keyCode) else { return nil }

        let label = Self.displayLabel(for: event.keyCode, event: event)
        guard !label.isEmpty else { return nil }

        return ShortcutBinding(
            keyCode: event.keyCode,
            keyDisplay: label,
            modifiers: ShortcutModifiers(eventFlags: event.modifierFlags),
            kind: .key,
            preset: nil
        )
    }

    static func fromModifierKeyCode(
        _ keyCode: UInt16,
        pressedModifierKeyCodes: Set<UInt16>
    ) -> ShortcutBinding? {
        guard modifierKeyCodes.contains(keyCode),
              let primaryModifier = modifierFlag(forKeyCode: keyCode) else {
            return nil
        }

        let activeModifiers = modifiers(for: pressedModifierKeyCodes)
        guard activeModifiers.contains(primaryModifier) else {
            return nil
        }

        var extraModifiers = activeModifiers
        extraModifiers.remove(primaryModifier)
        guard !extraModifiers.isEmpty else {
            return nil
        }

        return ShortcutBinding(
            keyCode: keyCode,
            keyDisplay: modifierDisplayLabel(for: keyCode),
            modifiers: extraModifiers,
            kind: .modifierKey,
            preset: nil
        )
    }

    static let modifierKeyCodes: Set<UInt16> = [54, 55, 56, 58, 59, 60, 61, 62, 63]

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

    private static func modifierFlag(forKeyCode keyCode: UInt16) -> ShortcutModifiers? {
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

    private static func modifiers(for pressedModifierKeyCodes: Set<UInt16>) -> ShortcutModifiers {
        var modifiers: ShortcutModifiers = []
        for keyCode in pressedModifierKeyCodes {
            if let modifier = modifierFlag(forKeyCode: keyCode) {
                modifiers.insert(modifier)
            }
        }
        return modifiers
    }

    private static func modifierDisplayLabel(for keyCode: UInt16) -> String {
        modifierKeyNames[keyCode] ?? "Modifier"
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
