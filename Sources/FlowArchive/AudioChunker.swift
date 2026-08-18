import AVFoundation
import Foundation

struct AudioChunk {
    var url: URL
    var duration: TimeInterval
    var deleteAfter: Bool
}

enum AudioChunker {
    static let maxUploadBytes: Int64 = 24 * 1024 * 1024

    static func chunks(for url: URL) async throws -> [AudioChunk] {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let size = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)
        let durationSeconds = CMTimeGetSeconds(duration)
        let safeDuration = durationSeconds.isFinite && durationSeconds > 0 ? durationSeconds : 0

        if size <= maxUploadBytes || size <= 0 {
            return [AudioChunk(url: url, duration: safeDuration, deleteAfter: false)]
        }

        let chunkCount = max(2, Int(ceil(Double(size) / Double(maxUploadBytes))))
        let chunkDuration = safeDuration / Double(chunkCount)
        guard chunkDuration > 0.5 else {
            return [AudioChunk(url: url, duration: safeDuration, deleteAfter: false)]
        }

        var result: [AudioChunk] = []
        for index in 0..<chunkCount {
            let start = CMTime(seconds: Double(index) * chunkDuration, preferredTimescale: 600)
            let remaining = safeDuration - Double(index) * chunkDuration
            let length = min(chunkDuration, remaining)
            guard length > 0.05 else { continue }
            let range = CMTimeRange(start: start, duration: CMTime(seconds: length, preferredTimescale: 600))
            let exported = try await export(asset: asset, timeRange: range, index: index)
            result.append(AudioChunk(url: exported, duration: length, deleteAfter: true))
        }
        return result.isEmpty
            ? [AudioChunk(url: url, duration: safeDuration, deleteAfter: false)]
            : result
    }

    private static func export(
        asset: AVAsset,
        timeRange: CMTimeRange,
        index: Int
    ) async throws -> URL {
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw ArchivePipelineError.chunkingFailed("Unable to create an audio export session.")
        }
        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("flowarchive-chunk-\(UUID().uuidString)-\(index).m4a")
        session.outputURL = output
        session.outputFileType = .m4a
        session.timeRange = timeRange

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            session.exportAsynchronously {
                switch session.status {
                case .completed:
                    continuation.resume()
                case .cancelled:
                    continuation.resume(throwing: CancellationError())
                default:
                    continuation.resume(
                        throwing: ArchivePipelineError.chunkingFailed(
                            session.error?.localizedDescription ?? "Audio export failed."
                        )
                    )
                }
            }
        }
        return output
    }
}
