import Foundation

enum PostProcessingServiceTests {
    static func run() {
        testAutoDetectAndEnglishLeavePromptUnchanged()
        testSelectedLanguageIsNamed()
        testOutputLanguageTakesPrecedence()
        testCustomPromptKeepsDirective()
        testFallbackModelReceivesSameDirective()
        testEnglishRequestIsUnchanged()
        testEmptyLatestContextStillProcessesCleanupAndCommand()
        testFallbackRefreshesContextForCleanupAndCommand()
    }

    private static let directive = "The dictation is primarily in Russian"

    private static func testAutoDetectAndEnglishLeavePromptUnchanged() {
        for language in ["", "  ", "English"] {
            TestSupport.expectEqual(
                PostProcessingService.cleanupSystemPrompt(
                    customSystemPrompt: "",
                    outputLanguage: "",
                    dictationLanguage: language
                ),
                PostProcessingService.defaultSystemPrompt
            )
        }
    }

    private static func testSelectedLanguageIsNamed() {
        let prompt = PostProcessingService.cleanupSystemPrompt(
            customSystemPrompt: "",
            outputLanguage: "",
            dictationLanguage: "Russian"
        )
        TestSupport.expect(prompt.hasPrefix(PostProcessingService.defaultSystemPrompt), "Directive must only append")
        TestSupport.expect(prompt.contains(directive), "Selected language must be named")
        TestSupport.expect(prompt.contains("Write the cleaned text in Russian"), "Output language must be named")
        TestSupport.expect(
            prompt.contains("Preserve mixed-language words and spans in their original languages"),
            "Naming a language must not override mixed-language preservation"
        )
        TestSupport.expect(!prompt.contains("Translate the final cleaned text"), "Keeping a language must not translate")
    }

    private static func testOutputLanguageTakesPrecedence() {
        let prompt = PostProcessingService.cleanupSystemPrompt(
            customSystemPrompt: "",
            outputLanguage: "German",
            dictationLanguage: "Russian"
        )
        TestSupport.expectEqual(
            prompt,
            PostProcessingService.applyOutputLanguage(PostProcessingService.defaultSystemPrompt, language: "German")
        )
        TestSupport.expect(!prompt.contains(directive), "Output Language must replace the dictation directive")
    }

    private static func testCustomPromptKeepsDirective() {
        let prompt = PostProcessingService.cleanupSystemPrompt(
            customSystemPrompt: "Synthetic custom prompt.",
            outputLanguage: "",
            dictationLanguage: "Russian"
        )
        TestSupport.expect(prompt.hasPrefix("Synthetic custom prompt."), "Custom prompt must replace the default")
        TestSupport.expect(!prompt.contains(PostProcessingService.defaultSystemPrompt), "Default prompt must not leak in")
        TestSupport.expect(prompt.contains(directive), "Custom prompt must still get the directive")
    }

    private static func testFallbackModelReceivesSameDirective() {
        // The primary returns empty content, which retries once on the fallback model.
        let requests = cleanupRequests(dictationLanguage: "Russian") { model in
            model == "synthetic-primary" ? "" : "Synthetic cleaned text."
        }
        TestSupport.expectEqual(requests.map(\.model), ["synthetic-primary", "synthetic-fallback"])
        for request in requests {
            TestSupport.expect(request.systemPrompt.contains(directive), "\(request.model) must get the directive")
        }
        TestSupport.expectEqual(requests[0].systemPrompt, requests[1].systemPrompt)
    }

    private static func testEnglishRequestIsUnchanged() {
        let requests = cleanupRequests(dictationLanguage: "English") { _ in "Synthetic cleaned text." }
        TestSupport.expectEqual(requests.map(\.systemPrompt), [PostProcessingService.defaultSystemPrompt])
    }

    private static func testEmptyLatestContextStillProcessesCleanupAndCommand() {
        let cleanup = runCleanup(
            contextSummaryProvider: { "" },
            reply: { _ in "Synthetic cleaned text." }
        )
        TestSupport.expectEqual(cleanup.result?.transcript, "Synthetic cleaned text.")
        TestSupport.expectEqual(cleanup.requests.count, 1)
        TestSupport.expect(
            cleanup.requests.first?.userPrompt.contains("Stale snapshot") == false,
            "Cleanup must omit invalidated context"
        )

        let command = runCommand(
            contextSummaryProvider: { "" },
            reply: { _ in "Synthetic transformed text." }
        )
        TestSupport.expectEqual(command.result?.transcript, "Synthetic transformed text.")
        TestSupport.expectEqual(command.requests.count, 1)
        TestSupport.expect(
            command.requests.first?.userPrompt.contains("Stale snapshot") == false,
            "Edit Mode must omit invalidated context"
        )
    }

    private static func testFallbackRefreshesContextForCleanupAndCommand() {
        let cleanupSummaries = SummarySequence(["Stale summary", ""])
        let cleanup = runCleanup(
            contextSummaryProvider: { await cleanupSummaries.next() },
            reply: { model in model == "synthetic-primary" ? "" : "Synthetic cleaned text." }
        )
        TestSupport.expectEqual(cleanup.result?.transcript, "Synthetic cleaned text.")
        TestSupport.expectEqual(cleanup.requests.map(\.model), ["synthetic-primary", "synthetic-fallback"])
        TestSupport.expect(
            cleanup.requests.first?.userPrompt.contains("Stale summary") == true,
            "Primary cleanup request should use its current summary"
        )
        TestSupport.expect(
            cleanup.requests.last?.userPrompt.contains("Stale summary") == false,
            "Fallback cleanup request must omit invalidated context"
        )

        let commandSummaries = SummarySequence(["Stale summary", ""])
        let command = runCommand(
            contextSummaryProvider: { await commandSummaries.next() },
            reply: { model in model == "synthetic-primary" ? "" : "Synthetic transformed text." }
        )
        TestSupport.expectEqual(command.result?.transcript, "Synthetic transformed text.")
        TestSupport.expectEqual(command.requests.map(\.model), ["synthetic-primary", "synthetic-fallback"])
        TestSupport.expect(
            command.requests.first?.userPrompt.contains("Stale summary") == true,
            "Primary Edit Mode request should use its current summary"
        )
        TestSupport.expect(
            command.requests.last?.userPrompt.contains("Stale summary") == false,
            "Fallback Edit Mode request must omit invalidated context"
        )
    }

