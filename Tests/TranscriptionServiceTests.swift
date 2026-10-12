import Foundation

// Every request is intercepted before networking. Keys, audio bytes, transcript
// text, hosts, and errors below are invented fixtures.
enum TranscriptionServiceTests {
    static func run() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FreeFlowSyntheticUploadTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let audioURL = directory.appendingPathComponent("synthetic.wav")
        let audio = Data("RIFF-synthetic-audio-fixture".utf8)
        try audio.write(to: audioURL)

        try await testOpenAIRequest(audioURL: audioURL, audio: audio)
        try await testElevenLabsRequest(audioURL: audioURL, audio: audio)
        try await testDefaultModelAndOptionalLanguage(audioURL: audioURL)
        try await testProviderDefaultEndpoints(audioURL: audioURL)
        await testAPIKeyValidationIsolation()
        try await testJSONAndVerboseJSONParsing(audioURL: audioURL)
        try await testMalformedResponses(audioURL: audioURL)
        try await testHTTPFailures(audioURL: audioURL)
        try await testTimeoutAndCancellation(audioURL: audioURL)
    }

    private static func testOpenAIRequest(audioURL: URL, audio: Data) async throws {
        let stub = UploadStub(.http(json(["text": "Synthetic upload transcript."]), 200))
        let service = try TranscriptionService(
            apiKey: "  synthetic-openai-key \n",
            baseURL: " https://synthetic-openai.invalid/openai/v1/// ",
            transcriptionModel: " gpt-4o-mini-transcribe ",
            language: " en ",
            timeoutSeconds: 3,
            upload: { try await stub.upload($0, $1) }
        )
        let text = try await service.transcribe(fileURL: audioURL)
        TestSupport.expectEqual(text, "Synthetic upload transcript.")
        let (request, body) = await stub.capturedRequest()
        TestSupport.expectEqual(request.url?.path, "/openai/v1/audio/transcriptions")
        TestSupport.expectEqual(request.httpMethod, "POST")
        TestSupport.expectEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer synthetic-openai-key")
        TestSupport.expectEqual(request.value(forHTTPHeaderField: "xi-api-key"), nil)
        TestSupport.expectEqual(request.timeoutInterval, 3)
        expectMultipart(request: request, body: body, audio: audio, fields: [
            ("model", "gpt-4o-mini-transcribe"), ("response_format", "json"), ("language", "en")
        ])
    }

    private static func testElevenLabsRequest(audioURL: URL, audio: Data) async throws {
        let stub = UploadStub(.http(json(["text": "Synthetic Scribe transcript."]), 200))
        let service = try TranscriptionService(
            provider: .elevenLabs,
            apiKey: " synthetic-elevenlabs-key ",
            baseURL: "https://synthetic-elevenlabs.invalid/v1/",
            // The batch provider must select Scribe even if the shared model
            // still contains the default OpenAI-compatible Whisper model.
            transcriptionModel: "whisper-large-v3",
            language: " de ",
            timeoutSeconds: 3,
            upload: { try await stub.upload($0, $1) }
        )
        let text = try await service.transcribe(fileURL: audioURL)
        TestSupport.expectEqual(text, "Synthetic Scribe transcript.")
        let (request, body) = await stub.capturedRequest()
        TestSupport.expectEqual(request.url?.path, "/v1/speech-to-text")
        TestSupport.expectEqual(request.httpMethod, "POST")
        TestSupport.expectEqual(request.value(forHTTPHeaderField: "xi-api-key"), "synthetic-elevenlabs-key")
        TestSupport.expectEqual(request.value(forHTTPHeaderField: "Authorization"), nil)
        expectMultipart(request: request, body: body, audio: audio, fields: [
            ("model_id", "scribe_v2"), ("tag_audio_events", "false"),
            ("timestamps_granularity", "none"), ("language_code", "de")
        ])
    }

    private static func testDefaultModelAndOptionalLanguage(audioURL: URL) async throws {
        TestSupport.expectEqual(TranscriptionService.defaultOpenAICompatibleBaseURL, "https://api.groq.com/openai/v1")
        TestSupport.expectEqual(TranscriptionService.defaultElevenLabsBaseURL, "https://api.elevenlabs.io/v1")
        TestSupport.expectEqual(TranscriptionService.defaultElevenLabsRealtimeModel, "scribe_v2_realtime")
        for model in ["whisper-1", "whisper-large-v3", "whisper-large-v3-turbo", " WHISPER-1 "] {
            TestSupport.expectEqual(TranscriptionService.responseFormat(forModel: model), "verbose_json")
        }
        for model in ["gpt-4o-transcribe", "gpt-4o-mini-transcribe", "synthetic-custom-model"] {
            TestSupport.expectEqual(TranscriptionService.responseFormat(forModel: model), "json")
        }

        for provider in TranscriptionProvider.allCases {
            let stub = UploadStub(.http(json(["text": ""]), 200))
            let service = try makeService(provider: provider, stub: stub, model: " \n ", language: " \n ")
            let text = try await service.transcribe(fileURL: audioURL)
            TestSupport.expectEqual(text, "")
            let (_, body) = await stub.capturedRequest()
            let encoded = String(decoding: body, as: UTF8.self)
            TestSupport.expect(!encoded.contains("name=\"language\""), "Blank language must be omitted")
            TestSupport.expect(!encoded.contains("name=\"language_code\""), "Blank language code must be omitted")
            if provider == .openAICompatible {
                TestSupport.expect(encoded.contains("\r\n\r\nwhisper-large-v3\r\n"), "Blank model must use the existing default")
                TestSupport.expect(encoded.contains("\r\n\r\nverbose_json\r\n"), "Whisper must request segment metadata")
            }
        }
    }

    private static func testProviderDefaultEndpoints(audioURL: URL) async throws {
        for provider in TranscriptionProvider.allCases {
            let stub = UploadStub(.http(json(["text": "Synthetic default endpoint."]), 200))
            let service = try TranscriptionService(
                provider: provider,
                apiKey: "synthetic-selected-provider-key",
                upload: { try await stub.upload($0, $1) }
            )
            _ = try await service.transcribe(fileURL: audioURL)
            let (request, _) = await stub.capturedRequest()
            let expectedHost = provider == .elevenLabs ? "api.elevenlabs.io" : "api.groq.com"
            TestSupport.expectEqual(request.url?.host, expectedHost)
            TestSupport.expectEqual(
                request.url?.path,
                provider == .elevenLabs ? "/v1/speech-to-text" : "/openai/v1/audio/transcriptions"
            )
            TestSupport.expectEqual(
                request.value(forHTTPHeaderField: provider == .elevenLabs ? "xi-api-key" : "Authorization"),
                provider == .elevenLabs ? "synthetic-selected-provider-key" : "Bearer synthetic-selected-provider-key"
            )
            TestSupport.expectEqual(request.value(forHTTPHeaderField: provider == .elevenLabs ? "Authorization" : "xi-api-key"), nil)
        }
    }

    private static func testAPIKeyValidationIsolation() async {
        for provider in TranscriptionProvider.allCases {
            let stub = UploadStub(.http(Data(), 200))
            let valid = await TranscriptionService.validateAPIKey(
                " synthetic-validation-key ",
                provider: provider,
                data: { try await stub.upload($0, Data()) }
            )
            TestSupport.expect(valid, "A successful validation response should accept the key")
            let (request, body) = await stub.capturedRequest()
            TestSupport.expect(body.isEmpty, "Validation does not send audio")
            TestSupport.expectEqual(request.url?.host, provider == .elevenLabs ? "api.elevenlabs.io" : "api.groq.com")
            TestSupport.expectEqual(request.url?.path, provider == .elevenLabs ? "/v1/models" : "/openai/v1/models")
            TestSupport.expectEqual(request.timeoutInterval, 10)
            TestSupport.expectEqual(
                request.value(forHTTPHeaderField: provider == .elevenLabs ? "xi-api-key" : "Authorization"),
                provider == .elevenLabs ? "synthetic-validation-key" : "Bearer synthetic-validation-key"
            )
            TestSupport.expectEqual(request.value(forHTTPHeaderField: provider == .elevenLabs ? "Authorization" : "xi-api-key"), nil)

            for reply in [UploadStub.Reply.http(Data(), 401), .failure(.cannotConnectToHost)] {
                let failureStub = UploadStub(reply)
                let valid = await TranscriptionService.validateAPIKey(
                    "synthetic-key",
                    baseURL: "https://synthetic-validation.invalid/v1/",
                    provider: provider,
                    data: { try await failureStub.upload($0, Data()) }
                )
                TestSupport.expect(!valid, "Rejected or unreachable validation must fail")
            }
            let unusedStub = UploadStub(.http(Data(), 200))
            let empty = await TranscriptionService.validateAPIKey(
                " \n ", provider: provider, data: { try await unusedStub.upload($0, Data()) }
            )
            TestSupport.expect(!empty, "Empty keys cannot pass validation")
            let received = await unusedStub.receivedRequest()
            TestSupport.expect(!received, "An empty key must not leave the process")
        }
    }

    private static func testJSONAndVerboseJSONParsing(audioURL: URL) async throws {
        let fixtures: [([String: Any], String, String)] = [
            (["text": "Synthetic JSON speech."], "gpt-4o-transcribe", "Synthetic JSON speech."),
            (["text": "Thank you."], "gpt-4o-transcribe", "Thank you."),
            (["text": "Thank you.", "segments": [["no_speech_prob": 0.1]]], "whisper-1", ""),
            (["text": "Thank you.", "segments": [["no_speech_prob": 0.099]]], "whisper-large-v3", "Thank you."),
            (["text": "Synthetic real speech.", "segments": [["no_speech_prob": 0.95]]], "whisper-large-v3-turbo", "Synthetic real speech.")
        ]
        for (response, model, expected) in fixtures {
            let stub = UploadStub(.http(json(response), 200))
            let service = try makeService(provider: .openAICompatible, stub: stub, model: model)
            let result = try await service.transcribe(fileURL: audioURL)
            TestSupport.expectEqual(result, expected)
            let (_, body) = await stub.capturedRequest()
            TestSupport.expect(
                String(decoding: body, as: UTF8.self).contains("\r\n\r\n\(TranscriptionService.responseFormat(forModel: model))\r\n"),
                "The upload must use the response format supported by its model"
            )
        }
        let scribeStub = UploadStub(.http(json(["text": "Thank you."]), 200))
        let scribe = try makeService(provider: .elevenLabs, stub: scribeStub)
        let result = try await scribe.transcribe(fileURL: audioURL)
        TestSupport.expectEqual(result, "Thank you.")
    }

    private static func testMalformedResponses(audioURL: URL) async throws {
        for provider in TranscriptionProvider.allCases {
            for data in [Data(), Data("{malformed synthetic JSON".utf8), Data([0xFF, 0xFE])] {
                let stub = UploadStub(.http(data, 200))
                let service = try makeService(provider: provider, stub: stub)
                await expectError({ try await service.transcribe(fileURL: audioURL) }) { error in
                    guard case TranscriptionError.pollFailed(let message) = error else {
                        return TestSupport.expect(false, "Malformed data must be a transcription parsing error")
                    }
                    TestSupport.expectEqual(message, provider == .elevenLabs ? "Invalid ElevenLabs response" : "Invalid response")
                }
            }
            let stub = UploadStub(.nonHTTP)
            let service = try makeService(provider: provider, stub: stub)
            await expectError({ try await service.transcribe(fileURL: audioURL) }) { error in
                guard case TranscriptionError.submissionFailed(let message) = error else {
                    return TestSupport.expect(false, "A non-HTTP response must fail submission")
                }
                TestSupport.expectEqual(message, "No response from server")
            }
        }
        let stub = UploadStub(.http(json(["unexpected": "synthetic"]), 200))
        let scribe = try makeService(provider: .elevenLabs, stub: stub)
        await expectError({ try await scribe.transcribe(fileURL: audioURL) }) { error in
            guard case TranscriptionError.pollFailed = error else {
                return TestSupport.expect(false, "Scribe requires the text field")
            }
        }
    }

    private static func testHTTPFailures(audioURL: URL) async throws {
        for provider in TranscriptionProvider.allCases {
            for status in [400, 401, 422] {
                let stub = UploadStub(.http(json(["error": "server-controlled synthetic note"]), status))
                let service = try makeService(provider: provider, stub: stub)
                await expectError({ try await service.transcribe(fileURL: audioURL) }) { error in
                    guard case TranscriptionError.submissionFailed(let message) = error else {
                        return TestSupport.expect(false, "HTTP errors must fail submission")
                    }
                    TestSupport.expectEqual(message, TranscriptionService.friendlyHTTPMessage(status: status, host: host(for: provider)))
                    TestSupport.expect(!message.contains("server-controlled"), "Provider response bodies must not enter friendly errors")
                    if status == 400 {
                        TestSupport.expect(message.contains("model name and Base URL"), "Preserve main's settings guidance")
                    }
                }
            }
        }
    }

    private static func testTimeoutAndCancellation(audioURL: URL) async throws {
        for provider in TranscriptionProvider.allCases {
            let timeoutStub = UploadStub(.failure(.timedOut))
            let service = try makeService(provider: provider, stub: timeoutStub, timeout: 2)
            await expectError({ try await service.transcribe(fileURL: audioURL) }) { error in
                guard case TranscriptionError.transcriptionTimedOut(let seconds) = error else {
                    return TestSupport.expect(false, "Transport timeout must use the transcription timeout error")
                }
                TestSupport.expectEqual(seconds, 2)
            }

            let stalledStub = UploadStub(.suspend)
            let stalled = try makeService(provider: provider, stub: stalledStub, timeout: 0.02)
            await expectError({ try await stalled.transcribe(fileURL: audioURL) }) { error in
                guard case TranscriptionError.transcriptionTimedOut(let seconds) = error else {
                    return TestSupport.expect(false, "Stalled upload must finish with a timeout")
                }
                TestSupport.expectEqual(seconds, 0.02)
            }
            await stalledStub.waitForCancellation()

            let cancelStub = UploadStub(.suspend)
            let cancellable = try makeService(provider: provider, stub: cancelStub, timeout: 3)
            let task = Task { try await cancellable.transcribe(fileURL: audioURL) }
            await cancelStub.waitForRequest()
            task.cancel()
            await expectError({ try await task.value }) { error in
                TestSupport.expect(error is CancellationError, "Caller cancellation must propagate")
            }
            await cancelStub.waitForCancellation()
        }
    }

    private static func makeService(
        provider: TranscriptionProvider,
        stub: UploadStub,
        model: String = "whisper-large-v3",
        language: String? = nil,
        timeout: TimeInterval = 3
    ) throws -> TranscriptionService {
        try TranscriptionService(
            provider: provider,
            apiKey: "synthetic-\(provider.rawValue)-key",
            baseURL: "https://\(host(for: provider))/v1",
            transcriptionModel: model,
            language: language,
            timeoutSeconds: timeout,
            upload: { try await stub.upload($0, $1) }
        )
    }

    private static func host(for provider: TranscriptionProvider) -> String {
        provider == .elevenLabs ? "synthetic-elevenlabs.invalid" : "synthetic-openai.invalid"
    }

    private static func json(_ object: [String: Any]) -> Data {
        guard let data = try? JSONSerialization.data(withJSONObject: object) else {
            fatalError("Synthetic fixture must be serializable")
        }
        return data
    }

    private static func expectMultipart(request: URLRequest, body: Data, audio: Data, fields: [(String, String)]) {
        guard let contentType = request.value(forHTTPHeaderField: "Content-Type"),
              contentType.hasPrefix("multipart/form-data; boundary=") else {
            return TestSupport.expect(false, "Upload needs a multipart Content-Type with boundary")
        }
        let boundary = String(contentType.dropFirst("multipart/form-data; boundary=".count))
        TestSupport.expect(!boundary.isEmpty, "Multipart boundary cannot be empty")
        let text = String(decoding: body, as: UTF8.self)
        TestSupport.expect(text.hasPrefix("--\(boundary)\r\n"), "Body must begin with its header boundary")
        TestSupport.expect(text.hasSuffix("\r\n--\(boundary)--\r\n"), "Body must close its header boundary")
        TestSupport.expectEqual(text.components(separatedBy: "Content-Disposition:").count - 1, fields.count + 1)
        for (name, value) in fields {
            TestSupport.expect(
                text.contains("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n"),
                "Expected multipart field \(name)"
            )
        }
        let fileHeader = Data("Content-Disposition: form-data; name=\"file\"; filename=\"synthetic.wav\"\r\nContent-Type: audio/wav\r\n\r\n".utf8)
        TestSupport.expect(body.range(of: fileHeader + audio + Data("\r\n".utf8)) != nil, "File field must preserve synthetic audio bytes and its MIME type")
    }

    private static func expectError(_ operation: () async throws -> String, verify: (Error) -> Void) async {
        do {
            _ = try await operation()
            TestSupport.expect(false, "Expected operation to fail")
        } catch {
            verify(error)
        }
    }
}

