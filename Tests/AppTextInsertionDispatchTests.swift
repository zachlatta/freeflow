import AppKit
import CoreGraphics
import Foundation

let pressEnterAfterPasteDelay: TimeInterval = 0.08

enum AppTextInsertionDispatchTests {
    static func run() {
        testAccessibilityPreparationRequiresEnabledMonitoringAndPermission()
        testFocusedEditsRejectWithoutClipboardOrInput()
        testEditsAfterFocusReturnsReject()
        testFocusedSelectionChangeRejectsBeforeClipboard()
        testUnchangedFocusedTargetPastesAndEntersOnce()
        testFocusedSupportedControlWithoutCapturePastesOnce()
        testUnreadableFocusedPasteRechecksFocusAndSession()
        testUnreadableUnsupportedAndMissingSnapshotsReject()
        testUnreadableBackgroundTargetStaysUnavailable()
        testEditsDuringClipboardPreparationRestoreWithoutPasting()
        testFocusChangeDuringClipboardPreparationRestoresWithoutPasting()
        testSessionChangeDuringClipboardPreparationRestoresWithoutPasting()
        testNewSessionCancelsPendingTargetAction()
        testInputDuringActivationAbortsWithEnterOffAndOn()
        testInputAndDestinationChangeDuringActivationAborts()
        testAXFieldChangeDuringActivationAborts()
        testAXWindowChangeDuringActivationAborts()
        testBackgroundAXInsertionAvoidsActivationAndPaste()
        testUnverifiedBackgroundWriteNeverFallsBack()
        testUnchangedBlurredTargetPastesOnceAndRestoresFocus()
        testInputDuringPasteBlocksDeferredFocusRestoration()
        testDeferredRestorationPreservesLaterChanges()
        testDelayedEnterAbortsAfterAppOrInputChange()
        testFocusedSupportedUnreadableTargetGetsEnterWithoutActivation()
        testFocusedUnsupportedUnreadableTargetSkipsEnter()
        testDelayedEnterCancelsForNewSession()
        testDisabledOriginalFieldUsesCurrentFieldPaste()
    }

    private static func testAccessibilityPreparationRequiresEnabledMonitoringAndPermission() {
        for enabled in [false, true] {
            for monitoring in [false, true] {
                for trusted in [false, true] {
                    let fixture = makeFixture(focused: true)
                    fixture.state.originalFieldInsertionEnabled = enabled
                    fixture.state.shouldMonitorHotkeys = monitoring
                    TestAX.isProcessTrusted = trusted

                    fixture.state.testPrepareForegroundApplicationForInsertion()
                    TestSupport.expect(TestInsertionTarget.preparedProcessIdentifiers.isEmpty,
                                       "The role request must be queued rather than block the caller")
                    TestAX.frontmostApplication = fixture.previousApplication
                    TestDispatchQueue.runAll()

                    let expected = enabled && monitoring && trusted ? [fixture.target.processIdentifier] : []
                    TestSupport.expectEqual(TestInsertionTarget.preparedProcessIdentifiers, expected)
                    TestSupport.expectEqual(fixture.state.clipboardWriteCount, 0)
                    TestSupport.expect(fixture.state.pasteCalls.isEmpty && fixture.state.enterCalls.isEmpty,
                                       "Preparing Accessibility must not send any input")
                }
            }
        }
        let fixture = makeFixture(focused: true)
        fixture.state.originalFieldInsertionEnabled = true
        fixture.state.shouldMonitorHotkeys = true
        TestAX.frontmostApplication = nil
        fixture.state.testPrepareForegroundApplicationForInsertion()
        TestDispatchQueue.runAll()
        TestSupport.expect(TestInsertionTarget.preparedProcessIdentifiers.isEmpty,
                           "Preparation requires a current foreground application")
    }

    private static func testFocusedEditsRejectWithoutClipboardOrInput() {
        let fixture = makeFixture(focused: true)
        fixture.target.value = "captured text edited"
        fixture.state.preserveClipboard = true

        fixture.state.testDispatchInsertion("dictation", target: fixture.target, shouldPressEnter: true, useOriginalField: true)
        TestDispatchQueue.runAll()

        TestSupport.expect(fixture.state.clipboardWriteCount == 0, "An edited focused field must be rejected before clipboard preparation")
        TestSupport.expectEqual(fixture.state.pasteCalls.count, 0)
        TestSupport.expectEqual(fixture.state.enterCalls.count, 0)
        TestSupport.expectEqual(fixture.state.clipboardRestoreCount, 0)
    }

    private static func testEditsAfterFocusReturnsReject() {
        let fixture = makeFixture(focused: true)
        TestAX.frontmostApplication = TestAX.runningApplication(processIdentifier: 501)
        fixture.target.value = "captured text edited while away"
        TestAX.frontmostApplication = TestAX.runningApplication(processIdentifier: fixture.target.processIdentifier)
        fixture.state.preserveClipboard = true

        fixture.state.testDispatchInsertion("dictation", target: fixture.target, shouldPressEnter: true, useOriginalField: true)
        TestDispatchQueue.runAll()

        TestSupport.expect(fixture.state.clipboardWriteCount == 0, "Returning focus must not make an edited snapshot current again")
        TestSupport.expectEqual(fixture.state.pasteCalls.count, 0)
        TestSupport.expectEqual(fixture.state.enterCalls.count, 0)
    }

