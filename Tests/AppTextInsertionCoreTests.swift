import AppKit
import Foundation

enum AppTextInsertionCoreTests {
    static func run() {
        testCaptureRoleEligibility()
        testWebAreaAncestorDetection()
        testEnterRoleEligibility()
        testVerifiedUTF16ReplacementAndCaret()
        testRequiredFocusForWebWrites()
        testWebFocusLossAfterWritePreservesCaret()
        testReplacementPreservesRichContentOutsideSelection()
        testUnavailableSnapshotsDoNotWrite()
        testExactUTF16SnapshotMatching()
        testWriteOutcomes()
        testDelayedWriteSequences()
        testPasteRequiresStableFocusedTarget()
        testPasteRestoresExactSelectionOnce()
    }

    private static func testCaptureRoleEligibility() {
        let eligible: [(String, String?)] = [
            ("AXTextArea", nil), ("AXTextArea", "AXUnknown"), ("AXTextArea", ""),
            ("AXTextField", ""), ("AXComboBox", "")
        ]
        for (role, subrole) in eligible {
            TestSupport.expect(
                AppTextInsertionCore.canCapture(role: role, subrole: subrole),
                "Supported non-secure fields should allow capture, including native text views without subroles"
            )
        }
        let excluded: [(String?, String?)] = [
            ("AXTextArea", "AXSecureTextField"), ("AXTextField", "AXSecureTextField"),
            ("AXTextField", nil), ("AXTextField", "AXUnknown"),
            ("AXButton", ""), (nil, ""), ("AXUnknown", ""), ("AXSecureTextField", "")
        ]
        for (role, subrole) in excluded {
            TestSupport.expect(
                !AppTextInsertionCore.canCapture(role: role, subrole: subrole),
                "Secure, unsupported, or unverifiable text-field roles must prevent capture"
            )
        }
    }

    private static func testEnterRoleEligibility() {
        for role in ["AXTextField", "AXTextArea", "AXComboBox"] {
            for subrole in [nil, "AXUnknown", ""] as [String?] {
                TestSupport.expect(AppTextInsertionCore.isSupportedTextControl(role: role, subrole: subrole),
                                   "Focused non-secure text controls can receive Enter without full text capture")
            }
            TestSupport.expect(!AppTextInsertionCore.isSupportedTextControl(role: role, subrole: "AXSecureTextField"),
                               "Secure fields must not receive targeted Enter")
        }
        for role in [nil, "AXButton", "AXUnknown", "AXSecureTextField"] as [String?] {
            TestSupport.expect(!AppTextInsertionCore.isSupportedTextControl(role: role, subrole: nil),
                               "Focus alone must not authorize Enter on non-text controls")
        }
        for subrole in [nil, "AXUnknown"] as [String?] {
            TestSupport.expect(!AppTextInsertionCore.canCapture(role: "AXTextField", subrole: subrole),
                               "Enter eligibility must not broaden full-field capture")
        }
    }

