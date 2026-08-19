import Foundation

enum RealtimeFinalizationAwaiterTests {
    static func run() {
        let finished = DispatchSemaphore(value: 0)
        Task {
            await testWaitTimesOutWhenNoFinalResultArrives()
            await testResolvedResultWinsBeforeDeadline()
            await testCancellationRemainsCancellation()
            finished.signal()
        }
        finished.wait()
    }

    private static func testWaitTimesOutWhenNoFinalResultArrives() async {
        let awaiter = RealtimeFinalizationAwaiter(timeoutNanoseconds: 1_000_000)

        do {
            _ = try await awaiter.wait()
            TestSupport.expect(false, "Expected an idle finalization wait to time out")
        } catch let error as RealtimeFinalizationError {
            TestSupport.expectEqual(error, .timedOut)
        } catch {
            TestSupport.expect(false, "Expected a realtime finalization timeout, got \(error)")
        }
    }

    private static func testResolvedResultWinsBeforeDeadline() async {
        let awaiter = RealtimeFinalizationAwaiter(timeoutNanoseconds: 100_000_000)
        Task {
            try? await Task.sleep(nanoseconds: 1_000_000)
            awaiter.resolve(.success("synthetic final transcript"))
        }

        do {
            let result = try await awaiter.wait()
            TestSupport.expectEqual(result, "synthetic final transcript")
            try? await Task.sleep(nanoseconds: 120_000_000)
        } catch {
            TestSupport.expect(false, "Expected the resolved transcript, got \(error)")
        }
    }

    private static func testCancellationRemainsCancellation() async {
        let awaiter = RealtimeFinalizationAwaiter(timeoutNanoseconds: 1_000_000_000)
        let waitTask = Task {
            try await awaiter.wait()
        }
        waitTask.cancel()

        do {
            _ = try await waitTask.value
            TestSupport.expect(false, "Expected the cancelled wait to throw")
        } catch is CancellationError {
            // Expected.
        } catch {
            TestSupport.expect(false, "Expected CancellationError, got \(error)")
        }
    }
}