    private static func testFocusedSelectionChangeRejectsBeforeClipboard() {
        let fixture = makeFixture(focused: true)
        fixture.target.selection = NSRange(location: 0, length: 0)
        fixture.state.preserveClipboard = true

        fixture.state.testDispatchInsertion("dictation", target: fixture.target, shouldPressEnter: true, useOriginalField: true)
        TestDispatchQueue.runAll()

        TestSupport.expect(fixture.state.clipboardWriteCount == 0, "A changed selection must not be overwritten or copied over")
        TestSupport.expectEqual(fixture.state.pasteCalls.count, 0)
        TestSupport.expectEqual(fixture.state.enterCalls.count, 0)
    }

    private static func testUnchangedFocusedTargetPastesAndEntersOnce() {
        let fixture = makeFixture(focused: true)
        fixture.state.preserveClipboard = true

        fixture.state.testDispatchInsertion("dictation", target: fixture.target, shouldPressEnter: true, useOriginalField: true)
        TestDispatchQueue.runAll()

        TestSupport.expectEqual(fixture.state.clipboardWriteCount, 1)
        TestSupport.expectEqual(fixture.state.pasteCalls, [fixture.target.processIdentifier])
        TestSupport.expectEqual(fixture.state.enterCalls, [fixture.target.processIdentifier])
        TestSupport.expectEqual(fixture.state.clipboardRestoreCount, 1)
        TestSupport.expect(fixture.target.selection == fixture.target.selectedTextRange,
                           "The unchanged captured selection remains the paste destination")
        TestSupport.expect(fixture.target.selectionRestoreCount == 0,
                           "The focused path must validate rather than reset a selection")
    }

    private static func testFocusedSupportedControlWithoutCapturePastesOnce() {
        for shouldPressEnter in [false, true] {
            let fixture = makeFixture(focused: true, captureText: false)
            fixture.state.preserveClipboard = true

            fixture.state.testDispatchInsertion(
                "dictation", target: fixture.target, shouldPressEnter: shouldPressEnter, useOriginalField: true
            )
            TestDispatchQueue.runAll()

            TestSupport.expectEqual(fixture.state.pasteCalls, [fixture.target.processIdentifier])
            TestSupport.expectEqual(fixture.state.enterCalls, shouldPressEnter ? [fixture.target.processIdentifier] : [])
            TestSupport.expectEqual(fixture.state.clipboardWriteCount, 1)
            TestSupport.expectEqual(fixture.state.clipboardRestoreCount, 1)
            TestSupport.expectEqual(fixture.target.insertCallCount, 0)
            TestSupport.expectEqual(fixture.target.selectionRestoreCount, 0)
            TestSupport.expectEqual(fixture.target.focusCallCount, 0)
            TestSupport.expectEqual(TestAX.activationCount, 0)
        }
    }

    private static func testUnreadableFocusedPasteRechecksFocusAndSession() {
        enum Change { case field, app, session }
        for change in [Change.field, .app, .session] {
            let fixture = makeFixture(focused: true, captureText: false)
            fixture.state.preserveClipboard = true
            let otherField = TestAXElement()
            fixture.state.afterClipboardWrite = {
                switch change {
                case .field: TestAX.setFocusedElement(otherField, for: fixture.target.processIdentifier)
                case .app: TestAX.frontmostApplication = fixture.previousApplication
                case .session: fixture.state.textInsertionTargetID = UUID()
                }
            }

            fixture.state.testDispatchInsertion(
                "dictation", target: fixture.target, shouldPressEnter: true, useOriginalField: true
            )
            TestDispatchQueue.runAll()

            TestSupport.expectEqual(fixture.state.clipboardWriteCount, 1)
            TestSupport.expectEqual(fixture.state.clipboardRestoreCount, 1)
            TestSupport.expectEqual(fixture.state.pasteCalls.count, 0)
            TestSupport.expectEqual(fixture.state.enterCalls.count, 0)
            TestSupport.expectEqual(fixture.target.focusCallCount, 0)
            TestSupport.expectEqual(TestAX.activationCount, 0)
            TestSupport.expectEqual(TestAX.restoreActionCount, 0)
        }
    }

    private static func testUnreadableUnsupportedAndMissingSnapshotsReject() {
        for supported in [false, true] {
            let fixture = makeFixture(focused: true, captureText: false)
            fixture.target.isSupportedTextControl = supported
            // A failed snapshot of a capture-eligible field must retain the content guard.
            fixture.target.allowsTextCapture = supported

            fixture.state.testDispatchInsertion(
                "dictation", target: fixture.target, shouldPressEnter: true, useOriginalField: true
            )
            TestDispatchQueue.runAll()

            TestSupport.expectEqual(fixture.state.clipboardWriteCount, 0)
            TestSupport.expectEqual(fixture.state.pasteCalls.count, 0)
            TestSupport.expectEqual(fixture.state.enterCalls.count, 0)
            TestSupport.expectEqual(TestAX.activationCount, 0)
        }
    }

