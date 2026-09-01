import Foundation

/// Runs the bundled Parakeet Core ML helper as an isolated, one-shot process.
/// The model is loaded only while prewarming or transcribing, keeping idle RAM
/// use close to the stock FreeFlow app. All audio and transcript data stay on
/// this Mac; the helper receives only a local file path and writes its result to
/// a temporary file that is deleted immediately after parsing.
final class LocalParakeetTranscriptionService {
    // ANE model loading can sporadically stall for 30–45 seconds after idle.
    // CPU-only remains much faster than real time on supported Macs, has a
    // predictable cold start, and still releases all model memory after use.
    static let computeUnits = "cpu"

    private let executableURL: URL
    private let modelDirectory: URL
    private let beforeProcessLaunch: (@Sendable () async -> Void)?

    init(
        modelDirectory: URL,
        executableURL: URL? = nil,
        beforeProcessLaunch: (@Sendable () async -> Void)? = nil
    ) throws {
        let resolvedURL: URL
        if let executableURL {
            resolvedURL = executableURL
        } else if let mainExecutable = Bundle.main.executableURL {
            resolvedURL = mainExecutable
                .deletingLastPathComponent()
                .appendingPathComponent("freeflow-local-asr", isDirectory: false)
        } else {
            throw LocalParakeetError.helperUnavailable
        }

        guard FileManager.default.isExecutableFile(atPath: resolvedURL.path) else {
            throw LocalParakeetError.helperUnavailable
        }
        guard FileManager.default.fileExists(atPath: modelDirectory.path) else {
            throw LocalParakeetError.modelUnavailable
        }
        self.executableURL = resolvedURL
        self.modelDirectory = modelDirectory
        self.beforeProcessLaunch = beforeProcessLaunch
    }

    func transcribe(fileURL: URL) async throws -> String {
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("freeflow-local-asr-\(UUID().uuidString)")
            .appendingPathExtension("txt")
        defer { try? FileManager.default.removeItem(at: outputURL) }

        guard FileManager.default.createFile(
            atPath: outputURL.path,
            contents: nil,
            attributes: [.posixPermissions: 0o600]
        ) else {
            throw LocalParakeetError.invalidOutput
        }
        let outputHandle = try FileHandle(forWritingTo: outputURL)
        defer { try? outputHandle.close() }

        let process = makeProcess(fileURL: fileURL)

        // Diagnostics go to stderr; stdout contains only the transcript. Keep
        // both out of persistent application logs and delete the private output
        // file immediately after parsing.
        process.standardOutput = outputHandle
        process.standardError = FileHandle.nullDevice

        try await run(process)
        guard process.terminationReason == .exit, process.terminationStatus == 0 else {
            throw LocalParakeetError.helperFailed(process.terminationStatus)
        }

        try outputHandle.synchronize()
        let data = try Data(contentsOf: outputURL)
        return try Self.parseTranscript(from: data)
    }

    /// Loads and exercises the same model path before recording stops, using
    /// generated silence only. The one-shot helper exits immediately, so this
    /// hides Core ML's cold start behind the user's recording without keeping
    /// model RAM resident while idle.
    func prewarm() async throws {
        let audioURL = try makePreparationAudio()
        defer { try? FileManager.default.removeItem(at: audioURL) }
        // Exercise the first prediction too: model load alone does not warm
        // Core ML's execution path and leaves several seconds after recording.
        let process = makeProcess(fileURL: audioURL, maxSeconds: 0.1)
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try await run(process)
        guard process.terminationReason == .exit, process.terminationStatus == 0 else {
            throw LocalParakeetError.helperFailed(process.terminationStatus)
        }
    }

