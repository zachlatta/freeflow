import AVFoundation
import CoreAudio
import Foundation
import os.log

private let recordingLog = OSLog(subsystem: "com.zachlatta.freeflow", category: "Recording")

struct AudioDevice: Identifiable {
    let id: AudioDeviceID
    let uid: String
    let name: String

    static func availableInputDevices() -> [AudioDevice] {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0, nil,
            &dataSize
        )
        guard status == noErr, dataSize > 0 else { return [] }

        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)
        status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0, nil,
            &dataSize,
            &deviceIDs
        )
        guard status == noErr else { return [] }

        var devices: [AudioDevice] = []
        for deviceID in deviceIDs {
            // Check if device has input streams
            var inputStreamAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyStreamConfiguration,
                mScope: kAudioDevicePropertyScopeInput,
                mElement: kAudioObjectPropertyElementMain
            )
            var streamSize: UInt32 = 0
            guard AudioObjectGetPropertyDataSize(deviceID, &inputStreamAddress, 0, nil, &streamSize) == noErr,
                  streamSize > 0 else { continue }

            let bufferListPointer = UnsafeMutablePointer<AudioBufferList>.allocate(capacity: 1)
            defer { bufferListPointer.deallocate() }
            guard AudioObjectGetPropertyData(deviceID, &inputStreamAddress, 0, nil, &streamSize, bufferListPointer) == noErr else { continue }

            let bufferList = UnsafeMutableAudioBufferListPointer(bufferListPointer)
            let inputChannels = bufferList.reduce(0) { $0 + Int($1.mNumberChannels) }
            guard inputChannels > 0 else { continue }

            // Get device UID
            var uidAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDeviceUID,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var uidRef: Unmanaged<CFString>?
            var uidSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            guard AudioObjectGetPropertyData(deviceID, &uidAddress, 0, nil, &uidSize, &uidRef) == noErr,
                  let uid = uidRef?.takeUnretainedValue() as String? else { continue }

            // Get device name
            var nameAddress = AudioObjectPropertyAddress(
                mSelector: kAudioObjectPropertyName,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var nameRef: Unmanaged<CFString>?
            var nameSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            guard AudioObjectGetPropertyData(deviceID, &nameAddress, 0, nil, &nameSize, &nameRef) == noErr,
                  let name = nameRef?.takeUnretainedValue() as String? else { continue }

            devices.append(AudioDevice(id: deviceID, uid: uid, name: name))
        }
        return devices
    }

    static func deviceID(forUID uid: String) -> AudioDeviceID? {
        // Look up through the enumerated devices to avoid CFString pointer issues
        return availableInputDevices().first(where: { $0.uid == uid })?.id
    }
}

enum AudioRecorderError: LocalizedError {
    case invalidInputFormat(String)
    case missingInputDevice

    var errorDescription: String? {
        switch self {
        case .invalidInputFormat(let details):
            return "Invalid input format: \(details)"
        case .missingInputDevice:
            return "No audio input device available."
        }
    }
}

class AudioRecorder: NSObject, ObservableObject {
    private var audioEngine: AVAudioEngine?
    private var audioFile: AVAudioFile?
    private var tempFileURL: URL?
    private let audioFileQueue = DispatchQueue(label: "com.zachlatta.freeflow.audiofile")
    private var recordingStartTime: CFAbsoluteTime = 0
    private var firstBufferLogged = false
    private var bufferCount: Int = 0
    private var currentDeviceUID: String?
    private var storedInputFormat: AVAudioFormat?

    @Published var isRecording = false
    /// Thread-safe flag read from the audio tap callback.
    private let _recording = OSAllocatedUnfairLock(initialState: false)
    @Published var audioLevel: Float = 0.0
    private var smoothedLevel: Float = 0.0

    /// Called on the audio thread when the first non-silent buffer arrives.
    var onRecordingReady: (() -> Void)?
    private var readyFired = false