    private static func testUnreadableBackgroundTargetStaysUnavailable() {
        let fixture = makeFixture(focused: false, captureText: false)
        fixture.target.insertionResult = .unavailable

        fixture.state.testDispatchInsertion(
            "dictation", target: fixture.target, shouldPressEnter: true, useOriginalField: true
        )
        TestDispatchQueue.runAll()

        TestSupport.expectEqual(fixture.target.insertCallCount, 1)
        TestSupport.expectEqual(fixture.state.clipboardWriteCount, 0)
        TestSupport.expectEqual(fixture.state.pasteCalls.count, 0)
        TestSupport.expectEqual(fixture.state.enterCalls.count, 0)
        TestSupport.expectEqual(fixture.target.focusCallCount, 0)
        TestSupport.expectEqual(TestAX.activationCount, 0)
    }

    private static func testEditsDuringClipboardPreparationRestoreWithoutPasting() {
        let fixture = makeFixture(focused: true)
        fixture.state.preserveClipboard = true
        fixture.state.afterClipboardWrite = { fixture.target.value = "edited during preparation" }

        fixture.state.testDispatchInsertion("dictation", target: fixture.target, shouldPressEnter: true, useOriginalField: true)
        TestDispatchQueue.runAll()

        TestSupport.expectEqual(fixture.state.clipboardWriteCount, 1)
        TestSupport.expect(fixture.state.pasteCalls.isEmpty,
                           "A value change during preparation must fail the second snapshot check")
        TestSupport.expectEqual(fixture.state.enterCalls.count, 0)
        TestSupport.expect(fixture.state.clipboardRestoreCount == 1,
                           "Clipboard state prepared before rejection must be restored once")
    }

    private static func testFocusChangeDuringClipboardPreparationRestoresWithoutPasting() {
        let fixture = makeFixture(focused: true)
        fixture.state.preserveClipboard = true
        let otherField = TestAXElement()
        fixture.state.afterClipboardWrite = { TestAX.setFocusedElement(otherField, for: fixture.target.processIdentifier) }

        fixture.state.testDispatchInsertion("dictation", target: fixture.target, shouldPressEnter: true, useOriginalField: true)
        TestDispatchQueue.runAll()

        TestSupport.expectEqual(fixture.state.clipboardWriteCount, 1)
        TestSupport.expect(fixture.state.pasteCalls.isEmpty,
                           "A focus change during preparation must fail the second focus check")
        TestSupport.expectEqual(fixture.state.enterCalls.count, 0)
        TestSupport.expectEqual(fixture.state.clipboardRestoreCount, 1)
        TestSupport.expect(TestAX.focusedElement(for: fixture.target.processIdentifier) === otherField,
                           "The field chosen during preparation must keep focus")
    }

    private static func testSessionChangeDuringClipboardPreparationRestoresWithoutPasting() {
        let fixture = makeFixture(focused: true)
        fixture.state.preserveClipboard = true
        fixture.state.afterClipboardWrite = { fixture.state.textInsertionTargetID = UUID() }

        fixture.state.testDispatchInsertion("dictation", target: fixture.target, shouldPressEnter: true, useOriginalField: true)
        TestDispatchQueue.runAll()

        TestSupport.expectEqual(fixture.state.clipboardWriteCount, 1)
        TestSupport.expect(fixture.state.pasteCalls.isEmpty, "A session change during preparation must fail the second current-target check")
        TestSupport.expectEqual(fixture.state.enterCalls.count, 0)
        TestSupport.expectEqual(fixture.state.clipboardRestoreCount, 1)
    }

    private static func testNewSessionCancelsPendingTargetAction() {
        let fixture = makeFixture(focused: false)
        fixture.state.preserveClipboard = true

        fixture.state.testDispatchInsertion("dictation", target: fixture.target, shouldPressEnter: true, useOriginalField: true)
        fixture.state.textInsertionTargetID = UUID()
        TestDispatchQueue.runAll()

        TestSupport.expectEqual(fixture.target.focusCallCount, 0)
        TestSupport.expectEqual(fixture.state.clipboardWriteCount, 0)
        TestSupport.expectEqual(fixture.state.pasteCalls.count, 0)
        TestSupport.expectEqual(fixture.state.enterCalls.count, 0)
        TestSupport.expectEqual(fixture.state.clipboardRestoreCount, 0)
        TestSupport.expectEqual(TestAX.restoreActionCount, 0)
    }

