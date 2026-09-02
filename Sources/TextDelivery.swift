import AppKit
import ApplicationServices
import Carbon
import Foundation

/// Where a transcript should land, captured at the moment the user stops
/// dictating. The point of pinning this is that transcription is asynchronous:
/// by the time text is ready the user may have switched app, window, tab or
/// Space. Delivery must go back to the element they were writing in, without
/// dragging their focus along with it.
struct DeliveryTarget {
    let sessionID: UUID
    let processIdentifier: pid_t
    let bundleIdentifier: String?
    let appName: String?
    /// The UI element that had keyboard focus at stop time. Held as a live
    /// AXUIElement reference so delivery targets that element specifically,
    /// not "whatever is focused now".
    let focusedElement: AXUIElement?
    let elementRole: String?
    let capturedAt: Date

    var describedApp: String {
        appName ?? bundleIdentifier ?? "pid \(processIdentifier)"
    }
}

/// Ordered delivery strategies, cheapest and least intrusive first.
enum DeliveryTier: String {
    /// Accessibility write straight into the pinned text element. No focus
    /// change, works across Spaces, works while the app is in the background.
    case accessibilityInsert = "ax-insert"
    /// Synthesised key events addressed to the target process. No activation,
    /// but the app only sees them if it processes background key events.
    case processKeystroke = "pid-keystroke"
    /// Bring the app forward and press Cmd-V. Steals focus; opt-in only.
    case activateAndPaste = "activate-paste"
    /// Leave the text on the clipboard and tell the user it is waiting.
    case clipboardOnly = "clipboard"
}

struct DeliveryOutcome {
    let tier: DeliveryTier
    let succeeded: Bool
    let target: String
    let attempts: [String]

    var summary: String {
        "\(tier.rawValue) → \(target)"
    }
}

/// Delivers transcripts to a pinned target without disturbing the user's
/// current focus. Stateless apart from configuration; every call carries its
/// own target so several dictations can be in flight at once.
final class TextDeliveryService {

    /// Allow the focus-stealing tier (activate + Cmd-V) as a last resort
    /// before falling back to clipboard-only.
    var allowFocusStealFallback: Bool

    /// Allow synthesised key events addressed to the target process.
    var allowProcessKeystroke: Bool

    init(allowFocusStealFallback: Bool = false, allowProcessKeystroke: Bool = true) {
        self.allowFocusStealFallback = allowFocusStealFallback
        self.allowProcessKeystroke = allowProcessKeystroke
    }

    // MARK: - Capture