    func startRecording(deviceUID: String? = nil) throws {
        let t0 = CFAbsoluteTimeGetCurrent()
        recordingStartTime = t0
        firstBufferLogged = false
        bufferCount = 0
        readyFired = false

        os_log(.info, log: recordingLog, "startRecording() entered")

        guard AVCaptureDevice.default(for: .audio) != nil else {
            throw AudioRecorderError.missingInputDevice
        }
        os_log(.info, log: recordingLog, "AVCaptureDevice check: %.3fms", (CFAbsoluteTimeGetCurrent() - t0) * 1000)

        // Reuse existing engine if same device, otherwise build new one
        if let _ = audioEngine, currentDeviceUID == deviceUID {
            os_log(.info, log: recordingLog, "reusing existing engine: %.3fms", (CFAbsoluteTimeGetCurrent() - t0) * 1000)
        } else {
            // Tear down old engine if device changed
            if audioEngine != nil {
                audioEngine?.inputNode.removeTap(onBus: 0)
                audioEngine?.stop()
                audioEngine = nil
            }

            let engine = AVAudioEngine()
            os_log(.info, log: recordingLog, "AVAudioEngine created: %.3fms", (CFAbsoluteTimeGetCurrent() - t0) * 1000)

            // Set specific input device if requested
            if let uid = deviceUID, !uid.isEmpty, uid != "default",
               let deviceID = AudioDevice.deviceID(forUID: uid) {
                os_log(.info, log: recordingLog, "device lookup resolved to %d: %.3fms", deviceID, (CFAbsoluteTimeGetCurrent() - t0) * 1000)
                let inputUnit = engine.inputNode.audioUnit!
                var id = deviceID
                AudioUnitSetProperty(
                    inputUnit,
                    kAudioOutputUnitProperty_CurrentDevice,
                    kAudioUnitScope_Global,
                    0,
                    &id,
                    UInt32(MemoryLayout<AudioDeviceID>.size)
                )
            }

            let inputNode = engine.inputNode
            os_log(.info, log: recordingLog, "inputNode accessed: %.3fms", (CFAbsoluteTimeGetCurrent() - t0) * 1000)
            let inputFormat = inputNode.outputFormat(forBus: 0)
            os_log(.info, log: recordingLog, "inputFormat retrieved (rate=%.0f, ch=%d): %.3fms", inputFormat.sampleRate, inputFormat.channelCount, (CFAbsoluteTimeGetCurrent() - t0) * 1000)
            guard inputFormat.sampleRate > 0 else {
                throw AudioRecorderError.invalidInputFormat("Invalid sample rate: \(inputFormat.sampleRate)")
            }
            guard inputFormat.channelCount > 0 else {
                throw AudioRecorderError.invalidInputFormat("No input channels available")
            }

            storedInputFormat = inputFormat

            // Install tap — checks isRecording and audioFile dynamically
            inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
                guard let self, self._recording.withLock({ $0 }) else { return }

                self.bufferCount += 1

                // Check if this buffer has real audio
                var rms: Float = 0
                let frames = Int(buffer.frameLength)
                if frames > 0, let channelData = buffer.floatChannelData {
                    let samples = channelData[0]
                    var sum: Float = 0
                    for i in 0..<frames { sum += samples[i] * samples[i] }
                    rms = sqrtf(sum / Float(frames))
                }

                if self.bufferCount <= 40 {
                    let elapsed = (CFAbsoluteTimeGetCurrent() - self.recordingStartTime) * 1000
                    os_log(.info, log: recordingLog, "buffer #%d at %.3fms, frames=%d, rms=%.6f", self.bufferCount, elapsed, buffer.frameLength, rms)
                }

                // Fire ready callback on first non-silent buffer
                if !self.readyFired && rms > 0 {
                    self.readyFired = true
                    let elapsed = (CFAbsoluteTimeGetCurrent() - self.recordingStartTime) * 1000
                    os_log(.info, log: recordingLog, "FIRST non-silent buffer at %.3fms — recording ready", elapsed)
                    self.onRecordingReady?()
                }

                self.audioFileQueue.sync {
                    if let file = self.audioFile {
                        do {
                            try file.write(from: buffer)
                        } catch {
                            self.audioFile = nil
                        }
                    }
                }
                self.computeAudioLevel(from: buffer)
            }
            os_log(.info, log: recordingLog, "tap installed: %.3fms", (CFAbsoluteTimeGetCurrent() - t0) * 1000)

            engine.prepare()
            os_log(.info, log: recordingLog, "engine prepared: %.3fms", (CFAbsoluteTimeGetCurrent() - t0) * 1000)

            self.audioEngine = engine
            self.currentDeviceUID = deviceUID
        }

