import AVFoundation
import CoreAudio
import CoreMedia
import Foundation
import os.log

private let recordingLog = OSLog(subsystem: "com.zachlatta.freeflow", category: "Recording")

struct AudioDevice: Identifiable {
    let id: AudioDeviceID
    let uid: String
    let name: String

    private static func stringProperty(
        deviceID: AudioDeviceID,
        selector: AudioObjectPropertySelector
    ) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size = UInt32(MemoryLayout<CFString?>.size)
        let raw = UnsafeMutableRawPointer.allocate(
            byteCount: Int(size),
            alignment: MemoryLayout<CFString?>.alignment
        )
        defer { raw.deallocate() }

        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, raw) == noErr,
              let ref = raw.load(as: CFString?.self) else {
            return nil
        }
        return ref as String
    }

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
            var inputStreamAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyStreamConfiguration,
                mScope: kAudioDevicePropertyScopeInput,
                mElement: kAudioObjectPropertyElementMain
            )
            var streamSize: UInt32 = 0
            guard AudioObjectGetPropertyDataSize(deviceID, &inputStreamAddress, 0, nil, &streamSize) == noErr,
                  streamSize > 0 else { continue }

            let bufferListRaw = UnsafeMutableRawPointer.allocate(
                byteCount: Int(streamSize),
                alignment: MemoryLayout<AudioBufferList>.alignment
            )
            defer { bufferListRaw.deallocate() }
            let bufferListPointer = bufferListRaw.bindMemory(to: AudioBufferList.self, capacity: 1)
            guard AudioObjectGetPropertyData(deviceID, &inputStreamAddress, 0, nil, &streamSize, bufferListPointer) == noErr else { continue }

            let bufferList = UnsafeMutableAudioBufferListPointer(bufferListPointer)
            let inputChannels = bufferList.reduce(0) { $0 + Int($1.mNumberChannels) }
            guard inputChannels > 0 else { continue }

            guard let uid = stringProperty(deviceID: deviceID, selector: kAudioDevicePropertyDeviceUID),
                  !uid.isEmpty,
                  let name = stringProperty(deviceID: deviceID, selector: kAudioObjectPropertyName),
                  !name.isEmpty else {
                continue
            }

            devices.append(AudioDevice(id: deviceID, uid: uid, name: name))
        }
        return devices
    }

    static func deviceID(forUID uid: String) -> AudioDeviceID? {
        availableInputDevices().first(where: { $0.uid == uid })?.id
    }

    static func description(forID deviceID: AudioDeviceID) -> String {
        let name = stringProperty(deviceID: deviceID, selector: kAudioObjectPropertyName) ?? "Unknown"
        let uid = stringProperty(deviceID: deviceID, selector: kAudioDevicePropertyDeviceUID) ?? "unknown-uid"
        return "\(name) [id=\(deviceID), uid=\(uid)]"
    }
}

enum AudioRecorderError: LocalizedError {
    case invalidInputFormat(String)
    case missingInputDevice
    case noAudioBuffersReceived
    case failedToCreateCaptureInput(String)
    case failedToStartCaptureSession(String)
    case failedToBeginFileRecording(String)

    var errorDescription: String? {
        switch self {
        case .invalidInputFormat(let details):
            return "Invalid input format: \(details)"
        case .missingInputDevice:
            return "No audio input device available."
        case .noAudioBuffersReceived:
            return "No audio buffers were received from the selected microphone."
        case .failedToCreateCaptureInput(let details):
            return "Could not open the selected microphone: \(details)"
        case .failedToStartCaptureSession(let details):
            return "Could not start the capture session: \(details)"
        case .failedToBeginFileRecording(let details):
            return "Could not begin recording audio: \(details)"
        }
    }
}

final class AudioRecorder: NSObject, ObservableObject, AVCaptureAudioDataOutputSampleBufferDelegate, AVCaptureFileOutputRecordingDelegate {
    private var captureSession: AVCaptureSession?
    private var currentInput: AVCaptureDeviceInput?
    private var audioFileOutput: AVCaptureAudioFileOutput?
    private var audioDataOutput: AVCaptureAudioDataOutput?
    private var sessionObservers: [NSObjectProtocol] = []
    private var tempFileURL: URL?
    private var recordingStartTime: CFAbsoluteTime = 0
    private let _bufferCount = OSAllocatedUnfairLock(initialState: 0)
    private var currentDeviceUID: String?
    private var watchdogTimer: DispatchSourceTimer?
    private let sessionQueue = DispatchQueue(label: "com.zachlatta.freeflow.capture.session")
    private let sampleBufferQueue = DispatchQueue(label: "com.zachlatta.freeflow.capture.samples")
    private var pendingStopCompletion: ((URL?) -> Void)?
    private var shouldDiscardRecording = false
    private var isSessionInterrupted = false

