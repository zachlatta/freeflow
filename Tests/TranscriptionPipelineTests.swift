import Foundation

/// Exercises the configuration and fallback seam used by AppState with real
/// file transcription clients. Only the HTTP upload boundary is mocked.
enum TranscriptionPipelineTests {
    static func run() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FreeFlowTests.SyntheticAudio.\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("synthetic-tone.wav")
        let audio = syntheticWAV()
        try audio.write(to: fileURL)

        try await testSwitchingProvidersUsesIsolatedRequests(fileURL: fileURL, audio: audio)
        try await testRealtimeSuccessSkipsRealUpload(fileURL: fileURL)
        try await testSilenceRemainsEmpty(fileURL: fileURL)
        try await testMissingElevenLabsKeyCannotUseOtherCredentials(fileURL: fileURL)
        try await testFallbackPreservesFileError(directory: directory)
    }

    private static func testSwitchingProvidersUsesIsolatedRequests(fileURL: URL, audio: Data) async throws {
        for provider in [TranscriptionProvider.openAICompatible, .elevenLabs, .openAICompatible] {
            let config = configuration(provider: provider)
            let recorder = PipelineUploadRecorder()
            let realtime = PipelineRealtimeClient(result: .failure(RealtimeTranscriptionError.finalizationTimedOut))
            let service = try makeService(config: config) { request, body in
                TestSupport.expectEqual(realtime.cancelCount, 1)
                recorder.record(request: request, body: body)
                return response(request: request, text: "An invented comet crossed the blue sky.")
            }
            let transcript = try await TranscriptionFallback.resolve(realtimeService: realtime) {
                try await service.transcribe(fileURL: fileURL)
            }
            TestSupport.expectEqual(transcript, "An invented comet crossed the blue sky.")
            TestSupport.expectEqual(realtime.commitCount, 1)
            TestSupport.expectEqual(recorder.uploads.count, 1)
            let upload = recorder.uploads[0]
            TestSupport.expectEqual(upload.request.httpMethod, "POST")
            TestSupport.expect(upload.body.range(of: audio) != nil, "The generated WAV must reach the upload unchanged")

            if provider == .openAICompatible {
                TestSupport.expectEqual(upload.request.url?.absoluteString, "https://transcription.example.invalid/v1/audio/transcriptions")
                TestSupport.expectEqual(upload.request.value(forHTTPHeaderField: "Authorization"), "Bearer synthetic-transcription-key")
                TestSupport.expectEqual(upload.request.value(forHTTPHeaderField: "xi-api-key"), nil)
                expectField("model", "gpt-4o-mini-transcribe", in: upload.body)
                expectField("response_format", "json", in: upload.body)
                expectField("language", "en", in: upload.body)
                TestSupport.expect(upload.body.range(of: Data("synthetic-elevenlabs-key".utf8)) == nil, "ElevenLabs credential must not enter the OpenAI-compatible body")
            } else {
                TestSupport.expectEqual(upload.request.url?.absoluteString, "https://api.elevenlabs.io/v1/speech-to-text")
                TestSupport.expectEqual(upload.request.value(forHTTPHeaderField: "Authorization"), nil)
                TestSupport.expectEqual(upload.request.value(forHTTPHeaderField: "xi-api-key"), "synthetic-elevenlabs-key")
                expectField("model_id", "scribe_v2", in: upload.body)
                expectField("language_code", "en", in: upload.body)
                expectField("tag_audio_events", "false", in: upload.body)
                TestSupport.expect(upload.body.range(of: Data("synthetic-transcription-key".utf8)) == nil, "OpenAI-compatible credential must not enter the ElevenLabs body")
            }
            TestSupport.expect(upload.body.range(of: Data("synthetic-llm-key".utf8)) == nil, "LLM credential must not enter a transcription request body")
        }
    }

    private static func testRealtimeSuccessSkipsRealUpload(fileURL: URL) async throws {
        for provider in TranscriptionProvider.allCases {
            let recorder = PipelineUploadRecorder()
            let service = try makeService(config: configuration(provider: provider)) { request, body in
                recorder.record(request: request, body: body)
                return response(request: request, text: "Unexpected batch result.")
            }
            let realtime = PipelineRealtimeClient(result: .success("An invented realtime sentence."))
            let transcript = try await TranscriptionFallback.resolve(realtimeService: realtime) {
                try await service.transcribe(fileURL: fileURL)
            }
            TestSupport.expectEqual(transcript, "An invented realtime sentence.")
            TestSupport.expectEqual(recorder.uploads.count, 0)
        }
    }

    private static func testSilenceRemainsEmpty(fileURL: URL) async throws {
        for provider in TranscriptionProvider.allCases {
            let recorder = PipelineUploadRecorder()
            let service = try makeService(config: configuration(provider: provider)) { request, body in
                recorder.record(request: request, body: body)
                return response(request: request, text: "")
            }
            let realtimeSilence = PipelineRealtimeClient(result: .success(""))
            let realtimeTranscript = try await TranscriptionFallback.resolve(realtimeService: realtimeSilence) {
                try await service.transcribe(fileURL: fileURL)
            }
            TestSupport.expectEqual(realtimeTranscript, "")
            TestSupport.expectEqual(recorder.uploads.count, 0)

            let unavailable = PipelineRealtimeClient(result: .failure(RealtimeTranscriptionError.closedBeforeFinal))
            let batchTranscript = try await TranscriptionFallback.resolve(realtimeService: unavailable) {
                try await service.transcribe(fileURL: fileURL)
            }
            TestSupport.expectEqual(batchTranscript, "")
            TestSupport.expectEqual(recorder.uploads.count, 1)
        }
    }

    private static func testMissingElevenLabsKeyCannotUseOtherCredentials(fileURL: URL) async throws {
        let config = configuration(provider: .elevenLabs, elevenLabsKey: "")
        let recorder = PipelineUploadRecorder()
        let service = try makeService(config: config) { request, body in
            recorder.record(request: request, body: body)
            return response(request: request, text: "Unexpected batch result.")
        }
        do {
            _ = try await TranscriptionFallback.resolve(realtimeService: nil) {
                try await service.transcribe(fileURL: fileURL)
            }
            TestSupport.expect(false, "Missing ElevenLabs credentials must reject the request")
        } catch TranscriptionError.submissionFailed {
        }
        TestSupport.expectEqual(recorder.uploads.count, 0)
    }

    private static func testFallbackPreservesFileError(directory: URL) async throws {
        let recorder = PipelineUploadRecorder()
        let service = try makeService(config: configuration(provider: .elevenLabs)) { request, body in
            recorder.record(request: request, body: body)
            return response(request: request, text: "Unexpected batch result.")
        }
        let realtime = PipelineRealtimeClient(result: .failure(RealtimeTranscriptionError.closedBeforeFinal))
        do {
            _ = try await TranscriptionFallback.resolve(realtimeService: realtime) {
                try await service.transcribe(fileURL: directory.appendingPathComponent("missing-synthetic.wav"))
            }
            TestSupport.expect(false, "Missing recorded audio must remain a file error")
        } catch let error as NSError {
            TestSupport.expectEqual(error.domain, NSCocoaErrorDomain)
            TestSupport.expectEqual(error.code, NSFileReadNoSuchFileError)
        }
        TestSupport.expectEqual(recorder.uploads.count, 0)
        TestSupport.expectEqual(realtime.cancelCount, 1)
    }

    private static func makeService(
        config: TranscriptionConfiguration,
        upload: @escaping TranscriptionUpload
    ) throws -> TranscriptionService {
        try TranscriptionService(
            provider: config.provider,
            apiKey: config.apiKey,
            baseURL: config.baseURL,
            transcriptionModel: config.batchModel,
            language: config.language,
            timeoutSeconds: 2,
            upload: upload
        )
    }

    private static func configuration(
        provider: TranscriptionProvider,
        elevenLabsKey: String = "synthetic-elevenlabs-key"
    ) -> TranscriptionConfiguration {
        TranscriptionConfiguration.resolve(
            provider: provider,
            apiKey: "synthetic-llm-key",
            apiBaseURL: "https://llm.example.invalid/v1",
            transcriptionAPIURL: "https://transcription.example.invalid/v1",
            transcriptionAPIKey: "synthetic-transcription-key",
            elevenLabsAPIKey: elevenLabsKey,
            transcriptionModel: "gpt-4o-mini-transcribe",
            realtimeStreamingModel: "synthetic-realtime-model",
            language: "en"
        )
    }

    private static func response(request: URLRequest, text: String) -> (Data, URLResponse) {
        let body = try! JSONSerialization.data(withJSONObject: ["text": text])
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
        return (body, response)
    }

    private static func expectField(_ name: String, _ value: String, in body: Data) {
        let field = "name=\"\(name)\"\r\n\r\n\(value)\r\n"
        TestSupport.expect(body.range(of: Data(field.utf8)) != nil, "Missing expected synthetic multipart field \(name)")
    }

    private static func syntheticWAV() -> Data {
        let sampleRate = 16_000
        let sampleCount = sampleRate / 4
        let audioByteCount = UInt32(sampleCount * 2)
        var data = Data("RIFF".utf8)
        appendUInt32(36 + audioByteCount, to: &data)
        data.append(Data("WAVEfmt ".utf8))
        appendUInt32(16, to: &data)
        appendUInt16(1, to: &data) // Linear PCM.
        appendUInt16(1, to: &data) // Mono.
        appendUInt32(UInt32(sampleRate), to: &data)
        appendUInt32(UInt32(sampleRate * 2), to: &data)
        appendUInt16(2, to: &data)
        appendUInt16(16, to: &data)
        data.append(Data("data".utf8))
        appendUInt32(audioByteCount, to: &data)
        for index in 0..<sampleCount {
            let sample = Int16(sin(2 * Double.pi * 440 * Double(index) / Double(sampleRate)) * 2_000)
            appendUInt16(UInt16(bitPattern: sample), to: &data)
        }
        return data
    }

    private static func appendUInt16(_ value: UInt16, to data: inout Data) {
        data.append(contentsOf: [UInt8(truncatingIfNeeded: value), UInt8(truncatingIfNeeded: value >> 8)])
    }

    private static func appendUInt32(_ value: UInt32, to data: inout Data) {
        data.append(contentsOf: (0..<4).map { UInt8(truncatingIfNeeded: value >> ($0 * 8)) })
    }
}

private final class PipelineRealtimeClient: RealtimeTranscriptionClient {
    private let result: Result<String, Error>
    private(set) var commitCount = 0
    private(set) var cancelCount = 0
    let pcmSampleRate: Double = 16_000

    init(result: Result<String, Error>) { self.result = result }
    func start() throws {}
    func appendPCM16(_ data: Data) {}
    func cancel() { cancelCount += 1 }
    func commitAndAwaitFinal() async throws -> String {
        commitCount += 1
        return try result.get()
    }
}

private final class PipelineUploadRecorder {
    struct Upload {
        let request: URLRequest
        let body: Data
    }

    private let lock = NSLock()
    private var recordedUploads: [Upload] = []

    var uploads: [Upload] {
        lock.lock()
        defer { lock.unlock() }
        return recordedUploads
    }

    func record(request: URLRequest, body: Data) {
        lock.lock()
        recordedUploads.append(Upload(request: request, body: body))
        lock.unlock()
    }
}