        // Start engine if not already running
        if let engine = audioEngine, !engine.isRunning {
            try engine.start()
            os_log(.info, log: recordingLog, "engine started: %.3fms", (CFAbsoluteTimeGetCurrent() - t0) * 1000)
        }

        guard let inputFormat = storedInputFormat else {
            throw AudioRecorderError.invalidInputFormat("No stored input format")
        }

        // Create a temp file to write audio to
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent(UUID().uuidString + ".wav")
        self.tempFileURL = fileURL

        // Try the input format first to avoid conversion issues, then fall back to 16-bit PCM.
        let newAudioFile: AVAudioFile
        do {
            newAudioFile = try AVAudioFile(forWriting: fileURL, settings: inputFormat.settings)
        } catch {
            let fallbackSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: inputFormat.sampleRate,
                AVNumberOfChannelsKey: inputFormat.channelCount,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsNonInterleaved: inputFormat.isInterleaved ? 0 : 1,
            ]
            newAudioFile = try AVAudioFile(
                forWriting: fileURL,
                settings: fallbackSettings,
                commonFormat: .pcmFormatInt16,
                interleaved: inputFormat.isInterleaved
            )
        }
        os_log(.info, log: recordingLog, "audio file created: %.3fms", (CFAbsoluteTimeGetCurrent() - t0) * 1000)

        audioFileQueue.sync { self.audioFile = newAudioFile }
        _recording.withLock { $0 = true }
        self.isRecording = true
        os_log(.info, log: recordingLog, "startRecording() complete: %.3fms total", (CFAbsoluteTimeGetCurrent() - t0) * 1000)
    }

    func stopRecording() -> URL? {
        let elapsed = (CFAbsoluteTimeGetCurrent() - recordingStartTime) * 1000
        os_log(.info, log: recordingLog, "stopRecording() called: %.3fms after start, %d buffers received", elapsed, bufferCount)

        _recording.withLock { $0 = false }
        audioFileQueue.sync { audioFile = nil }
        isRecording = false
        smoothedLevel = 0.0
        DispatchQueue.main.async { self.audioLevel = 0.0 }

        // Stop engine so mic indicator goes away — keep engine object for fast restart
        audioEngine?.stop()
        os_log(.info, log: recordingLog, "engine stopped (mic indicator off)")

        return tempFileURL
    }

    private func computeAudioLevel(from buffer: AVAudioPCMBuffer) {
        let frames = Int(buffer.frameLength)
        guard frames > 0 else { return }

        var sumOfSquares: Float = 0.0
        if let channelData = buffer.floatChannelData {
            let samples = channelData[0]
            for i in 0..<frames {
                let sample = samples[i]
                sumOfSquares += sample * sample
            }
        } else if let channelData = buffer.int16ChannelData {
            let samples = channelData[0]
            for i in 0..<frames {
                let sample = Float(samples[i]) / Float(Int16.max)
                sumOfSquares += sample * sample
            }
        } else {
            return
        }

        let rms = sqrtf(sumOfSquares / Float(frames))

        // Scale RMS (~0.01-0.1 for speech) to 0-1 range
        let scaled = min(rms * 10.0, 1.0)

        // Fast attack, slower release — follows speech dynamics closely
        if scaled > smoothedLevel {
            smoothedLevel = smoothedLevel * 0.3 + scaled * 0.7
        } else {
            smoothedLevel = smoothedLevel * 0.6 + scaled * 0.4
        }

        DispatchQueue.main.async {
            self.audioLevel = self.smoothedLevel
        }
    }

    func cleanup() {
        if let url = tempFileURL {
            try? FileManager.default.removeItem(at: url)
            tempFileURL = nil
        }
    }
}