    @Published var isRecording = false
    private let _recording = OSAllocatedUnfairLock(initialState: false)
    @Published var audioLevel: Float = 0.0
    private var smoothedLevel: Float = 0.0

    var onRecordingReady: (() -> Void)?
    var onRecordingFailure: ((Error) -> Void)?
    private var readyFired = false
    private var failureReported = false
    private static let watchdogTimeout: TimeInterval = 2.0
    private static let sampleRateLogLimit = 40

    deinit {
        sessionQueue.sync {
            self.cancelWatchdog()
            self.teardownSessionLocked()
        }
    }

    private static func captureDevices() -> [AVCaptureDevice] {
        let deviceTypes: [AVCaptureDevice.DeviceType]
        if #available(macOS 14.0, *) {
            deviceTypes = [.microphone, .external]
        } else {
            deviceTypes = [.builtInMicrophone, .externalUnknown]
        }

        return AVCaptureDevice.DiscoverySession(
            deviceTypes: deviceTypes,
            mediaType: .audio,
            position: .unspecified
        ).devices
    }

    private static func captureDevice(forUID uid: String) -> AVCaptureDevice? {
        captureDevices().first(where: { $0.uniqueID == uid })
    }

    private static func defaultCaptureDevice() -> AVCaptureDevice? {
        AVCaptureDevice.default(for: .audio) ?? captureDevices().first
    }

    private func preferredCaptureDevice(
        for requestedDeviceUID: String?,
        reason: String
    ) -> AVCaptureDevice? {
        guard let requestedDeviceUID, !requestedDeviceUID.isEmpty, requestedDeviceUID != "default" else {
            let device = Self.defaultCaptureDevice()
            if let device {
                os_log(.info, log: recordingLog, "%{public}@ — using system default device: %{public}@", reason, device.localizedName)
            }
            return device
        }

        if let device = Self.captureDevice(forUID: requestedDeviceUID) {
            os_log(.info, log: recordingLog, "%{public}@ — keeping selected device: %{public}@ [uid=%{public}@]", reason, device.localizedName, device.uniqueID)
            return device
        }

        let fallbackDevice = Self.defaultCaptureDevice()
        if let fallbackDevice {
            os_log(.info, log: recordingLog, "%{public}@ — selected device unavailable, falling back to system default: %{public}@ [uid=%{public}@]", reason, fallbackDevice.localizedName, fallbackDevice.uniqueID)
        }
        return fallbackDevice
    }

    private func installSessionObservers(for session: AVCaptureSession) {
        removeSessionObservers()

        let runtimeObserver = NotificationCenter.default.addObserver(
            forName: AVCaptureSession.runtimeErrorNotification,
            object: session,
            queue: nil
        ) { [weak self] notification in
            let error = notification.userInfo?[AVCaptureSessionErrorKey] as? NSError
            let wrapped = error.map { AudioRecorderError.failedToStartCaptureSession($0.localizedDescription) }
                ?? AudioRecorderError.failedToStartCaptureSession("Unknown runtime error")
            self?.reportRecordingFailure(wrapped)
        }
        sessionObservers.append(runtimeObserver)

        let interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVCaptureSession.wasInterruptedNotification,
            object: session,
            queue: nil
        ) { [weak self] notification in
            self?.handleSessionInterrupted(notification)
        }
        sessionObservers.append(interruptionObserver)

        let interruptionEndedObserver = NotificationCenter.default.addObserver(
            forName: AVCaptureSession.interruptionEndedNotification,
            object: session,
            queue: nil
        ) { [weak self] notification in
            self?.handleSessionInterruptionEnded(notification)
        }
        sessionObservers.append(interruptionEndedObserver)
    }

    private func removeSessionObservers() {
        for observer in sessionObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        sessionObservers.removeAll()
    }

    private func teardownSessionLocked() {
        removeSessionObservers()
        isSessionInterrupted = false

        audioDataOutput?.setSampleBufferDelegate(nil, queue: nil)
        if let session = captureSession, session.isRunning {
            session.stopRunning()
        }

        captureSession = nil
        currentInput = nil
        audioFileOutput = nil
        audioDataOutput = nil
        currentDeviceUID = nil
    }

    private func reportRecordingFailure(_ error: Error, completion: ((URL?) -> Void)? = nil) {
        sessionQueue.async {
            guard !self.failureReported else { return }
            self.failureReported = true
            self.cancelWatchdog()
            self._recording.withLock { $0 = false }

            let completion = completion ?? self.pendingStopCompletion
            self.pendingStopCompletion = nil
            let discardURL = self.tempFileURL
            self.shouldDiscardRecording = false
            self.teardownSessionLocked()
            self.tempFileURL = nil
            if let discardURL {
                try? FileManager.default.removeItem(at: discardURL)
            }

            DispatchQueue.main.async {
                self.isRecording = false
                self.audioLevel = 0.0
                self.onRecordingFailure?(error)
                completion?(nil)
            }
        }
    }

    private func startBufferWatchdog() {
        let baselineCount = _bufferCount.withLock { $0 }
        cancelWatchdog()

        let timer = DispatchSource.makeTimerSource(queue: sessionQueue)
        timer.schedule(deadline: .now() + Self.watchdogTimeout)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            guard self._recording.withLock({ $0 }) else { return }
            guard !self.isSessionInterrupted else {
                os_log(.info, log: recordingLog, "watchdog suspended while capture session is interrupted")
                return
            }

            let count = self._bufferCount.withLock { $0 }
            if count == baselineCount {
                os_log(.error, log: recordingLog, "watchdog: no new buffers after %.1fs — giving up", Self.watchdogTimeout)
                self.reportRecordingFailure(AudioRecorderError.noAudioBuffersReceived)
            } else {
                os_log(.info, log: recordingLog, "watchdog: %d new buffers after %.1fs — healthy", count - baselineCount, Self.watchdogTimeout)
            }
        }
        timer.resume()
        watchdogTimer = timer
    }

    private func cancelWatchdog() {
        watchdogTimer?.cancel()
        watchdogTimer = nil
    }

    private func handleSessionInterrupted(_ notification: Notification) {
        _ = notification
        sessionQueue.async {
            guard self._recording.withLock({ $0 }) else { return }
            self.isSessionInterrupted = true
            self.cancelWatchdog()
            os_log(.info, log: recordingLog, "capture session interrupted — waiting for recovery")
        }
    }

    private func handleSessionInterruptionEnded(_ notification: Notification) {
        _ = notification
        sessionQueue.async {
            guard self._recording.withLock({ $0 }) else { return }
            self.isSessionInterrupted = false
            os_log(.info, log: recordingLog, "capture session interruption ended — restarting watchdog")
            self.startBufferWatchdog()
        }
    }

    private func makeSession(deviceUID: String?, outputURL: URL) throws {
        teardownSessionLocked()

        guard let device = preferredCaptureDevice(for: deviceUID, reason: "initial start") else {
            throw AudioRecorderError.missingInputDevice
        }

        let session = AVCaptureSession()
        let fileOutput = AVCaptureAudioFileOutput()
        let dataOutput = AVCaptureAudioDataOutput()
        dataOutput.audioSettings = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ]
        dataOutput.setSampleBufferDelegate(self, queue: sampleBufferQueue)

        let input: AVCaptureDeviceInput
        do {
            input = try AVCaptureDeviceInput(device: device)
        } catch {
            throw AudioRecorderError.failedToCreateCaptureInput(error.localizedDescription)
        }

        session.beginConfiguration()
        var needsCommitConfiguration = true
        defer {
            if needsCommitConfiguration {
                session.commitConfiguration()
            }
        }

        guard session.canAddInput(input) else {
            throw AudioRecorderError.failedToCreateCaptureInput("Session rejected device input for \(device.localizedName).")
        }
        session.addInput(input)

        guard session.canAddOutput(fileOutput) else {
            throw AudioRecorderError.failedToBeginFileRecording("Session rejected audio file output.")
        }
        session.addOutput(fileOutput)

        guard session.canAddOutput(dataOutput) else {
            throw AudioRecorderError.failedToStartCaptureSession("Session rejected audio data output.")
        }
        session.addOutput(dataOutput)

        session.commitConfiguration()
        needsCommitConfiguration = false

        captureSession = session
        currentInput = input
        audioFileOutput = fileOutput
        audioDataOutput = dataOutput
        currentDeviceUID = device.uniqueID
        isSessionInterrupted = false
        installSessionObservers(for: session)

        os_log(.info, log: recordingLog, "configured capture session with device %{public}@ [uid=%{public}@]", device.localizedName, device.uniqueID)

        session.startRunning()
        guard session.isRunning else {
            throw AudioRecorderError.failedToStartCaptureSession("Session failed to enter running state.")
        }

        os_log(.info, log: recordingLog, "capture session running with device %{public}@ [uid=%{public}@]", device.localizedName, device.uniqueID)

        let availableFileTypes = type(of: fileOutput).availableOutputFileTypes()
        guard availableFileTypes.contains(.wav) else {
            throw AudioRecorderError.failedToBeginFileRecording("WAV output is not supported by AVCaptureAudioFileOutput.")
        }

        fileOutput.startRecording(to: outputURL, outputFileType: .wav, recordingDelegate: self)
    }

    func startRecording(deviceUID: String? = nil) throws {
        let t0 = CFAbsoluteTimeGetCurrent()
        recordingStartTime = t0
        _bufferCount.withLock { $0 = 0 }
        readyFired = false
        failureReported = false
        shouldDiscardRecording = false
        pendingStopCompletion = nil
        smoothedLevel = 0.0

        os_log(.info, log: recordingLog, "startRecording() entered")

        let tempDir = FileManager.default.temporaryDirectory
        let outputURL = tempDir.appendingPathComponent(UUID().uuidString + ".wav")
        tempFileURL = outputURL

        do {
            try sessionQueue.sync {
                try self.makeSession(deviceUID: deviceUID, outputURL: outputURL)
                self._recording.withLock { $0 = true }
                self.startBufferWatchdog()
            }
        } catch {
            tempFileURL = nil
            throw error
        }

        DispatchQueue.main.async {
            self.isRecording = true
            self.audioLevel = 0.0
        }
        os_log(.info, log: recordingLog, "startRecording() complete: %.3fms total", (CFAbsoluteTimeGetCurrent() - t0) * 1000)
    }

    func stopRecording(completion: @escaping (URL?) -> Void) {
        let count = _bufferCount.withLock { $0 }
        let elapsed = (CFAbsoluteTimeGetCurrent() - recordingStartTime) * 1000
        os_log(.info, log: recordingLog, "stopRecording() called: %.3fms after start, %d buffers received", elapsed, count)

        sessionQueue.async {
            self.cancelWatchdog()
            self._recording.withLock { $0 = false }
            self.pendingStopCompletion = completion
            self.shouldDiscardRecording = false

            if let fileOutput = self.audioFileOutput, fileOutput.isRecording {
                fileOutput.stopRecording()
            } else {
                let outputURL = self.tempFileURL
                self.pendingStopCompletion = nil
                self.teardownSessionLocked()
                DispatchQueue.main.async {
                    self.isRecording = false
                    self.audioLevel = 0.0
                    completion(outputURL)
                }
            }
        }
    }

    func cancelRecording() {
        sessionQueue.async {
            self.cancelWatchdog()
            self._recording.withLock { $0 = false }
            self.pendingStopCompletion = nil
            self.shouldDiscardRecording = true

            if let fileOutput = self.audioFileOutput, fileOutput.isRecording {
                fileOutput.stopRecording()
            } else {
                let discardURL = self.tempFileURL
                self.tempFileURL = nil
                self.teardownSessionLocked()
                if let discardURL {
                    try? FileManager.default.removeItem(at: discardURL)
                }
                DispatchQueue.main.async {
                    self.isRecording = false
                    self.audioLevel = 0.0
                }
            }
        }
    }

    func cleanup() {
        if let url = tempFileURL {
            try? FileManager.default.removeItem(at: url)
            tempFileURL = nil
        }
    }

    private func updateAudioLevel(from sampleBuffer: CMSampleBuffer) -> Float {
        guard let dataBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { return 0 }

        var lengthAtOffset = 0
        var totalLength = 0
        var dataPointer: UnsafeMutablePointer<Int8>?
        let status = CMBlockBufferGetDataPointer(
            dataBuffer,
            atOffset: 0,
            lengthAtOffsetOut: &lengthAtOffset,
            totalLengthOut: &totalLength,
            dataPointerOut: &dataPointer
        )

        guard status == kCMBlockBufferNoErr, totalLength > 0, let dataPointer else { return 0 }

        let sampleCount = totalLength / MemoryLayout<Float>.size
        guard sampleCount > 0 else { return 0 }

        let floatPointer = UnsafeRawPointer(dataPointer).assumingMemoryBound(to: Float.self)
        var sumOfSquares: Float = 0
        for index in 0..<sampleCount {
            let sample = floatPointer[index]
            sumOfSquares += sample * sample
        }

        let rms = sqrtf(sumOfSquares / Float(sampleCount))
        let scaled = min(rms * 10.0, 1.0)

        if scaled > smoothedLevel {
            smoothedLevel = smoothedLevel * 0.3 + scaled * 0.7
        } else {
            smoothedLevel = smoothedLevel * 0.6 + scaled * 0.4
        }

        DispatchQueue.main.async {
            self.audioLevel = self.smoothedLevel
        }
        return rms
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard _recording.withLock({ $0 }) else { return }

        let count = _bufferCount.withLock { value -> Int in
            value += 1
            return value
        }

        let rms = updateAudioLevel(from: sampleBuffer)
        if count <= Self.sampleRateLogLimit {
            let elapsed = (CFAbsoluteTimeGetCurrent() - recordingStartTime) * 1000
            os_log(.info, log: recordingLog, "buffer #%d at %.3fms, rms=%.6f", count, elapsed, rms)
        }

        if !readyFired && rms > 0 {
            readyFired = true
            let elapsed = (CFAbsoluteTimeGetCurrent() - recordingStartTime) * 1000
            os_log(.info, log: recordingLog, "FIRST non-silent buffer at %.3fms — recording ready", elapsed)
            DispatchQueue.main.async {
                self.onRecordingReady?()
            }
        }
    }

    func fileOutput(
        _ output: AVCaptureFileOutput,
        didStartRecordingTo outputFileURL: URL,
        from connections: [AVCaptureConnection]
    ) {
        os_log(.info, log: recordingLog, "file output started writing to %{public}@", outputFileURL.path)
    }

    func fileOutput(
        _ output: AVCaptureFileOutput,
        didFinishRecordingTo outputFileURL: URL,
        from connections: [AVCaptureConnection],
        error: Error?
    ) {
        sessionQueue.async {
            let completion = self.pendingStopCompletion
            self.pendingStopCompletion = nil
            let shouldDiscardRecording = self.shouldDiscardRecording
            self.shouldDiscardRecording = false
            self.cancelWatchdog()
            let recordingSuccessfullyFinished = (error as NSError?)?.userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? Bool ?? false

            if let error, !recordingSuccessfullyFinished {
                if !shouldDiscardRecording {
                    os_log(.error, log: recordingLog, "file output finished with error: %{public}@", error.localizedDescription)
                    self.reportRecordingFailure(
                        AudioRecorderError.failedToBeginFileRecording(error.localizedDescription),
                        completion: completion
                    )
                } else {
                    self.teardownSessionLocked()
                    self.tempFileURL = nil
                    try? FileManager.default.removeItem(at: outputFileURL)
                    DispatchQueue.main.async {
                        self.isRecording = false
                        self.audioLevel = 0.0
                    }
                }
                return
            }

            if let error {
                os_log(.info, log: recordingLog, "file output finished with recoverable stop status: %{public}@", error.localizedDescription)
            }

            self.teardownSessionLocked()

            DispatchQueue.main.async {
                self.isRecording = false
                self.audioLevel = 0.0
            }

            if shouldDiscardRecording {
                try? FileManager.default.removeItem(at: outputFileURL)
                self.tempFileURL = nil
                return
            }

            self.tempFileURL = outputFileURL
            DispatchQueue.main.async {
                completion?(outputFileURL)
            }
        }
    }
}
