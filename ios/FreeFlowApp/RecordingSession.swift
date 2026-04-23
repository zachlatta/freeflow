import AVFoundation
import Foundation
import UIKit
import os.log

private let sessionLog = OSLog(subsystem: "com.shebetoff.freeflow.app", category: "RecordingSession")

@MainActor
final class RecordingSession {
    static let shared = RecordingSession()

    private let storage = SharedStorage.shared
    private let audioEngine = AVAudioEngine()
    private var audioFile: AVAudioFile?
    private var currentFileURL: URL?
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    private var expiryTimer: Timer?
    private var suspensionWorkItem: DispatchWorkItem?
    private let observer = DarwinObserver()
    private var handledCommandID: String?
    private var isObserving = false
    private var isSessionActive = false
    private let pipeline = KeyboardPipeline()

    private init() {
        setupObservers()
    }

    func prime(suspendAfter: Bool = false) {
        os_log(.info, log: sessionLog, "Priming audio session (suspendAfter=%{public}d)", suspendAfter)
        do {
            try activateAudioSession()
            try startKeepAliveEngine()
            markPrimed()
            beginBackgroundTaskIfNeeded()
            scheduleExpiry()
            if suspendAfter {
                scheduleSelfSuspension()
            }
        } catch {
            os_log(.error, log: sessionLog, "prime failed: %{public}@", error.localizedDescription)
            storage.writeResult(id: UUID().uuidString, text: nil, error: "Priming failed: \(error.localizedDescription)")
            tearDown()
        }
    }

    private func setupObservers() {
        guard !isObserving else { return }
        isObserving = true
        observer.add(name: DarwinNotifications.prime) { [weak self] in
            Task { @MainActor in self?.prime(suspendAfter: false) }
        }
        observer.add(name: DarwinNotifications.command) { [weak self] in
            Task { @MainActor in self?.handleKeyboardCommand() }
        }
        NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.handleKeyboardCommand() }
        }
    }

    private func activateAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        try? session.setActive(false, options: [.notifyOthersOnDeactivation])

        let options: AVAudioSession.CategoryOptions = [.defaultToSpeaker, .allowBluetoothHFP]
        do {
            try session.setCategory(.playAndRecord, mode: .default, options: options)
        } catch {
            try session.setCategory(.record, mode: .default, options: [])
        }
        if let input = session.availableInputs?.first {
            try? session.setPreferredInput(input)
        }
        try session.setActive(true, options: [])
        isSessionActive = true
        os_log(.info, log: sessionLog, "Audio session active")
    }

    private func startKeepAliveEngine() throws {
        if audioEngine.isRunning { return }
        let input = audioEngine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw NSError(
                domain: "FreeFlow",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Input format unavailable (sr=\(format.sampleRate) ch=\(format.channelCount))"]
            )
        }
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            guard let self, let file = self.audioFile else { return }
            try? file.write(from: buffer)
        }
        audioEngine.prepare()
        try audioEngine.start()
        os_log(.info, log: sessionLog, "Keep-alive engine running")
    }

    private func markPrimed() {
        let duration = storage.primedDurationSeconds
        storage.sessionPrimedUntil = Date().addingTimeInterval(duration)
        storage.recorderState = "primed"
    }

    private func beginBackgroundTaskIfNeeded() {
        guard backgroundTask == .invalid else { return }
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "FreeFlowSession") { [weak self] in
            Task { @MainActor in self?.tearDown() }
        }
    }

    private func scheduleExpiry() {
        expiryTimer?.invalidate()
        let duration = storage.primedDurationSeconds
        expiryTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.tearDown() }
        }
    }

    private func scheduleSelfSuspension() {
        suspensionWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard self != nil else { return }
            os_log(.info, log: sessionLog, "Suspending to return focus to previous app")
            let selector = NSSelectorFromString("suspend")
            if UIApplication.shared.responds(to: selector) {
                UIApplication.shared.perform(selector)
            }
        }
        suspensionWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    private func handleKeyboardCommand() {
        guard let command = storage.readCommand() else { return }
        guard command.id != handledCommandID else { return }
        handledCommandID = command.id
        os_log(.info, log: sessionLog, "Command id=%{public}@ action=%{public}@", command.id, command.action)

        switch command.action {
        case "start":
            startRecording(commandID: command.id)
        case "stop":
            stopRecordingAndProcess(commandID: command.id)
        case "cancel":
            cancelRecording()
        default:
            break
        }
    }

    private func startRecording(commandID: String) {
        do {
            if !isSessionActive { try activateAudioSession() }
            if !audioEngine.isRunning { try startKeepAliveEngine() }

            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("caf")
            let input = audioEngine.inputNode
            let format = input.outputFormat(forBus: 0)
            let file = try AVAudioFile(
                forWriting: tempURL,
                settings: format.settings,
                commonFormat: format.commonFormat,
                interleaved: format.isInterleaved
            )
            audioFile = file
            currentFileURL = tempURL
            storage.recorderState = "recording"
            scheduleExpiry()
            os_log(.info, log: sessionLog, "Recording → %{public}@", tempURL.lastPathComponent)
        } catch {
            os_log(.error, log: sessionLog, "startRecording failed: %{public}@", error.localizedDescription)
            storage.writeResult(id: commandID, text: nil, error: error.localizedDescription)
            storage.recorderState = "primed"
        }
    }

    private func stopRecordingAndProcess(commandID: String) {
        guard let fileURL = currentFileURL else {
            storage.writeResult(id: commandID, text: nil, error: "No recording in progress")
            return
        }
        audioFile = nil
        currentFileURL = nil
        storage.recorderState = "processing"

        let context = PipelineContext.load()
        Task { [fileURL, commandID] in
            let outcome = await self.pipeline.run(audioURL: fileURL, context: context)
            await MainActor.run {
                switch outcome {
                case .inserted(let text), .macro(_, let text):
                    self.storage.writeResult(id: commandID, text: text, error: nil)
                case .empty:
                    self.storage.writeResult(id: commandID, text: "", error: nil)
                case .failure(let message):
                    self.storage.writeResult(id: commandID, text: nil, error: message)
                }
                self.storage.recorderState = "primed"
                self.scheduleExpiry()
            }
        }
    }

    private func cancelRecording() {
        if let url = currentFileURL {
            try? FileManager.default.removeItem(at: url)
        }
        audioFile = nil
        currentFileURL = nil
        storage.recorderState = "primed"
    }

    private func tearDown() {
        os_log(.info, log: sessionLog, "Tearing down")
        expiryTimer?.invalidate()
        expiryTimer = nil
        suspensionWorkItem?.cancel()
        suspensionWorkItem = nil
        cancelRecording()
        if audioEngine.isRunning {
            audioEngine.inputNode.removeTap(onBus: 0)
            audioEngine.stop()
        }
        if isSessionActive {
            try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
            isSessionActive = false
        }
        storage.sessionPrimedUntil = nil
        storage.recorderState = "idle"
        if backgroundTask != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTask)
            backgroundTask = .invalid
        }
    }
}