private actor UploadStub {
    enum Reply {
        case http(Data, Int)
        case nonHTTP
        case failure(URLError.Code)
        case suspend
    }

    private let reply: Reply
    private var captured: (URLRequest, Data)?
    private var cancelled = false
    private var requestWaiter: CheckedContinuation<Void, Never>?
    private var cancellationWaiter: CheckedContinuation<Void, Never>?

    init(_ reply: Reply) { self.reply = reply }

    func upload(_ request: URLRequest, _ body: Data) async throws -> (Data, URLResponse) {
        captured = (request, body)
        requestWaiter?.resume()
        requestWaiter = nil
        guard let url = request.url else { fatalError("Synthetic request must have a URL") }
        switch reply {
        case .http(let data, let status):
            guard let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil) else {
                fatalError("Synthetic HTTP response must be constructible")
            }
            return (data, response)
        case .nonHTTP:
            return (Data(), URLResponse(url: url, mimeType: nil, expectedContentLength: 0, textEncodingName: nil))
        case .failure(let code):
            throw URLError(code)
        case .suspend:
            do {
                try await Task.sleep(nanoseconds: 60_000_000_000)
                fatalError("Synthetic stalled upload should be cancelled")
            } catch {
                cancelled = true
                cancellationWaiter?.resume()
                cancellationWaiter = nil
                throw error
            }
        }
    }

    func receivedRequest() -> Bool { captured != nil }

    func capturedRequest() -> (URLRequest, Data) {
        guard let captured else { fatalError("Upload must have reached the synthetic transport") }
        return captured
    }

    func waitForRequest() async {
        if captured != nil { return }
        await withCheckedContinuation { requestWaiter = $0 }
    }

    func waitForCancellation() async {
        if cancelled { return }
        await withCheckedContinuation { cancellationWaiter = $0 }
    }
}
