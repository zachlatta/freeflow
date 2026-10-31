import AppKit
import ApplicationServices
import Foundation

/// Kept only for the active dictation; field contents never enter provider requests or history.
struct AppTextInsertionTarget {
    let identifier = UUID()
    let element: AXUIElement
    let window: AXUIElement?
    let valueAtCapture: String?
    let selectedTextRange: NSRange?
    let processIdentifier: pid_t
    let allowsTextCapture: Bool
    let isSupportedTextControl: Bool
    let isWebContent: Bool

    /// Requests normal native Accessibility support; Electron builds its editor tree asynchronously.
    static func prepareAccessibility(processIdentifier: pid_t) {
        _ = attribute(from: AXUIElementCreateApplication(processIdentifier), name: kAXRoleAttribute)
    }

    /// Captures element identity; excludes known secure controls and limits text/range reads by role.
    static func capture(from app: AXUIElement, processIdentifier: pid_t) -> Self? {
        guard let element = accessibilityElement(from: app, attribute: kAXFocusedUIElementAttribute),
              attribute(from: element, name: kAXSubroleAttribute) as? String != kAXSecureTextFieldSubrole else {
            return nil
        }
        let role = attribute(from: element, name: kAXRoleAttribute) as? String
        let subrole = attribute(from: element, name: kAXSubroleAttribute) as? String
        let canCaptureValue = AppTextInsertionCore.canCapture(role: role, subrole: subrole)
        let isWebContent = canCaptureValue && Self.isWebContent(of: element)
        return Self(
            element: element,
            window: accessibilityElement(from: app, attribute: kAXFocusedWindowAttribute),
            valueAtCapture: canCaptureValue ? textValue(from: element) : nil,
            selectedTextRange: canCaptureValue ? selection(from: element) : nil,
            processIdentifier: processIdentifier,
            allowsTextCapture: canCaptureValue,
            isSupportedTextControl: AppTextInsertionCore.isSupportedTextControl(role: role, subrole: subrole),
            isWebContent: isWebContent
        )
    }

    /// Requires the original AX element in the frontmost app, excluding known secure fields.
    var isFocused: Bool {
        NSWorkspace.shared.frontmostApplication?.processIdentifier == processIdentifier && isFocusedInApplication
    }

    /// Checks retained element focus within its owning app, including while that app is inactive.
    var isFocusedInApplication: Bool {
        guard let focused = Self.accessibilityElement(
                from: AXUIElementCreateApplication(processIdentifier),
                attribute: kAXFocusedUIElementAttribute
              ) else { return false }
        return CFEqual(focused, element)
            && Self.attribute(from: focused, name: kAXSubroleAttribute) as? String != kAXSecureTextFieldSubrole
    }

    var isMinimized: Bool {
        guard let window else { return false }
        return Self.attribute(from: window, name: kAXMinimizedAttribute) as? Bool ?? false
    }

    /// Allows PID-directed Enter without activation when an eligible text control retains app focus.
    var canSendEnter: Bool {
        allowsTextCapture && isFocusedInApplication && Self.canReadText(from: element)
    }