    private static func testInputDuringActivationAbortsWithEnterOffAndOn() {
        for shouldPressEnter in [false, true] {
            let fixture = makeFixture(focused: false)
            fixture.state.preserveClipboard = true
            TestAX.afterActivation = { processIdentifier in
                TestAX.incrementInputCount(for: .keyDown)
            }

            fixture.state.testDispatchInsertion("dictation", target: fixture.target,
                                                shouldPressEnter: shouldPressEnter, useOriginalField: true)
            TestDispatchQueue.runAll()

            TestSupport.expect(fixture.target.focusCallCount == 0,
                               "Physical input during activation must abort before refocusing")
            TestSupport.expectEqual(fixture.state.clipboardWriteCount, 0)
            TestSupport.expectEqual(fixture.state.pasteCalls.count, 0)
            TestSupport.expectEqual(fixture.state.enterCalls.count, 0)
            TestSupport.expectEqual(fixture.state.clipboardRestoreCount, 0)
            TestSupport.expectEqual(TestAX.restoreActionCount, 0)
            TestDispatchQueue.reset()
            TestAX.afterActivation = nil
        }
    }

    private static func testInputAndDestinationChangeDuringActivationAborts() {
        let fixture = makeFixture(focused: false)
        fixture.state.preserveClipboard = true
        TestAX.afterActivation = { processIdentifier in
            TestAX.incrementInputCount(for: .keyDown)
            TestAX.setFocusedElement(TestAXElement(), for: processIdentifier)
            TestAX.setFocusedWindow(TestAXElement(), for: processIdentifier)
        }

        fixture.state.testDispatchInsertion("dictation", target: fixture.target, shouldPressEnter: true, useOriginalField: true)
        expectActivationAbort(fixture)
    }

    private static func testAXFieldChangeDuringActivationAborts() {
        for shouldPressEnter in [false, true] {
            let fixture = makeFixture(focused: false)
            let otherField = TestAXElement()
            TestAX.afterActivation = { processIdentifier in
                TestAX.setFocusedElement(otherField, for: processIdentifier)
            }

            fixture.state.testDispatchInsertion("dictation", target: fixture.target,
                                                shouldPressEnter: shouldPressEnter, useOriginalField: true)
            TestDispatchQueue.runAll()

            expectActivationAbort(fixture)
            TestSupport.expect(TestAX.focusedElement(for: fixture.target.processIdentifier) === otherField,
                               "An Accessibility-only field choice must remain active")
        }
    }

    private static func testAXWindowChangeDuringActivationAborts() {
        for shouldPressEnter in [false, true] {
            let fixture = makeFixture(focused: false)
            let otherWindow = TestAXElement()
            TestAX.afterActivation = { processIdentifier in
                TestAX.setFocusedWindow(otherWindow, for: processIdentifier)
            }

            fixture.state.testDispatchInsertion("dictation", target: fixture.target,
                                                shouldPressEnter: shouldPressEnter, useOriginalField: true)
            TestDispatchQueue.runAll()

            expectActivationAbort(fixture)
            TestSupport.expect(TestAX.focusedWindow(for: fixture.target.processIdentifier) === otherWindow,
                               "An Accessibility-only window choice must remain active")
        }
    }

    private static func testBackgroundAXInsertionAvoidsActivationAndPaste() {
        let fixture = makeFixture(focused: false)
        fixture.target.insertionResult = .inserted
        fixture.state.preserveClipboard = true

        fixture.state.testDispatchInsertion("dictation", target: fixture.target, shouldPressEnter: true, useOriginalField: true)
        TestDispatchQueue.runAll()

        TestSupport.expectEqual(fixture.target.insertCallCount, 1)
        TestSupport.expectEqual(TestAX.activationCount, 0)
        TestSupport.expectEqual(fixture.target.focusCallCount, 0)
        TestSupport.expectEqual(fixture.state.clipboardWriteCount, 0)
        TestSupport.expectEqual(fixture.state.pasteCalls.count, 0)
        TestSupport.expectEqual(fixture.state.enterCalls, [fixture.target.processIdentifier])
        TestSupport.expectEqual(fixture.state.clipboardRestoreCount, 0)
        TestSupport.expectEqual(TestAX.frontmostApplication?.processIdentifier,
                                Optional(fixture.previousApplication.processIdentifier))
    }

    private static func testUnverifiedBackgroundWriteNeverFallsBack() {
        for shouldPressEnter in [false, true] {
            let fixture = makeFixture(focused: false)
            fixture.target.insertionResult = .unverified

            fixture.state.testDispatchInsertion(
                "dictation", target: fixture.target, shouldPressEnter: shouldPressEnter, useOriginalField: true
            )
            TestDispatchQueue.runAll()

            TestSupport.expectEqual(fixture.target.insertCallCount, 1)
            TestSupport.expectEqual(TestAX.activationCount, 0)
            TestSupport.expectEqual(fixture.target.focusCallCount, 0)
            TestSupport.expectEqual(fixture.state.clipboardWriteCount, 0)
            TestSupport.expectEqual(fixture.state.pasteCalls.count, 0)
            TestSupport.expectEqual(fixture.state.enterCalls.count, 0)
            TestSupport.expectEqual(fixture.state.clipboardRestoreCount, 0)
            TestSupport.expectEqual(TestAX.restoreActionCount, 0)
            TestSupport.expectEqual(TestAX.frontmostApplication?.processIdentifier,
                                    Optional(fixture.previousApplication.processIdentifier))
        }
    }

