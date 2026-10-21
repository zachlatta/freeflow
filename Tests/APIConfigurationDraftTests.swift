private actor DraftValidationGate {
    private var pending: CheckedContinuation<Bool, Never>?
    private var waitingForStart: CheckedContinuation<Void, Never>?
    private var started = false

    func validate() async -> Bool {
        if started { return true }
        started = true
        return await withCheckedContinuation { continuation in
            pending = continuation
            waitingForStart?.resume()
            waitingForStart = nil
        }
    }

    func waitUntilStarted() async {
        if started { return }
        await withCheckedContinuation { waitingForStart = $0 }
    }

    func finish(_ valid: Bool) {
        guard let pending else { fatalError("Synthetic validation was not started") }
        self.pending = nil
        pending.resume(returning: valid)
    }
}

enum APIConfigurationDraftTests {
    private static func configuration(_ name: String) -> ValidatedAPIConfiguration {
        ValidatedAPIConfiguration(
            apiKey: "synthetic-\(name)-main",
            baseURL: "https://\(name)-main.invalid/v1",
            transcriptionAPIURL: "https://\(name)-transcription.invalid/v1",
            transcriptionAPIKey: "synthetic-\(name)-transcription"
        )
    }

    private static func edit(_ draft: inout APIConfigurationDraft, to value: ValidatedAPIConfiguration) {
        draft.apiKey = value.apiKey
        draft.baseURL = value.baseURL
        draft.transcriptionAPIURL = value.transcriptionAPIURL
        draft.transcriptionAPIKey = value.transcriptionAPIKey
    }

    @MainActor
    static func run() async {
        await testDelayedOldViewCommitReconcilesReplacement()
        testDirtyPairsRemainCoherentAndAdvanceBaseline()
        testOwnPendingEditsAreNotNormalizedOrMarkedSaved()
        testSuccessfulNormalizationAndStatus()
        testOldPresentationCannotCompleteNewPresentation()
        await testFailureDoesNotCommitOrReplaceNewEdits()
    }

    @MainActor
    private static func testDelayedOldViewCommitReconcilesReplacement() async {
        let previous = configuration("previous")
        let next = configuration("next")
        var oldView = APIConfigurationDraft()
        oldView.present(previous)
        edit(&oldView, to: next)
        let submission = oldView.submission
        var replacement = APIConfigurationDraft()
        var committed = previous
        var acceptedOldView = false
        let gate = DraftValidationGate()
        let validation = Task { @MainActor in
            await APIConfigurationSaveFlow.validateAndApply(
                apiKey: submission.configuration.apiKey,
                baseURL: submission.configuration.baseURL,
                transcriptionAPIURL: submission.configuration.transcriptionAPIURL,
                transcriptionAPIKey: submission.configuration.transcriptionAPIKey,
                validator: { _, _ in await gate.validate() }
            ) { saved in
                acceptedOldView = oldView.accept(saved, for: submission)
                committed = saved
                replacement.reconcile(saved)
            }
        }
        await gate.waitUntilStarted()
        oldView.dismiss()
        replacement.present(committed)
        TestSupport.expectEqual(replacement.configuration, previous)
        await gate.finish(true)
        let valid = await validation.value
        TestSupport.expect(valid, "Synthetic delayed validation succeeds")
        TestSupport.expectEqual(committed, next)
        TestSupport.expectEqual(replacement.configuration, next)
        TestSupport.expect(!acceptedOldView && !oldView.isCurrent(submission), "Closed form cannot normalize or advance its replacement")
        TestSupport.expect(!replacement.showsSavedSuccess(nil, committed: next), "Reopened form does not invent a successful submission banner")
    }

    private static func testDirtyPairsRemainCoherentAndAdvanceBaseline() {
        let previous = configuration("previous")
        let next = configuration("next")
        let later = configuration("later")
        for field in 0..<4 {
            var replacement = APIConfigurationDraft()
            replacement.present(previous)
            switch field {
            case 0: replacement.baseURL = "https://dirty-main.invalid/v1"
            case 1: replacement.apiKey = "synthetic-dirty-main"
            case 2: replacement.transcriptionAPIURL = "https://dirty-transcription.invalid/v1"
            default: replacement.transcriptionAPIKey = "synthetic-dirty-transcription"
            }
            let dirty = replacement.configuration
            replacement.reconcile(next)
            if field < 2 {
                TestSupport.expectEqual(replacement.apiKey, dirty.apiKey)
                TestSupport.expectEqual(replacement.baseURL, dirty.baseURL)
                TestSupport.expectEqual(replacement.transcriptionAPIURL, next.transcriptionAPIURL)
                TestSupport.expectEqual(replacement.transcriptionAPIKey, next.transcriptionAPIKey)
            } else {
                TestSupport.expectEqual(replacement.apiKey, next.apiKey)
                TestSupport.expectEqual(replacement.baseURL, next.baseURL)
                TestSupport.expectEqual(replacement.transcriptionAPIURL, dirty.transcriptionAPIURL)
                TestSupport.expectEqual(replacement.transcriptionAPIKey, dirty.transcriptionAPIKey)
            }
            // Returning the dirty pair to the new baseline makes it clean for
            // the next complete commit; the baseline advanced even while dirty.
            edit(&replacement, to: next)
            replacement.reconcile(later)
            TestSupport.expectEqual(replacement.configuration, later)
        }
    }