    /// Pins the currently focused app and text element. Call this at stop time,
    /// before anything can change focus.
    ///
    /// - Parameter fallbackBundleIdentifier: bundle id captured at recording
    ///   start, used when the app itself is frontmost (the user clicked stop in
    ///   the menu bar rather than releasing a hotkey).
    static func captureTarget(
        sessionID: UUID = UUID(),
        ownBundleIdentifier: String?,
        fallbackBundleIdentifier: String?
    ) -> DeliveryTarget? {
        var app: NSRunningApplication?

        if let front = NSWorkspace.shared.frontmostApplication,
           front.bundleIdentifier != ownBundleIdentifier {
            app = front
        } else if let fallbackBundleIdentifier, fallbackBundleIdentifier != ownBundleIdentifier {
            app = NSWorkspace.shared.runningApplications.first {
                $0.bundleIdentifier == fallbackBundleIdentifier && $0.activationPolicy == .regular
            }
        }

        guard let app else { return nil }

        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        // Chromium and Electron keep their accessibility tree switched off
        // until something asks for it. Harmless everywhere else.
        AXUIElementSetAttributeValue(appElement, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        let focused = Self.copyElement(appElement, kAXFocusedUIElementAttribute as CFString)
        let role = focused.flatMap { Self.copyString($0, kAXRoleAttribute as CFString) }

        return DeliveryTarget(
            sessionID: sessionID,
            processIdentifier: app.processIdentifier,
            bundleIdentifier: app.bundleIdentifier,
            appName: app.localizedName,
            focusedElement: focused,
            elementRole: role,
            capturedAt: Date()
        )
    }

    // MARK: - Delivery

    /// Runs the tier ladder for one transcript. The caller is responsible for
    /// having placed `text` on the pasteboard already when it wants the
    /// clipboard tiers to work.
    @discardableResult
    func deliver(
        _ text: String,
        to target: DeliveryTarget?,
        completion: @escaping (DeliveryOutcome) -> Void
    ) -> Bool {
        var attempts: [String] = []

        guard let target else {
            attempts.append("no target captured")
            completion(DeliveryOutcome(
                tier: .clipboardOnly,
                succeeded: false,
                target: "none",
                attempts: attempts
            ))
            return false
        }

        let describedApp = target.describedApp
        // Terminals expose an AXTextArea that can report kAXSelectedText as
        // settable while the write only touches the display and never reaches
        // the tty. Send keys there first and treat the AX path as the fallback.
        let preferKeystroke = Self.isTerminalLike(target)

        if isTerminated(target) {
            attempts.append("target app no longer running")
            completion(DeliveryOutcome(
                tier: .clipboardOnly,
                succeeded: false,
                target: describedApp,
                attempts: attempts
            ))
            return false
        }

        if preferKeystroke, allowProcessKeystroke {
            if postUnicode(text, toProcess: target.processIdentifier) {
                attempts.append("pid-keystroke posted (terminal-like target)")
                completion(DeliveryOutcome(
                    tier: .processKeystroke,
                    succeeded: true,
                    target: describedApp,
                    attempts: attempts
                ))
                return true
            }
            attempts.append("pid-keystroke could not be posted")
        }

        // Tier 1 — Accessibility insert into the pinned element.
        switch insertViaAccessibility(text, target: target) {
        case .success:
            attempts.append("ax-insert ok")
            completion(DeliveryOutcome(
                tier: .accessibilityInsert,
                succeeded: true,
                target: describedApp,
                attempts: attempts
            ))
            return true
        case .failure(let reason):
            attempts.append("ax-insert failed: \(reason)")
        }

        // Tier 2 — key events posted to the process, no activation.
        if allowProcessKeystroke && !preferKeystroke {
            if postUnicode(text, toProcess: target.processIdentifier) {
                attempts.append("pid-keystroke posted")
                completion(DeliveryOutcome(
                    tier: .processKeystroke,
                    succeeded: true,
                    target: describedApp,
                    attempts: attempts
                ))
                return true
            }
            attempts.append("pid-keystroke could not be posted")
        } else {
            attempts.append("pid-keystroke disabled")
        }

        // Tier 3 — focus steal, opt-in only.
        if allowFocusStealFallback, let app = runningApplication(for: target) {
            attempts.append("activating \(describedApp)")
            app.activate(options: [.activateIgnoringOtherApps])
            waitUntilFrontmost(app, attemptsLeft: 20) { [weak self] in
                self?.sendCmdV()
                completion(DeliveryOutcome(
                    tier: .activateAndPaste,
                    succeeded: true,
                    target: describedApp,
                    attempts: attempts
                ))
            }
            return true
        }

        // Tier 4 — leave it on the clipboard.
        attempts.append("left on clipboard")
        completion(DeliveryOutcome(
            tier: .clipboardOnly,
            succeeded: false,
            target: describedApp,
            attempts: attempts
        ))
        return false
    }

    /// Terminal emulators and other apps whose text area is a rendered view
    /// rather than a real editable field.
    static func isTerminalLike(_ target: DeliveryTarget) -> Bool {
        let terminalBundles: Set<String> = [
            "com.apple.Terminal",
            "com.googlecode.iterm2",
            "dev.warp.Warp-Stable",
            "dev.warp.Warp-Preview",
            "net.kovidgoyal.kitty",
            "io.alacritty",
            "com.mitchellh.ghostty",
            "com.github.wez.wezterm",
            "co.zeit.hyper",
            "com.tabby.app"
        ]
        if let bundle = target.bundleIdentifier, terminalBundles.contains(bundle) {
            return true
        }
        return false
    }

    // MARK: - Tier 1: Accessibility

    private enum InsertResult {
        case success
        case failure(String)
    }

    private func insertViaAccessibility(_ text: String, target: DeliveryTarget) -> InsertResult {
        guard let element = target.focusedElement else {
            return .failure("no focused element captured")
        }

        // A stale reference reports kAXErrorInvalidUIElement on any read.
        var roleValue: CFTypeRef?
        let roleStatus = AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleValue)
        guard roleStatus == .success else {
            return .failure("element gone (\(Self.describe(roleStatus)))")
        }

        var settable: DarwinBoolean = false
        let settableStatus = AXUIElementIsAttributeSettable(
            element,
            kAXSelectedTextAttribute as CFString,
            &settable
        )
        guard settableStatus == .success, settable.boolValue else {
            return .failure("selected text not settable (\(Self.describe(settableStatus)))")
        }

        let setStatus = AXUIElementSetAttributeValue(
            element,
            kAXSelectedTextAttribute as CFString,
            text as CFTypeRef
        )
        guard setStatus == .success else {
            return .failure("set failed (\(Self.describe(setStatus)))")
        }

        return .success
    }

    // MARK: - Tier 2: key events to a process

