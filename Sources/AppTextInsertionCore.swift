import Foundation

/// Verification outcome; only `notInserted` permits automatic paste fallback.
enum AppTextInsertionResult: Equatable {
    case inserted
    case notInserted
    case unverified
    case unavailable
}

enum AppTextInsertionCore {
    static func isWebContent<Element>(
        of element: Element,
        parent: (Element) -> Element?,
        role: (Element) -> String?,
        attributeNames: (Element) -> [String] = { _ in [] }
    ) -> Bool {
        if attributeNames(element).contains("AXDOMClassList") { return true }
        var ancestor = parent(element)
        for _ in 0..<32 {
            guard let current = ancestor else { return false }
            if role(current) == "AXWebArea" { return true }
            ancestor = parent(current)
        }
        return false
    }

    /// Checks role eligibility only; callers must still verify focus before sending Enter.
    static func isSupportedTextControl(role: String?, subrole: String?) -> Bool {
        guard subrole != "AXSecureTextField" else { return false }
        switch role {
        case "AXTextField", "AXTextArea", "AXComboBox": return true
        default: return false
        }
    }

    /// Applies stricter eligibility to reading field contents than to foreground Enter.
    static func canCapture(role: String?, subrole: String?) -> Bool {
        guard isSupportedTextControl(role: role, subrole: subrole) else { return false }
        // Native text views need not expose a subrole; secure controls use the text-field role.
        return role == "AXTextArea" || (subrole != nil && subrole != "AXUnknown")
    }

    /// Accepts exact expected text as inserted; prior ambiguity keeps paste fallback disabled.
    static func classifyWrite(
        originalValue: String,
        expectedValue: String,
        writeSucceeded: Bool,
        observedValue: String?,
        priorResult: AppTextInsertionResult? = nil
    ) -> AppTextInsertionResult {
        if matches(actual: observedValue, expected: expectedValue) {
            return .inserted
        }
        // Once a readback was ambiguous, an unchanged value cannot prove the write had no effect.
        if priorResult != .unverified,
           !writeSucceeded,
           matches(actual: observedValue, expected: originalValue) {
            return .notInserted
        }
        return .unverified
    }

    /// Replaces only the captured range; the full expected value is for readback verification.
    static func insert(
        _ text: String,
        capturedValue: String?,
        range: NSRange?,
        requiresFocus: Bool = false,
        isTargetFocused: () -> Bool = { true },
        readValue: () -> String?,
        replaceText: (_ range: NSRange, _ text: String, _ expectedValue: String) -> Bool,
        placeCursor: (NSRange) -> Void
    ) -> AppTextInsertionResult {
        guard
            let capturedValue,
            let currentValue = readValue(),
            matches(actual: currentValue, expected: capturedValue),
            let range,
            isValid(range, in: currentValue)
        else {
            return .unavailable
        }

        let (cursorLocation, cursorOverflow) = range.location.addingReportingOverflow(text.utf16.count)
        guard !cursorOverflow else { return .unavailable }
        // Blurred web editors may acknowledge AX actions without applying the edit.
        guard !requiresFocus || isTargetFocused() else { return .notInserted }

        let expectedValue = (currentValue as NSString).replacingCharacters(in: range, with: text)
        let writeSucceeded = replaceText(range, text, expectedValue)
        let valueAfterWrite = readValue()

        let result = classifyWrite(
            originalValue: currentValue,
            expectedValue: expectedValue,
            writeSucceeded: writeSucceeded,
            observedValue: valueAfterWrite
        )
        if result == .inserted, !requiresFocus || isTargetFocused() {
            placeCursor(NSRange(location: cursorLocation, length: 0))
        }
        return result
    }

    /// Validates the snapshot/range before clipboard preparation, then rechecks before issuing one paste.
    static func pasteIfTargetMatches(
        capturedValue: String?,
        range: NSRange?,
        readValue: () -> String?,
        isTargetFocused: () -> Bool,
        restoreSelection: (NSRange) -> Bool,
        readSelection: () -> NSRange?,
        preparePaste: () -> Void = {},
        paste: () -> Void
    ) -> Bool {
        guard
            let capturedValue,
            let range,
            isValid(range, in: capturedValue),
            isTargetFocused(),
            matches(actual: readValue(), expected: capturedValue),
            restoreSelection(range),
            isTargetFocused(),
            matches(actual: readValue(), expected: capturedValue),
            readSelection() == range
        else {
            return false
        }

        preparePaste()
        guard isTargetFocused(),
              matches(actual: readValue(), expected: capturedValue),
              readSelection() == range else { return false }
        paste()
        return true
    }

    /// Compares UTF-16 code units so Unicode normalization cannot hide a changed snapshot.
    private static func matches(actual: String?, expected: String) -> Bool {
        actual?.utf16.elementsEqual(expected.utf16) == true
    }

    /// Rejects out-of-bounds UTF-16 ranges and boundaries that cannot map to String indices.
    private static func isValid(_ range: NSRange, in value: String) -> Bool {
        let utf16Length = (value as NSString).length
        guard range.location >= 0,
              range.length >= 0,
              range.location <= utf16Length,
              range.length <= utf16Length - range.location
        else {
            return false
        }
        guard let stringRange = Range(range, in: value) else { return false }
        return stringRange.lowerBound.samePosition(in: value) != nil
            && stringRange.upperBound.samePosition(in: value) != nil
    }
}
