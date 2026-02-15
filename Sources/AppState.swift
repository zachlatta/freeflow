import Foundation
import Combine
import AppKit

class AppState: ObservableObject {
    private let apiKeyStorageKey = "groq_api_key"
    private let legacyAssemblyAIStorageKey = "assemblyai_api_key"
    private let customVocabularyStorageKey = "custom_vocabulary"
    private let pipelineHistoryStorageKey = "pipeline_history"
    private let transcribingIndicatorDelay: TimeInterval = 1.0
    private let maxPipelineHistoryCount = 20

    @Published var hasCompletedSetup: Bool {
        didSet {
            UserDefaults.standard.set(hasCompletedSetup, forKey: "hasCompletedSetup")
        }
    }

    @Published var apiKey: String {
        didSet {
            UserDefaults.standard.set(apiKey, forKey: apiKeyStorageKey)
            UserDefaults.standard.removeObject(forKey: legacyAssemblyAIStorageKey)
            contextService = AppContextService(apiKey: apiKey)
        }
    }

    @Published var selectedHotkey: HotkeyOption {
        didSet {
            UserDefaults.standard.set(selectedHotkey.rawValue, forKey: "hotkey_option")
            restartHotkeyMonitoring()
        }
    }

    @Published var customVocabulary: String {
        didSet {
            UserDefaults.standard.set(customVocabulary, forKey: customVocabularyStorageKey)
        }
    }

    @Published var isRecording = false
    @Published var isTranscribing = false
    @Published var lastTranscript: String = ""
    @Published var errorMessage: String?
    @Published var statusText: String = "Ready"
    @Published var hasAccessibility = false
    @Published var isDebugOverlayActive = false
    @Published var isDebugPanelVisible = false
    @Published var pipelineHistory: [PipelineHistoryItem] = [] {
        didSet {
            persistPipelineHistory()
        }
    }
    @Published var debugStatusMessage = "Idle"
    @Published var lastRawTranscript = ""
    @Published var lastPostProcessedTranscript = ""
    @Published var lastPostProcessingPrompt = ""
    @Published var lastContextSummary = ""
    @Published var lastPostProcessingStatus = ""
    @Published var lastContextScreenshotDataURL: String? = nil
    @Published var lastContextScreenshotStatus = "No screenshot"
    @Published var hasScreenRecordingPermission = false

    let audioRecorder = AudioRecorder()
    let hotkeyManager = HotkeyManager()
    let overlayManager = RecordingOverlayManager()
    private var accessibilityTimer: Timer?
    private var audioLevelCancellable: AnyCancellable?
    private var debugOverlayTimer: Timer?
    private var transcribingIndicatorTask: Task<Void, Never>?
    private var contextService: AppContextService
    private var contextCaptureTask: Task<AppContext?, Never>?
    private var capturedContext: AppContext?
    private var hasShownScreenshotPermissionAlert = false

    init() {
        let hasCompletedSetup = UserDefaults.standard.bool(forKey: "hasCompletedSetup")
        let apiKey = UserDefaults.standard.string(forKey: apiKeyStorageKey)
            ?? UserDefaults.standard.string(forKey: legacyAssemblyAIStorageKey)
            ?? ""
        let selectedHotkey = HotkeyOption(rawValue: UserDefaults.standard.string(forKey: "hotkey_option") ?? "fn") ?? .fnKey
        let customVocabulary = UserDefaults.standard.string(forKey: customVocabularyStorageKey) ?? ""
        let initialAccessibility = AXIsProcessTrusted()
        let initialScreenCapturePermission = CGPreflightScreenCaptureAccess()
        let savedHistory = Self.loadPipelineHistory(forKey: pipelineHistoryStorageKey)

        self.contextService = AppContextService(apiKey: apiKey)
        self.hasCompletedSetup = hasCompletedSetup
        self.apiKey = apiKey
        self.selectedHotkey = selectedHotkey
        self.customVocabulary = customVocabulary
        self.pipelineHistory = savedHistory
        self.hasAccessibility = initialAccessibility
        self.hasScreenRecordingPermission = initialScreenCapturePermission
    }

