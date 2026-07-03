import Foundation

/// Transcribes audio in the background while recording is still in progress.
///
/// Audio is accumulated as raw PCM16 samples (24 kHz mono, matching
/// `AudioRecorder.onPCM16Samples`).  Every 28 seconds a WAV file is
/// written to a temporary location and submitted to the configured
/// transcription service.  Chunks are processed *serially* so upstream
/// API rate limits are respected.
///
/// If `saveURL` is provided, each completed chunk's transcript is appended
/// to that file immediately after transcription — so a crash loses at most
/// one in-flight chunk rather than the entire session.
///
/// Call `appendPCM16(_:)` from any thread while recording, then
/// `commitAndAwaitFinal()` from an async context when recording stops.
/// The full merged transcript is returned; individual chunk results are
/// combined in order.  Falls back gracefully: if a chunk fails, it is
/// skipped rather than aborting the session.
final class PrefetchTranscriber: @unchecked Sendable {

    // MARK: Configuration

    private let service: TranscriptionService
    private static let chunkSeconds: Int = 28
    private static let sampleRate: Int = 24_000   // matches pcm16TargetFormat
    private static let bytesPerSample: Int = 2     // PCM16
    private static let chunkBytes: Int = chunkSeconds * sampleRate * bytesPerSample

    /// Optional file that receives each chunk's transcript as it completes.
    /// Created (or truncated) at init time; appended after every chunk so
    /// partial transcripts survive an app crash.
    private let saveURL: URL?

    // MARK: State (guarded by lock)

    private let lock = NSLock()
    private var buffer = Data()
    private var segments: [String] = []

    /// Serial chain of chunk-transcription Tasks.  Each new chunk task
    /// awaits the completion of the previous one before starting.
    private var chainTail: Task<String?, Never> = Task { nil }

    // MARK: Init

    init(service: TranscriptionService, saveURL: URL? = nil) {
        self.service = service
        self.saveURL = saveURL
        if let url = saveURL {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
    }

    // MARK: Public API

    /// Append raw PCM16 samples. Safe to call from any thread or queue.
    func appendPCM16(_ data: Data) {
        let chunk: Data? = lock.withLock {
            buffer.append(data)
            guard buffer.count >= Self.chunkBytes else { return nil }
            let c = Data(buffer.prefix(Self.chunkBytes))
            buffer = Data(buffer.dropFirst(Self.chunkBytes))
            return c
        }
        guard let chunk else { return }
        enqueueChunk(chunk, label: "background chunk")
    }

    /// Wait for all in-flight chunks, transcribe the remaining tail, and
    /// return the merged transcript.  Must be called from an async context.
    func commitAndAwaitFinal() async -> String {
        // Wait for the last enqueued chunk to complete.
        _ = await chainTail.value

        // Transcribe the tail (< 28 s remaining in the buffer).
        let tail: Data = lock.withLock {
            let t = buffer
            buffer = Data()
            return t
        }
        if !tail.isEmpty {
            if let text = await transcribeWAV(Self.buildWAV(from: tail)), !text.isEmpty {
                lock.withLock { segments.append(text) }
                appendToSaveFile(text)
            }
        }

        return lock.withLock { segments.joined(separator: " ") }
    }

    // MARK: Private helpers

    private func enqueueChunk(_ chunk: Data, label: String) {
        let prev = chainTail
        let newTask: Task<String?, Never> = Task { [weak self] in
            guard let self else { return nil }
            // Ensure serial execution: wait for the preceding chunk.
            _ = await prev.value
            let wav = Self.buildWAV(from: chunk)
            return await self.transcribeWAV(wav)
        }
        chainTail = newTask

        // Collect the result into `segments` once done and persist to disk.
        Task { [weak self] in
            guard let self else { return }
            if let text = await newTask.value, !text.isEmpty {
                self.lock.withLock { self.segments.append(text) }
                self.appendToSaveFile(text)
            }
        }
    }

    /// Appends one chunk's text to the durable save file.
    /// Uses `FileHandle` for atomic append without reading the whole file.
    private func appendToSaveFile(_ text: String) {
        guard let url = saveURL else { return }
        let line = text + "\n\n"
        guard let data = line.data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            handle.write(data)
        }
    }

    private func transcribeWAV(_ wav: Data) async -> String? {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("prefetch_\(UUID().uuidString).wav")
        do {
            try wav.write(to: url)
            defer { try? FileManager.default.removeItem(at: url) }
            return try await service.transcribe(fileURL: url)
        } catch {
            return nil
        }
    }

    /// Build a minimal WAV container around raw PCM16 mono data.
    private static func buildWAV(from pcm: Data) -> Data {
        var wav = Data()
        func le<T: FixedWidthInteger>(_ v: T) {
            var x = v.littleEndian
            wav.append(Data(bytes: &x, count: MemoryLayout<T>.size))
        }
        let dataLen = UInt32(pcm.count)
        wav += "RIFF".data(using: .ascii)!; le(dataLen + 36)
        wav += "WAVEfmt ".data(using: .ascii)!
        le(UInt32(16)); le(UInt16(1)); le(UInt16(1))   // fmt, PCM, mono
        le(UInt32(sampleRate))
        le(UInt32(sampleRate * bytesPerSample))        // byte rate
        le(UInt16(bytesPerSample))                     // block align
        le(UInt16(16))                                 // bits per sample
        wav += "data".data(using: .ascii)!; le(dataLen)
        wav += pcm
        return wav
    }
}