    private static func testUnchangedBlurredTargetPastesOnceAndRestoresFocus() {
        let fixture = makeFixture(focused: false)
        TestAX.setFocusedElement(nil, for: fixture.target.processIdentifier)
        fixture.state.preserveClipboard = true

        fixture.state.testDispatchInsertion("dictation", target: fixture.target, shouldPressEnter: true, useOriginalField: true)
        TestDispatchQueue.runAll()

        TestSupport.expectEqual(fixture.target.insertCallCount, 1)
        TestSupport.expectEqual(fixture.target.focusCallCount, 1)
        TestSupport.expectEqual(fixture.state.clipboardWriteCount, 1)
        TestSupport.expectEqual(fixture.state.pasteCalls, [fixture.target.processIdentifier])
        TestSupport.expectEqual(fixture.state.enterCalls, [fixture.target.processIdentifier])
        TestSupport.expectEqual(fixture.state.clipboardRestoreCount, 1)
        TestSupport.expectEqual(TestAX.frontmostApplication?.processIdentifier, Optional(fixture.previousApplication.processIdentifier))
        TestSupport.expect(TestAX.focusedElement(for: fixture.previousApplication.processIdentifier) === fixture.previousField,
                           "Successful background paste restores the previous app field")
    }

    private static func testInputDuringPasteBlocksDeferredFocusRestoration() {
        let fixture = makeFixture(focused: false)
        fixture.state.preserveClipboard = true
        fixture.state.afterClipboardWrite = { TestAX.incrementInputCount(for: .keyDown) }

        fixture.state.testDispatchInsertion("dictation", target: fixture.target,
                                            shouldPressEnter: false, useOriginalField: true)
        TestDispatchQueue.runAll()

        TestSupport.expectEqual(fixture.state.pasteCalls, [fixture.target.processIdentifier])
        TestSupport.expectEqual(fixture.state.clipboardWriteCount, 1)
        TestSupport.expectEqual(fixture.state.clipboardRestoreCount, 1)
        TestSupport.expect(TestAX.restoreActionCount == 0,
                           "Input during the paste attempt must block deferred focus restoration")
        TestSupport.expect(TestAX.frontmostApplication?.processIdentifier == fixture.target.processIdentifier,
                           "The app activated for paste must stay frontmost after new input")
    }

    private static func testDeferredRestorationPreservesLaterChanges() {
        enum Change: Equatable { case input, field, window, session }

        for change in [Change.input, .field, .window, .session] {
            let fixture = makeFixture(focused: false)
            fixture.state.preserveClipboard = true
            fixture.state.testDispatchInsertion("dictation", target: fixture.target,
                                                shouldPressEnter: false, useOriginalField: true)
            TestSupport.expect(TestDispatchQueue.runNext(), "The delayed insertion callback should be queued")

            let chosenField = TestAXElement()
            let chosenWindow = TestAXElement()
            switch change {
            case .input:
                TestAX.incrementInputCount(for: .keyDown)
            case .field:
                TestAX.setFocusedElement(chosenField, for: fixture.target.processIdentifier)
            case .window:
                TestAX.setFocusedWindow(chosenWindow, for: fixture.target.processIdentifier)
            case .session:
                fixture.state.textInsertionTargetID = UUID()
            }
            TestDispatchQueue.runAll()

            TestSupport.expectEqual(fixture.state.pasteCalls, [fixture.target.processIdentifier])
            TestSupport.expectEqual(fixture.state.clipboardRestoreCount, 1)
            TestSupport.expect(TestAX.restoreActionCount == 0,
                               "Deferred restoration must not override a later input, field, window, or session change")
            TestSupport.expectEqual(TestAX.frontmostApplication?.processIdentifier,
                                    Optional(fixture.target.processIdentifier))
            if change == .field {
                TestSupport.expect(TestAX.focusedElement(for: fixture.target.processIdentifier) === chosenField,
                                   "A later field choice must remain focused")
            }
            if change == .window {
                TestSupport.expect(TestAX.focusedWindow(for: fixture.target.processIdentifier) === chosenWindow,
                                   "A later window choice must remain active")
            }
        }
    }

    private static func testDelayedEnterCancelsForNewSession() {
        let fixture = makeFixture(focused: true)

        fixture.state.testScheduleEnterAfterPaste(target: fixture.target)
        fixture.state.textInsertionTargetID = UUID()
        TestDispatchQueue.runAll()

        TestSupport.expect(fixture.state.enterCalls.isEmpty, "A delayed Enter must not cross into a newer session")
    }

