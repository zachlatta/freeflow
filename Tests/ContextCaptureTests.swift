import Foundation

@MainActor
final class TestContextService {
    private var completion: CheckedContinuation<AppContext, Never>?
    private var started: CheckedContinuation<Void, Never>?
    private(set) var calls = 0

    func collectContext() async -> AppContext {
        calls += 1
        return await withCheckedContinuation { continuation in
            completion = continuation
            started?.resume()
            started = nil
        }
    }

    func waitForStart() async {
        if completion != nil { return }
        await withCheckedContinuation { started = $0 }
    }

    func finish() {
        completion?.resume(returning: AppContext(
            appName: "Synthetic Editor", bundleIdentifier: "test.editor", windowTitle: "Fixture",
            selectedText: "Synthetic selection", currentActivity: "Synthetic context",
            contextSystemPrompt: nil, contextPrompt: nil,
            screenshotDataURL: "synthetic-image", screenshotMimeType: "image/png", screenshotError: nil
        ))
        completion = nil
    }
}

enum ContextCaptureTests {
    @MainActor static func run() async {
        let suite = "FreeFlowTests.ContextCapture.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        TestSupport.expect(TestContextState(defaults: defaults).contextCaptureEnabled,
                           "Missing preference must preserve context capture for existing users")
        TestSupport.expect(defaults.object(forKey: "context_capture_enabled") == nil,
                           "Loading the default must not save a choice")
        for choice in [false, true] {
            let state = TestContextState(defaults: defaults)
            state.contextCaptureEnabled = choice
            TestSupport.expectEqual(TestContextState(defaults: defaults).contextCaptureEnabled, choice)
        }

        let disabled = TestContextState(defaults: defaults)
        disabled.contextCaptureEnabled = false
        disabled.startContextCapture()
        TestSupport.expect(disabled.contextCaptureTask == nil, "Disabled capture must not start a task")
        TestSupport.expectEqual(disabled.contextService.calls, 0)

        for reenable in [false, true] {
            let state = TestContextState(defaults: defaults)
            state.contextCaptureEnabled = true
            state.startContextCapture()
            let task = state.contextCaptureTask!
            await state.contextService.waitForStart()
            // This local reference models transcription retaining the task after recording stops.
            state.contextCaptureEnabled = false
            TestSupport.expect(task.isCancelled, "Disabling must cancel the task retained by transcription")
            if reenable { state.contextCaptureEnabled = true }
            state.contextService.finish() // Simulate a provider that completes despite cancellation.
            let result = await task.value
            TestSupport.expect(result == nil && state.capturedContext == nil,
                               "Late completion must not restore cancelled context")
            TestSupport.expect(state.lastContextScreenshotDataURL == nil,
                               "Late completion must not publish a screenshot")
            TestSupport.expectEqual(state.screenshotIssueCalls, 0)
            let resolved = await state.contextForTranscription(nil, task: task)
            TestSupport.expectEqual(resolved.screenshotError, "Disabled in Settings")
        }

        let enabled = TestContextState(defaults: defaults)
        enabled.contextCaptureEnabled = true
        enabled.startContextCapture()
        let task = enabled.contextCaptureTask!
        await enabled.contextService.waitForStart()
        enabled.contextService.finish()
        let snapshot = await task.value
        TestSupport.expectEqual(snapshot?.currentActivity, "Synthetic context")
        TestSupport.expectEqual(enabled.capturedContext?.screenshotDataURL, "synthetic-image")
        // Cleanup has already resolved its context when the preference changes.
        let resolved = await enabled.contextForTranscription(snapshot, task: task)
        let generation = enabled.contextCaptureGeneration
        let syntheticPrompt = "Synthetic cleanup prompt containing window context"
        let unchanged = enabled.contextForPublication(resolved, prompt: syntheticPrompt, generation: generation)
        TestSupport.expectEqual(unchanged.context.screenshotDataURL, "synthetic-image")
        TestSupport.expectEqual(unchanged.prompt, syntheticPrompt)
        for reenable in [false, true] {
            enabled.contextCaptureEnabled = false
            if reenable { enabled.contextCaptureEnabled = true }
            let publication = enabled.contextForPublication(resolved, prompt: syntheticPrompt, generation: generation)
            TestSupport.expect(publication.context.screenshotDataURL == nil && publication.context.selectedText == nil
                               && publication.context.windowTitle == nil && publication.context.appName == nil,
                               "Disabling during cleanup must remove resolved context before UI/history publication")
            TestSupport.expectEqual(publication.prompt, "")
            let errorPublication = enabled.contextForPublication(resolved, prompt: "", generation: generation)
            TestSupport.expect(errorPublication.context.screenshotDataURL == nil,
                               "Error history must also reject previously resolved context")
        }
        let nextRun = enabled.contextForPublication(resolved, prompt: syntheticPrompt,
                                                   generation: enabled.contextCaptureGeneration)
        TestSupport.expectEqual(nextRun.context.screenshotDataURL, "synthetic-image")
        TestSupport.expectEqual(nextRun.prompt, syntheticPrompt)
        enabled.contextCaptureEnabled = false
        enabled.contextCaptureEnabled = true
        let discarded = await enabled.contextForTranscription(snapshot, task: task)
        TestSupport.expect(discarded.screenshotDataURL == nil && discarded.selectedText == nil,
                           "Disabling must invalidate an already captured snapshot on success and error paths")
    }
}