    static func parseTranscript(from data: Data) throws -> String {
        guard let output = String(data: data, encoding: .utf8) else {
            throw LocalParakeetError.invalidOutput
        }
        let repairedTranscript = removingSingleTrailingForeignScriptArtifact(
            in: output.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        let transcript = collapseRepeatedTerminalPunctuation(in: repairedTranscript)
        guard !transcript.isEmpty else {
            throw LocalParakeetError.invalidOutput
        }
        return transcript
    }

    /// Some short Latin-script dictations end with one unrelated script token.
    /// Remove only that narrow decoder artifact; never filter a non-Latin
    /// transcript or an actual multi-character word.
    private static func removingSingleTrailingForeignScriptArtifact(in transcript: String) -> String {
        guard let last = transcript.last,
              last.unicodeScalars.contains(where: { CharacterSet.letters.contains($0) && !isLatin($0) }),
              let lastIndex = transcript.indices.last,
              lastIndex > transcript.startIndex else { return transcript }
        let prefixEnd = transcript.index(before: lastIndex)
        guard transcript[prefixEnd].isWhitespace else { return transcript }
        let prefix = transcript[..<prefixEnd].trimmingCharacters(in: .whitespacesAndNewlines)
        let letters = prefix.unicodeScalars.filter { CharacterSet.letters.contains($0) }
        guard letters.count >= 4,
              letters.filter({ isLatin($0) }).count * 10 >= letters.count * 9 else { return transcript }
        return prefix
    }

    private static func isLatin(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x0041...0x005A, 0x0061...0x007A, 0x00C0...0x024F:
            return true
        default:
            return false
        }
    }

    /// The current Core ML decoder can repeat its terminal punctuation token
    /// (for example `sentence........`). This local, deterministic repair is
    /// deliberately narrow and never rewrites dictated words.
    private static func collapseRepeatedTerminalPunctuation(in transcript: String) -> String {
        var characters = Array(transcript)
        let collapsible: Set<Character> = [".", "!", "?"]
        while characters.count >= 2,
              let last = characters.last,
              collapsible.contains(last),
              characters[characters.count - 2] == last {
            characters.removeLast()
        }
        return String(characters)
    }

    private func makeProcess(fileURL: URL, maxSeconds: Double? = nil) -> Process {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = [
            "transcribe", fileURL.path,
            "--models", modelDirectory.path,
            "--compute-units", Self.computeUnits,
        ]
        if let maxSeconds {
            process.arguments? += ["--max-seconds", String(maxSeconds)]
        }
        return process
    }

    private func makePreparationAudio() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("freeflow-local-model-prewarm-\(UUID().uuidString).wav")
        let sampleCount: UInt32 = 1_600
        let dataByteCount = sampleCount * 2
        var data = Data("RIFF".utf8)
        data.appendLittleEndian(36 + dataByteCount)
        data.append(Data("WAVEfmt ".utf8))
        data.appendLittleEndian(UInt32(16))
        data.appendLittleEndian(UInt16(1))
        data.appendLittleEndian(UInt16(1))
        data.appendLittleEndian(UInt32(16_000))
        data.appendLittleEndian(UInt32(32_000))
        data.appendLittleEndian(UInt16(2))
        data.appendLittleEndian(UInt16(16))
        data.append(Data("data".utf8))
        data.appendLittleEndian(dataByteCount)
        data.append(Data(count: Int(dataByteCount)))
        try data.write(to: url, options: .atomic)
        return url
    }

    private func run(_ process: Process) async throws {
        await beforeProcessLaunch?()
        try Task.checkCancellation()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                process.terminationHandler = { _ in
                    continuation.resume()
                }
                do {
                    guard !Task.isCancelled else {
                        process.terminationHandler = nil
                        continuation.resume(throwing: CancellationError())
                        return
                    }
                    try process.run()
                    if Task.isCancelled, process.isRunning {
                        process.terminate()
                    }
                } catch {
                    process.terminationHandler = nil
                    continuation.resume(throwing: error)
                }
            }
        } onCancel: {
            if process.isRunning {
                process.terminate()
            }
        }
        try Task.checkCancellation()
    }
}

private extension Data {
    mutating func appendLittleEndian<T: FixedWidthInteger>(_ value: T) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { append(contentsOf: $0) }
    }
}

enum LocalParakeetError: LocalizedError {
    case helperUnavailable
    case modelUnavailable
    case helperFailed(Int32)
    case invalidOutput

    var errorDescription: String? {
        switch self {
        case .helperUnavailable:
            return "The bundled local transcription engine is missing or cannot be executed."
        case .modelUnavailable:
            return "The on-device transcription model is not installed. Open Settings to download it."
        case .helperFailed(let status):
            return "Local transcription failed (engine exit \(status))."
        case .invalidOutput:
            return "The local transcription engine returned no readable transcript."
        }
    }
}