    /// Posts `text` as unicode key events addressed to a single process, so no
    /// activation and no Space switch is needed. Chunked because a single
    /// event's unicode payload is not reliably honoured beyond a short string.
    private func postUnicode(_ text: String, toProcess pid: pid_t) -> Bool {
        guard !text.isEmpty else { return false }
        guard let source = CGEventSource(stateID: .hidSystemState) else { return false }

        let units = Array(text.utf16)
        let chunkSize = 16
        var index = 0

        while index < units.count {
            let end = min(index + chunkSize, units.count)
            var chunk = Array(units[index..<end])

            guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
                  let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) else {
                return false
            }

            keyDown.flags = []
            keyUp.flags = []
            keyDown.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: &chunk)
            keyUp.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: &chunk)

            keyDown.postToPid(pid)
            keyUp.postToPid(pid)

            index = end
        }

        return true
    }

    /// Presses Return in the target, matching however the text got there.
    func pressReturn(target: DeliveryTarget, tier: DeliveryTier) {
        switch tier {
        case .accessibilityInsert, .processKeystroke:
            guard let source = CGEventSource(stateID: .hidSystemState) else { return }
            let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 36, keyDown: true)
            let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 36, keyDown: false)
            keyDown?.postToPid(target.processIdentifier)
            keyUp?.postToPid(target.processIdentifier)
        case .activateAndPaste:
            guard let source = CGEventSource(stateID: .hidSystemState) else { return }
            CGEvent(keyboardEventSource: source, virtualKey: 36, keyDown: true)?
                .post(tap: .cgSessionEventTap)
            CGEvent(keyboardEventSource: source, virtualKey: 36, keyDown: false)?
                .post(tap: .cgSessionEventTap)
        case .clipboardOnly:
            break
        }
    }

    // MARK: - Tier 3: activate and paste

    private func waitUntilFrontmost(
        _ app: NSRunningApplication,
        attemptsLeft: Int,
        completion: @escaping () -> Void
    ) {
        if NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier
            || attemptsLeft <= 0 {
            completion()
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.waitUntilFrontmost(app, attemptsLeft: attemptsLeft - 1, completion: completion)
        }
    }

    private func sendCmdV() {
        guard let source = CGEventSource(stateID: .hidSystemState) else { return }
        let vKeyCode = Self.keyCodeForCharacter("v") ?? 9

        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true)
        keyDown?.flags = .maskCommand
        keyDown?.post(tap: .cgSessionEventTap)

        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false)
        keyUp?.flags = .maskCommand
        keyUp?.post(tap: .cgSessionEventTap)
    }

    // MARK: - Helpers

    private func runningApplication(for target: DeliveryTarget) -> NSRunningApplication? {
        NSRunningApplication(processIdentifier: target.processIdentifier)
    }

    private func isTerminated(_ target: DeliveryTarget) -> Bool {
        guard let app = runningApplication(for: target) else { return true }
        return app.isTerminated
    }

    static func copyElement(_ element: AXUIElement, _ attribute: CFString) -> AXUIElement? {
        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(element, attribute, &value)
        guard status == .success,
              let raw = value,
              CFGetTypeID(raw) == AXUIElementGetTypeID() else {
            return nil
        }
        return unsafeBitCast(raw, to: AXUIElement.self)
    }

    static func copyString(_ element: AXUIElement, _ attribute: CFString) -> String? {
        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(element, attribute, &value)
        guard status == .success, let string = value as? String else { return nil }
        return string
    }

    static func describe(_ error: AXError) -> String {
        switch error {
        case .success: return "success"
        case .failure: return "failure"
        case .illegalArgument: return "illegalArgument"
        case .invalidUIElement: return "invalidUIElement"
        case .invalidUIElementObserver: return "invalidUIElementObserver"
        case .cannotComplete: return "cannotComplete"
        case .attributeUnsupported: return "attributeUnsupported"
        case .actionUnsupported: return "actionUnsupported"
        case .notificationUnsupported: return "notificationUnsupported"
        case .notImplemented: return "notImplemented"
        case .notificationAlreadyRegistered: return "notificationAlreadyRegistered"
        case .notificationNotRegistered: return "notificationNotRegistered"
        case .apiDisabled: return "apiDisabled"
        case .noValue: return "noValue"
        case .parameterizedAttributeUnsupported: return "parameterizedAttributeUnsupported"
        case .notEnoughPrecision: return "notEnoughPrecision"
        @unknown default: return "unknown(\(error.rawValue))"
        }
    }

    static func keyCodeForCharacter(_ character: String) -> CGKeyCode? {
        guard let char = character.lowercased().utf16.first else { return nil }
        let source = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
        guard let layoutDataRef = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            return nil
        }
        let layoutData = unsafeBitCast(layoutDataRef, to: CFData.self) as Data
        return layoutData.withUnsafeBytes { (ptr: UnsafeRawBufferPointer) -> CGKeyCode? in
            guard let layout = ptr.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else {
                return nil
            }
            for keyCode in UInt16(0)..<UInt16(128) {
                var chars = [UniChar](repeating: 0, count: 4)
                var charCount = 0
                var deadKeyState: UInt32 = 0
                let status = UCKeyTranslate(
                    layout, keyCode, UInt16(kUCKeyActionDisplay), 0,
                    UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysBit),
                    &deadKeyState, 4, &charCount, &chars
                )
                if status == noErr, charCount > 0, chars[0] == char {
                    return CGKeyCode(keyCode)
                }
            }
            return nil
        }
    }
}