    private static func testWebAreaAncestorDetection() {
        let webChain = [
            TestAXRoleNode(role: "AXTextArea", parentIndex: 1),
            TestAXRoleNode(role: "AXGroup", parentIndex: 2),
            TestAXRoleNode(role: "AXWebArea", parentIndex: nil)
        ]
        TestSupport.expect(
            AppTextInsertionCore.isWebContent(
                of: 0, parent: { webChain[$0].parentIndex }, role: { webChain[$0].role }
            ),
            "A web area in the parent chain should classify the target as web content"
        )

        var directMarkerParentReads = 0
        var directMarkerRoleReads = 0
        TestSupport.expect(
            AppTextInsertionCore.isWebContent(
                of: 0,
                parent: { _ in directMarkerParentReads += 1; return nil },
                role: { _ in directMarkerRoleReads += 1; return nil },
                attributeNames: { _ in ["AXDOMClassList"] }
            ),
            "AXDOMClassList should identify web content without walking parents"
        )
        TestSupport.expectEqual(directMarkerParentReads, 0)
        TestSupport.expectEqual(directMarkerRoleReads, 0)

        let nativeChain = [
            TestAXRoleNode(role: "AXTextArea", parentIndex: 1),
            TestAXRoleNode(role: "AXGroup", parentIndex: 2),
            TestAXRoleNode(role: "AXWindow", parentIndex: nil)
        ]
        TestSupport.expect(
            !AppTextInsertionCore.isWebContent(
                of: 0, parent: { nativeChain[$0].parentIndex }, role: { nativeChain[$0].role }
            ),
            "A native AX parent chain should not be classified as web content"
        )

        let missingParent = [TestAXRoleNode(role: "AXTextArea", parentIndex: nil)]
        let missingRole = [
            TestAXRoleNode(role: "AXTextArea", parentIndex: 1),
            TestAXRoleNode(role: nil, parentIndex: nil)
        ]
        TestSupport.expect(
            !AppTextInsertionCore.isWebContent(
                of: 0, parent: { missingParent[$0].parentIndex }, role: { missingParent[$0].role }
            ),
            "A missing parent should terminate the search"
        )
        TestSupport.expect(
            !AppTextInsertionCore.isWebContent(
                of: 0, parent: { missingRole[$0].parentIndex }, role: { missingRole[$0].role }
            ),
            "A missing role should not match AXWebArea"
        )

        let cyclicChain = [
            TestAXRoleNode(role: "AXGroup", parentIndex: 1),
            TestAXRoleNode(role: "AXGroup", parentIndex: 0)
        ]
        var cyclicRoleReads = 0
        TestSupport.expect(
            !AppTextInsertionCore.isWebContent(
                of: 0,
                parent: { cyclicChain[$0].parentIndex },
                role: { cyclicRoleReads += 1; return cyclicChain[$0].role }
            ),
            "A cyclic chain without a web area should stop at the fixed traversal bound"
        )
        TestSupport.expectEqual(cyclicRoleReads, 32)

        let atBound = (0...32).map { index in
            TestAXRoleNode(role: index == 32 ? "AXWebArea" : "AXGroup",
                           parentIndex: index < 32 ? index + 1 : nil)
        }
        let beyondBound = (0...33).map { index in
            TestAXRoleNode(role: index == 33 ? "AXWebArea" : "AXGroup",
                           parentIndex: index < 33 ? index + 1 : nil)
        }
        TestSupport.expect(
            AppTextInsertionCore.isWebContent(
                of: 0, parent: { atBound[$0].parentIndex }, role: { atBound[$0].role }
            ),
            "The final ancestor within the bound should be checked"
        )
        TestSupport.expect(
            !AppTextInsertionCore.isWebContent(
                of: 0, parent: { beyondBound[$0].parentIndex }, role: { beyondBound[$0].role }
            ),
            "An ancestor beyond the fixed bound should not be classified as web content"
        )
    }

    private static func testVerifiedUTF16ReplacementAndCaret() {
        let originalValue = "one 🧪 two"
        let selectedRange = NSRange(location: 4, length: 2)
        var value: String? = originalValue
        var writes = 0
        var cursorRanges: [NSRange] = []

        let result = AppTextInsertionCore.insert(
            "🦊!",
            capturedValue: originalValue,
            range: selectedRange,
            readValue: { value },
            replaceText: { _, _, expectedValue in
                writes += 1
                value = expectedValue
                return true
            },
            placeCursor: { cursorRanges.append($0) }
        )

        TestSupport.expectEqual(result, .inserted)
        TestSupport.expectEqual(value, "one 🦊! two")
        TestSupport.expectEqual(writes, 1)
        TestSupport.expectEqual(cursorRanges, [NSRange(location: 7, length: 0)])
    }

