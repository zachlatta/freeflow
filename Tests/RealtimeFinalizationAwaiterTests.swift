import Foundation

enum RealtimeFinalizationAwaiterTests {
    private enum SyntheticError: Error, Equatable {
        case socketClosed
    }

    static func run() {
        let finished = DispatchSemaphore(value: 0)
        Task {
            await testWaitTimesOutWhenNoFinalResultArrives()
            await testSuccessResolvedBeforeWaitIgnoresLaterResults()
            await testErrorResolvedBeforeWaitIgnoresLaterResults()
            await testAlreadyCancelledWaitRemainsCancellation()
            finished.signal()
        }
        finished.wait()
    }

    private static func testWaitTimesOutWhenNoFinalResultArrives() async {
        // No competing result: a zero deadline exercises the registered
        // continuation without relying on relative task scheduling.
        let awaiter = RealtimeFinalizationAwaiter(timeoutNanoseconds: 0)

        do {
            _ = try await awaiter.wait()
            TestSupport.expect(false, "Expected an idle finalization wait to time out")
        } catch let error as RealtimeFinalizationError {
            TestSupport.expectEqual(error, .timedOut)
        } catch {
            TestSupport.expect(false, "Expected a realtime finalization timeout, got \(error)")
        }

        awaiter.resolve(.success("synthetic late transcript"))
        awaiter.resolve(.failure(CancellationError()))
        do {
            _ = try await awaiter.wait()
            TestSupport.expect(false, "Late results must not replace a timeout")
        } catch let error as RealtimeFinalizationError {
            TestSupport.expectEqual(error, .timedOut)
        } catch {
            TestSupport.expect(false, "Expected the original timeout, got \(error)")
        }
    }

    private static func testSuccessResolvedBeforeWaitIgnoresLaterResults() async {
        let awaiter = RealtimeFinalizationAwaiter(timeoutNanoseconds: 0)
        awaiter.resolve(.success("synthetic final transcript"))

        do {
            let result = try await awaiter.wait()
            TestSupport.expectEqual(result, "synthetic final transcript")
            awaiter.resolve(.success("synthetic duplicate transcript"))
            awaiter.resolve(.failure(SyntheticError.socketClosed))
            awaiter.resolve(.failure(RealtimeFinalizationError.timedOut))
            let repeatedResult = try await awaiter.wait()
            TestSupport.expectEqual(repeatedResult, "synthetic final transcript")
        } catch {
            TestSupport.expect(false, "Expected the resolved transcript, got \(error)")
        }
    }

    private static func testErrorResolvedBeforeWaitIgnoresLaterResults() async {
        let awaiter = RealtimeFinalizationAwaiter(timeoutNanoseconds: 0)
        awaiter.resolve(.failure(SyntheticError.socketClosed))

        for attempt in 0..<2 {
            if attempt == 1 {
                awaiter.resolve(.success("synthetic late transcript"))
                awaiter.resolve(.failure(RealtimeFinalizationError.timedOut))
            }
            do {
                _ = try await awaiter.wait()
                TestSupport.expect(false, "Expected the original synthetic socket error")
            } catch let error as SyntheticError {
                TestSupport.expectEqual(error, .socketClosed)
            } catch {
                TestSupport.expect(false, "Expected the original synthetic socket error, got \(error)")
            }
        }
    }

    private static func testAlreadyCancelledWaitRemainsCancellation() async {
        let awaiter = RealtimeFinalizationAwaiter(timeoutNanoseconds: 0)
        let waitTask = Task {
            // Cancel this task before entering wait, guaranteeing the
            // cancellation-before-registration path without a timing race.
            withUnsafeCurrentTask { $0?.cancel() }
            return try await awaiter.wait()
        }

        do {
            _ = try await waitTask.value
            TestSupport.expect(false, "Expected the cancelled wait to throw")
        } catch is CancellationError {
            // Expected.
        } catch {
            TestSupport.expect(false, "Expected CancellationError, got \(error)")
        }

        awaiter.resolve(.success("synthetic late transcript"))
        awaiter.resolve(.failure(RealtimeFinalizationError.timedOut))
        do {
            _ = try await awaiter.wait()
            TestSupport.expect(false, "Late results must not replace cancellation")
        } catch is CancellationError {
            // The original cancellation remains terminal.
        } catch {
            TestSupport.expect(false, "Expected the original CancellationError, got \(error)")
        }
    }
}