    // MARK: - Request capture

    private struct CapturedRequest {
        let model: String
        let systemPrompt: String
        let userPrompt: String
    }

    private struct ProcessingRun {
        let result: PostProcessingResult?
        let requests: [CapturedRequest]
    }

    private actor SummarySequence {
        private var summaries: [String]

        init(_ summaries: [String]) {
            self.summaries = summaries
        }

        func next() -> String {
            summaries.isEmpty ? "" : summaries.removeFirst()
        }
    }

    private final class RequestRecorder: @unchecked Sendable {
        private let lock = NSLock()
        private var bodies: [Data] = []

        func record(_ body: Data?) {
            lock.lock()
            defer { lock.unlock() }
            bodies.append(body ?? Data())
        }

        var captured: [CapturedRequest] {
            lock.lock()
            defer { lock.unlock() }
            return bodies.map { body in
                let json = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] ?? [:]
                let messages = json["messages"] as? [[String: Any]] ?? []
                let system = messages.first { $0["role"] as? String == "system" }
                let user = messages.first { $0["role"] as? String == "user" }
                return CapturedRequest(
                    model: json["model"] as? String ?? "",
                    systemPrompt: system?["content"] as? String ?? "",
                    userPrompt: user?["content"] as? String ?? ""
                )
            }
        }
    }

    private final class ResultRecorder: @unchecked Sendable {
        private let lock = NSLock()
        private var storedResult: PostProcessingResult?

        func record(_ result: PostProcessingResult?) {
            lock.lock()
            defer { lock.unlock() }
            storedResult = result
        }

        var result: PostProcessingResult? {
            lock.lock()
            defer { lock.unlock() }
            return storedResult
        }
    }

    private static func cleanupRequests(
        dictationLanguage: String,
        reply: @escaping @Sendable (String) -> String
    ) -> [CapturedRequest] {
        let recorder = RequestRecorder()
        let service = makeService(recorder: recorder, reply: reply)
        _ = runService {
            try await service.postProcess(
                transcript: "synthetic transcript",
                context: makeContext(),
                customVocabulary: "",
                dictationLanguage: dictationLanguage
            )
        }
        return recorder.captured
    }

    private static func runCleanup(
        contextSummaryProvider: @escaping @Sendable () async -> String,
        reply: @escaping @Sendable (String) -> String
    ) -> ProcessingRun {
        let recorder = RequestRecorder()
        let service = makeService(recorder: recorder, reply: reply)
        let result = runService {
            try await service.postProcess(
                transcript: "synthetic transcript",
                context: makeContext(summary: "Stale snapshot"),
                customVocabulary: "",
                contextSummaryProvider: contextSummaryProvider
            )
        }
        return ProcessingRun(result: result, requests: recorder.captured)
    }

    private static func runCommand(
        contextSummaryProvider: @escaping @Sendable () async -> String,
        reply: @escaping @Sendable (String) -> String
    ) -> ProcessingRun {
        let recorder = RequestRecorder()
        let service = makeService(recorder: recorder, reply: reply)
        let result = runService {
            try await service.commandTransform(
                selectedText: "Synthetic selected text.",
                voiceCommand: "Shorten this.",
                context: makeContext(summary: "Stale snapshot"),
                customVocabulary: "",
                contextSummaryProvider: contextSummaryProvider
            )
        }
        return ProcessingRun(result: result, requests: recorder.captured)
    }

    private static func makeService(
        recorder: RequestRecorder,
        reply: @escaping @Sendable (String) -> String
    ) -> PostProcessingService {
        PostProcessingService(
            apiKey: "synthetic-key",
            baseURL: "https://example.invalid/v1",
            preferredModel: "synthetic-primary",
            preferredFallbackModel: "synthetic-fallback",
            transport: { request in
                recorder.record(request.httpBody)
                let json = (try? JSONSerialization.jsonObject(with: request.httpBody ?? Data())) as? [String: Any]
                let model = json?["model"] as? String ?? ""
                let body = try JSONSerialization.data(withJSONObject: [
                    "choices": [["message": ["content": reply(model)]]]
                ])
                let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (body, response)
            }
        )
    }

    private static func runService(
        _ operation: @escaping @Sendable () async throws -> PostProcessingResult
    ) -> PostProcessingResult? {
        let result = ResultRecorder()
        let done = DispatchSemaphore(value: 0)
        Task {
            result.record(try? await operation())
            done.signal()
        }
        done.wait()
        return result.result
    }

    private static func makeContext(summary: String = "") -> AppContext {
        AppContext(
            appName: nil,
            bundleIdentifier: nil,
            windowTitle: nil,
            selectedText: nil,
            currentActivity: summary,
            contextSystemPrompt: nil,
            contextPrompt: nil,
            screenshotDataURL: nil,
            screenshotMimeType: nil,
            screenshotError: nil
        )
    }
}
