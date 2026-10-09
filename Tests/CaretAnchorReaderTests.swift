import CoreGraphics
import Foundation

enum CaretAnchorReaderTests {
    static func run() {
        timeoutIsScopedToTheAppAndFocusedElement()
        missingPidMakesNoAccessibilityCalls()
        noFocusedElementLeavesFocusedTimeoutUnset()
        emptyCaretRectIsRejected()
    }

    private final class FakeClient: CaretAnchorAXClient {
        var focused: String? = "focused"
        var bounds: CGRect? = CGRect(x: 10, y: 20, width: 2, height: 16)
        private(set) var timeouts: [(String, Float)] = []
        private(set) var calls = 0

        func applicationElement(pid: pid_t) -> String {
            calls += 1
            return "app:\(pid)"
        }

        func setMessagingTimeout(_ element: String, seconds: Float) {
            calls += 1
            timeouts.append((element, seconds))
        }

        func focusedElement(of application: String) -> String? {
            calls += 1
            return focused
        }

        func caretBounds(of element: String) -> CGRect? {
            calls += 1
            return bounds
        }
    }

    private static func timeoutIsScopedToTheAppAndFocusedElement() {
        let client = FakeClient()
        let rect = CaretAnchorReader.caretRect(pid: 42, timeout: 0.25, client: client)
        TestSupport.expectEqual(rect, CGRect(x: 10, y: 20, width: 2, height: 16))
        TestSupport.expectEqual(client.timeouts.map(\.0), ["app:42", "focused"])
        TestSupport.expect(client.timeouts.allSatisfy { $0.1 == 0.25 }, "Every scoped timeout must use the caret timeout")
    }

    private static func missingPidMakesNoAccessibilityCalls() {
        let client = FakeClient()
        TestSupport.expect(CaretAnchorReader.caretRect(pid: nil, timeout: 0.25, client: client) == nil, "No frontmost app must give no caret")
        TestSupport.expectEqual(client.calls, 0)
    }

    private static func noFocusedElementLeavesFocusedTimeoutUnset() {
        let client = FakeClient()
        client.focused = nil
        TestSupport.expect(CaretAnchorReader.caretRect(pid: 7, timeout: 0.25, client: client) == nil, "No focused element must give no caret")
        TestSupport.expectEqual(client.timeouts.map(\.0), ["app:7"])
    }

    private static func emptyCaretRectIsRejected() {
        let client = FakeClient()
        client.bounds = CGRect(x: 5, y: 5, width: 0, height: 0)
        TestSupport.expect(CaretAnchorReader.caretRect(pid: 7, timeout: 0.25, client: client) == nil, "A zero-height caret must keep the pointer anchor")
    }
}
