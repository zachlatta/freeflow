import Foundation

@main
struct DictationShortcutSessionControllerTests {
    static func main() {
        testSingleHoldStillStartsAndStopsOnRelease()
        testDoubleTapLatchesIntoToggle()
        testDoubleTapLatchSurvivesTranscriptionOfTheFirstTap()
        testLatchedSessionIsStoppedByTheNextTap()
        testReleaseOfTheSecondTapDoesNotStop()
        testSlowSecondTapIsAnOrdinaryHold()
        testDoubleTapCanBeDisabled()
        testToggleShortcutSessionIsUnaffectedByHoldEvents()
        testHoldThenToggleStillSwitchesToToggle()
        print("DictationShortcutSessionControllerTests passed")
    }

    // MARK: - Existing behaviour must not change

    private static func testSingleHoldStillStartsAndStopsOnRelease() {
        let clock = TestClock()
        let controller = makeController(clock: clock)

        expectEqual(controller.handle(event: .holdActivated, isTranscribing: false), .start(.hold))
        clock.advance(1.0)
        expectEqual(controller.handle(event: .holdDeactivated, isTranscribing: false), .stop)
        expect(controller.activeMode == nil, "Session should be over after the key is released")
    }

    private static func testToggleShortcutSessionIsUnaffectedByHoldEvents() {
        let clock = TestClock()
        let controller = makeController(clock: clock)

        expectEqual(controller.handle(event: .toggleActivated, isTranscribing: false), .start(.toggle))
        expectEqual(controller.handle(event: .holdActivated, isTranscribing: false), nil)
        expectEqual(controller.handle(event: .holdDeactivated, isTranscribing: false), nil)
        expect(controller.activeMode == .toggle, "A toggle session must ignore hold events")

        expectEqual(controller.handle(event: .toggleDeactivated, isTranscribing: false), nil)
        expectEqual(controller.handle(event: .toggleActivated, isTranscribing: false), .stop)
    }

    private static func testHoldThenToggleStillSwitchesToToggle() {
        let clock = TestClock()
        let controller = makeController(clock: clock)

        expectEqual(controller.handle(event: .holdActivated, isTranscribing: false), .start(.hold))
        expectEqual(controller.handle(event: .toggleActivated, isTranscribing: false), .switchedToToggle)
        // Entered from the toggle shortcut, so the hold key must not end it.
        expectEqual(controller.handle(event: .holdDeactivated, isTranscribing: false), nil)
        expect(controller.activeMode == .toggle, "Latched session should still be running")
    }

    // MARK: - Double tap

    private static func testDoubleTapLatchesIntoToggle() {
        let clock = TestClock()
        let controller = makeController(clock: clock)

        expectEqual(controller.handle(event: .holdActivated, isTranscribing: false), .start(.hold))
        clock.advance(0.09)
        expectEqual(controller.handle(event: .holdDeactivated, isTranscribing: false), .stop)
        clock.advance(0.15)
        expectEqual(controller.handle(event: .holdActivated, isTranscribing: false), .start(.toggle))
        expect(controller.activeMode == .toggle, "The second tap should latch")
    }

    private static func testDoubleTapLatchSurvivesTranscriptionOfTheFirstTap() {
        let clock = TestClock()
        let controller = makeController(clock: clock)

        _ = controller.handle(event: .holdActivated, isTranscribing: false)
        clock.advance(0.08)
        _ = controller.handle(event: .holdDeactivated, isTranscribing: false)
        // The first tap's near-empty clip is still in flight. The second tap
        // must not be swallowed, or the speaker gets nothing at all.
        clock.advance(0.12)
        expectEqual(controller.handle(event: .holdActivated, isTranscribing: true), .start(.toggle))
    }

    private static func testLatchedSessionIsStoppedByTheNextTap() {
        let clock = TestClock()
        let controller = makeController(clock: clock)

        _ = controller.handle(event: .holdActivated, isTranscribing: false)
        clock.advance(0.08)
        _ = controller.handle(event: .holdDeactivated, isTranscribing: false)
        clock.advance(0.12)
        expectEqual(controller.handle(event: .holdActivated, isTranscribing: false), .start(.toggle))

        clock.advance(0.05)
        expectEqual(controller.handle(event: .holdDeactivated, isTranscribing: false), nil)
        clock.advance(12.0)
        expectEqual(controller.handle(event: .holdActivated, isTranscribing: false), .stop)
        expect(controller.activeMode == nil, "The third tap should end the latched session")
    }

    private static func testReleaseOfTheSecondTapDoesNotStop() {
        let clock = TestClock()
        let controller = makeController(clock: clock)

        _ = controller.handle(event: .holdActivated, isTranscribing: false)
        clock.advance(0.08)
        _ = controller.handle(event: .holdDeactivated, isTranscribing: false)
        clock.advance(0.12)
        _ = controller.handle(event: .holdActivated, isTranscribing: false)

        clock.advance(0.06)
        expectEqual(controller.handle(event: .holdDeactivated, isTranscribing: false), nil)
        expect(controller.activeMode == .toggle, "Letting go of the second tap must keep recording")
    }

    private static func testSlowSecondTapIsAnOrdinaryHold() {
        let clock = TestClock()
        let controller = makeController(clock: clock)

        _ = controller.handle(event: .holdActivated, isTranscribing: false)
        clock.advance(0.5)
        _ = controller.handle(event: .holdDeactivated, isTranscribing: false)
        clock.advance(0.9)
        expectEqual(controller.handle(event: .holdActivated, isTranscribing: false), .start(.hold))
        expect(controller.activeMode == .hold, "A slow second press is just another hold")
    }

    private static func testDoubleTapCanBeDisabled() {
        let clock = TestClock()
        let controller = makeController(clock: clock, enabled: false)

        _ = controller.handle(event: .holdActivated, isTranscribing: false)
        clock.advance(0.08)
        _ = controller.handle(event: .holdDeactivated, isTranscribing: false)
        clock.advance(0.12)
        expectEqual(controller.handle(event: .holdActivated, isTranscribing: false), .start(.hold))
    }

    // MARK: - Helpers

    private final class TestClock {
        private var current = Date(timeIntervalSince1970: 1_000_000)
        func advance(_ seconds: TimeInterval) { current = current.addingTimeInterval(seconds) }
        func now() -> Date { current }
    }

    private static func makeController(clock: TestClock, enabled: Bool = true) -> DictationShortcutSessionController {
        DictationShortcutSessionController(
            doubleTapLatchEnabled: enabled,
            doubleTapWindow: 0.4,
            now: { clock.now() }
        )
    }

    private static func expectEqual(
        _ actual: DictationShortcutAction?,
        _ expected: DictationShortcutAction?,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        expect(
            actual == expected,
            "Expected \(String(describing: expected)), got \(String(describing: actual))",
            file: file,
            line: line
        )
    }

    private static func expect(_ condition: Bool, _ message: String, file: StaticString = #file, line: UInt = #line) {
        if !condition {
            fatalError("\(file):\(line): \(message)")
        }
    }
}