    private static func testRequiredFocusForWebWrites() {
        let originalValue = "synthetic text"
        let selectedRange = NSRange(location: originalValue.utf16.count, length: 0)
        let cases: [(name: String, requiresFocus: Bool, focused: Bool, expected: AppTextInsertionResult, writes: Int)] = [
            ("unfocused web target", true, false, .notInserted, 0),
            ("focused web target", true, true, .inserted, 1),
            ("unfocused native target", false, false, .inserted, 1)
        ]

        for testCase in cases {
            var value: String? = originalValue
            var focusChecks = 0
            var writes = 0
            var cursorRanges: [NSRange] = []
            let result = AppTextInsertionCore.insert(
                "!",
                capturedValue: originalValue,
                range: selectedRange,
                requiresFocus: testCase.requiresFocus,
                isTargetFocused: { focusChecks += 1; return testCase.focused },
                readValue: { value },
                replaceText: { _, _, expectedValue in
                    writes += 1
                    value = expectedValue
                    return true
                },
                placeCursor: { cursorRanges.append($0) }
            )

            TestSupport.expect(result == testCase.expected, "Unexpected result for \(testCase.name)")
            TestSupport.expect(writes == testCase.writes, "Unexpected write count for \(testCase.name)")
            TestSupport.expect(focusChecks == (testCase.requiresFocus ? (testCase.focused ? 2 : 1) : 0),
                               "Focus should only gate web-backed writes for \(testCase.name)")
            TestSupport.expectEqual(value, testCase.writes == 0 ? originalValue : "synthetic text!")
            TestSupport.expectEqual(cursorRanges, testCase.writes == 0 ? [] : [NSRange(location: 15, length: 0)])
        }
    }

    private static func testWebFocusLossAfterWritePreservesCaret() {
        var value = "synthetic text"
        var focused = true
        var caretMoves = 0
        let result = AppTextInsertionCore.insert(
            "!", capturedValue: value, range: NSRange(location: value.utf16.count, length: 0),
            requiresFocus: true, isTargetFocused: { focused }, readValue: { value },
            replaceText: { _, _, expected in
                value = expected
                focused = false
                return true
            },
            placeCursor: { _ in caretMoves += 1 }
        )
        TestSupport.expectEqual(result, .inserted)
        TestSupport.expectEqual(value, "synthetic text!")
        TestSupport.expectEqual(caretMoves, 0)
    }

    private static func testReplacementPreservesRichContentOutsideSelection() {
        let attachmentData = Data([0x46, 0x46, 0x01])
        let attachment = NSTextAttachment(data: attachmentData, ofType: "application/octet-stream")
        let original = NSMutableAttributedString(string: "bold link target \u{FFFC} end")
        let boldRange = (original.string as NSString).range(of: "bold")
        let linkRange = (original.string as NSString).range(of: "link")
        let selectedRange = (original.string as NSString).range(of: "target")
        let attachmentRange = (original.string as NSString).range(of: "\u{FFFC}")
        let boldFont = NSFont.boldSystemFont(ofSize: 12)
        let link = URL(string: "https://example.invalid")!
        original.addAttribute(.font, value: boldFont, range: boldRange)
        original.addAttribute(.link, value: link, range: linkRange)
        original.addAttribute(.attachment, value: attachment, range: attachmentRange)

        let expectedText = (original.string as NSString).replacingCharacters(in: selectedRange, with: "new")
        var writes = 0
        let result = AppTextInsertionCore.insert(
            "new",
            capturedValue: original.string,
            range: selectedRange,
            readValue: { original.string },
            replaceText: { range, text, expectedReadbackValue in
                TestSupport.expectEqual(range, selectedRange)
                TestSupport.expectEqual(text, "new")
                TestSupport.expectEqual(expectedReadbackValue, expectedText)
                writes += 1
                original.replaceCharacters(in: range, with: text)
                return true
            },
            placeCursor: { _ in }
        )

        let shiftedAttachmentRange = NSRange(
            location: attachmentRange.location - selectedRange.length + ("new" as NSString).length,
            length: attachmentRange.length
        )
        TestSupport.expectEqual(result, .inserted)
        TestSupport.expectEqual(writes, 1)
        TestSupport.expectEqual(original.string, expectedText)
        TestSupport.expectEqual(original.attribute(.font, at: boldRange.location, effectiveRange: nil) as? NSFont, boldFont)
        TestSupport.expectEqual(original.attribute(.link, at: linkRange.location, effectiveRange: nil) as? URL, link)
        TestSupport.expect(original.attribute(.attachment, at: shiftedAttachmentRange.location, effectiveRange: nil) as? NSTextAttachment === attachment,
                           "A synthetic attachment outside the selected range should remain the same object")
        TestSupport.expectEqual(attachment.contents, attachmentData)
    }

