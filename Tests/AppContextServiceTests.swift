import Foundation

enum AppContextServiceTests {
    static func run() {
        testScreenshotFallbackRejectsWindowsFromOtherProcesses()
        testScreenshotSelectionPrefersFocusedWindowBounds()
        testScreenshotSelectionUsesFocusedWindowTitleWhenBoundsAreUnavailable()
        testScreenshotFallbackUsesBestFrontmostProcessWindow()
        testQwenRawOutputIsSummarized()
        testQwenReasoningOutputIsStripped()
        testNonStrippingModelPreservesExistingBehavior()
        testDeprecatedGroqModelsAreNotPredefined()
        testQwenCleanupDisablesReasoning()
    }

    private static func testScreenshotFallbackRejectsWindowsFromOtherProcesses() {
        let selectedWindowID = AppContextService.screenshotWindowID(
            processIdentifier: 42,
            focusedWindowBounds: nil,
            focusedWindowTitle: nil,
            candidates: [
                ScreenshotWindowCandidate(
                    id: 9001,
                    processIdentifier: 84,
                    layer: 0,
                    bounds: CGRect(x: 0, y: 0, width: 1280, height: 720),
                    title: "Synthetic unrelated window"
                )
            ]
        )

        TestSupport.expectEqual(selectedWindowID, nil)
    }

    private static func testScreenshotSelectionPrefersFocusedWindowBounds() {
        let selectedWindowID = AppContextService.screenshotWindowID(
            processIdentifier: 42,
            focusedWindowBounds: CGRect(x: 500, y: 100, width: 400, height: 300),
            focusedWindowTitle: nil,
            candidates: [
                ScreenshotWindowCandidate(
                    id: 100,
                    processIdentifier: 42,
                    layer: 0,
                    bounds: CGRect(x: 0, y: 0, width: 1600, height: 900),
                    title: "Synthetic background window"
                ),
                ScreenshotWindowCandidate(
                    id: 101,
                    processIdentifier: 42,
                    layer: 0,
                    bounds: CGRect(x: 500, y: 100, width: 400, height: 300),
                    title: "Synthetic focused window"
                )
            ]
        )

        TestSupport.expectEqual(selectedWindowID, 101)
    }

    private static func testScreenshotSelectionUsesFocusedWindowTitleWhenBoundsAreUnavailable() {
        let selectedWindowID = AppContextService.screenshotWindowID(
            processIdentifier: 42,
            focusedWindowBounds: nil,
            focusedWindowTitle: "Synthetic focused document",
            candidates: [
                ScreenshotWindowCandidate(
                    id: 200,
                    processIdentifier: 42,
                    layer: 0,
                    bounds: CGRect(x: 0, y: 0, width: 1400, height: 900),
                    title: "Synthetic unrelated document"
                ),
                ScreenshotWindowCandidate(
                    id: 201,
                    processIdentifier: 42,
                    layer: 0,
                    bounds: CGRect(x: 100, y: 100, width: 800, height: 600),
                    title: "Synthetic focused document — Edited"
                )
            ]
        )

        TestSupport.expectEqual(selectedWindowID, 201)
    }

    private static func testScreenshotFallbackUsesBestFrontmostProcessWindow() {
        let selectedWindowID = AppContextService.screenshotWindowID(
            processIdentifier: 42,
            focusedWindowBounds: nil,
            focusedWindowTitle: nil,
            candidates: [
                ScreenshotWindowCandidate(
                    id: 300,
                    processIdentifier: 42,
                    layer: 1,
                    bounds: CGRect(x: 0, y: 0, width: 1200, height: 800),
                    title: nil
                ),
                ScreenshotWindowCandidate(
                    id: 301,
                    processIdentifier: 42,
                    layer: 0,
                    bounds: CGRect(x: 20, y: 20, width: 900, height: 700),
                    title: nil
                ),
                ScreenshotWindowCandidate(
                    id: 302,
                    processIdentifier: 84,
                    layer: 0,
                    bounds: CGRect(x: 0, y: 0, width: 1600, height: 1000),
                    title: nil
                )
            ]
        )

        TestSupport.expectEqual(selectedWindowID, 301)
    }

    private static func testQwenRawOutputIsSummarized() {
        let output = """
        The user is replying to an email about the product launch. They likely intend to confirm the next steps. This third sentence should be dropped.
        """

        let summary = AppContextService.activitySummary(from: output, model: "qwen/qwen3.6-27b")

        TestSupport.expectEqual(
            summary,
            "The user is replying to an email about the product launch. They likely intend to confirm the next steps."
        )
    }

    private static func testQwenReasoningOutputIsStripped() {
        let output = """
        <think>
        Hidden chain of thought should never appear in context.
        It contains misleading details.
        </think>
        The user is editing a project note in FreeFlow. They likely intend to tighten the release wording.
        """

        let summary = AppContextService.activitySummary(from: output, model: "qwen/qwen3.6-27b")

        TestSupport.expectEqual(
            summary,
            "The user is editing a project note in FreeFlow. They likely intend to tighten the release wording."
        )
        TestSupport.expect(summary?.contains("Hidden chain of thought") == false, "Qwen reasoning leaked into summary")
    }

    private static func testNonStrippingModelPreservesExistingBehavior() {
        let output = "<think>Visible for non-stripping models.</think> The user is writing a status update."

        let summary = AppContextService.activitySummary(
            from: output,
            model: "meta-llama/llama-4-scout-17b-16e-instruct"
        )

        TestSupport.expectEqual(summary, output)
    }

    private static func testDeprecatedGroqModelsAreNotPredefined() {
        let deprecatedModels = [
            "qwen/qwen3-32b",
            "meta-llama/llama-4-scout-17b-16e-instruct",
            "llama-3.1-8b-instant",
            "llama-3.3-70b-versatile"
        ]

        for model in deprecatedModels {
            TestSupport.expect(!ModelConfiguration.llmModels.contains(model), "Deprecated model remains in picker: \(model)")
        }
        TestSupport.expect(ModelConfiguration.llmModels.contains("qwen/qwen3.6-27b"), "New fallback is missing from picker")
    }

    private static func testQwenCleanupDisablesReasoning() {
        let config = ModelConfiguration.config(for: "qwen/qwen3.6-27b")

        TestSupport.expect(config.reasoningEffort == "none", "Qwen cleanup should disable reasoning")
        TestSupport.expect(config.includeReasoning == false, "Qwen cleanup should exclude reasoning output")
    }
}
