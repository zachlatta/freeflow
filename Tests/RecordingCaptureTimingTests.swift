enum RecordingCaptureTimingTests {
    static func run() {
        var timing = RecordingCaptureTiming()
        TestSupport.expectEqual(timing.recordingStartIfReady(rms: 0.1), nil)

        let captureStart = ContinuousClock.now
        timing.start(at: captureStart, generation: timing.prepare())
        // Silent audio is captured without making the overlay ready.
        TestSupport.expectEqual(timing.recordingStartIfReady(rms: 0), nil)
        TestSupport.expectEqual(timing.recordingStartIfReady(rms: 0), nil)

        let speechStart = captureStart.advanced(by: .seconds(5))
        guard let event = timing.recordingStartIfReady(rms: 0.1) else {
            fatalError("First non-silent audio must report readiness")
        }
        TestSupport.expectEqual(event.instant, captureStart)
        TestSupport.expect(timing.isCurrent(event), "Active recording event must be accepted")
        TestSupport.expectEqual(event.instant.duration(to: speechStart), .seconds(5))

        // Later silence and sound must not restart the timer or fire readiness again.
        TestSupport.expectEqual(timing.recordingStartIfReady(rms: 0), nil)
        TestSupport.expectEqual(timing.recordingStartIfReady(rms: 0.2), nil)

        // A new recording starts its own clock and can report readiness again.
        let nextStart = captureStart.advanced(by: .seconds(30))
        timing.start(at: nextStart, generation: timing.prepare())
        TestSupport.expectEqual(timing.recordingStartIfReady(rms: 0), nil)
        TestSupport.expectEqual(timing.recordingStartIfReady(rms: 0.1)?.instant, nextStart)
        TestSupport.expect(!timing.isCurrent(event), "New recording must reject the previous event")

        testInvalidationBeforeReadiness()
        testQueuedEventAfterCancellation()
        testRestartWithSameTimestamp()
        testCancelledStartup()
        testSupersededStartup()
        testDuplicateStartup()
    }

    private static func testInvalidationBeforeReadiness() {
        var timing = RecordingCaptureTiming()
        timing.start(at: .now, generation: timing.prepare())
        timing.invalidate()
        TestSupport.expectEqual(timing.recordingStartIfReady(rms: 0.5), nil)
    }

    private static func testQueuedEventAfterCancellation() {
        var timing = RecordingCaptureTiming()
        let start = ContinuousClock.now
        timing.start(at: start, generation: timing.prepare())
        guard let queuedEvent = timing.recordingStartIfReady(rms: 0.5) else {
            fatalError("Expected a readiness event")
        }
        timing.invalidate()
        TestSupport.expect(!timing.isCurrent(queuedEvent), "Stop/cancel must reject queued readiness")
        TestSupport.expectEqual(timing.recordingStartIfReady(rms: 0.5), nil)

        timing.start(at: start.advanced(by: .seconds(1)), generation: timing.prepare())
        TestSupport.expect(!timing.isCurrent(queuedEvent), "Queued A event must not reach recording B")
        guard let newEvent = timing.recordingStartIfReady(rms: 0.5) else {
            fatalError("New recording must report readiness")
        }
        TestSupport.expect(timing.isCurrent(newEvent), "Recording B must accept its own event")
    }

    private static func testRestartWithSameTimestamp() {
        var timing = RecordingCaptureTiming()
        let start = ContinuousClock.now
        timing.start(at: start, generation: timing.prepare())
        guard let firstEvent = timing.recordingStartIfReady(rms: 0.5) else {
            fatalError("Expected a readiness event")
        }
        timing.start(at: start, generation: timing.prepare())
        TestSupport.expect(!timing.isCurrent(firstEvent), "Session identity must not depend on timestamp")
    }

    private static func testCancelledStartup() {
        var timing = RecordingCaptureTiming()
        let pending = timing.prepare()
        TestSupport.expectEqual(timing.recordingStartIfReady(rms: 0.5), nil)
        // Capture setup finishes after cancellation. It must not revive readiness.
        timing.invalidate()
        timing.start(at: .now, generation: pending)
        TestSupport.expectEqual(timing.recordingStartIfReady(rms: 0.5), nil)
    }

    private static func testSupersededStartup() {
        var timing = RecordingCaptureTiming()
        let first = timing.prepare()
        timing.invalidate()
        let second = timing.prepare()
        let start = ContinuousClock.now
        timing.start(at: start, generation: first)
        TestSupport.expectEqual(timing.recordingStartIfReady(rms: 0.5), nil)
        let secondStart = start.advanced(by: .seconds(5))
        timing.start(at: secondStart, generation: second)
        // Even a late completion of A after B starts must not replace B's clock.
        timing.start(at: start, generation: first)
        TestSupport.expectEqual(timing.recordingStartIfReady(rms: 0.5)?.instant, secondStart)
    }

    private static func testDuplicateStartup() {
        var timing = RecordingCaptureTiming()
        let generation = timing.prepare()
        let start = ContinuousClock.now
        timing.start(at: start, generation: generation)
        timing.start(at: start.advanced(by: .seconds(5)), generation: generation)
        TestSupport.expectEqual(timing.recordingStartIfReady(rms: 0.5)?.instant, start)
        timing.start(at: start.advanced(by: .seconds(10)), generation: generation)
        TestSupport.expectEqual(timing.recordingStartIfReady(rms: 0.5), nil)
    }

}