    private static func testDelayedEnterAbortsAfterAppOrInputChange() {
        enum Change { case appAndInput, appOnly }

        for change in [Change.appAndInput, .appOnly] {
            let fixture = makeFixture(focused: false)
            fixture.state.preserveClipboard = true
            fixture.state.testDispatchInsertion("dictation", target: fixture.target,
                                                shouldPressEnter: true, useOriginalField: true)
            TestSupport.expect(TestDispatchQueue.runNext(), "The delayed fallback paste callback should be queued")
            TestSupport.expectEqual(fixture.state.pasteCalls, [fixture.target.processIdentifier])
            let activationCountAfterPaste = TestAX.activationCount

            TestAX.frontmostApplication = fixture.previousApplication
            if case .appAndInput = change {
                TestAX.incrementInputCount(for: .keyDown)
                TestAX.incrementInputCount(for: .leftMouseDown)
            }
            TestDispatchQueue.runAll()

            TestSupport.expectEqual(fixture.state.pasteCalls, [fixture.target.processIdentifier])
            TestSupport.expect(fixture.state.enterCalls.isEmpty,
                               "A new app choice or input must cancel delayed targeted Enter")
            TestSupport.expect(TestAX.activationCount == activationCountAfterPaste,
                               "Delayed Enter cancellation must not activate an app again")
            TestSupport.expect(TestAX.restoreActionCount == 0,
                               "Delayed Enter cancellation must not restore the old app focus")
            TestSupport.expectEqual(TestAX.frontmostApplication?.processIdentifier,
                                    Optional(fixture.previousApplication.processIdentifier))
        }
    }

    private static func testFocusedSupportedUnreadableTargetGetsEnterWithoutActivation() {
        let fixture = makeFixture(focused: true)
        fixture.target.allowsTextCapture = false
        fixture.target.isSupportedTextControl = true

        fixture.state.testScheduleEnterAfterPaste(target: fixture.target)
        TestDispatchQueue.runAll()

        TestSupport.expectEqual(fixture.state.enterCalls, [fixture.target.processIdentifier])
        TestSupport.expectEqual(TestAX.activationCount, 0)
    }

    private static func testFocusedUnsupportedUnreadableTargetSkipsEnter() {
        let fixture = makeFixture(focused: true)
        fixture.target.allowsTextCapture = false
        fixture.target.isSupportedTextControl = false

        fixture.state.testScheduleEnterAfterPaste(target: fixture.target)
        TestDispatchQueue.runAll()

        TestSupport.expect(fixture.state.enterCalls.isEmpty,
                           "Enter must be skipped for an unreadable unsupported control")
        TestSupport.expectEqual(TestAX.activationCount, 0)
    }

    private static func testDisabledOriginalFieldUsesCurrentFieldPaste() {
        let fixture = makeFixture(focused: true)
        fixture.state.preserveClipboard = true

        fixture.state.testDispatchInsertion("dictation", target: fixture.target, shouldPressEnter: true, useOriginalField: false)
        TestDispatchQueue.runAll()

        TestSupport.expectEqual(fixture.state.clipboardWriteCount, 1)
        TestSupport.expect(fixture.state.pasteCalls == [nil],
                           "Disabled original-field insertion keeps the legacy current-field paste")
        TestSupport.expectEqual(fixture.state.enterCalls, [nil])
        TestSupport.expectEqual(fixture.state.clipboardRestoreCount, 1)
        TestSupport.expectEqual(fixture.target.focusCallCount, 0)
    }

    private static func expectActivationAbort(_ fixture: Fixture) {
        TestDispatchQueue.runAll()
        TestSupport.expectEqual(fixture.target.focusCallCount, 0)
        TestSupport.expectEqual(fixture.state.clipboardWriteCount, 0)
        TestSupport.expectEqual(fixture.state.pasteCalls.count, 0)
        TestSupport.expectEqual(fixture.state.enterCalls.count, 0)
        TestSupport.expectEqual(fixture.state.clipboardRestoreCount, 0)
        TestSupport.expectEqual(TestAX.restoreActionCount, 0)
        TestAX.afterActivation = nil
    }

    private struct Fixture {
        let state: TestInsertionState
        let target: TestInsertionTarget
        let previousApplication: TestApplication
        let previousField: TestAXElement
    }

    private static func makeFixture(focused: Bool, captureText: Bool = true) -> Fixture {
        TestDispatchQueue.reset()
        TestAX.reset()

        let previousApplication = TestApplication(processIdentifier: 501)
        let targetApplication = TestApplication(processIdentifier: 502)
        let previousWindow = TestAXElement()
        let previousField = TestAXElement()
        let targetWindow = TestAXElement()
        let targetElement = TestAXElement()
        TestAX.register(previousApplication)
        TestAX.register(targetApplication)
        TestAX.setFocusedWindow(previousWindow, for: previousApplication.processIdentifier)
        TestAX.setFocusedElement(previousField, for: previousApplication.processIdentifier)
        TestAX.setFocusedWindow(targetWindow, for: targetApplication.processIdentifier)
        TestAX.setFocusedElement(targetElement, for: targetApplication.processIdentifier)
        TestAX.frontmostApplication = focused ? targetApplication : previousApplication

        let capturedValue = "captured text"
        let capturedRange = NSRange(location: 9, length: 4)
        let target = TestInsertionTarget(
            element: targetElement, window: targetWindow, value: captureText ? capturedValue : nil,
            selection: captureText ? capturedRange : nil, processIdentifier: targetApplication.processIdentifier
        )
        target.allowsTextCapture = captureText
        let state = TestInsertionState()
        state.textInsertionTargetID = target.identifier
        return Fixture(state: state, target: target, previousApplication: previousApplication, previousField: previousField)
    }
}