    private static func testUnavailableSnapshotsDoNotWrite() {
        expectUnavailable(capturedValue: nil, currentValue: "synthetic", range: NSRange(location: 0, length: 0))
        expectUnavailable(capturedValue: "synthetic", currentValue: nil, range: NSRange(location: 0, length: 0))
        expectUnavailable(capturedValue: "captured", currentValue: "changed", range: NSRange(location: 0, length: 0))
        expectUnavailable(capturedValue: "synthetic", currentValue: "synthetic", range: nil)

        let invalidRanges = [
            NSRange(location: -1, length: 0),
            NSRange(location: 0, length: -1),
            NSRange(location: 0, length: 10),
            NSRange(location: NSNotFound, length: 0),
            NSRange(location: Int.max - 1, length: Int.max)
        ]
        for range in invalidRanges {
            expectUnavailable(capturedValue: "small", currentValue: "small", range: range)
        }
        expectUnavailable(
            capturedValue: "🧪",
            currentValue: "🧪",
            range: NSRange(location: 1, length: 1)
        )
    }

    private static func testExactUTF16SnapshotMatching() {
        let capturedValue = "é abc"
        let normalizedCurrentValue = "e\u{301} abc"
        let selectedRange = NSRange(location: 2, length: 1)
        var writes = 0
        var cursorCount = 0

        let mismatchResult = AppTextInsertionCore.insert(
            "X",
            capturedValue: capturedValue,
            range: selectedRange,
            readValue: { normalizedCurrentValue },
            replaceText: { _, _, _ in
                writes += 1
                return true
            },
            placeCursor: { _ in cursorCount += 1 }
        )
        TestSupport.expectEqual(mismatchResult, .unavailable)
        TestSupport.expectEqual(writes, 0)
        TestSupport.expectEqual(cursorCount, 0)

        var restoredRanges: [NSRange] = []
        var pasteCount = 0
        let mismatchPaste = AppTextInsertionCore.pasteIfTargetMatches(
            capturedValue: capturedValue,
            range: selectedRange,
            readValue: { normalizedCurrentValue },
            isTargetFocused: { true },
            restoreSelection: {
                restoredRanges.append($0)
                return true
            },
            readSelection: { selectedRange },
            paste: { pasteCount += 1 }
        )
        TestSupport.expect(!mismatchPaste, "Canonically equivalent text with different UTF-16 must reject paste")
        TestSupport.expectEqual(restoredRanges.count, 0)
        TestSupport.expectEqual(pasteCount, 0)

        var matchingValue: String? = capturedValue
        var matchingCursorRanges: [NSRange] = []
        let matchingInsert = AppTextInsertionCore.insert(
            "X",
            capturedValue: capturedValue,
            range: selectedRange,
            readValue: { matchingValue },
            replaceText: { _, _, expectedValue in
                matchingValue = expectedValue
                return true
            },
            placeCursor: { matchingCursorRanges.append($0) }
        )
        TestSupport.expectEqual(matchingInsert, .inserted)
        TestSupport.expectEqual(matchingValue, "é Xbc")
        TestSupport.expectEqual(matchingCursorRanges, [NSRange(location: 3, length: 0)])

        var matchingPasteCount = 0
        let matchingPaste = AppTextInsertionCore.pasteIfTargetMatches(
            capturedValue: capturedValue,
            range: selectedRange,
            readValue: { capturedValue },
            isTargetFocused: { true },
            restoreSelection: { $0 == selectedRange },
            readSelection: { selectedRange },
            paste: { matchingPasteCount += 1 }
        )
        TestSupport.expect(matchingPaste, "An exact UTF-16 snapshot should remain pasteable")
        TestSupport.expectEqual(matchingPasteCount, 1)
    }