    private static func testOwnPendingEditsAreNotNormalizedOrMarkedSaved() {
        let previous = configuration("previous")
        let submitted = configuration("submitted")
        for field in 0..<4 {
            var draft = APIConfigurationDraft()
            draft.present(previous)
            edit(&draft, to: submitted)
            let submission = draft.submission
            switch field {
            case 0: draft.apiKey = "synthetic-newer-main"
            case 1: draft.baseURL = "https://newer-main.invalid/v1"
            case 2: draft.transcriptionAPIURL = "https://newer-transcription.invalid/v1"
            default: draft.transcriptionAPIKey = "synthetic-newer-transcription"
            }
            let newerEdits = draft.configuration
            TestSupport.expect(!draft.accept(submitted, for: submission), "Later edits cannot be normalized by old submission")
            TestSupport.expectEqual(draft.configuration, newerEdits)
            draft.reconcile(submitted)
            TestSupport.expectEqual(draft.configuration, newerEdits)
            TestSupport.expect(!draft.matches(submission), "Later edits cannot inherit an old error or advance Setup")
            TestSupport.expect(!draft.showsSavedSuccess(submitted, committed: submitted), "Later edits must not be labeled saved")
        }
    }

    private static func testSuccessfulNormalizationAndStatus() {
        let saved = configuration("normalized")
        var draft = APIConfigurationDraft()
        draft.present(configuration("previous"))
        draft.apiKey = " \(saved.apiKey) "
        draft.baseURL = " \(saved.baseURL) "
        draft.transcriptionAPIURL = " \(saved.transcriptionAPIURL) "
        draft.transcriptionAPIKey = " \(saved.transcriptionAPIKey) "
        let submission = draft.submission
        TestSupport.expect(draft.accept(saved, for: submission), "Unchanged submitting form accepts normalization")
        TestSupport.expectEqual(draft.configuration, saved)
        TestSupport.expect(draft.showsSavedSuccess(saved, committed: saved), "Only exact committed four-field success is displayed")
        TestSupport.expect(!draft.showsSavedSuccess(saved, committed: configuration("other")), "Another commit invalidates obsolete success")
        draft.transcriptionAPIKey = ""
        TestSupport.expect(!draft.showsSavedSuccess(saved, committed: saved), "Clearing any field invalidates obsolete success")
    }

    private static func testOldPresentationCannotCompleteNewPresentation() {
        let saved = configuration("saved")
        var draft = APIConfigurationDraft()
        draft.present(saved)
        let oldSubmission = draft.submission
        var replacement = APIConfigurationDraft()
        replacement.present(saved)
        TestSupport.expect(!replacement.isCurrent(oldSubmission), "Distinct forms cannot share a submission presentation token")
        draft.dismiss()
        draft.present(saved)
        TestSupport.expect(!draft.isCurrent(oldSubmission), "A new presentation cannot be advanced by an older task")
        TestSupport.expect(!draft.accept(configuration("late"), for: oldSubmission), "Old presentation cannot overwrite the new form")
        TestSupport.expectEqual(draft.configuration, saved)
        draft.reconcile(configuration("late"))
        TestSupport.expectEqual(draft.configuration, configuration("late"))
    }

    @MainActor
    private static func testFailureDoesNotCommitOrReplaceNewEdits() async {
        let previous = configuration("previous")
        let next = configuration("next")
        var draft = APIConfigurationDraft()
        draft.present(previous)
        edit(&draft, to: next)
        let submission = draft.submission
        var committed = previous
        var applyCount = 0
        let gate = DraftValidationGate()
        let validation = Task { @MainActor in
            await APIConfigurationSaveFlow.validateAndApply(
                apiKey: submission.configuration.apiKey,
                baseURL: submission.configuration.baseURL,
                transcriptionAPIURL: submission.configuration.transcriptionAPIURL,
                transcriptionAPIKey: submission.configuration.transcriptionAPIKey,
                validator: { _, _ in await gate.validate() }
            ) { saved in
                applyCount += 1
                committed = saved
                draft.accept(saved, for: submission)
            }
        }
        await gate.waitUntilStarted()
        draft.baseURL = "https://newer.invalid/v1"
        let newer = draft.configuration
        await gate.finish(false)
        let valid = await validation.value
        TestSupport.expect(!valid && applyCount == 0, "Failed validation never publishes a commit")
        TestSupport.expectEqual(committed, previous)
        TestSupport.expectEqual(draft.configuration, newer)
        TestSupport.expect(!draft.matches(submission), "Obsolete validation error is not shown on newer edits")
    }
}