    private static func loadPipelineHistory(forKey key: String) -> [PipelineHistoryItem] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let items = try? JSONDecoder().decode([PipelineHistoryItem].self, from: data) else {
            return []
        }
        return items
    }

    private func persistPipelineHistory() {
        guard let data = try? JSONEncoder().encode(pipelineHistory) else { return }
        UserDefaults.standard.set(data, forKey: pipelineHistoryStorageKey)
    }

    func startAccessibilityPolling() {
        accessibilityTimer?.invalidate()
        hasAccessibility = AXIsProcessTrusted()
        hasScreenRecordingPermission = hasScreenCapturePermission()
        accessibilityTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                self?.hasAccessibility = AXIsProcessTrusted()
                self?.hasScreenRecordingPermission = self?.hasScreenCapturePermission() ?? false
            }
        }
    }

    func stopAccessibilityPolling() {
        accessibilityTimer?.invalidate()
        accessibilityTimer = nil
    }

    func openAccessibilitySettings() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    func hasScreenCapturePermission() -> Bool {
        CGPreflightScreenCaptureAccess()
    }

    func requestScreenCapturePermission() {
        let granted = CGRequestScreenCaptureAccess()
        hasScreenRecordingPermission = granted
        if !granted {
            openScreenCaptureSettings()
        }
    }

    func openScreenCaptureSettings() {
        let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
        if let url = settingsURL {
            NSWorkspace.shared.open(url)
        }
    }

    func startHotkeyMonitoring() {
        hotkeyManager.onKeyDown = { [weak self] in
            DispatchQueue.main.async {
                self?.handleHotkeyDown()
            }
        }
        hotkeyManager.onKeyUp = { [weak self] in
            DispatchQueue.main.async {
                self?.handleHotkeyUp()
            }
        }
        hotkeyManager.start(option: selectedHotkey)
    }

    private func restartHotkeyMonitoring() {
        hotkeyManager.start(option: selectedHotkey)
    }

    private func handleHotkeyDown() {
        guard !isRecording && !isTranscribing else { return }
        startRecording()
    }

    private func handleHotkeyUp() {
        guard isRecording else { return }
        stopAndTranscribe()
    }

    func toggleRecording() {
        if isRecording {
            stopAndTranscribe()
        } else {
            startRecording()
        }
    }

    private func startRecording() {
        guard hasAccessibility else {
            errorMessage = "Accessibility permission required. Grant access in System Settings > Privacy & Security > Accessibility."
            statusText = "No Accessibility"
            showAccessibilityAlert()
            return
        }
        errorMessage = nil
        do {
            try audioRecorder.startRecording()
            isRecording = true
            statusText = "Recording..."
            hasShownScreenshotPermissionAlert = false
            NSSound(named: "Tink")?.play()
            overlayManager.showRecording()
            startContextCapture()
            audioLevelCancellable = audioRecorder.$audioLevel
                .receive(on: DispatchQueue.main)
                .sink { [weak self] level in
                    self?.overlayManager.updateAudioLevel(level)
                }
        } catch {
            errorMessage = "Failed to start recording: \(error.localizedDescription)"
            statusText = "Error"
        }
    }

    func showAccessibilityAlert() {
        let alert = NSAlert()
        alert.messageText = "Accessibility Permission Required"
        alert.informativeText = "Voice to Text cannot type transcriptions without Accessibility access.\n\nGo to System Settings > Privacy & Security > Accessibility and enable Voice to Text."
        alert.alertStyle = .critical
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Dismiss")
        alert.icon = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: nil)

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            openAccessibilitySettings()
        }
    }

    private func stopAndTranscribe() {
        audioLevelCancellable?.cancel()
        audioLevelCancellable = nil
        debugStatusMessage = "Preparing audio"
        let sessionContext = capturedContext
        let inFlightContextTask = contextCaptureTask
        capturedContext = nil
        contextCaptureTask = nil
        lastRawTranscript = ""
        lastPostProcessedTranscript = ""
        lastContextSummary = ""
        lastPostProcessingStatus = ""
        lastPostProcessingPrompt = ""
        lastContextScreenshotDataURL = nil
        lastContextScreenshotStatus = "No screenshot"

        guard let fileURL = audioRecorder.stopRecording() else {
            errorMessage = "No audio recorded"
            isRecording = false
            statusText = "Error"
            return
        }
        isRecording = false
        isTranscribing = true
        statusText = "Transcribing..."
        debugStatusMessage = "Transcribing audio"
        errorMessage = nil
        NSSound(named: "Pop")?.play()
        overlayManager.slideUpToNotch { }

        transcribingIndicatorTask?.cancel()
        let indicatorDelay = transcribingIndicatorDelay
        transcribingIndicatorTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: UInt64(indicatorDelay * 1_000_000_000))
                await MainActor.run {
                    guard let self, self.isTranscribing else { return }
                    self.overlayManager.showTranscribing()
                }
            } catch {}
        }

        let transcriptionService = TranscriptionService(apiKey: apiKey)
        let postProcessingService = PostProcessingService(apiKey: apiKey)

        Task {
            do {
                async let transcript = transcriptionService.transcribe(fileURL: fileURL)
                let rawTranscript = try await transcript
                let appContext: AppContext
                if let sessionContext {
                    appContext = sessionContext
                } else if let inFlightContext = await inFlightContextTask?.value {
                    appContext = inFlightContext
                } else {
                    appContext = fallbackContextAtStop()
                }
                await MainActor.run { [weak self] in
                    self?.debugStatusMessage = "Running post-processing"
                }
                let finalTranscript: String
                let processingStatus: String
                let postProcessingPrompt: String
                do {
                    let postProcessingResult = try await postProcessingService.postProcess(
                        transcript: rawTranscript,
                        context: appContext,
                        customVocabulary: customVocabulary
                    )
                    finalTranscript = postProcessingResult.transcript
                    processingStatus = "Post-processing succeeded"
                    postProcessingPrompt = postProcessingResult.prompt
                } catch {
                    finalTranscript = rawTranscript
                    processingStatus = "Post-processing failed, using raw transcript"
                    postProcessingPrompt = ""
                }
                await MainActor.run {
                    self.lastContextSummary = appContext.contextSummary
                    self.lastContextScreenshotDataURL = appContext.screenshotDataURL
                    self.lastContextScreenshotStatus = appContext.screenshotError
                        ?? "available (\(appContext.screenshotMimeType ?? "image"))"
                    let trimmedRawTranscript = rawTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
                    let trimmedFinalTranscript = finalTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
                    self.lastPostProcessingPrompt = postProcessingPrompt
                    self.lastRawTranscript = trimmedRawTranscript
                    self.lastPostProcessedTranscript = trimmedFinalTranscript
                    self.lastPostProcessingStatus = processingStatus
                    self.recordPipelineHistoryEntry(
                        rawTranscript: trimmedRawTranscript,
                        postProcessedTranscript: trimmedFinalTranscript,
                        postProcessingPrompt: postProcessingPrompt,
                        context: appContext,
                        processingStatus: processingStatus
                    )
                    self.transcribingIndicatorTask?.cancel()
                    self.transcribingIndicatorTask = nil
                    self.lastTranscript = trimmedFinalTranscript
                    self.isTranscribing = false
                    self.debugStatusMessage = "Done"

                    if trimmedFinalTranscript.isEmpty {
                        self.statusText = "Nothing to transcribe"
                        self.overlayManager.dismiss()
                    } else {
                        self.statusText = "Copied to clipboard!"
                        self.overlayManager.showDone()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                            self.overlayManager.dismiss()
                        }

                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(trimmedFinalTranscript, forType: .string)

                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            self.pasteAtCursor()
                        }
                    }

                    self.audioRecorder.cleanup()

                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        if self.statusText == "Copied to clipboard!" || self.statusText == "Nothing to transcribe" {
                            self.statusText = "Ready"
                        }
                    }
                }
            } catch {
                let resolvedContext: AppContext
                if let sessionContext {
                    resolvedContext = sessionContext
                } else if let inFlightContext = await inFlightContextTask?.value {
                    resolvedContext = inFlightContext
                } else {
                    resolvedContext = fallbackContextAtStop()
                }
                await MainActor.run {
                    self.transcribingIndicatorTask?.cancel()
                    self.transcribingIndicatorTask = nil
                    self.errorMessage = error.localizedDescription
                    self.isTranscribing = false
                    self.statusText = "Error"
                    self.audioRecorder.cleanup()
                    self.overlayManager.dismiss()
                    self.lastPostProcessedTranscript = ""
                    self.lastRawTranscript = ""
                    self.lastContextSummary = ""
                    self.lastPostProcessingStatus = "Error: \(error.localizedDescription)"
                    self.lastPostProcessingPrompt = ""
                    self.lastContextScreenshotDataURL = resolvedContext.screenshotDataURL
                    self.lastContextScreenshotStatus = resolvedContext.screenshotError
                        ?? "available (\(resolvedContext.screenshotMimeType ?? "image"))"
                    self.recordPipelineHistoryEntry(
                        rawTranscript: "",
                        postProcessedTranscript: "",
                        postProcessingPrompt: "",
                        context: resolvedContext,
                        processingStatus: "Error: \(error.localizedDescription)"
                    )
                }
            }
        }
    }

    private func recordPipelineHistoryEntry(
        rawTranscript: String,
        postProcessedTranscript: String,
        postProcessingPrompt: String,
        context: AppContext,
        processingStatus: String
    ) {
        var entries = pipelineHistory
        let newEntry = PipelineHistoryItem(
            timestamp: Date(),
            rawTranscript: rawTranscript,
            postProcessedTranscript: postProcessedTranscript,
            postProcessingPrompt: postProcessingPrompt,
            contextSummary: context.contextSummary,
            contextScreenshotDataURL: context.screenshotDataURL,
            contextScreenshotStatus: context.screenshotError
                ?? "available (\(context.screenshotMimeType ?? "image"))",
            postProcessingStatus: processingStatus,
            debugStatus: debugStatusMessage,
            customVocabulary: customVocabulary
        )

        entries.insert(newEntry, at: 0)
        if entries.count > maxPipelineHistoryCount {
            entries = Array(entries.prefix(maxPipelineHistoryCount))
        }
        pipelineHistory = entries
    }

    private func startContextCapture() {
        contextCaptureTask?.cancel()
        capturedContext = nil
        lastContextSummary = "Collecting app context..."
        lastPostProcessingStatus = ""
        lastContextScreenshotDataURL = nil
        lastContextScreenshotStatus = "Collecting screenshot..."

        contextCaptureTask = Task { [weak self] in
            guard let self else { return nil }
            let context = await self.contextService.collectContext()
            await MainActor.run {
                self.capturedContext = context
                self.lastContextSummary = context.contextSummary
                self.lastContextScreenshotDataURL = context.screenshotDataURL
                self.lastContextScreenshotStatus = context.screenshotError
                    ?? "available (\(context.screenshotMimeType ?? "image"))"
                self.lastPostProcessingStatus = "App context captured"
                self.handleScreenshotCaptureIssue(context.screenshotError)
            }
            return context
        }
    }

    private func fallbackContextAtStop() -> AppContext {
        let frontmostApp = NSWorkspace.shared.frontmostApplication
        return AppContext(
            appName: frontmostApp?.localizedName,
            bundleIdentifier: frontmostApp?.bundleIdentifier,
            windowTitle: frontmostApp?.localizedName,
            selectedText: nil,
            currentActivity: "Could not refresh app context at stop time; using text-only post-processing.",
            screenshotDataURL: nil,
            screenshotMimeType: nil,
            screenshotError: "No app context captured before stop"
        )
    }

    private func handleScreenshotCaptureIssue(_ message: String?) {
        guard let message, !message.isEmpty else {
            hasShownScreenshotPermissionAlert = false
            return
        }

        errorMessage = "Screenshot capture issue: \(message)"
        NSSound(named: "Basso")?.play()

        if isScreenCapturePermissionError(message) && !hasShownScreenshotPermissionAlert {
            hasShownScreenshotPermissionAlert = true
            showScreenshotPermissionAlert(message: message)
            return
        }

        showScreenshotCaptureErrorAlert(message: message)
    }

    private func isScreenCapturePermissionError(_ message: String) -> Bool {
        let lowered = message.lowercased()
        return lowered.contains("permission") || lowered.contains("screen recording")
    }

    private func showScreenshotPermissionAlert(message: String) {
        let alert = NSAlert()
        alert.messageText = "Screen Recording Not Available"
        alert.informativeText = "\(message)\n\nOpen System Settings to grant Screen Recording permission."
        alert.alertStyle = .critical
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Continue Without Screenshot")
        alert.icon = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: nil)

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            openScreenCaptureSettings()
        }
    }

    private func showScreenshotCaptureErrorAlert(message: String) {
        let alert = NSAlert()
        alert.messageText = "Screenshot Capture Failed"
        alert.informativeText = "\(message)\n\nContext-aware post-processing will continue without a screenshot."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Dismiss")
        alert.icon = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: nil)
        _ = alert.runModal()
    }

    func toggleDebugOverlay() {
        if isDebugOverlayActive {
            stopDebugOverlay()
        } else {
            startDebugOverlay()
        }
    }

    private func startDebugOverlay() {
        isDebugOverlayActive = true
        overlayManager.showRecording()

        // Simulate audio levels with a timer
        var phase: Double = 0.0
        debugOverlayTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            phase += 0.15
            // Generate a fake audio level that oscillates like speech
            let base = 0.3 + 0.2 * sin(phase)
            let noise = Float.random(in: -0.15...0.15)
            let level = min(max(Float(base) + noise, 0.0), 1.0)
            self.overlayManager.updateAudioLevel(level)
        }
    }

    private func stopDebugOverlay() {
        debugOverlayTimer?.invalidate()
        debugOverlayTimer = nil
        isDebugOverlayActive = false
        overlayManager.dismiss()
    }

    func toggleDebugPanel() {
        isDebugPanelVisible.toggle()
        NotificationCenter.default.post(name: .toggleDebugPanel, object: nil)
    }

    private func pasteAtCursor() {
        let source = CGEventSource(stateID: .hidSystemState)

        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true)
        keyDown?.flags = .maskCommand
        keyDown?.post(tap: .cgSessionEventTap)

        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false)
        keyUp?.flags = .maskCommand
        keyUp?.post(tap: .cgSessionEventTap)
    }
}