    private static func testWriteOutcomes() {
        let originalValue = "synthetic original"
        let selectedRange = NSRange(location: 10, length: 8)
        let unchangedValue: String? = originalValue
        var unchangedCursorCount = 0
        let failedWithoutMutation = AppTextInsertionCore.insert(
            "replacement",
            capturedValue: originalValue,
            range: selectedRange,
            readValue: { unchangedValue },
            replaceText: { _, _, _ in false },
            placeCursor: { _ in unchangedCursorCount += 1 }
        )
        TestSupport.expectEqual(failedWithoutMutation, .notInserted)
        TestSupport.expectEqual(unchangedCursorCount, 0)

        var expectedAfterFailedWrite: String? = originalValue
        var failedWriteCursorRanges: [NSRange] = []
        let failedStatusButVerified = AppTextInsertionCore.insert(
            "replacement",
            capturedValue: originalValue,
            range: selectedRange,
            readValue: { expectedAfterFailedWrite },
            replaceText: { _, _, expectedValue in
                expectedAfterFailedWrite = expectedValue
                return false
            },
            placeCursor: { failedWriteCursorRanges.append($0) }
        )
        TestSupport.expectEqual(failedStatusButVerified, .inserted)
        TestSupport.expectEqual(expectedAfterFailedWrite, "synthetic replacement")
        TestSupport.expectEqual(failedWriteCursorRanges, [NSRange(location: 21, length: 0)])

        var partiallyChangedValue: String? = originalValue
        let failedAfterMutation = AppTextInsertionCore.insert(
            "replacement",
            capturedValue: originalValue,
            range: selectedRange,
            readValue: { partiallyChangedValue },
            replaceText: { _, _, _ in
                partiallyChangedValue = "synthetic partial"
                return false
            },
            placeCursor: { _ in TestSupport.expect(false, "Unverified writes must not move the caret") }
        )
        TestSupport.expectEqual(failedAfterMutation, .unverified)

        var mismatchedReadbackValue: String? = originalValue
        var writes = 0
        var cursorCount = 0
        let successfulButUnverified = AppTextInsertionCore.insert(
            "replacement",
            capturedValue: originalValue,
            range: selectedRange,
            readValue: { mismatchedReadbackValue },
            replaceText: { _, _, _ in
                writes += 1
                mismatchedReadbackValue = "synthetic changed"
                return true
            },
            placeCursor: { _ in cursorCount += 1 }
        )
        TestSupport.expectEqual(successfulButUnverified, .unverified)
        TestSupport.expectEqual(writes, 1)
        TestSupport.expectEqual(cursorCount, 0)

        let unchangedAfterSuccessfulWrite: String? = originalValue
        var unchangedSuccessCursorCount = 0
        let successfulButUnchanged = AppTextInsertionCore.insert(
            "replacement",
            capturedValue: originalValue,
            range: selectedRange,
            readValue: { unchangedAfterSuccessfulWrite },
            replaceText: { _, _, _ in true },
            placeCursor: { _ in unchangedSuccessCursorCount += 1 }
        )
        TestSupport.expectEqual(successfulButUnchanged, .unverified)
        TestSupport.expectEqual(unchangedSuccessCursorCount, 0)

        let identicalText = "synthetic same"
        let identicalRange = NSRange(location: 10, length: 4)
        for writeSucceeded in [true, false] {
            var unchangedValue: String? = identicalText
            var cursorRanges: [NSRange] = []
            let identicalReplacement = AppTextInsertionCore.insert(
                "same",
                capturedValue: identicalText,
                range: identicalRange,
                readValue: { unchangedValue },
                replaceText: { _, _, expectedValue in
                    unchangedValue = expectedValue
                    return writeSucceeded
                },
                placeCursor: { cursorRanges.append($0) }
            )
            TestSupport.expectEqual(identicalReplacement, .inserted)
            TestSupport.expectEqual(unchangedValue, identicalText)
            TestSupport.expectEqual(cursorRanges, [NSRange(location: 14, length: 0)])
        }

        var unreadableValue: String? = originalValue
        let failedWithUnreadableReadback = AppTextInsertionCore.insert(
            "replacement",
            capturedValue: originalValue,
            range: selectedRange,
            readValue: { unreadableValue },
            replaceText: { _, _, _ in
                unreadableValue = nil
                return false
            },
            placeCursor: { _ in TestSupport.expect(false, "Unreadable writes must not move the caret") }
        )
        TestSupport.expectEqual(failedWithUnreadableReadback, .unverified)
    }

