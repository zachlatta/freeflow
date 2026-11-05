import ApplicationServices
import CoreGraphics

/// The accessibility calls the near-cursor caret lookup makes. Kept behind a
/// protocol so tests can check which elements get a messaging timeout.
protocol CaretAnchorAXClient {
    associatedtype Element

    func applicationElement(pid: pid_t) -> Element
    func setMessagingTimeout(_ element: Element, seconds: Float)
    func focusedElement(of application: Element) -> Element?
    func caretBounds(of element: Element) -> CGRect?
}

enum CaretAnchorReader {
    /// Reads the focused caret rect of the app with `pid`. The messaging
    /// timeout is set only on that app's element and its focused element,
    /// never on the system-wide element, whose timeout is the process-wide
    /// default for every other accessibility call.
    static func caretRect<Client: CaretAnchorAXClient>(
        pid: pid_t?,
        timeout: Float,
        client: Client
    ) -> CGRect? {
        guard let pid else { return nil }
        let application = client.applicationElement(pid: pid)
        client.setMessagingTimeout(application, seconds: timeout)
        guard let focused = client.focusedElement(of: application) else { return nil }
        client.setMessagingTimeout(focused, seconds: timeout)
        guard let rect = client.caretBounds(of: focused),
              rect.height > 0,
              rect != .zero else { return nil }
        return rect
    }
}

struct SystemCaretAnchorAXClient: CaretAnchorAXClient {
    func applicationElement(pid: pid_t) -> AXUIElement {
        AXUIElementCreateApplication(pid)
    }

    func setMessagingTimeout(_ element: AXUIElement, seconds: Float) {
        _ = AXUIElementSetMessagingTimeout(element, seconds)
    }

    func focusedElement(of application: AXUIElement) -> AXUIElement? {
        var focusedValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            application,
            kAXFocusedUIElementAttribute as CFString,
            &focusedValue
        ) == .success,
              let focusedRaw = focusedValue,
              CFGetTypeID(focusedRaw) == AXUIElementGetTypeID() else { return nil }
        return unsafeBitCast(focusedRaw, to: AXUIElement.self)
    }

    func caretBounds(of element: AXUIElement) -> CGRect? {
        var rangeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            &rangeValue
        ) == .success,
              let rangeRaw = rangeValue,
              CFGetTypeID(rangeRaw) == AXValueGetTypeID() else { return nil }

        var boundsValue: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXBoundsForRangeParameterizedAttribute as CFString,
            rangeRaw,
            &boundsValue
        ) == .success,
              let boundsRaw = boundsValue,
              CFGetTypeID(boundsRaw) == AXValueGetTypeID() else { return nil }

        var rect = CGRect.zero
        guard AXValueGetValue(unsafeBitCast(boundsRaw, to: AXValue.self), .cgRect, &rect) else { return nil }
        return rect
    }
}