    /// Requests a window-state change without confirming success; callers guard session ownership.
    func setMinimized(_ minimized: Bool) {
        guard let window else { return }
        AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString,
                                    minimized ? kCFBooleanTrue : kCFBooleanFalse)
    }

    /// Reports AX setter acknowledgement; callers must verify focus before sending input.
    func focus() -> Bool {
        AXUIElementSetAttributeValue(element, kAXFocusedAttribute as CFString, kCFBooleanTrue) == .success
    }

    /// Attempts one range-local write, then verifies readback without repeating the write.
    /// The caller checks session ownership before entry; `isCurrent` guards delayed verification.
    func insert(
        _ text: String, isCurrent: @escaping () -> Bool,
        completion: @escaping (AppTextInsertionResult) -> Void
    ) {
        var expectedValue: String?
        var writeSucceeded = false
        let result = AppTextInsertionCore.insert(
            text, capturedValue: valueAtCapture, range: selectedTextRange,
            requiresFocus: isWebContent,
            isTargetFocused: { isFocusedInApplication },
            readValue: { Self.textValue(from: element) },
            replaceText: { range, replacementText, expectedReadbackValue in
                var settable = DarwinBoolean(false)
                guard AXUIElementIsAttributeSettable(
                    element, kAXSelectedTextAttribute as CFString, &settable
                ) == .success,
                settable.boolValue else { return false }
                guard setSelection(range) else { return false }
                guard let capturedValue = valueAtCapture,
                      let currentValue = Self.textValue(from: element),
                      currentValue.utf16.elementsEqual(capturedValue.utf16),
                      Self.selection(from: element) == range else { return false }
                guard !isWebContent || isFocusedInApplication else { return false }
                expectedValue = expectedReadbackValue
                writeSucceeded = AXUIElementSetAttributeValue(
                    element, kAXSelectedTextAttribute as CFString, replacementText as CFString
                ) == .success
                return writeSucceeded
            },
            placeCursor: { range in _ = setSelection(range) }
        )
        guard result != .inserted, let expectedValue, let originalValue = valueAtCapture,
              let range = selectedTextRange else {
            completion(result)
            return
        }
        // Core validated this cursor arithmetic before attempting the write.
        let cursor = NSRange(location: range.location + text.utf16.count, length: 0)
        verifyWrite(
            originalValue: originalValue, expectedValue: expectedValue, writeSucceeded: writeSucceeded,
            cursor: cursor, attempt: 0, priorResult: result, isCurrent: isCurrent, completion: completion
        )
    }

    /// Carries ambiguity across polls so a later unchanged value cannot authorize fallback paste.
    private func verifyWrite(
        originalValue: String, expectedValue: String, writeSucceeded: Bool, cursor: NSRange,
        attempt: Int, priorResult: AppTextInsertionResult, isCurrent: @escaping () -> Bool,
        completion: @escaping (AppTextInsertionResult) -> Void
    ) {
        // Some editors acknowledge AX writes before their value updates. Never repeat the write.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            guard isCurrent() else {
                completion(.unavailable)
                return
            }
            let result = AppTextInsertionCore.classifyWrite(
                originalValue: originalValue, expectedValue: expectedValue, writeSucceeded: writeSucceeded,
                observedValue: Self.textValue(from: element), priorResult: priorResult
            )
            if result == .inserted {
                _ = setSelection(cursor)
                completion(result)
            } else if attempt < 9 {
                verifyWrite(
                    originalValue: originalValue, expectedValue: expectedValue, writeSucceeded: writeSucceeded,
                    cursor: cursor, attempt: attempt + 1, priorResult: result,
                    isCurrent: isCurrent, completion: completion
                )
            } else {
                completion(result)
            }
        }
    }

    /// Checks captured text/range before clipboard preparation and again before posting paste.
    /// A focused target preserves newer selections; activation fallback can restore the captured range.
    func pasteIfUnchanged(
        restoringSelection: Bool, isCurrent: () -> Bool,
        preparePaste: () -> Void, paste: () -> Void
    ) -> Bool {
        AppTextInsertionCore.pasteIfTargetMatches(
            capturedValue: valueAtCapture, range: selectedTextRange,
            readValue: { Self.textValue(from: element) },
            isTargetFocused: { isCurrent() && isFocused },
            restoreSelection: { restoringSelection ? setSelection($0) : Self.selection(from: element) == $0 },
            readSelection: { Self.selection(from: element) },
            preparePaste: preparePaste,
            paste: paste
        )
    }

    /// Requires exact range readback rather than trusting AX setter success alone.
    private func setSelection(_ range: NSRange) -> Bool {
        guard !isWebContent || isFocusedInApplication else { return false }
        var selectedRange = CFRange(location: range.location, length: range.length)
        guard let value = AXValueCreate(.cfRange, &selectedRange),
              AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, value) == .success else {
            return false
        }
        return Self.selection(from: element) == range
    }

    private static func attribute(from element: AXUIElement, name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }

    private static func accessibilityElement(from element: AXUIElement, attribute name: String) -> AXUIElement? {
        guard let value = attribute(from: element, name: name),
              CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return unsafeBitCast(value, to: AXUIElement.self)
    }

    /// Uses AX attribute names only before falling back to bounded parent-role traversal.
    private static func isWebContent(of element: AXUIElement) -> Bool {
        AppTextInsertionCore.isWebContent(
            of: element,
            parent: { accessibilityElement(from: $0, attribute: kAXParentAttribute) },
            role: { attribute(from: $0, name: kAXRoleAttribute) as? String },
            attributeNames: { attributeNames(from: $0) }
        )
    }

    private static func attributeNames(from element: AXUIElement) -> [String] {
        var names: CFArray?
        guard AXUIElementCopyAttributeNames(element, &names) == .success,
              let names else { return [] }
        return (names as? [String]) ?? []
    }

    /// Reads plain text for comparison only; attributed content must never become a full-field write.
    private static func textValue(from element: AXUIElement) -> String? {
        guard canReadText(from: element),
              let value = attribute(from: element, name: kAXValueAttribute) else { return nil }
        if let text = value as? String { return text }
        return (value as? NSAttributedString)?.string
    }

    /// Rechecks the current role/subrole; capture-time eligibility alone cannot authorize later reads.
    private static func canReadText(from element: AXUIElement) -> Bool {
        AppTextInsertionCore.canCapture(
            role: attribute(from: element, name: kAXRoleAttribute) as? String,
            subrole: attribute(from: element, name: kAXSubroleAttribute) as? String
        )
    }

    /// Reads a UTF-16 AX range; insertion validates its bounds against the captured text.
    private static func selection(from element: AXUIElement) -> NSRange? {
        guard let value = attribute(from: element, name: kAXSelectedTextRangeAttribute),
              CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var range = CFRange()
        guard AXValueGetValue(unsafeBitCast(value, to: AXValue.self), .cfRange, &range) else { return nil }
        return NSRange(location: range.location, length: range.length)
    }
}