    private static func testDelayedWriteSequences() {
        let originalValue = "synthetic original"
        let expectedValue = "synthetic replacement"
        let sequences: [(
            name: String, writeSucceeded: Bool, immediate: String?, polls: [String?],
            results: [AppTextInsertionResult]
        )] = [
            ("successful unchanged", true, originalValue, [originalValue, expectedValue], [.unverified, .unverified, .inserted]),
            ("successful partial", true, "synthetic partial", [expectedValue], [.unverified, .inserted]),
            ("successful unreadable", true, nil, [expectedValue], [.unverified, .inserted]),
            ("failed unchanged", false, originalValue, [originalValue], [.notInserted, .notInserted]),
            ("failed partial", false, "synthetic partial", [originalValue, expectedValue],
             [.unverified, .unverified, .inserted]),
            ("failed unreadable", false, nil, [originalValue, expectedValue],
             [.unverified, .unverified, .inserted]),
            ("poll turns ambiguous", false, originalValue,
             ["synthetic partial", originalValue, originalValue, expectedValue],
             [.notInserted, .unverified, .unverified, .unverified, .inserted]),
            ("unreadable poll turns ambiguous", false, originalValue,
             [nil, originalValue, originalValue, expectedValue],
             [.notInserted, .unverified, .unverified, .unverified, .inserted]),
            ("successful expected", true, expectedValue, [], [.inserted])
        ]

        for sequence in sequences {
            var readbacks: [String?] = [originalValue, sequence.immediate]
            var writes = 0
            var cursorPlacements = 0
            var result = AppTextInsertionCore.insert(
                "replacement", capturedValue: originalValue, range: NSRange(location: 10, length: 8),
                readValue: { readbacks.removeFirst() },
                replaceText: { _, _, _ in writes += 1; return sequence.writeSucceeded },
                placeCursor: { _ in cursorPlacements += 1 }
            )
            var actualResults = [result]
            for observedValue in sequence.polls {
                result = AppTextInsertionCore.classifyWrite(
                    originalValue: originalValue, expectedValue: expectedValue,
                    writeSucceeded: sequence.writeSucceeded, observedValue: observedValue,
                    priorResult: result
                )
                actualResults.append(result)
            }
            TestSupport.expect(
                actualResults == sequence.results,
                "\(sequence.name) produced \(actualResults), expected \(sequence.results)"
            )
            TestSupport.expectEqual(writes, 1)
            TestSupport.expectEqual(cursorPlacements, sequence.results[0] == .inserted ? 1 : 0)
        }
    }

