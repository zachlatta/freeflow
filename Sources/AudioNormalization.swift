import AVFoundation
import Foundation

enum AudioNormalization {
    static func writePreferredAudioCopy(from sourceURL: URL, to outputURL: URL) throws {
        let inputFile = try AVAudioFile(forReading: sourceURL)
        let inputFormat = inputFile.processingFormat
        guard let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 16_000,
            channels: 1,
            interleaved: false
        ) else {
            throw AudioNormalizationError.preparationFailed("Could not create normalized output format")
        }
        guard let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
            throw AudioNormalizationError.preparationFailed("Could not create audio converter")
        }

        converter.sampleRateConverterQuality = AVAudioQuality.medium.rawValue

        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: true
        ]
        let outputFile = try AVAudioFile(
            forWriting: outputURL,
            settings: outputSettings,
            commonFormat: .pcmFormatInt16,
            interleaved: false
        )

        let inputFrameCapacity: AVAudioFrameCount = 4096
        let outputFrameCapacity = AVAudioFrameCount(
            ceil(Double(inputFrameCapacity) * outputFormat.sampleRate / inputFormat.sampleRate)
        ) + 32

        var reachedEndOfInput = false
        var readError: Error?
        var conversionError: NSError?

        while true {
            guard let outputBuffer = AVAudioPCMBuffer(
                pcmFormat: outputFormat,
                frameCapacity: outputFrameCapacity
            ) else {
                throw AudioNormalizationError.preparationFailed("Could not allocate normalized audio buffer")
            }

            let status = converter.convert(to: outputBuffer, error: &conversionError) { _, outStatus in
                if reachedEndOfInput {
                    outStatus.pointee = .endOfStream
                    return nil
                }

                let remainingFrames = inputFile.length - inputFile.framePosition
                guard remainingFrames > 0 else {
                    reachedEndOfInput = true
                    outStatus.pointee = .endOfStream
                    return nil
                }

                let framesToRead = AVAudioFrameCount(min(Int64(inputFrameCapacity), remainingFrames))
                guard let inputBuffer = AVAudioPCMBuffer(
                    pcmFormat: inputFormat,
                    frameCapacity: framesToRead
                ) else {
                    readError = AudioNormalizationError.preparationFailed("Could not allocate source audio buffer")
                    outStatus.pointee = .noDataNow
                    return nil
                }

                do {
                    try inputFile.read(into: inputBuffer, frameCount: framesToRead)
                } catch {
                    readError = error
                    outStatus.pointee = .noDataNow
                    return nil
                }

                if inputBuffer.frameLength == 0 {
                    reachedEndOfInput = true
                    outStatus.pointee = .endOfStream
                    return nil
                }

                outStatus.pointee = .haveData
                return inputBuffer
            }

            if let readError {
                throw AudioNormalizationError.preparationFailed(readError.localizedDescription)
            }
            if let conversionError {
                throw AudioNormalizationError.preparationFailed(conversionError.localizedDescription)
            }

            switch status {
            case .haveData:
                try outputFile.write(from: outputBuffer)
            case .inputRanDry:
                continue
            case .endOfStream:
                if outputBuffer.frameLength > 0 {
                    try outputFile.write(from: outputBuffer)
                }
                return
            case .error:
                throw AudioNormalizationError.preparationFailed("Audio conversion failed")
            @unknown default:
                throw AudioNormalizationError.preparationFailed("Unknown audio conversion status")
            }
        }
    }
}

enum AudioNormalizationError: LocalizedError {
    case preparationFailed(String)

    var errorDescription: String? {
        switch self {
        case .preparationFailed(let message):
            return message
        }
    }
}
