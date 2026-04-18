import Foundation

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

enum ShortcutEvent: Equatable {
    case holdActivated
    case holdDeactivated
    case toggleActivated
    case toggleDeactivated
}

struct ShortcutConfiguration: Equatable {
    let hold: ShortcutBinding
    let toggle: ShortcutBinding

    static let disabled = ShortcutConfiguration(hold: .disabled, toggle: .disabled)
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

struct ShortcutBinding: Codable, Hashable, Identifiable, Equatable {
    let keyCode: UInt16
    let keyDisplay: String
    let modifiers: ShortcutModifiers
    let kind: ShortcutBindingKind
    let preset: ShortcutPreset?
    let exactModifierKeyCodes: Set<UInt16>?

    init(
        keyCode: UInt16,
        keyDisplay: String,
        modifiers: ShortcutModifiers,
        kind: ShortcutBindingKind,
        preset: ShortcutPreset?,
        exactModifierKeyCodes: Set<UInt16>? = nil
    ) {
        self.keyCode = keyCode
        self.keyDisplay = keyDisplay
        self.modifiers = modifiers
        self.kind = kind
        self.preset = preset
        self.exactModifierKeyCodes = exactModifierKeyCodes
    }

    var id: String {
        let exactModifierID = Self.orderedExactModifierKeyCodes(
            exactModifierKeyCodes ?? []
        ).map(String.init).joined(separator: ",")
        return "\(kind.rawValue):\(keyCode):\(modifiers.rawValue):\(preset?.rawValue ?? "custom"):\(exactModifierID)"
    }

    var displayName: String {
        if isDisabled { return "Disabled" }
        let parts = modifierDisplayNames + [keyDisplay]
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
        modifierDisplayNames.count
    }

    var usesFnKey: Bool {
        guard !isDisabled else { return false }
        return keyCode == 63 || modifiers.contains(.function)
    }

    var requiresExactModifierMatch: Bool {
        kind == .modifierKey || exactModifierKeyCodes != nil
    }

    func withAddedModifiers(_ extraModifiers: ShortcutModifiers) -> ShortcutBinding {
        guard !isDisabled else { return self }
        return ShortcutBinding(
            keyCode: keyCode,
            keyDisplay: keyDisplay,
            modifiers: modifiers.union(extraModifiers),
            kind: kind,
            preset: preset,
            exactModifierKeyCodes: exactModifierKeyCodes
        )
    }

    func normalizedForStorageMigration() -> ShortcutBinding {
        let normalizedExactModifierKeyCodes = Self.normalizedExactModifierKeyCodes(exactModifierKeyCodes)
        let normalizedModifiers = modifiers.union(Self.modifiers(for: normalizedExactModifierKeyCodes ?? []))

        guard normalizedExactModifierKeyCodes != exactModifierKeyCodes || normalizedModifiers != modifiers else {
            return self
        }

        return ShortcutBinding(
            keyCode: keyCode,
            keyDisplay: keyDisplay,
            modifiers: normalizedModifiers,
            kind: kind,
            preset: preset,
            exactModifierKeyCodes: normalizedExactModifierKeyCodes
        )
    }

    func conflicts(with other: ShortcutBinding) -> Bool {
        guard !isDisabled, !other.isDisabled else { return false }
        guard primaryInputOverlaps(with: other) else { return false }

        let orderedModifierKeyCodes = Array(Self.modifierKeyCodes).sorted()
        let combinations = 1 << orderedModifierKeyCodes.count

        for mask in 0..<combinations {
            var pressedModifierKeyCodes: Set<UInt16> = []
            for (index, keyCode) in orderedModifierKeyCodes.enumerated() where (mask & (1 << index)) != 0 {
                pressedModifierKeyCodes.insert(keyCode)
            }

            let selfActive = isActive(for: pressedModifierKeyCodes)
            let otherActive = other.isActive(for: pressedModifierKeyCodes)
            if selfActive && otherActive && specificityScore == other.specificityScore {
                return true
            }
        }

        return false
    }

    var modifierDisplayNames: [String] {
        Self.modifierDisplayNames(
            for: modifiers,
            exactModifierKeyCodes: displayedExactModifierKeyCodes
        )
    }

