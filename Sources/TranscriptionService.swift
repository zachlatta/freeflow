import AVFoundation
import Foundation
import os.log

private let transcriptionLog = OSLog(subsystem: "com.zachlatta.freeflow", category: "Transcription")

class TranscriptionService {
    private let transcriptionProvider: TranscriptionProvider
    private let apiKey: String
    private let baseURL: String
    private let awsConfig: AWSConfig?
    private let transcribeLanguageCode: String
    private let transcriptionModel = "whisper-large-v3"
    private let transcriptionResponseFormat = "verbose_json"
    private let transcriptionTimeoutSeconds: TimeInterval = 30
    private let uploadSampleRate = 16_000.0
    private let uploadChannelCount: AVAudioChannelCount = 1

    init(
        transcriptionProvider: TranscriptionProvider = .groq,
        apiKey: String,
        baseURL: String = "https://api.groq.com/openai/v1",
        awsConfig: AWSConfig? = nil,
        transcribeLanguageCode: String = "en-US"
    ) {
        self.transcriptionProvider = transcriptionProvider
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.awsConfig = awsConfig
        self.transcribeLanguageCode = transcribeLanguageCode
    }

    // Validate API key by hitting a lightweight endpoint
    static func validateAPIKey(_ key: String, baseURL: String = "https://api.groq.com/openai/v1") async -> Bool {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        var request = URLRequest(url: URL(string: "\(baseURL)/models")!)
        request.timeoutInterval = 10
        request.setValue("Bearer \(trimmed)", forHTTPHeaderField: "Authorization")

        do {
            let (_, response) = try await LLMAPITransport.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            return status == 200
        } catch {
            return false
        }
    }

    // Upload audio file, submit for transcription, poll until done, return text
    func transcribe(fileURL: URL) async throws -> String {
        guard !Task.isCancelled else {
            throw CancellationError()
        }

        do {
            return try await transcribeAudio(fileURL: fileURL)
        } catch let urlError as URLError where urlError.code == .timedOut {
            throw TranscriptionError.transcriptionTimedOut(transcriptionTimeoutSeconds)
        }
    }

    // Send audio file for transcription and return text
    private func transcribeAudio(fileURL: URL) async throws -> String {
        switch transcriptionProvider {
        case .awsTranscribe:
            guard let aws = awsConfig else {
                throw TranscriptionError.submissionFailed("AWS credentials not configured")
            }
            return try await transcribeWithAmazon(fileURL: fileURL, aws: aws)
        case .groq:
            break
        }

        let preparedAudio = try prepareAudioForUpload(from: fileURL)
        defer { preparedAudio.cleanup() }

        return try await transcribeAudioWithURLSession(fileURL: preparedAudio.fileURL)
    }

    private func transcribeAudioWithURLSession(fileURL: URL) async throws -> String {
        let url = URL(string: "\(baseURL)/audio/transcriptions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = transcriptionTimeoutSeconds
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        let audioData = try Data(contentsOf: fileURL)
        let body = makeMultipartBody(
            audioData: audioData,
            fileName: fileURL.lastPathComponent,
            model: transcriptionModel,
            responseFormat: transcriptionResponseFormat,
            boundary: boundary
        )

        do {
            let (data, response) = try await LLMAPITransport.upload(for: request, from: body)
            return try validateTranscriptionResponse(data: data, response: response, fileURL: fileURL)
        } catch {
            let nsError = error as NSError
            os_log(
                .error,
                log: transcriptionLog,
                "URLSession upload failed for %{public}@ (bytes=%{public}lld): domain=%{public}@ code=%ld desc=%{public}@",
                fileURL.lastPathComponent,
                fileSizeBytes(for: fileURL),
                nsError.domain,
                nsError.code,
                error.localizedDescription
            )
            throw error
        }
    }

    private func validateTranscriptionResponse(data: Data, response: URLResponse, fileURL: URL) throws -> String {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw TranscriptionError.submissionFailed("No response from server")
        }

        guard httpResponse.statusCode == 200 else {
            let responseBody = String(data: data, encoding: .utf8) ?? ""
            os_log(
                .error,
                log: transcriptionLog,
                "URLSession upload returned HTTP %ld for %{public}@ (bytes=%{public}lld)",
                httpResponse.statusCode,
                fileURL.lastPathComponent,
                fileSizeBytes(for: fileURL)
            )
            throw TranscriptionError.submissionFailed("Status \(httpResponse.statusCode): \(responseBody)")
        }

        return try parseTranscript(from: data)
    }
    private func audioContentType(for fileName: String) -> String {
        if fileName.lowercased().hasSuffix(".wav") {
            return "audio/wav"
        }
        if fileName.lowercased().hasSuffix(".mp3") {
            return "audio/mpeg"
        }
        if fileName.lowercased().hasSuffix(".m4a") {
            return "audio/mp4"
        }
        return "audio/mp4"
    }