final class TestInsertionState {
    var originalFieldInsertionEnabled = false
    var shouldMonitorHotkeys = false
    let insertionAccessibilityQueue = TestDispatchQueue.main
    var textInsertionTargetID: UUID?
    var statusText = ""
    var preserveClipboard = false
    var keepDictationInClipboardHistory = false
    var clipboardWriteCount = 0
    var clipboardRestoreCount = 0
    var pasteCalls: [pid_t?] = []
    var enterCalls: [pid_t?] = []
    var afterClipboardWrite: (() -> Void)?

    func accessibilityElement(from application: TestApplication, attribute: String) -> TestAXElement? {
        switch attribute {
        case TestAX.focusedWindowAttribute: return TestAX.focusedWindow(for: application.processIdentifier)
        case TestAX.focusedElementAttribute: return TestAX.focusedElement(for: application.processIdentifier)
        default: return nil
        }
    }

    func performAfterShortcutReleased(action: @escaping () -> Void) { action() }

    func pasteAtCursorWhenShortcutReleased(completion: (() -> Void)? = nil) {
        pasteAtCursor()
        completion?()
    }

    func pasteAtCursor(processIdentifier: pid_t? = nil) { pasteCalls.append(processIdentifier) }
    func pressEnter(processIdentifier: pid_t? = nil) { enterCalls.append(processIdentifier) }

    func writeTranscriptToPasteboard(_ transcript: String) -> TestPendingClipboardRestore? {
        clipboardWriteCount += 1
        let pending = preserveClipboard ? TestPendingClipboardRestore(state: self) : nil
        afterClipboardWrite?()
        return pending
    }

    func restoreClipboardIfNeeded(_ pending: TestPendingClipboardRestore?) {
        guard let pending else { return }
        TestDispatchQueue.main.asyncAfter(deadline: .now() + 0.01) { [weak self] in
            guard self != nil, !pending.didRestore else { return }
            pending.didRestore = true
            pending.state.clipboardRestoreCount += 1
        }
    }

    func scheduleReadyStatusReset(after delay: TimeInterval, matching statuses: Set<String>? = nil) {}

    func transcriptTextForInsertion(_ transcript: String) -> String {
        guard let last = transcript.last, ".!?".contains(last) else { return transcript }
        return transcript + " "
    }
}

final class TestInsertionTarget {
    static var preparedProcessIdentifiers: [pid_t] = []
    static func prepareAccessibility(processIdentifier: pid_t) {
        preparedProcessIdentifiers.append(processIdentifier)
    }
    let identifier = UUID()
    let element: TestAXElement
    let window: TestAXElement?
    let valueAtCapture: String?
    let selectedTextRange: NSRange?
    let processIdentifier: pid_t
    var allowsTextCapture = true
    var isSupportedTextControl = true
    var value: String?
    var selection: NSRange?
    var isMinimized = false
    var insertionResult: AppTextInsertionResult = .notInserted
    var insertCallCount = 0
    var focusCallCount = 0
    var selectionRestoreCount = 0
    var minimizeChangeCount = 0
    var allowsSelectionRestore = true

    init(element: TestAXElement, window: TestAXElement?, value: String?, selection: NSRange?, processIdentifier: pid_t) {
        self.element = element
        self.window = window
        self.valueAtCapture = value
        self.selectedTextRange = selection
        self.value = value
        self.selection = selection
        self.processIdentifier = processIdentifier
    }

    var isFocused: Bool {
        TestAX.frontmostApplication?.processIdentifier == processIdentifier && isFocusedInApplication
    }

    var isFocusedInApplication: Bool {
        TestAX.focusedElement(for: processIdentifier) === element
    }

    var canSendEnter: Bool { allowsTextCapture && isFocusedInApplication }

    func setMinimized(_ minimized: Bool) {
        isMinimized = minimized
        minimizeChangeCount += 1
    }

    func focus() -> Bool {
        focusCallCount += 1
        TestAX.setFocusedWindow(window, for: processIdentifier)
        TestAX.setFocusedElement(element, for: processIdentifier)
        return true
    }

    func insert(_ text: String, isCurrent: @escaping () -> Bool, completion: @escaping (AppTextInsertionResult) -> Void) {
        insertCallCount += 1
        completion(isCurrent() ? insertionResult : .unavailable)
    }

    func pasteIfUnchanged(
        restoringSelection: Bool,
        isCurrent: () -> Bool,
        preparePaste: () -> Void,
        paste: () -> Void
    ) -> Bool {
        AppTextInsertionCore.pasteIfTargetMatches(
            capturedValue: valueAtCapture,
            range: selectedTextRange,
            readValue: { self.value },
            isTargetFocused: { isCurrent() && self.isFocused },
            restoreSelection: { range in
                guard restoringSelection else { return self.selection == range }
                guard self.allowsSelectionRestore else { return false }
                self.selection = range
                self.selectionRestoreCount += 1
                return self.selection == range
            },
            readSelection: { self.selection },
            preparePaste: preparePaste,
            paste: paste
        )
    }
}