    private var displayedExactModifierKeyCodes: Set<UInt16>? {
        guard let exactModifierKeyCodes else { return nil }
        let filteredModifierKeyCodes: Set<UInt16>
        if kind == .modifierKey {
            filteredModifierKeyCodes = exactModifierKeyCodes.subtracting([keyCode])
        } else {
            filteredModifierKeyCodes = exactModifierKeyCodes
        }
        return Self.normalizedExactModifierKeyCodes(filteredModifierKeyCodes)
    }

    private func primaryInputOverlaps(with other: ShortcutBinding) -> Bool {
        guard kind == other.kind else { return false }

        switch kind {
        case .disabled:
            return false
        case .key, .modifierKey:
            return keyCode == other.keyCode
        }
    }

    private func isActive(for pressedModifierKeyCodes: Set<UInt16>) -> Bool {
        let currentModifiers = Self.modifiers(for: pressedModifierKeyCodes)
        guard currentModifiers.isSuperset(of: modifiers) else {
            return false
        }

        if let exactModifierKeyCodes = exactModifierKeyCodes,
           pressedModifierKeyCodes != exactModifierKeyCodes {
            return false
        }

        switch kind {
        case .disabled:
            return false
        case .key:
            return true
        case .modifierKey:
            return pressedModifierKeyCodes.contains(keyCode)
        }
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

    static let modifierKeyCodes: Set<UInt16> = [54, 55, 56, 58, 59, 60, 61, 62, 63]

    static func logicalModifier(forKeyCode keyCode: UInt16) -> ShortcutModifiers? {
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

    static func modifiers(for pressedModifierKeyCodes: Set<UInt16>) -> ShortcutModifiers {
        var modifiers: ShortcutModifiers = []
        for keyCode in pressedModifierKeyCodes {
            if let modifier = logicalModifier(forKeyCode: keyCode) {
                modifiers.insert(modifier)
            }
        }
        return modifiers
    }

    static func canonicalModifierKeyCode(for keyCode: UInt16) -> UInt16 {
        switch keyCode {
        case 54:
            return 55
        case 60:
            return 56
        case 61:
            return 58
        case 62:
            return 59
        default:
            return keyCode
        }
    }

    static func logicalModifierDisplayLabel(for keyCode: UInt16) -> String {
        switch keyCode {
        case 55:
            return "Command"
        case 59:
            return "Control"
        case 58:
            return "Option"
        case 56:
            return "Shift"
        case 63:
            return "Fn"
        default:
            return "Modifier"
        }
    }

    static func normalizedExactModifierKeyCodes(_ exactModifierKeyCodes: Set<UInt16>?) -> Set<UInt16>? {
        guard let exactModifierKeyCodes else { return nil }
        let normalized = exactModifierKeyCodes.filter { modifierKeyCodes.contains($0) }
        return normalized.isEmpty ? nil : normalized
    }

    static func orderedExactModifierKeyCodes(_ exactModifierKeyCodes: Set<UInt16>) -> [UInt16] {
        modifierDisplayOrder.filter(exactModifierKeyCodes.contains)
    }

    static func modifierDisplayNames(
        for modifiers: ShortcutModifiers,
        exactModifierKeyCodes: Set<UInt16>?
    ) -> [String] {
        let normalizedExactModifierKeyCodes = normalizedExactModifierKeyCodes(exactModifierKeyCodes) ?? []
        var names: [String] = []

        for spec in modifierDisplaySpecs {
            let exactNames = spec.exactDisplayNames.compactMap { keyCode, displayName in
                normalizedExactModifierKeyCodes.contains(keyCode) ? displayName : nil
            }
            if !exactNames.isEmpty {
                names.append(contentsOf: exactNames)
            } else if modifiers.contains(spec.logicalModifier) {
                names.append(spec.genericDisplayName)
            }
        }

        return names
    }

    private static let modifierDisplayOrder: [UInt16] = [55, 54, 59, 62, 58, 61, 56, 60, 63]

    private static let modifierDisplaySpecs: [(logicalModifier: ShortcutModifiers, genericDisplayName: String, exactDisplayNames: [(UInt16, String)])] = [
        (.command, "⌘", [(55, "⌘"), (54, "⌘ →")]),
        (.control, "⌃", [(59, "⌃"), (62, "⌃ →")]),
        (.option, "⌥", [(58, "⌥"), (61, "⌥ →")]),
        (.shift, "⇧", [(56, "⇧"), (60, "⇧ →")]),
        (.function, "fn", [(63, "fn")])
    ]
}