    private func fileSizeBytes(for fileURL: URL) -> Int64 {
        let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path)
        return (attributes?[.size] as? NSNumber)?.int64Value ?? -1
    }

    private func makeMultipartBody(
        audioData: Data,
        fileName: String,
        model: String,
        responseFormat: String,
        boundary: String
    ) -> Data {
        var body = Data()

        func append(_ value: String) {
            body.append(Data(value.utf8))
        }

        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"model\"\r\n\r\n")
        append("\(model)\r\n")

        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"response_format\"\r\n\r\n")
        append("\(responseFormat)\r\n")

        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileName)\"\r\n")
        append("Content-Type: \(audioContentType(for: fileName))\r\n\r\n")
        body.append(audioData)
        append("\r\n")
        append("--\(boundary)--\r\n")

        return body
    }

    private func prepareAudioForUpload(from fileURL: URL) throws -> PreparedUploadAudio {
        let inputFile = try AVAudioFile(forReading: fileURL)
        if isPreferredUploadFormat(file: inputFile, fileURL: fileURL) {
            return PreparedUploadAudio(fileURL: fileURL, deleteOnCleanup: false)
        }

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("wav")
        do {
            try AudioNormalization.writePreferredAudioCopy(from: fileURL, to: outputURL)
        } catch {
            throw TranscriptionError.audioPreparationFailed(error.localizedDescription)
        }
        return PreparedUploadAudio(fileURL: outputURL, deleteOnCleanup: true)
    }

    private func isPreferredUploadFormat(file: AVAudioFile, fileURL: URL) -> Bool {
        let format = file.fileFormat
        return fileURL.pathExtension.lowercased() == "wav"
            && abs(format.sampleRate - uploadSampleRate) < 0.5
            && format.channelCount == uploadChannelCount
            && format.commonFormat == .pcmFormatInt16
    }

    // Whisper-large-v3 hallucinates common short phrases on silence/background
    // noise. Drop them when whisper itself reports a high no_speech_prob.
    // Add a new (phrase, minNoSpeechProb) pair here to filter more hallucinations.
    //
    // Thresholds tuned on ~500 samples from quiet and noisy environments, including
    // both positive cases (real "thank you" speech) and empty-audio cases. Kept
    // conservative to minimize false positives (filtering real user speech).
    // Normal speech included audios have very low no_speech_prob.
    private let hallucinationPhrases = [
        "thank you",
        "thank you very much",
        "thank you so much",
        "you"
    ]

    private let hallucinationNoSpeechThreshold = 0.1

    // MARK: - Amazon Transcribe

    private func transcribeWithAmazon(fileURL: URL, aws: AWSConfig) async throws -> String {
        // 1. Extract raw PCM from the WAV file
        let preparedAudio = try prepareAudioForUpload(from: fileURL)
        defer { preparedAudio.cleanup() }

        let pcmData = try extractPCMData(from: preparedAudio.fileURL)

        // Debug: save WAV copy
        try? FileManager.default.copyItem(at: preparedAudio.fileURL, to: URL(fileURLWithPath: "/tmp/freeflow-test.wav"))

        // Debug: log WAV file info and PCM bytes
        if let audioFile = try? AVAudioFile(forReading: preparedAudio.fileURL) {
            let fmt = audioFile.fileFormat
            var info = "WAV: rate=\(fmt.sampleRate) ch=\(fmt.channelCount) fmt=\(fmt.commonFormat.rawValue) pcmBytes=\(pcmData.count)"
            // First 16 bytes of PCM in hex
            let preview = pcmData.prefix(16).map { String(format: "%02x", $0) }.joined(separator: " ")
            info += "\nPCM[0..15]: \(preview)"
            try? info.write(to: URL(fileURLWithPath: "/tmp/freeflow-audio-debug.txt"), atomically: true, encoding: .utf8)
        }

        // 2. Sign the HTTP request (body hash = empty — Transcribe streaming requires this)
        let langCode = transcribeLanguageCode
        let endpointURL = URL(string: "https://transcribestreaming.\(aws.region).amazonaws.com/stream-transcription")!

        let extraHeaders: [String: String] = [
            "content-type": "application/vnd.amazon.eventstream",
            "x-amzn-transcribe-language-code": langCode,
            "x-amzn-transcribe-media-encoding": "pcm",
            "x-amzn-transcribe-sample-rate": "16000"
        ]

        let signed = AWSSignature.signRequest(
            method: "POST",
            url: endpointURL,
            headers: extraHeaders,
            body: Data(), // streaming: body hash is hash of empty string
            service: "transcribe",
            region: aws.region,
            accessKeyId: aws.accessKeyId,
            secretAccessKey: aws.secretAccessKey,
            sessionToken: aws.sessionToken
        )

        // 3. Build event stream body with per-frame chunk signatures
        let chunkSize = 8 * 1024
        var body = Data()
        var priorSig = signed.signatureBytes
        var chunkOffset = 0
        while chunkOffset < pcmData.count {
            let end = min(chunkOffset + chunkSize, pcmData.count)
            let chunk = Data(pcmData[chunkOffset..<end])
            let (frame, newSig) = EventStream.signedAudioFrame(
                audio: chunk,
                priorSignature: priorSig,
                signingKey: signed.signingKey,
                credentialScope: signed.credentialScope
            )
            body.append(frame)
            priorSig = newSig
            chunkOffset = end
        }
        // Empty audio frame signals end of audio stream ("empty frame" per AWS protocol)
        let (emptyFrame, emptySig) = EventStream.signedAudioFrame(
            audio: Data(),
            priorSignature: priorSig,
            signingKey: signed.signingKey,
            credentialScope: signed.credentialScope
        )
        body.append(emptyFrame)
        priorSig = emptySig
        // Terminal "complete signal" frame (signed outer frame with empty payload)
        body.append(EventStream.signedTerminalFrame(
            priorSignature: priorSig,
            signingKey: signed.signingKey,
            credentialScope: signed.credentialScope
        ))

        // Debug: dump first frame
        if let firstFrameEnd = body.indices.first.map({ _ in
            let totalLen = Int((UInt32(body[0]) << 24) | (UInt32(body[1]) << 16) | (UInt32(body[2]) << 8) | UInt32(body[3]))
            return totalLen
        }) {
            let firstFrame = body.prefix(min(firstFrameEnd, 300))
            let hex = firstFrame.map { String(format: "%02x", $0) }.joined(separator: " ")
            try? ("First frame (\(firstFrameEnd) bytes):\n" + hex).write(to: URL(fileURLWithPath: "/tmp/freeflow-frame-debug.txt"), atomically: true, encoding: .utf8)
        }

        // 4. Build request
        var request = URLRequest(url: endpointURL)
        request.httpMethod = "POST"
        request.timeoutInterval = transcriptionTimeoutSeconds
        for (k, v) in extraHeaders { request.setValue(v, forHTTPHeaderField: k) }
        for (k, v) in signed.headers { request.setValue(v, forHTTPHeaderField: k) }

        // 5. Send and receive (body supplied via upload(for:from:), not request.httpBody)
        let (responseData, response): (Data, URLResponse)
        do {
            (responseData, response) = try await URLSession.shared.upload(for: request, from: body)
        } catch {
            os_log(.error, log: transcriptionLog, "Transcribe request failed: %{public}@", error.localizedDescription)
            throw TranscriptionError.submissionFailed(error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw TranscriptionError.submissionFailed("No HTTP response from Transcribe")
        }
        guard httpResponse.statusCode == 200 else {
            let msg = String(data: responseData, encoding: .utf8) ?? ""
            os_log(.error, log: transcriptionLog, "Transcribe HTTP %ld: %{public}@", httpResponse.statusCode, msg)
            throw TranscriptionError.submissionFailed("Transcribe status \(httpResponse.statusCode): \(msg)")
        }

        // 5. Parse response event stream
        let debugFrames = EventStream.decodeFrames(from: responseData)
        var debugLog = "Transcribe response: \(responseData.count) bytes, \(debugFrames.count) frames\n"
        for (i, frame) in debugFrames.enumerated() {
            let eventType = frame.headers[":event-type"] ?? frame.headers[":exception-type"] ?? "(none)"
            let msgType = frame.headers[":message-type"] ?? "(none)"
            let payloadStr = String(data: frame.payload.prefix(512), encoding: .utf8) ?? "(binary)"
            debugLog += "Frame[\(i)] msg-type=\(msgType) event-type=\(eventType) payload=\(payloadStr)\n"
        }
        try? debugLog.write(to: URL(fileURLWithPath: "/tmp/freeflow-transcribe-debug.txt"), atomically: true, encoding: .utf8)
        return try parseTranscribeEventStream(responseData)
    }

    /// Extract raw PCM bytes from a WAV file by scanning for the "data" chunk.
    private func extractPCMData(from wavURL: URL) throws -> Data {
        let fileData = try Data(contentsOf: wavURL)
        guard fileData.count >= 12,
              String(bytes: fileData[0..<4], encoding: .ascii) == "RIFF",
              String(bytes: fileData[8..<12], encoding: .ascii) == "WAVE" else {
            throw TranscriptionError.audioPreparationFailed("Not a WAVE file")
        }

        var offset = 12
        while offset + 8 <= fileData.count {
            let chunkId = String(bytes: fileData[offset..<(offset + 4)], encoding: .ascii) ?? ""
            let chunkSize: UInt32 = fileData[(offset + 4)..<(offset + 8)].withUnsafeBytes {
                $0.loadUnaligned(as: UInt32.self)
            }.littleEndian
            if chunkId == "data" {
                let dataStart = offset + 8
                let dataEnd = min(dataStart + Int(chunkSize), fileData.count)
                return Data(fileData[dataStart..<dataEnd])
            }
            offset += 8 + Int(chunkSize)
            if chunkSize & 1 != 0 { offset += 1 } // WAV chunks are word-aligned
        }
        throw TranscriptionError.audioPreparationFailed("Could not find PCM data chunk in WAV file")
    }

    /// Parse a Transcribe streaming response (event stream) and return the full transcript.
    private func parseTranscribeEventStream(_ data: Data) throws -> String {
        let frames = EventStream.decodeFrames(from: data)
        var finalSegments: [String] = []
        var partialSegments: [String] = []

        for frame in frames {
            guard frame.headers[":event-type"] == "TranscriptEvent" else { continue }
            guard !frame.payload.isEmpty else { continue }

            guard let json = try? JSONSerialization.jsonObject(with: frame.payload) as? [String: Any],
                  let outerTranscript = json["Transcript"] as? [String: Any],
                  let results = outerTranscript["Results"] as? [[String: Any]] else {
                continue
            }

            for result in results {
                let isPartial = result["IsPartial"] as? Bool ?? true
                guard let alternatives = result["Alternatives"] as? [[String: Any]],
                      let first = alternatives.first,
                      let text = first["Transcript"] as? String,
                      !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    continue
                }
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if isPartial {
                    partialSegments.append(trimmed)
                } else {
                    finalSegments.append(trimmed)
                }
            }
        }

        // Prefer final results; fall back to partials (common for short recordings)
        let segments = finalSegments.isEmpty ? partialSegments : finalSegments
        let combined = segments.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !combined.isEmpty else {
            throw TranscriptionError.transcriptionFailed("Transcribe returned no transcript")
        }
        return combined
    }

    private func parseTranscript(from data: Data) throws -> String {
        if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
           let text = json["text"] as? String {
            if isHallucination(text: text, json: json) {
                return ""
            }
            return text
        }

        let plainText = String(data: data, encoding: .utf8) ?? ""
        let text = plainText
                .components(separatedBy: .newlines)
                .joined(separator: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            throw TranscriptionError.pollFailed("Invalid response")
        }

        return text
    }

    private func isHallucination(text: String, json: [String: Any]) -> Bool {
        let normalized = text
            .lowercased()
            .trimmingCharacters(in: CharacterSet.punctuationCharacters.union(.whitespacesAndNewlines))
        guard hallucinationPhrases.contains(normalized) else {
            return false
        }
        guard let segments = json["segments"] as? [[String: Any]],
              let noSpeechProb = segments.first?["no_speech_prob"] as? Double else {
            return false
        }
        return noSpeechProb >= hallucinationNoSpeechThreshold
    }
}

enum TranscriptionError: LocalizedError {
    case uploadFailed(String)
    case submissionFailed(String)
    case transcriptionFailed(String)
    case transcriptionTimedOut(TimeInterval)
    case pollFailed(String)
    case audioPreparationFailed(String)

    var errorDescription: String? {
        switch self {
        case .uploadFailed(let msg): return "Upload failed: \(msg)"
        case .submissionFailed(let msg): return "Submission failed: \(msg)"
        case .transcriptionTimedOut(let seconds): return "Transcription timed out after \(Int(seconds))s"
        case .transcriptionFailed(let msg): return "Transcription failed: \(msg)"
        case .pollFailed(let msg): return "Polling failed: \(msg)"
        case .audioPreparationFailed(let msg): return "Audio preparation failed: \(msg)"
        }
    }
}

private struct PreparedUploadAudio {
    let fileURL: URL
    let deleteOnCleanup: Bool

    func cleanup() {
        guard deleteOnCleanup else { return }
        try? FileManager.default.removeItem(at: fileURL)
    }
}