final class TestPendingClipboardRestore {
    let state: TestInsertionState
    var didRestore = false

    init(state: TestInsertionState) { self.state = state }
}

final class TestAXElement {
    let identifier = UUID()
}

final class TestApplication {
    let processIdentifier: pid_t
    var isTerminated = false

    init(processIdentifier: pid_t) { self.processIdentifier = processIdentifier }

    func activate() { TestAX.activate(processIdentifier: processIdentifier) }
}

struct TestDispatchQueue {
    private struct Scheduled {
        let deadline: UInt64
        let order: Int
        let action: () -> Void
    }

    static let main = TestDispatchQueue()
    private static var scheduled: [Scheduled] = []
    private static var nextOrder = 0

    func async(execute action: @escaping () -> Void) {
        asyncAfter(deadline: .now(), execute: action)
    }

    func asyncAfter(deadline: DispatchTime, execute action: @escaping () -> Void) {
        Self.scheduled.append(Scheduled(deadline: deadline.uptimeNanoseconds, order: Self.nextOrder, action: action))
        Self.nextOrder += 1
    }

    static func reset() {
        scheduled.removeAll()
        nextOrder = 0
    }

    @discardableResult
    static func runNext() -> Bool {
        guard let nextIndex = scheduled.indices.min(by: {
            let left = scheduled[$0]
            let right = scheduled[$1]
            return left.deadline == right.deadline ? left.order < right.order : left.deadline < right.deadline
        }) else { return false }
        let task = scheduled.remove(at: nextIndex)
        task.action()
        return true
    }

    static func runAll() {
        var executions = 0
        while runNext() {
            executions += 1
            TestSupport.expect(executions < 200, "The fake dispatch queue should drain without a retry loop")
        }
    }
}

enum TestAX {
    static let focusedWindowAttribute = "focusedWindow"
    static let focusedElementAttribute = "focusedElement"
    static let focusedAttribute = "focused"
    static let raiseAction = "raise"

    static var frontmostApplication: TestApplication?
    static var isProcessTrusted = true
    static var afterActivation: ((pid_t) -> Void)?
    static var activationCount = 0
    static var restoreActionCount = 0
    private static var applications: [pid_t: TestApplication] = [:]
    private static var windows: [pid_t: TestAXElement] = [:]
    private static var elements: [pid_t: TestAXElement] = [:]
    private static var inputCounts: [CGEventType: UInt32] = [:]
    private static var elementOwners: [ObjectIdentifier: pid_t] = [:]

    static func reset() {
        isProcessTrusted = true
        TestInsertionTarget.preparedProcessIdentifiers = []
        frontmostApplication = nil
        afterActivation = nil
        activationCount = 0
        restoreActionCount = 0
        applications.removeAll()
        windows.removeAll()
        elements.removeAll()
        inputCounts.removeAll()
        elementOwners.removeAll()
    }

    static func register(_ application: TestApplication) { applications[application.processIdentifier] = application }

    static func runningApplication(processIdentifier: pid_t) -> TestApplication? {
        applications[processIdentifier]
    }

    static func applicationElement(_ processIdentifier: pid_t) -> TestApplication {
        applications[processIdentifier]!
    }

    static func focusedWindow(for processIdentifier: pid_t) -> TestAXElement? { windows[processIdentifier] }
    static func focusedElement(for processIdentifier: pid_t) -> TestAXElement? { elements[processIdentifier] }
    static func setFocusedWindow(_ window: TestAXElement?, for processIdentifier: pid_t) {
        windows[processIdentifier] = window
        if let window { elementOwners[ObjectIdentifier(window)] = processIdentifier }
    }

    static func setFocusedElement(_ element: TestAXElement?, for processIdentifier: pid_t) {
        elements[processIdentifier] = element
        if let element { elementOwners[ObjectIdentifier(element)] = processIdentifier }
    }

    static func activate(processIdentifier: pid_t) {
        activationCount += 1
        frontmostApplication = applications[processIdentifier]
        afterActivation?(processIdentifier)
    }

    static func performAction(_ element: TestAXElement, _ action: String) {
        restoreActionCount += 1
    }

    static func setAttributeValue(_ element: TestAXElement, _ attribute: String, _ value: Any) {
        guard attribute == focusedAttribute,
              let processIdentifier = elementOwners[ObjectIdentifier(element)] else { return }
        elements[processIdentifier] = element
    }

    static func elementsEqual(_ lhs: TestAXElement, _ rhs: TestAXElement) -> Bool {
        lhs.identifier == rhs.identifier
    }

    static func incrementInputCount(for eventType: CGEventType) { inputCounts[eventType, default: 0] += 1 }

    static func counterForEventType(_ stateID: CGEventSourceStateID, eventType: CGEventType) -> UInt32 {
        inputCounts[eventType, default: 0]
    }
}