    private static func testPasteRequiresStableFocusedTarget() {
        expectPasteRejected(
            capturedValue: "captured value",
            currentValue: "captured value",
            range: NSRange(location: 0, length: 0),
            focused: false,
            expectedRestoreCount: 0
        )
        expectPasteRejected(
            capturedValue: "captured value",
            currentValue: "changed value",
            range: NSRange(location: 0, length: 0),
            focused: true,
            expectedRestoreCount: 0
        )
        expectPasteRejected(
            capturedValue: nil,
            currentValue: "captured value",
            range: NSRange(location: 0, length: 0),
            focused: true,
            expectedRestoreCount: 0
        )
        expectPasteRejected(
            capturedValue: "captured value",
            currentValue: "captured value",
            range: NSRange(location: 100, length: 0),
            focused: true,
            expectedRestoreCount: 0
        )
        expectPasteRejected(
            capturedValue: "captured value",
            currentValue: "captured value",
            range: NSRange(location: 0, length: 0),
            focused: true,
            restoreSucceeds: false,
            expectedRestoreCount: 1
        )
        expectPasteRejected(
            capturedValue: "captured value",
            currentValue: "captured value",
            range: NSRange(location: 0, length: 0),
            focused: true,
            loseFocusDuringRestore: true,
            expectedRestoreCount: 1
        )
        expectPasteRejected(
            capturedValue: "captured value",
            currentValue: "captured value",
            range: NSRange(location: 0, length: 0),
            focused: true,
            changeTextDuringRestore: true,
            expectedRestoreCount: 1
        )
    }

    private static func testPasteRestoresExactSelectionOnce() {
        let originalValue = "one 🧪 two"
        let originalRange = NSRange(location: 4, length: 2)
        var restoredRanges: [NSRange] = []
        var pasteCount = 0

        let didPaste = AppTextInsertionCore.pasteIfTargetMatches(
            capturedValue: originalValue,
            range: originalRange,
            readValue: { originalValue },
            isTargetFocused: { true },
            restoreSelection: {
                restoredRanges.append($0)
                return true
            },
            readSelection: { originalRange },
            paste: { pasteCount += 1 }
        )

        TestSupport.expect(didPaste, "A stable focused target should allow paste")
        TestSupport.expectEqual(restoredRanges, [originalRange])
        TestSupport.expectEqual(pasteCount, 1)
    }

    private static func expectUnavailable(
        capturedValue: String?,
        currentValue: String?,
        range: NSRange?
    ) {
        var writes = 0
        var cursorCount = 0
        var focusChecks = 0
        let result = AppTextInsertionCore.insert(
            "replacement",
            capturedValue: capturedValue,
            range: range,
            requiresFocus: true,
            isTargetFocused: { focusChecks += 1; return false },
            readValue: { currentValue },
            replaceText: { _, _, _ in
                writes += 1
                return true
            },
            placeCursor: { _ in cursorCount += 1 }
        )
        TestSupport.expectEqual(result, .unavailable)
        TestSupport.expectEqual(writes, 0)
        TestSupport.expectEqual(cursorCount, 0)
        TestSupport.expectEqual(focusChecks, 0)
    }

    private static func expectPasteRejected(
        capturedValue: String?,
        currentValue initialValue: String?,
        range: NSRange?,
        focused initialFocus: Bool,
        restoreSucceeds: Bool = true,
        loseFocusDuringRestore: Bool = false,
        changeTextDuringRestore: Bool = false,
        expectedRestoreCount: Int
    ) {
        var currentValue = initialValue
        var focused = initialFocus
        var restoredRanges: [NSRange] = []
        var pasteCount = 0
        let result = AppTextInsertionCore.pasteIfTargetMatches(
            capturedValue: capturedValue,
            range: range,
            readValue: { currentValue },
            isTargetFocused: { focused },
            restoreSelection: { selectedRange in
                restoredRanges.append(selectedRange)
                if loseFocusDuringRestore { focused = false }
                if changeTextDuringRestore { currentValue = "changed during restore" }
                return restoreSucceeds
            },
            readSelection: { range },
            paste: { pasteCount += 1 }
        )

        TestSupport.expect(!result, "Unsafe paste conditions should be rejected")
        TestSupport.expectEqual(restoredRanges.count, expectedRestoreCount)
        TestSupport.expectEqual(pasteCount, 0)
    }

    private struct TestAXRoleNode {
        let role: String?
        let parentIndex: Int?
    }
}
