/// Keeps capture duration independent of when the first non-silent buffer arrives.
/// AudioRecorder protects this state with its captureTiming lock.
struct RecordingCaptureTiming {
    struct ReadyEvent: Equatable {
        let generation: UInt64
        let instant: ContinuousClock.Instant
    }

    private var generation: UInt64 = 0
    private var startedAt: ContinuousClock.Instant?
    private var reportedReady = false

    /// Reserves identity before background capture setup can race with cancellation.
    mutating func prepare() -> UInt64 {
        invalidate()
        return generation
    }

    /// Attaches capture time only if this startup request has not been superseded.
    mutating func start(at instant: ContinuousClock.Instant, generation: UInt64) {
        guard self.generation == generation, startedAt == nil else { return }
        startedAt = instant
    }

    /// Invalidates queued readiness callbacks before asynchronous shutdown begins.
    mutating func invalidate() {
        generation &+= 1
        startedAt = nil
        reportedReady = false
    }

    /// Reports readiness once per recording, carrying its identity and start instant.
    mutating func recordingStartIfReady(rms: Float) -> ReadyEvent? {
        guard !reportedReady, rms > 0, let startedAt else { return nil }
        reportedReady = true
        return ReadyEvent(generation: generation, instant: startedAt)
    }

    func isCurrent(_ event: ReadyEvent) -> Bool {
        startedAt != nil && event.generation == generation
    }
}
