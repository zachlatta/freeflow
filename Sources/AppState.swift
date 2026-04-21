import Foundation
import Combine
import AppKit
import AVFoundation
import ServiceManagement
import ApplicationServices
import ScreenCaptureKit
import os.log
private let recordingLog = OSLog(subsystem: "com.zachlatta.freeflow", category: "Recording")

struct VoiceMacro: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var command: String
    var payload: String
}

struct PrecomputedMacro {
    let original: VoiceMacro
    let normalizedCommand: String
}

enum SettingsTab: String, CaseIterable, Identifiable {
    case general
    case prompts
    case macros
    case runLog

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "General"
        case .prompts: return "Prompts"
        case .macros: return "Voice Macros"
        case .runLog: return "Run Log"
        }
    }

    var icon: String {
        switch self {
        case .general: return "gearshape"
        case .prompts: return "text.bubble"
        case .macros: return "music.mic"
        case .runLog: return "clock.arrow.circlepath"
        }
    }
}

private struct PreservedPasteboardEntry {
    let type: NSPasteboard.PasteboardType
    let value: Value

    enum Value {
        case string(String)
        case propertyList(Any)
        case data(Data)
    }
}

private struct PreservedPasteboardItem {
    let entries: [PreservedPasteboardEntry]

    init(item: NSPasteboardItem) {
        self.entries = item.types.compactMap { type in
            if let string = item.string(forType: type) {
                return PreservedPasteboardEntry(type: type, value: .string(string))
            }
            if let propertyList = item.propertyList(forType: type) {
                return PreservedPasteboardEntry(type: type, value: .propertyList(propertyList))
            }
            if let data = item.data(forType: type) {
                return PreservedPasteboardEntry(type: type, value: .data(data))
            }
            return nil
        }
    }

    func makePasteboardItem() -> NSPasteboardItem {
        let item = NSPasteboardItem()
        for entry in entries {
            switch entry.value {
            case .string(let string):
                item.setString(string, forType: entry.type)
            case .propertyList(let propertyList):
                item.setPropertyList(propertyList, forType: entry.type)
            case .data(let data):
                item.setData(data, forType: entry.type)
            }
        }
        return item
    }
}

private struct PreservedPasteboardSnapshot {
    let items: [PreservedPasteboardItem]

    init(pasteboard: NSPasteboard) {
        self.items = (pasteboard.pasteboardItems ?? []).map(PreservedPasteboardItem.init)
    }

    func restore(to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        guard !items.isEmpty else { return }
        _ = pasteboard.writeObjects(items.map { $0.makePasteboardItem() })
    }
}

private struct PendingClipboardRestore {
    let snapshot: PreservedPasteboardSnapshot
    let expectedChangeCount: Int
}

private enum CommandInvocation: String {
    case automatic
    case manual
}

private enum SessionIntent {
    case dictation
    case command(invocation: CommandInvocation, selectedText: String)

    var isCommandMode: Bool {
        switch self {
        case .dictation:
            return false
        case .command:
            return true
        }
    }

    var persistedIntent: PipelineHistoryItemIntent {
        switch self {
        case .dictation:
            return .dictation
        case .command(let invocation, _):
            switch invocation {
            case .automatic:
                return .commandAutomatic
            case .manual:
                return .commandManual
            }
        }
    }

    var persistedSelectedText: String? {
        switch self {
        case .dictation:
            return nil
        case .command(_, let selectedText):
            return selectedText
        }
    }

    static func fromPersisted(intent: PipelineHistoryItemIntent, selectedText: String?) -> SessionIntent {
        if intent == .commandAutomatic, let selectedText {
            return .command(invocation: .automatic, selectedText: selectedText)
        }
        if intent == .commandManual, let selectedText {
            return .command(invocation: .manual, selectedText: selectedText)
        }
        return .dictation
    }
}

final class AppState: ObservableObject, @unchecked Sendable {
    private let apiKeyStorageKey = "groq_api_key"
    private let apiBaseURLStorageKey = "api_base_url"
    private let transcriptionModelStorageKey = "transcription_model"
    private let postProcessingModelStorageKey = "post_processing_model"
    private let postProcessingFallbackModelStorageKey = "post_processing_fallback_model"
    private let contextModelStorageKey = "context_model"
    private let holdShortcutStorageKey = "hold_shortcut"
    private let toggleShortcutStorageKey = "toggle_shortcut"
    private let savedHoldCustomShortcutStorageKey = "saved_hold_custom_shortcut"
    private let savedToggleCustomShortcutStorageKey = "saved_toggle_custom_shortcut"
    private let customVocabularyStorageKey = "custom_vocabulary"
    private let selectedMicrophoneStorageKey = "selected_microphone_id"
    private let customSystemPromptStorageKey = "custom_system_prompt"
    private let customContextPromptStorageKey = "custom_context_prompt"
    private let customSystemPromptLastModifiedStorageKey = "custom_system_prompt_last_modified"
    private let customContextPromptLastModifiedStorageKey = "custom_context_prompt_last_modified"
    private let contextScreenshotMaxDimensionStorageKey = "context_screenshot_max_dimension"
    private let shortcutStartDelayStorageKey = "shortcut_start_delay"
    private let preserveClipboardStorageKey = "preserve_clipboard"
    private let alertSoundsEnabledStorageKey = "alert_sounds_enabled"
    private let soundVolumeStorageKey = "sound_volume"
    private let voiceMacrosStorageKey = "voice_macros"
    private let commandModeEnabledStorageKey = "command_mode_enabled"
    private let commandModeStyleStorageKey = "command_mode_style"
    private let commandModeManualModifierStorageKey = "command_mode_manual_modifier"
    private let outputLanguageStorageKey = "output_language"
    private let transcribingIndicatorDelay: TimeInterval = 0.25
    private let clipboardRestoreDelay: TimeInterval = 0.15
    let maxPipelineHistoryCount = 20
    static let defaultContextScreenshotMaxDimension = Int(AppContextService.defaultScreenshotMaxDimension)
    static let contextScreenshotDimensionOptions = [1024, 768, 640, 512]
    static let defaultTranscriptionModel = "whisper-large-v3"
    static let defaultPostProcessingModel = "openai/gpt-oss-20b"
    static let defaultPostProcessingFallbackModel = "meta-llama/llama-4-scout-17b-16e-instruct"
    static let defaultContextModel = "meta-llama/llama-4-scout-17b-16e-instruct"

    @Published var hasCompletedSetup: Bool {
        didSet {
            UserDefaults.standard.set(hasCompletedSetup, forKey: "hasCompletedSetup")
        }
    }

    @Published var apiKey: String {
        didSet {
            persistAPIKey(apiKey)
            rebuildContextService()
        }
    }

    @Published var apiBaseURL: String {
        didSet {
            persistAPIBaseURL(apiBaseURL)
            rebuildContextService()
        }
    }

    @Published var transcriptionModel: String {
        didSet {
            UserDefaults.standard.set(transcriptionModel, forKey: transcriptionModelStorageKey)
        }
    }

    @Published var postProcessingModel: String {
        didSet {
            UserDefaults.standard.set(postProcessingModel, forKey: postProcessingModelStorageKey)
        }
    }

    @Published var postProcessingFallbackModel: String {
        didSet {
            UserDefaults.standard.set(postProcessingFallbackModel, forKey: postProcessingFallbackModelStorageKey)
        }
    }

    @Published var contextModel: String {
        didSet {
            UserDefaults.standard.set(contextModel, forKey: contextModelStorageKey)
            rebuildContextService()
        }
    }

    @Published var holdShortcut: ShortcutBinding {
        didSet {
            persistShortcut(holdShortcut, key: holdShortcutStorageKey)
            restartHotkeyMonitoring()
        }
    }

    @Published var toggleShortcut: ShortcutBinding {
        didSet {
            persistShortcut(toggleShortcut, key: toggleShortcutStorageKey)
            restartHotkeyMonitoring()
        }
    }

    @Published private(set) var savedHoldCustomShortcut: ShortcutBinding? {
        didSet {
            persistOptionalShortcut(savedHoldCustomShortcut, key: savedHoldCustomShortcutStorageKey)
        }
    }

    @Published private(set) var savedToggleCustomShortcut: ShortcutBinding? {
        didSet {
            persistOptionalShortcut(savedToggleCustomShortcut, key: savedToggleCustomShortcutStorageKey)
        }
    }

    @Published var isCommandModeEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isCommandModeEnabled, forKey: commandModeEnabledStorageKey)
            restartHotkeyMonitoring()
        }
    }

    @Published var commandModeStyle: CommandModeStyle {
        didSet {
            UserDefaults.standard.set(commandModeStyle.rawValue, forKey: commandModeStyleStorageKey)
            restartHotkeyMonitoring()
        }
    }

    @Published private(set) var commandModeManualModifier: CommandModeManualModifier {
        didSet {
            UserDefaults.standard.set(commandModeManualModifier.rawValue, forKey: commandModeManualModifierStorageKey)
            restartHotkeyMonitoring()
        }
    }

    @Published var customVocabulary: String {
        didSet {
            UserDefaults.standard.set(customVocabulary, forKey: customVocabularyStorageKey)
        }
    }

    @Published var customSystemPrompt: String {
        didSet {
            UserDefaults.standard.set(customSystemPrompt, forKey: customSystemPromptStorageKey)
        }
    }

    @Published var customContextPrompt: String {
        didSet {
            UserDefaults.standard.set(customContextPrompt, forKey: customContextPromptStorageKey)
            rebuildContextService()
        }
    }

    @Published var contextScreenshotMaxDimension: Int {
        didSet {
            let normalizedDimension = Self.normalizedContextScreenshotMaxDimension(contextScreenshotMaxDimension)
            if normalizedDimension != contextScreenshotMaxDimension {
                contextScreenshotMaxDimension = normalizedDimension
            }
            UserDefaults.standard.set(contextScreenshotMaxDimension, forKey: contextScreenshotMaxDimensionStorageKey)
            rebuildContextService()
        }
    }

    @Published var customSystemPromptLastModified: String {
        didSet {
            UserDefaults.standard.set(customSystemPromptLastModified, forKey: customSystemPromptLastModifiedStorageKey)
        }
    }

    @Published var customContextPromptLastModified: String {
        didSet {
            UserDefaults.standard.set(customContextPromptLastModified, forKey: customContextPromptLastModifiedStorageKey)
        }
    }

    @Published var outputLanguage: String {
        didSet {
            UserDefaults.standard.set(outputLanguage, forKey: outputLanguageStorageKey)
        }
    }

    @Published var shortcutStartDelay: TimeInterval {
        didSet {
            UserDefaults.standard.set(shortcutStartDelay, forKey: shortcutStartDelayStorageKey)
        }
    }

    @Published var preserveClipboard: Bool {
        didSet {
            UserDefaults.standard.set(preserveClipboard, forKey: preserveClipboardStorageKey)
        }
    }

    @Published var alertSoundsEnabled: Bool {
        didSet {
            UserDefaults.standard.set(alertSoundsEnabled, forKey: alertSoundsEnabledStorageKey)
        }
    }

    @Published var soundVolume: Float {
        didSet {
            UserDefaults.standard.set(soundVolume, forKey: soundVolumeStorageKey)
        }
    }

    private var precomputedMacros: [PrecomputedMacro] = []

    @Published var voiceMacros: [VoiceMacro] = [] {
        didSet {
            if let data = try? JSONEncoder().encode(voiceMacros) {
                UserDefaults.standard.set(data, forKey: voiceMacrosStorageKey)
            }
            precomputeMacros()
        }
    }

    @Published var isRecording = false
    @Published var isTranscribing = false
    @Published var retryingItemIDs: Set<UUID> = []
    @Published var lastTranscript: String = ""
    @Published var errorMessage: String?
    @Published var statusText: String = "Ready"
    @Published var hasAccessibility = false
    @Published var hotkeyMonitoringErrorMessage: String?
    @Published var isDebugOverlayActive = false
    @Published var selectedSettingsTab: SettingsTab? = .general
    @Published var pipelineHistory: [PipelineHistoryItem] = []
    @Published var debugStatusMessage = "Idle"
    @Published var lastRawTranscript = ""
    @Published var lastPostProcessedTranscript = ""
    @Published var lastPostProcessingPrompt = ""
    @Published var lastContextSummary = ""
    @Published var lastPostProcessingStatus = ""
    @Published var lastContextScreenshotDataURL: String? = nil
    @Published var lastContextScreenshotStatus = "No screenshot"
    @Published var hasScreenRecordingPermission = false
    @Published var launchAtLogin: Bool {
        didSet { setLaunchAtLogin(launchAtLogin) }
    }

    @Published var selectedMicrophoneID: String {
        didSet {
            UserDefaults.standard.set(selectedMicrophoneID, forKey: selectedMicrophoneStorageKey)
        }
    }
    @Published var availableMicrophones: [AudioDevice] = []

    let audioRecorder = AudioRecorder()
    let hotkeyManager = HotkeyManager()
    let overlayManager = RecordingOverlayManager()
    private var accessibilityTimer: Timer?
    private var audioLevelCancellable: AnyCancellable?
    private var debugOverlayTimer: Timer?
    private var recordingInitializationTimer: DispatchSourceTimer?
    private var transcribingIndicatorTask: Task<Void, Never>?
    private var transcriptionTask: Task<Void, Never>?
    private var transcribingAudioFileName: String?
    private var contextService: AppContextService
    private var contextCaptureTask: Task<AppContext?, Never>?
    private var capturedContext: AppContext?
    private var hasShownScreenshotPermissionAlert = false
    private var audioDeviceObservers: [NSObjectProtocol] = []
    private var needsMicrophoneRefreshAfterRecording = false
    private let pipelineHistoryStore = PipelineHistoryStore()
    private let shortcutSessionController = DictationShortcutSessionController()
    private var activeRecordingTriggerMode: RecordingTriggerMode?
    private var currentSessionIntent: SessionIntent = .dictation
    private var pendingSelectionSnapshot: AppSelectionSnapshot?
    private var pendingManualCommandInvocation = false
    private var pendingShortcutStartTask: Task<Void, Never>?
    private var pendingShortcutStartMode: RecordingTriggerMode?
    private var pendingOverlayDismissToken: UUID?
    private var shouldMonitorHotkeys = false
    private var isCapturingShortcut = false
    private var isAwaitingMicrophonePermission = false
    private var pendingMicrophonePermissionTriggerMode: RecordingTriggerMode?

    init() {
        UserDefaults.standard.removeObject(forKey: "force_http2_transcription")
        let hasCompletedSetup = UserDefaults.standard.bool(forKey: "hasCompletedSetup")
        let apiKey = Self.loadStoredAPIKey(account: apiKeyStorageKey)
        let apiBaseURL = Self.loadStoredAPIBaseURL(account: "api_base_url")
        let transcriptionModel = UserDefaults.standard.string(forKey: transcriptionModelStorageKey) ?? Self.defaultTranscriptionModel
        let postProcessingModel = UserDefaults.standard.string(forKey: postProcessingModelStorageKey) ?? Self.defaultPostProcessingModel
        let postProcessingFallbackModel = UserDefaults.standard.string(forKey: postProcessingFallbackModelStorageKey) ?? Self.defaultPostProcessingFallbackModel
        let contextModel = UserDefaults.standard.string(forKey: contextModelStorageKey) ?? Self.defaultContextModel
        let shortcuts = Self.loadShortcutConfiguration(
            holdKey: holdShortcutStorageKey,
            toggleKey: toggleShortcutStorageKey
        )
        let savedHoldCustomShortcut = Self.loadSavedCustomShortcut(
            forKey: savedHoldCustomShortcutStorageKey,
            fallback: shortcuts.hold.isCustom ? shortcuts.hold : nil
        )
        let savedToggleCustomShortcut = Self.loadSavedCustomShortcut(
            forKey: savedToggleCustomShortcutStorageKey,
            fallback: shortcuts.toggle.isCustom ? shortcuts.toggle : nil
        )
        let customVocabulary = UserDefaults.standard.string(forKey: customVocabularyStorageKey) ?? ""
        let customSystemPrompt = UserDefaults.standard.string(forKey: customSystemPromptStorageKey) ?? ""
        let customContextPrompt = UserDefaults.standard.string(forKey: customContextPromptStorageKey) ?? ""
        let customSystemPromptLastModified = UserDefaults.standard.string(forKey: customSystemPromptLastModifiedStorageKey) ?? ""
        let customContextPromptLastModified = UserDefaults.standard.string(forKey: customContextPromptLastModifiedStorageKey) ?? ""
        let outputLanguage = UserDefaults.standard.string(forKey: outputLanguageStorageKey) ?? ""
        let storedContextScreenshotMaxDimension = UserDefaults.standard.object(forKey: contextScreenshotMaxDimensionStorageKey) != nil
            ? UserDefaults.standard.integer(forKey: contextScreenshotMaxDimensionStorageKey)
            : Self.defaultContextScreenshotMaxDimension
        let contextScreenshotMaxDimension = Self.normalizedContextScreenshotMaxDimension(storedContextScreenshotMaxDimension)
        let shortcutStartDelay = max(0, UserDefaults.standard.double(forKey: shortcutStartDelayStorageKey))
        let isCommandModeEnabled = UserDefaults.standard.object(forKey: commandModeEnabledStorageKey) == nil
            ? false
            : UserDefaults.standard.bool(forKey: commandModeEnabledStorageKey)
        let commandModeStyle = CommandModeStyle(
            rawValue: UserDefaults.standard.string(forKey: commandModeStyleStorageKey) ?? ""
        ) ?? .automatic
        let commandModeManualModifier = CommandModeManualModifier(
            rawValue: UserDefaults.standard.string(forKey: commandModeManualModifierStorageKey) ?? ""
        ) ?? .option
        let preserveClipboard = UserDefaults.standard.object(forKey: preserveClipboardStorageKey) == nil
            ? true
            : UserDefaults.standard.bool(forKey: preserveClipboardStorageKey)
        let soundVolume: Float = UserDefaults.standard.object(forKey: soundVolumeStorageKey) != nil
            ? UserDefaults.standard.float(forKey: soundVolumeStorageKey) : 1.0
        let alertSoundsEnabled = UserDefaults.standard.object(forKey: alertSoundsEnabledStorageKey) != nil
            ? UserDefaults.standard.bool(forKey: alertSoundsEnabledStorageKey)
            : soundVolume > 0
        
        let initialMacros: [VoiceMacro]
        if let data = UserDefaults.standard.data(forKey: "voice_macros"),
           let decoded = try? JSONDecoder().decode([VoiceMacro].self, from: data) {
            initialMacros = decoded
        } else {
            initialMacros = []
        }

        let initialAccessibility = AXIsProcessTrusted()
        let initialScreenCapturePermission = CGPreflightScreenCaptureAccess()
        var removedAudioFileNames: [String] = []
        do {
            removedAudioFileNames = try pipelineHistoryStore.trim(to: maxPipelineHistoryCount)
        } catch {
            print("Failed to trim pipeline history during init: \(error)")
        }
        for audioFileName in removedAudioFileNames {
            Self.deleteAudioFile(audioFileName)
        }
        let savedHistory = pipelineHistoryStore.loadAllHistory()

        let selectedMicrophoneID = UserDefaults.standard.string(forKey: selectedMicrophoneStorageKey) ?? "default"

        self.contextService = Self.makeAppContextService(
            apiKey: apiKey,
            baseURL: apiBaseURL,
            customContextPrompt: customContextPrompt,
            contextModel: contextModel,
            contextScreenshotMaxDimension: contextScreenshotMaxDimension
        )
        self.hasCompletedSetup = hasCompletedSetup
        self.apiKey = apiKey
        self.apiBaseURL = apiBaseURL
        self.transcriptionModel = transcriptionModel
        self.postProcessingModel = postProcessingModel
        self.postProcessingFallbackModel = postProcessingFallbackModel
        self.contextModel = contextModel
        self.holdShortcut = shortcuts.hold
        self.toggleShortcut = shortcuts.toggle
        self.savedHoldCustomShortcut = savedHoldCustomShortcut.binding
        self.savedToggleCustomShortcut = savedToggleCustomShortcut.binding
        self.isCommandModeEnabled = isCommandModeEnabled
        self.commandModeStyle = commandModeStyle
        self.commandModeManualModifier = commandModeManualModifier
        self.customVocabulary = customVocabulary
        self.customSystemPrompt = customSystemPrompt
        self.customContextPrompt = customContextPrompt
        self.contextScreenshotMaxDimension = contextScreenshotMaxDimension
        self.customSystemPromptLastModified = customSystemPromptLastModified
        self.customContextPromptLastModified = customContextPromptLastModified
        self.outputLanguage = outputLanguage
        self.shortcutStartDelay = shortcutStartDelay
        self.preserveClipboard = preserveClipboard
        self.alertSoundsEnabled = alertSoundsEnabled
        self.soundVolume = soundVolume
        self.voiceMacros = initialMacros
        self.pipelineHistory = savedHistory
        self.hasAccessibility = initialAccessibility
        self.hasScreenRecordingPermission = initialScreenCapturePermission
        self.launchAtLogin = SMAppService.mainApp.status == .enabled
        self.selectedMicrophoneID = selectedMicrophoneID
        self.precomputeMacros()

        refreshAvailableMicrophones()
        installAudioDeviceObservers()

        if shortcuts.didUpdateHoldStoredValue {
            persistShortcut(shortcuts.hold, key: holdShortcutStorageKey)
        }
        if shortcuts.didUpdateToggleStoredValue {
            persistShortcut(shortcuts.toggle, key: toggleShortcutStorageKey)
        }
        if savedHoldCustomShortcut.didUpdateStoredValue {
            persistOptionalShortcut(savedHoldCustomShortcut.binding, key: savedHoldCustomShortcutStorageKey)
        }
        if savedToggleCustomShortcut.didUpdateStoredValue {
            persistOptionalShortcut(savedToggleCustomShortcut.binding, key: savedToggleCustomShortcutStorageKey)
        }

        overlayManager.onStopButtonPressed = { [weak self] in
            DispatchQueue.main.async {
                self?.handleOverlayStopButtonPressed()
            }
        }
    }

    deinit {
        removeAudioDeviceObservers()
    }

    private func removeAudioDeviceObservers() {
        let notificationCenter = NotificationCenter.default
        for observer in audioDeviceObservers {
            notificationCenter.removeObserver(observer)
        }
        audioDeviceObservers.removeAll()
    }

    private static func loadStoredAPIKey(account: String) -> String {
        if let storedKey = AppSettingsStorage.load(account: account), !storedKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return storedKey
        }
        return ""
    }

    private func persistAPIKey(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            AppSettingsStorage.delete(account: apiKeyStorageKey)
        } else {
            AppSettingsStorage.save(trimmed, account: apiKeyStorageKey)
        }
    }

    static let defaultAPIBaseURL = "https://api.groq.com/openai/v1"

    private struct StoredShortcutConfiguration {
        let hold: ShortcutBinding
        let toggle: ShortcutBinding
        let didUpdateHoldStoredValue: Bool
        let didUpdateToggleStoredValue: Bool
    }

    private struct StoredOptionalShortcut {
        let binding: ShortcutBinding?
        let didUpdateStoredValue: Bool
    }

    private struct StoredShortcutLoadResult {
        let binding: ShortcutBinding?
        let hadStoredValue: Bool
        let didNormalize: Bool
    }

    private static func loadStoredAPIBaseURL(account: String) -> String {
        if let stored = AppSettingsStorage.load(account: account), !stored.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return stored
        }
        return defaultAPIBaseURL
    }

    private static func loadShortcutConfiguration(holdKey: String, toggleKey: String) -> StoredShortcutConfiguration {
        let legacyPreset = ShortcutPreset(
            rawValue: UserDefaults.standard.string(forKey: "hotkey_option") ?? ShortcutPreset.fnKey.rawValue
        ) ?? .fnKey
        let hold = legacyPreset.binding
        let toggle = hold.withAddedModifiers(.command)
        let storedHold = loadShortcut(forKey: holdKey)
        let storedToggle = loadShortcut(forKey: toggleKey)
        return StoredShortcutConfiguration(
            hold: storedHold.binding ?? hold,
            toggle: storedToggle.binding ?? toggle,
            didUpdateHoldStoredValue: storedHold.binding == nil || storedHold.didNormalize,
            didUpdateToggleStoredValue: storedToggle.binding == nil || storedToggle.didNormalize
        )
    }

    private static func loadShortcut(forKey key: String) -> StoredShortcutLoadResult {
        guard let data = UserDefaults.standard.data(forKey: key) else {
            return StoredShortcutLoadResult(binding: nil, hadStoredValue: false, didNormalize: false)
        }
        guard let decoded = try? JSONDecoder().decode(ShortcutBinding.self, from: data) else {
            return StoredShortcutLoadResult(binding: nil, hadStoredValue: true, didNormalize: false)
        }
        let normalized = decoded.normalizedForStorageMigration()
        return StoredShortcutLoadResult(
            binding: normalized,
            hadStoredValue: true,
            didNormalize: normalized != decoded
        )
    }

    private static func loadSavedCustomShortcut(
        forKey key: String,
        fallback: ShortcutBinding?
    ) -> StoredOptionalShortcut {
        let stored = loadShortcut(forKey: key)
        if let binding = stored.binding {
            return StoredOptionalShortcut(binding: binding, didUpdateStoredValue: stored.didNormalize)
        }

        return StoredOptionalShortcut(
            binding: fallback,
            didUpdateStoredValue: stored.hadStoredValue || fallback != nil
        )
    }

    static func normalizedContextScreenshotMaxDimension(_ value: Int) -> Int {
        contextScreenshotDimensionOptions.contains(value)
            ? value
            : defaultContextScreenshotMaxDimension
    }

    static func makeAppContextService(
        apiKey: String,
        baseURL: String,
        customContextPrompt: String,
        contextModel: String,
        contextScreenshotMaxDimension: Int
    ) -> AppContextService {
        AppContextService(
            apiKey: apiKey,
            baseURL: baseURL,
            customContextPrompt: customContextPrompt,
            contextModel: contextModel,
            screenshotMaxDimension: CGFloat(normalizedContextScreenshotMaxDimension(contextScreenshotMaxDimension))
        )
    }

    func makeAppContextService() -> AppContextService {
        Self.makeAppContextService(
            apiKey: apiKey,
            baseURL: apiBaseURL,
            customContextPrompt: customContextPrompt,
            contextModel: contextModel,
            contextScreenshotMaxDimension: contextScreenshotMaxDimension
        )
    }

    private func rebuildContextService() {
        contextService = makeAppContextService()
    }

    private func persistAPIBaseURL(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == Self.defaultAPIBaseURL {
            AppSettingsStorage.delete(account: apiBaseURLStorageKey)
        } else {
            AppSettingsStorage.save(trimmed, account: apiBaseURLStorageKey)
        }
    }

    private func persistShortcut(_ binding: ShortcutBinding, key: String) {
        let normalizedBinding = binding.normalizedForStorageMigration()
        guard let data = try? JSONEncoder().encode(normalizedBinding) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    private func persistOptionalShortcut(_ binding: ShortcutBinding?, key: String) {
        guard let binding else {
            UserDefaults.standard.removeObject(forKey: key)
            return
        }
        persistShortcut(binding, key: key)
    }

    struct SavedAudioFile {
        let fileName: String
        let fileURL: URL
    }

    static func audioStorageDirectory() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appName = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "FreeFlow"
        let audioDir = appSupport.appendingPathComponent("\(appName)/audio", isDirectory: true)
        if !FileManager.default.fileExists(atPath: audioDir.path) {
            try? FileManager.default.createDirectory(at: audioDir, withIntermediateDirectories: true)
        }
        return audioDir
    }

    static func saveAudioFile(from tempURL: URL) -> SavedAudioFile? {
        let fileName = UUID().uuidString + ".wav"
        let destURL = audioStorageDirectory().appendingPathComponent(fileName)
        do {
            try AudioNormalization.writePreferredAudioCopy(from: tempURL, to: destURL)
            return SavedAudioFile(fileName: fileName, fileURL: destURL)
        } catch {
            return nil
        }
    }

    private static func deleteAudioFile(_ fileName: String) {
        let fileURL = audioStorageDirectory().appendingPathComponent(fileName)
        try? FileManager.default.removeItem(at: fileURL)
    }

    func clearPipelineHistory() {
        do {
            let removedAudioFileNames = try pipelineHistoryStore.clearAll()
            for audioFileName in removedAudioFileNames {
                Self.deleteAudioFile(audioFileName)
            }
            pipelineHistory = []
        } catch {
            errorMessage = "Unable to clear run history: \(error.localizedDescription)"
        }
    }

    func deleteHistoryEntry(id: UUID) {
        guard let index = pipelineHistory.firstIndex(where: { $0.id == id }) else { return }
        do {
            if let audioFileName = try pipelineHistoryStore.delete(id: id) {
                Self.deleteAudioFile(audioFileName)
            }
            pipelineHistory.remove(at: index)
        } catch {
            errorMessage = "Unable to delete run history entry: \(error.localizedDescription)"
        }
    }

    func retryTranscription(item: PipelineHistoryItem) {
        guard let audioFileName = item.audioFileName else { return }
        guard !retryingItemIDs.contains(item.id) else { return }

        retryingItemIDs.insert(item.id)

        let audioURL = Self.audioStorageDirectory().appendingPathComponent(audioFileName)
        guard FileManager.default.fileExists(atPath: audioURL.path) else {
            retryingItemIDs.remove(item.id)
            errorMessage = "Audio file not found for retry."
            return
        }

        let restoredContext = AppContext(
            appName: nil,
            bundleIdentifier: nil,
            windowTitle: nil,
            selectedText: nil,
            currentActivity: item.contextSummary,
            contextPrompt: item.contextPrompt,
            screenshotDataURL: item.contextScreenshotDataURL,
            screenshotMimeType: item.contextScreenshotDataURL != nil ? "image/jpeg" : nil,
            screenshotError: nil
        )

        let postProcessingService = PostProcessingService(
            apiKey: apiKey,
            baseURL: apiBaseURL,
            preferredModel: postProcessingModel,
            preferredFallbackModel: postProcessingFallbackModel
        )
        let capturedCustomVocabulary = customVocabulary
        let capturedCustomSystemPrompt = customSystemPrompt

        Task {
            do {
                let transcriptionService = try TranscriptionService(
                    apiKey: apiKey,
                    baseURL: apiBaseURL,
                    transcriptionModel: transcriptionModel
                )
                let rawTranscript = try await transcriptionService.transcribe(fileURL: audioURL)

                let finalTranscript: String
                let processingStatus: String
                let postProcessingPrompt: String
                let restoredIntent = SessionIntent.fromPersisted(
                    intent: item.intent,
                    selectedText: item.selectedText
                )
                let result = await self.processTranscript(
                    rawTranscript,
                    intent: restoredIntent,
                    context: restoredContext,
                    postProcessingService: postProcessingService,
                    customVocabulary: capturedCustomVocabulary,
                    customSystemPrompt: capturedCustomSystemPrompt,
                    outputLanguage: self.outputLanguage
                )
                finalTranscript = result.finalTranscript
                processingStatus = result.outcome.statusMessage(isRetry: true)
                postProcessingPrompt = result.prompt

                await MainActor.run {
                    let updatedItem = PipelineHistoryItem(
                        intent: item.intent,
                        selectedText: item.selectedText,
                        id: item.id,
                        timestamp: item.timestamp,
                        rawTranscript: rawTranscript.trimmingCharacters(in: .whitespacesAndNewlines),
                        postProcessedTranscript: finalTranscript.trimmingCharacters(in: .whitespacesAndNewlines),
                        postProcessingPrompt: postProcessingPrompt,
                        contextSummary: item.contextSummary,
                        contextPrompt: item.contextPrompt,
                        contextScreenshotDataURL: item.contextScreenshotDataURL,
                        contextScreenshotStatus: item.contextScreenshotStatus,
                        postProcessingStatus: processingStatus,
                        debugStatus: "Retried",
                        customVocabulary: item.customVocabulary,
                        audioFileName: item.audioFileName
                    )
                    do {
                        try pipelineHistoryStore.update(updatedItem)
                        pipelineHistory = pipelineHistoryStore.loadAllHistory()
                    } catch {
                        errorMessage = "Failed to save retry result: \(error.localizedDescription)"
                    }
                    retryingItemIDs.remove(item.id)
                }
            } catch {
                await MainActor.run {
                    let updatedItem = PipelineHistoryItem(
                        intent: item.intent,
                        selectedText: item.selectedText,
                        id: item.id,
                        timestamp: item.timestamp,
                        rawTranscript: item.rawTranscript,
                        postProcessedTranscript: item.postProcessedTranscript,
                        postProcessingPrompt: item.postProcessingPrompt,
                        contextSummary: item.contextSummary,
                        contextPrompt: item.contextPrompt,
                        contextScreenshotDataURL: item.contextScreenshotDataURL,
                        contextScreenshotStatus: item.contextScreenshotStatus,
                        postProcessingStatus: "Error: \(error.localizedDescription)",
                        debugStatus: "Retry failed",
                        customVocabulary: item.customVocabulary,
                        audioFileName: item.audioFileName
                    )
                    do {
                        try pipelineHistoryStore.update(updatedItem)
                        pipelineHistory = pipelineHistoryStore.loadAllHistory()
                    } catch {}
                    retryingItemIDs.remove(item.id)
                }
            }
        }
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

    func openMicrophoneSettings() {
        let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
        if let url = settingsURL {
            NSWorkspace.shared.open(url)
        }
    }

    func requestMicrophoneAccess(completion: @escaping (Bool) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            refreshAvailableMicrophones()
            DispatchQueue.main.async {
                completion(true)
            }
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                DispatchQueue.main.async {
                    if granted {
                        self?.refreshAvailableMicrophones()
                    }
                    completion(granted)
                }
            }
        case .denied, .restricted:
            openMicrophoneSettings()
            DispatchQueue.main.async {
                completion(false)
            }
        @unknown default:
            openMicrophoneSettings()
            DispatchQueue.main.async {
                completion(false)
            }
        }
    }

    func hasScreenCapturePermission() -> Bool {
        CGPreflightScreenCaptureAccess()
    }

    func requestScreenCapturePermission() {
        // ScreenCaptureKit triggers the "Screen & System Audio Recording"
        // permission dialog on macOS Sequoia+, correctly identifying the
        // running app (unlike the legacy CGWindowListCreateImage path).
        SCShareableContent.getExcludingDesktopWindows(false, onScreenWindowsOnly: false) { [weak self] _, _ in
            DispatchQueue.main.async {
                self?.hasScreenRecordingPermission = CGPreflightScreenCaptureAccess()
            }
        }

        hasScreenRecordingPermission = CGPreflightScreenCaptureAccess()
    }

    func openScreenCaptureSettings() {
        let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
        if let url = settingsURL {
            NSWorkspace.shared.open(url)
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // Revert the toggle on failure without re-triggering didSet
            let current = SMAppService.mainApp.status == .enabled
            if current != launchAtLogin {
                launchAtLogin = current
            }
        }
    }

    func refreshLaunchAtLoginStatus() {
        let current = SMAppService.mainApp.status == .enabled
        if current != launchAtLogin {
            launchAtLogin = current
        }
    }

    func refreshAvailableMicrophones() {
        guard !isRecording, !audioRecorder.isRecording else {
            needsMicrophoneRefreshAfterRecording = true
            return
        }

        needsMicrophoneRefreshAfterRecording = false
        availableMicrophones = AudioDevice.availableInputDevices()
    }

    private func refreshAvailableMicrophonesIfNeeded() {
        guard needsMicrophoneRefreshAfterRecording else { return }
        refreshAvailableMicrophones()
    }

    private func installAudioDeviceObservers() {
        removeAudioDeviceObservers()

        let notificationCenter = NotificationCenter.default
        let refreshOnAudioDeviceChange: (Notification) -> Void = { [weak self] notification in
            guard let device = notification.object as? AVCaptureDevice,
                  device.hasMediaType(.audio) else {
                return
            }
            self?.refreshAvailableMicrophones()
        }

        audioDeviceObservers.append(
            notificationCenter.addObserver(
                forName: .AVCaptureDeviceWasConnected,
                object: nil,
                queue: .main,
                using: refreshOnAudioDeviceChange
            )
        )
        audioDeviceObservers.append(
            notificationCenter.addObserver(
                forName: .AVCaptureDeviceWasDisconnected,
                object: nil,
                queue: .main,
                using: refreshOnAudioDeviceChange
            )
        )
    }

    var usesFnShortcut: Bool {
        holdShortcut.usesFnKey || toggleShortcut.usesFnKey
    }

    var hasEnabledHoldShortcut: Bool {
        !holdShortcut.isDisabled
    }

    var hasEnabledToggleShortcut: Bool {
        !toggleShortcut.isDisabled
    }

    var shortcutStatusText: String {
        if hotkeyMonitoringErrorMessage != nil {
            return "Global shortcuts unavailable"
        }

        switch (hasEnabledHoldShortcut, hasEnabledToggleShortcut) {
        case (true, true):
            return "Hold \(holdShortcut.displayName) or tap \(toggleShortcut.displayName) to dictate"
        case (true, false):
            return "Hold \(holdShortcut.displayName) to dictate"
        case (false, true):
            return "Tap \(toggleShortcut.displayName) to dictate"
        case (false, false):
            return "No dictation shortcut enabled"
        }
    }

    var shortcutStartDelayMilliseconds: Int {
        Int((shortcutStartDelay * 1000).rounded())
    }

    func savedCustomShortcut(for role: ShortcutRole) -> ShortcutBinding? {
        switch role {
        case .hold:
            return savedHoldCustomShortcut
        case .toggle:
            return savedToggleCustomShortcut
        }
    }

    var commandModeManualModifierValidationMessage: String? {
        guard isCommandModeEnabled, commandModeStyle == .manual else { return nil }
        return commandModeManualModifierCollisionMessage(for: commandModeManualModifier)
    }

    @discardableResult
    func setCommandModeEnabled(_ enabled: Bool) -> String? {
        isCommandModeEnabled = enabled
        if enabled, commandModeStyle == .manual {
            return commandModeManualModifierCollisionMessage(for: commandModeManualModifier)
        }
        return nil
    }

    @discardableResult
    func setCommandModeStyle(_ style: CommandModeStyle) -> String? {
        commandModeStyle = style
        if isCommandModeEnabled, style == .manual {
            return commandModeManualModifierCollisionMessage(for: commandModeManualModifier)
        }
        return nil
    }

    @discardableResult
    func setCommandModeManualModifier(_ modifier: CommandModeManualModifier) -> String? {
        if isCommandModeEnabled,
           commandModeStyle == .manual,
           let message = commandModeManualModifierCollisionMessage(for: modifier) {
            return message
        }

        commandModeManualModifier = modifier
        return nil
    }

    @discardableResult
    func setShortcut(_ binding: ShortcutBinding, for role: ShortcutRole) -> String? {
        let binding = binding.normalizedForStorageMigration()
        let nextHoldShortcut = role == .hold ? binding : holdShortcut
        let nextToggleShortcut = role == .toggle ? binding : toggleShortcut
        let otherBinding = role == .hold ? toggleShortcut : holdShortcut
        if binding.isDisabled && otherBinding.isDisabled {
            return "At least one shortcut must remain enabled."
        }
        guard !binding.conflicts(with: otherBinding) else {
            return "Hold and tap shortcuts must be distinct."
        }
        if isCommandModeEnabled,
           commandModeStyle == .manual,
           let message = commandModeManualModifierCollisionMessage(
            for: commandModeManualModifier,
            holdBinding: nextHoldShortcut,
            toggleBinding: nextToggleShortcut
           ) {
            return message
        }

        switch role {
        case .hold:
            if binding.isCustom {
                savedHoldCustomShortcut = binding
            }
            holdShortcut = binding
        case .toggle:
            if binding.isCustom {
                savedToggleCustomShortcut = binding
            }
            toggleShortcut = binding
        }

        return nil
    }

    private func commandModeManualModifierCollisionMessage(
        for modifier: CommandModeManualModifier,
        holdBinding: ShortcutBinding? = nil,
        toggleBinding: ShortcutBinding? = nil
    ) -> String? {
        let holdBinding = holdBinding ?? holdShortcut
        let toggleBinding = toggleBinding ?? toggleShortcut
        let manualModifier = modifier.shortcutModifier

        if !holdBinding.isDisabled && holdBinding.modifiers.contains(manualModifier) {
            return "That modifier is already part of the hold shortcut."
        }
        if !toggleBinding.isDisabled && toggleBinding.modifiers.contains(manualModifier) {
            return "That modifier is already part of the tap shortcut."
        }

        return nil
    }

    func startHotkeyMonitoring() {
        shouldMonitorHotkeys = true
        hotkeyManager.onShortcutEvent = { [weak self] event in
            DispatchQueue.main.async {
                self?.handleShortcutEvent(event)
            }
        }
        hotkeyManager.onEscapeKeyPressed = { [weak self] in
            self?.handleEscapeKeyPress() ?? false
        }
        restartHotkeyMonitoring()
    }

    func stopHotkeyMonitoring() {
        shouldMonitorHotkeys = false
        hotkeyMonitoringErrorMessage = nil
        hotkeyManager.onShortcutEvent = nil
        hotkeyManager.onEscapeKeyPressed = nil
        hotkeyManager.stop()
    }

    func suspendHotkeyMonitoringForShortcutCapture() {
        isCapturingShortcut = true
        restartHotkeyMonitoring()
    }

    func resumeHotkeyMonitoringAfterShortcutCapture() {
        isCapturingShortcut = false
        restartHotkeyMonitoring()
    }

    private var activeShortcutConfiguration: ShortcutConfiguration {
        let permittedAdditionalExactMatchModifiers: ShortcutModifiers
        if isCommandModeEnabled, commandModeStyle == .manual {
            permittedAdditionalExactMatchModifiers = commandModeManualModifier.shortcutModifier
        } else {
            permittedAdditionalExactMatchModifiers = []
        }

        return ShortcutConfiguration(
            hold: holdShortcut,
            toggle: toggleShortcut,
            permittedAdditionalExactMatchModifiers: permittedAdditionalExactMatchModifiers
        )
    }

    private func restartHotkeyMonitoring() {
        guard shouldMonitorHotkeys, !isCapturingShortcut, !isAwaitingMicrophonePermission else {
            hotkeyManager.stop()
            return
        }

        do {
            try hotkeyManager.start(configuration: activeShortcutConfiguration)
            hotkeyMonitoringErrorMessage = nil
        } catch {
            hotkeyMonitoringErrorMessage = error.localizedDescription
            os_log(.error, log: recordingLog, "Hotkey monitoring failed to start: %{public}@", error.localizedDescription)
        }
    }

    private func handleShortcutEvent(_ event: ShortcutEvent) {
        guard let action = shortcutSessionController.handle(event: event, isTranscribing: isTranscribing) else {
            return
        }

        switch action {
        case .start(let mode):
            os_log(.info, log: recordingLog, "Shortcut start fired for mode %{public}@", mode.rawValue)
            scheduleShortcutStart(mode: mode)
        case .stop:
            cancelPendingShortcutStart()
            guard isRecording else {
                shortcutSessionController.reset()
                activeRecordingTriggerMode = nil
                return
            }
            stopAndTranscribe()
        case .switchedToToggle:
            if isRecording {
                activeRecordingTriggerMode = .toggle
                overlayManager.setRecordingTriggerMode(.toggle, animated: true)
            } else if pendingShortcutStartMode != nil {
                pendingShortcutStartMode = .toggle
            }
        }
    }

    private func handleEscapeKeyPress() -> Bool {
        if isTranscribing {
            cancelTranscription()
            return true
        }

        if pendingShortcutStartMode == .toggle || activeRecordingTriggerMode == .toggle {
            cancelToggleShortcutSession()
            return true
        }

        return false
    }

    func toggleRecording() {
        os_log(.info, log: recordingLog, "toggleRecording() called, isRecording=%{public}d", isRecording)
        cancelPendingShortcutStart()
        if isRecording {
            stopAndTranscribe()
        } else {
            shortcutSessionController.beginManual(mode: .toggle)
            startRecording(triggerMode: .toggle)
        }
    }

    private func handleOverlayStopButtonPressed() {
        guard isRecording, activeRecordingTriggerMode == .toggle else { return }
        stopAndTranscribe()
    }

    private func cancelToggleShortcutSession() {
        guard pendingShortcutStartMode == .toggle || activeRecordingTriggerMode == .toggle else { return }

        cancelPendingShortcutStart()
        shortcutSessionController.reset()
        activeRecordingTriggerMode = nil
        audioRecorder.onRecordingReady = nil
        audioRecorder.onRecordingFailure = nil
        audioLevelCancellable?.cancel()
        audioLevelCancellable = nil
        cancelRecordingInitializationTimer()
        contextCaptureTask?.cancel()
        contextCaptureTask = nil
        capturedContext = nil
        currentSessionIntent = .dictation
        isRecording = false
        errorMessage = nil
        debugStatusMessage = "Cancelled"
        statusText = "Cancelled"
        overlayManager.dismiss()
        audioRecorder.cancelRecording()
        refreshAvailableMicrophonesIfNeeded()
        if !isRecording && !isTranscribing && statusText == "Cancelled" {
            scheduleReadyStatusReset(after: 2, matching: ["Cancelled"])
        }
    }

    private func cancelTranscription() {
        guard isTranscribing else { return }

        transcriptionTask?.cancel()
        transcriptionTask = nil
        transcribingIndicatorTask?.cancel()
        transcribingIndicatorTask = nil
        contextCaptureTask?.cancel()
        contextCaptureTask = nil
        capturedContext = nil
        shortcutSessionController.reset()
        activeRecordingTriggerMode = nil
        currentSessionIntent = .dictation
        isRecording = false
        isTranscribing = false
        errorMessage = nil
        debugStatusMessage = "Cancelled"
        statusText = "Cancelled"
        overlayManager.dismiss()
        audioRecorder.cleanup()
        if let transcribingAudioFileName {
            Self.deleteAudioFile(transcribingAudioFileName)
            self.transcribingAudioFileName = nil
        }
        refreshAvailableMicrophonesIfNeeded()
        if !isRecording && !isTranscribing && statusText == "Cancelled" {
            scheduleReadyStatusReset(after: 2, matching: ["Cancelled"])
        }
    }

    private func scheduleShortcutStart(mode: RecordingTriggerMode) {
        cancelPendingShortcutStart(resetMode: false)
        pendingSelectionSnapshot = contextService.collectSelectionSnapshot()
        pendingManualCommandInvocation = hotkeyManager.currentPressedModifiers.contains(
            commandModeManualModifier.shortcutModifier
        )
        pendingShortcutStartMode = mode
        let delay = shortcutStartDelay

        guard delay > 0 else {
            pendingShortcutStartMode = nil
            startRecording(triggerMode: mode)
            return
        }

        pendingShortcutStartTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            } catch {
                return
            }

            await MainActor.run { [weak self] in
                guard let self, let pendingMode = self.pendingShortcutStartMode else { return }
                self.pendingShortcutStartTask = nil
                self.pendingShortcutStartMode = nil
                self.startRecording(triggerMode: pendingMode)
            }
        }
    }

    private func cancelPendingShortcutStart(resetMode: Bool = true) {
        pendingShortcutStartTask?.cancel()
        pendingShortcutStartTask = nil
        pendingSelectionSnapshot = nil
        pendingManualCommandInvocation = false
        if resetMode {
            pendingShortcutStartMode = nil
        }
    }

    private func resolveSessionIntent(
        triggerMode: RecordingTriggerMode,
        selectionSnapshot: AppSelectionSnapshot,
        manualCommandRequested: Bool
    ) -> SessionIntent? {
        guard isCommandModeEnabled else {
            return .dictation
        }

        let rawSelectedText = selectionSnapshot.selectedText ?? ""
        let trimmedSelectedText = rawSelectedText.trimmingCharacters(in: .whitespacesAndNewlines)

        switch commandModeStyle {
        case .automatic:
            if !trimmedSelectedText.isEmpty {
                return .command(invocation: .automatic, selectedText: rawSelectedText)
            }
            return .dictation
        case .manual:
            if let message = commandModeManualModifierCollisionMessage(for: commandModeManualModifier) {
                rejectInvalidCommandModeModifier(triggerMode: triggerMode, message: message)
                return nil
            }
            guard manualCommandRequested else {
                return .dictation
            }
            guard !trimmedSelectedText.isEmpty else {
                rejectCommandModeSelectionRequirement(triggerMode: triggerMode)
                return nil
            }
            return .command(invocation: .manual, selectedText: rawSelectedText)
        }
    }

    private func rejectCommandModeSelectionRequirement(triggerMode: RecordingTriggerMode) {
        currentSessionIntent = .dictation
        activeRecordingTriggerMode = nil
        pendingSelectionSnapshot = nil
        pendingManualCommandInvocation = false
        errorMessage = "Select text to transform first."
        statusText = "Select text to transform first"
        debugStatusMessage = "Edit mode requires selected text"
        shortcutSessionController.reset()
        if triggerMode == .toggle {
            cancelPendingShortcutStart()
        }
        playAlertSound(named: "Basso")
        scheduleReadyStatusReset(after: 2, matching: ["Select text to transform first"])
    }

    private func rejectInvalidCommandModeModifier(triggerMode: RecordingTriggerMode, message: String) {
        currentSessionIntent = .dictation
        activeRecordingTriggerMode = nil
        pendingSelectionSnapshot = nil
        pendingManualCommandInvocation = false
        errorMessage = message
        statusText = "Fix Edit Mode modifier"
        debugStatusMessage = "Edit mode modifier conflicts with dictation shortcuts"
        shortcutSessionController.reset()
        if triggerMode == .toggle {
            cancelPendingShortcutStart()
        }
        playAlertSound(named: "Basso")
        scheduleReadyStatusReset(after: 2, matching: ["Fix Edit Mode modifier"])
    }

    private func startRecording(triggerMode: RecordingTriggerMode) {
        let t0 = CFAbsoluteTimeGetCurrent()
        os_log(.info, log: recordingLog, "startRecording() entered")
        guard !isRecording && !isTranscribing else { return }
        let scheduledSelectionSnapshot = pendingSelectionSnapshot
        let scheduledManualCommandInvocation = pendingManualCommandInvocation
        cancelPendingShortcutStart()
        guard prepareRecordingStart(
            triggerMode: triggerMode,
            selectionSnapshot: scheduledSelectionSnapshot,
            manualCommandRequested: scheduledSelectionSnapshot == nil
                ? hotkeyManager.currentPressedModifiers.contains(commandModeManualModifier.shortcutModifier)
                : scheduledManualCommandInvocation,
            startedAt: t0
        ) else { return }
        guard ensureMicrophoneAccess() else { return }
        os_log(.info, log: recordingLog, "mic access check passed: %.3fms", (CFAbsoluteTimeGetCurrent() - t0) * 1000)
        beginRecording(triggerMode: triggerMode)
        os_log(.info, log: recordingLog, "startRecording() finished: %.3fms", (CFAbsoluteTimeGetCurrent() - t0) * 1000)
    }

    private func prepareRecordingStart(
        triggerMode: RecordingTriggerMode,
        selectionSnapshot: AppSelectionSnapshot? = nil,
        manualCommandRequested: Bool? = nil,
        startedAt: CFAbsoluteTime? = nil
    ) -> Bool {
        activeRecordingTriggerMode = triggerMode
        guard hasAccessibility else {
            errorMessage = "Accessibility permission required. Grant access in System Settings > Privacy & Security > Accessibility."
            statusText = "No Accessibility"
            activeRecordingTriggerMode = nil
            currentSessionIntent = .dictation
            shortcutSessionController.reset()
            showAccessibilityAlert()
            return false
        }
        if let startedAt {
            os_log(.info, log: recordingLog, "accessibility check passed: %.3fms", (CFAbsoluteTimeGetCurrent() - startedAt) * 1000)
        }

        let selectionSnapshot = selectionSnapshot ?? contextService.collectSelectionSnapshot()
        let manualCommandRequested = manualCommandRequested
            ?? hotkeyManager.currentPressedModifiers.contains(commandModeManualModifier.shortcutModifier)
        guard let resolvedIntent = resolveSessionIntent(
            triggerMode: triggerMode,
            selectionSnapshot: selectionSnapshot,
            manualCommandRequested: manualCommandRequested
        ) else { return false }

        if resolvedIntent.isCommandMode {
            guard ensureScreenCaptureAccess() else { return false }
            if let startedAt {
                os_log(.info, log: recordingLog, "screen capture check passed: %.3fms", (CFAbsoluteTimeGetCurrent() - startedAt) * 1000)
            }
        } else {
            hasScreenRecordingPermission = hasScreenCapturePermission()
        }

        currentSessionIntent = resolvedIntent
        overlayManager.setRecordingTriggerMode(triggerMode, animated: false)
        return true
    }

    private func ensureScreenCaptureAccess() -> Bool {
        let granted = hasScreenCapturePermission()
        hasScreenRecordingPermission = granted
        guard granted else {
            let message = "Screen recording permission not granted. Enable in System Settings > Privacy & Security > Screen Recording."
            errorMessage = message
            statusText = "Screenshot Required"
            activeRecordingTriggerMode = nil
            currentSessionIntent = .dictation
            shortcutSessionController.reset()
            playAlertSound(named: "Basso")
            showScreenshotPermissionAlert(message: message)
            return false
        }

        return true
    }

    private func ensureMicrophoneAccess() -> Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        switch status {
        case .authorized:
            return true
        case .notDetermined:
            guard let triggerMode = activeRecordingTriggerMode else {
                return false
            }

            prepareForMicrophonePermissionPrompt(triggerMode: triggerMode)
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                DispatchQueue.main.async {
                    guard let strongSelf = self else { return }
                    let pendingTriggerMode = strongSelf.pendingMicrophonePermissionTriggerMode
                    strongSelf.pendingMicrophonePermissionTriggerMode = nil
                    strongSelf.isAwaitingMicrophonePermission = false
                    strongSelf.restartHotkeyMonitoring()

                    guard let triggerMode = pendingTriggerMode else { return }
                    if granted {
                        strongSelf.errorMessage = nil
                        if triggerMode == .toggle {
                            guard strongSelf.prepareRecordingStart(triggerMode: .toggle) else { return }
                            strongSelf.shortcutSessionController.beginManual(mode: .toggle)
                            strongSelf.beginRecording(triggerMode: .toggle)
                        } else {
                            strongSelf.currentSessionIntent = .dictation
                            strongSelf.statusText = "Microphone access granted. Press and hold again to record."
                            strongSelf.scheduleReadyStatusReset(
                                after: 2,
                                matching: ["Microphone access granted. Press and hold again to record."]
                            )
                        }
                    } else {
                        strongSelf.errorMessage = "Microphone permission denied. Grant access in System Settings > Privacy & Security > Microphone."
                        strongSelf.statusText = "No Microphone"
                        strongSelf.activeRecordingTriggerMode = nil
                        strongSelf.currentSessionIntent = .dictation
                        strongSelf.shortcutSessionController.reset()
                        strongSelf.showMicrophonePermissionAlert()
                    }
                }
            }
            return false
        default:
            errorMessage = "Microphone permission denied. Grant access in System Settings > Privacy & Security > Microphone."
            statusText = "No Microphone"
            activeRecordingTriggerMode = nil
            currentSessionIntent = .dictation
            shortcutSessionController.reset()
            showMicrophonePermissionAlert()
            return false
        }
    }

    private func prepareForMicrophonePermissionPrompt(triggerMode: RecordingTriggerMode) {
        isAwaitingMicrophonePermission = true
        pendingMicrophonePermissionTriggerMode = triggerMode
        hotkeyManager.stop()
        shortcutSessionController.reset()
        activeRecordingTriggerMode = nil
        cancelRecordingInitializationTimer()
        audioRecorder.onRecordingReady = nil
        audioRecorder.onRecordingFailure = nil
        audioLevelCancellable?.cancel()
        audioLevelCancellable = nil
        overlayManager.dismiss()
    }

    private func beginRecording(triggerMode: RecordingTriggerMode) {
        os_log(.info, log: recordingLog, "beginRecording() entered")
        clearPendingOverlayDismissToken()
        errorMessage = nil

        isRecording = true
        statusText = "Starting..."
        hasShownScreenshotPermissionAlert = false

        // Show initializing dots only if engine takes longer than 0.2s to start
        var overlayShown = false
        cancelRecordingInitializationTimer()
        let initTimer = DispatchSource.makeTimerSource(queue: .main)
        recordingInitializationTimer = initTimer
        initTimer.schedule(deadline: .now() + 0.2)
        initTimer.setEventHandler { [weak self] in
            guard let self, !overlayShown else { return }
            overlayShown = true
            os_log(.info, log: recordingLog, "engine slow — showing initializing overlay")
            self.clearPendingOverlayDismissToken()
            self.overlayManager.showInitializing(
                mode: self.activeRecordingTriggerMode ?? triggerMode,
                isCommandMode: self.currentSessionIntent.isCommandMode
            )
        }
        initTimer.resume()

        // Transition to waveform when first real audio arrives (any non-zero RMS)
        let deviceUID = selectedMicrophoneID
        audioRecorder.onRecordingReady = { [weak self] in
            DispatchQueue.main.async {
                guard let self else { return }
                self.cancelRecordingInitializationTimer()
                os_log(.info, log: recordingLog, "first real audio — transitioning to waveform")
                self.statusText = "Recording..."
                self.clearPendingOverlayDismissToken()
                if overlayShown {
                    self.overlayManager.transitionToRecording(
                        mode: self.activeRecordingTriggerMode ?? triggerMode,
                        isCommandMode: self.currentSessionIntent.isCommandMode
                    )
                } else {
                    self.overlayManager.showRecording(
                        mode: self.activeRecordingTriggerMode ?? triggerMode,
                        isCommandMode: self.currentSessionIntent.isCommandMode
                    )
                }
                overlayShown = true
                self.playAlertSound(named: "Tink")
            }
        }
        audioRecorder.onRecordingFailure = { [weak self] error in
            DispatchQueue.main.async {
                guard let self else { return }
                self.cancelRecordingInitializationTimer()
                self.handleRecordingFailure(error)
            }
        }

        // Start engine on background thread so UI isn't blocked
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let t0 = CFAbsoluteTimeGetCurrent()
            do {
                try self.audioRecorder.startRecording(deviceUID: deviceUID)
                os_log(.info, log: recordingLog, "audioRecorder.startRecording() done: %.3fms", (CFAbsoluteTimeGetCurrent() - t0) * 1000)
                DispatchQueue.main.async {
                    guard self.isRecording, self.activeRecordingTriggerMode != nil else { return }
                    self.startContextCapture()
                    self.audioLevelCancellable = self.audioRecorder.$audioLevel
                        .receive(on: DispatchQueue.main)
                        .sink { [weak self] level in
                            self?.overlayManager.updateAudioLevel(level)
                        }
                }
            } catch {
                DispatchQueue.main.async {
                    self.cancelRecordingInitializationTimer()
                    guard self.isRecording || self.activeRecordingTriggerMode != nil else { return }
                    self.handleRecordingFailure(error)
                }
            }
        }
    }

    private func handleRecordingFailure(_ error: Error) {
        cancelRecordingInitializationTimer()
        audioRecorder.onRecordingReady = nil
        audioRecorder.onRecordingFailure = nil
        audioLevelCancellable?.cancel()
        audioLevelCancellable = nil
        contextCaptureTask?.cancel()
        contextCaptureTask = nil
        capturedContext = nil
        audioRecorder.cleanup()
        isRecording = false
        isTranscribing = false
        transcriptionTask?.cancel()
        transcriptionTask = nil
        transcribingIndicatorTask?.cancel()
        transcribingIndicatorTask = nil
        if let transcribingAudioFileName {
            Self.deleteAudioFile(transcribingAudioFileName)
            self.transcribingAudioFileName = nil
        }
        activeRecordingTriggerMode = nil
        currentSessionIntent = .dictation
        shortcutSessionController.reset()
        errorMessage = formattedRecordingStartError(error)
        statusText = "Error"
        overlayManager.dismiss()
        refreshAvailableMicrophonesIfNeeded()
    }

    private func formattedRecordingStartError(_ error: Error) -> String {
        if let recorderError = error as? AudioRecorderError {
            return "Failed to start recording: \(recorderError.localizedDescription)"
        }

        let lower = error.localizedDescription.lowercased()
        if lower.contains("operation couldn't be completed") || lower.contains("operation could not be completed") {
            return "Failed to start recording: Audio input error. Verify microphone access is granted and a working mic is selected in System Settings > Sound > Input."
        }

        let nsError = error as NSError
        if nsError.domain == NSOSStatusErrorDomain {
            return "Failed to start recording (audio subsystem error \(nsError.code)). Check microphone permissions and selected input device."
        }

        return "Failed to start recording: \(error.localizedDescription)"
    }

    func showMicrophonePermissionAlert() {
        let alert = NSAlert()
        alert.messageText = "Microphone Permission Required"
        alert.informativeText = "FreeFlow cannot record audio without Microphone access.\n\nGo to System Settings > Privacy & Security > Microphone and enable FreeFlow."
        alert.alertStyle = .critical
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Dismiss")
        alert.icon = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: nil)

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            openMicrophoneSettings()
        }
    }

    func showAccessibilityAlert() {
        let alert = NSAlert()
        alert.messageText = "Accessibility Permission Required"
        alert.informativeText = "FreeFlow cannot type transcriptions without Accessibility access.\n\nGo to System Settings > Privacy & Security > Accessibility and enable FreeFlow."
        alert.alertStyle = .critical
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Dismiss")
        alert.icon = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: nil)

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            openAccessibilitySettings()
        }
    }

    private func precomputeMacros() {
        precomputedMacros = voiceMacros.map { macro in
            PrecomputedMacro(
                original: macro,
                normalizedCommand: normalize(macro.command)
            )
        }
    }

    private func normalize(_ text: String) -> String {
        let lowercased = text.lowercased()
        let strippedPunctuation = lowercased.components(separatedBy: CharacterSet.punctuationCharacters).joined()
        return strippedPunctuation.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func playAlertSound(named name: String) {
        guard alertSoundsEnabled else { return }

        let sound = NSSound(named: name)
        sound?.volume = soundVolume
        sound?.play()
    }

    private func findMatchingMacro(for transcript: String) -> VoiceMacro? {
        let normalizedTranscript = normalize(transcript)
        guard !normalizedTranscript.isEmpty else { return nil }

        return precomputedMacros.first {
            normalizedTranscript == $0.normalizedCommand
        }?.original
    }

    private enum TranscriptProcessingOutcome {
        case skippedEmptyRawTranscript
        case voiceMacro(command: String)
        case postProcessingSucceeded
        case postProcessingFailedFallback
        case commandModeSucceeded(invocation: CommandInvocation)
        case commandModeFailedFallback(invocation: CommandInvocation)

        func statusMessage(isRetry: Bool = false) -> String {
            switch self {
            case .skippedEmptyRawTranscript:
                return "Skipped macros and post-processing for empty raw transcript"
            case .voiceMacro(let command):
                return "Voice macro used: \(command)"
            case .postProcessingSucceeded:
                return isRetry ? "Post-processing succeeded (retried)" : "Post-processing succeeded"
            case .postProcessingFailedFallback:
                return isRetry
                    ? "Post-processing failed on retry, using raw transcript"
                    : "Post-processing failed, using raw transcript"
            case .commandModeSucceeded(let invocation):
                return "Edit mode succeeded (\(invocation.rawValue))"
            case .commandModeFailedFallback(let invocation):
                return "Edit mode failed, using selected text (\(invocation.rawValue))"
            }
        }
    }

    private func processTranscript(
        _ rawTranscript: String,
        intent: SessionIntent,
        context: AppContext,
        postProcessingService: PostProcessingService,
        customVocabulary: String,
        customSystemPrompt: String,
        outputLanguage: String = ""
    ) async -> (finalTranscript: String, outcome: TranscriptProcessingOutcome, prompt: String) {
        let trimmedRawTranscript = rawTranscript.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedRawTranscript.isEmpty else {
            return ("", .skippedEmptyRawTranscript, "")
        }

        if case .command(let invocation, let selectedText) = intent {
            do {
                let result = try await postProcessingService.commandTransform(
                    selectedText: selectedText,
                    voiceCommand: rawTranscript,
                    context: context,
                    customVocabulary: customVocabulary,
                    outputLanguage: outputLanguage
                )
                return (result.transcript, .commandModeSucceeded(invocation: invocation), result.prompt)
            } catch {
                os_log(.error, log: recordingLog, "Edit mode failed: %{public}@", error.localizedDescription)
                return (selectedText, .commandModeFailedFallback(invocation: invocation), "")
            }
        }

        if let macro = findMatchingMacro(for: trimmedRawTranscript) {
            os_log(.info, log: recordingLog, "Voice macro triggered: %{public}@", macro.command)
            return (macro.payload, .voiceMacro(command: macro.command), "")
        }
        
        do {
            let result = try await postProcessingService.postProcess(
                transcript: trimmedRawTranscript,
                context: context,
                customVocabulary: customVocabulary,
                customSystemPrompt: customSystemPrompt,
                outputLanguage: outputLanguage
            )
            return (result.transcript, .postProcessingSucceeded, result.prompt)
        } catch {
            os_log(.error, log: recordingLog, "Post-processing failed: %{public}@", error.localizedDescription)
            return (trimmedRawTranscript, .postProcessingFailedFallback, "")
        }
    }

    private func stopAndTranscribe() {
        cancelPendingShortcutStart()
        cancelRecordingInitializationTimer()
        shortcutSessionController.reset()
        activeRecordingTriggerMode = nil
        let sessionIntent = currentSessionIntent
        currentSessionIntent = .dictation
        audioRecorder.onRecordingReady = nil
        audioRecorder.onRecordingFailure = nil
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
        isRecording = false
        isTranscribing = true
        statusText = "Preparing audio..."
        errorMessage = nil
        playAlertSound(named: "Pop")
        overlayManager.prepareForTranscribing()
        audioRecorder.stopRecording { [weak self] fileURL in
            guard let self else { return }
            guard let fileURL else {
                self.isTranscribing = false
                self.audioRecorder.cleanup()
                self.errorMessage = "No audio recorded"
                self.statusText = "Error"
                self.overlayManager.dismiss()
                self.refreshAvailableMicrophonesIfNeeded()
                return
            }

            let savedAudioFile = Self.saveAudioFile(from: fileURL)
            let transcriptionFileURL = savedAudioFile?.fileURL ?? fileURL
            self.transcribingAudioFileName = savedAudioFile?.fileName
            self.statusText = "Transcribing..."
            self.debugStatusMessage = "Transcribing audio"

            self.transcribingIndicatorTask?.cancel()
            let indicatorDelay = self.transcribingIndicatorDelay
            self.transcribingIndicatorTask = Task { [weak self] in
                do {
                    try await Task.sleep(nanoseconds: UInt64(indicatorDelay * 1_000_000_000))
                    let shouldShowTranscribing = self?.isTranscribing ?? false
                    guard shouldShowTranscribing else { return }
                    await MainActor.run { [weak self] in
                        self?.overlayManager.showTranscribing()
                    }
                } catch {}
            }

        let postProcessingService = PostProcessingService(
            apiKey: apiKey,
            baseURL: apiBaseURL,
            preferredModel: postProcessingModel,
            preferredFallbackModel: postProcessingFallbackModel
        )

            self.transcriptionTask?.cancel()
            self.transcriptionTask = Task {
                do {
                    let transcriptionService = try TranscriptionService(
                        apiKey: self.apiKey,
                        baseURL: self.apiBaseURL,
                        transcriptionModel: self.transcriptionModel
                    )
                    async let transcript = transcriptionService.transcribe(fileURL: transcriptionFileURL)
                    let rawTranscript = try await transcript
                    try Task.checkCancellation()
                    let appContext: AppContext
                    if let sessionContext {
                        appContext = sessionContext
                    } else if let inFlightContext = await inFlightContextTask?.value {
                        appContext = inFlightContext
                    } else {
                        appContext = self.fallbackContextAtStop()
                    }
                    try Task.checkCancellation()
                    await MainActor.run { [weak self] in
                        self?.debugStatusMessage = "Running post-processing"
                    }
                    let result = await self.processTranscript(
                        rawTranscript,
                        intent: sessionIntent,
                        context: appContext,
                        postProcessingService: postProcessingService,
                        customVocabulary: self.customVocabulary,
                        customSystemPrompt: self.customSystemPrompt,
                        outputLanguage: self.outputLanguage
                    )
                    try Task.checkCancellation()

                    await MainActor.run {
                        guard self.isTranscribing else { return }
                        self.lastContextSummary = appContext.contextSummary
                        self.lastContextScreenshotDataURL = appContext.screenshotDataURL
                        self.lastContextScreenshotStatus = appContext.screenshotError
                            ?? "available (\(appContext.screenshotMimeType ?? "image"))"
                        let trimmedRawTranscript = rawTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
                        let trimmedFinalTranscript = result.finalTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
                        let processingStatus = result.outcome.statusMessage()
                        self.lastPostProcessingPrompt = result.prompt
                        self.lastRawTranscript = trimmedRawTranscript
                        self.lastPostProcessedTranscript = trimmedFinalTranscript
                        self.lastPostProcessingStatus = processingStatus
                        self.recordPipelineHistoryEntry(
                            rawTranscript: trimmedRawTranscript,
                            postProcessedTranscript: trimmedFinalTranscript,
                            postProcessingPrompt: result.prompt,
                            context: appContext,
                            processingStatus: processingStatus,
                            intent: sessionIntent,
                            audioFileName: savedAudioFile?.fileName
                        )
                        self.transcriptionTask = nil
                        self.transcribingIndicatorTask?.cancel()
                        self.transcribingIndicatorTask = nil
                        self.transcribingAudioFileName = nil
                        self.lastTranscript = trimmedFinalTranscript
                        self.isTranscribing = false
                        self.debugStatusMessage = "Done"
                        let completionStatusText = self.preserveClipboard ? "Pasted at cursor!" : "Copied to clipboard!"

                        let shouldPersistRawDictationFallback: Bool
                        switch result.outcome {
                        case .postProcessingFailedFallback:
                            shouldPersistRawDictationFallback = !trimmedFinalTranscript.isEmpty
                        default:
                            shouldPersistRawDictationFallback = false
                        }

                        if trimmedFinalTranscript.isEmpty {
                            self.statusText = "Nothing to transcribe"
                            self.clearPendingOverlayDismissToken()
                            self.overlayManager.dismiss()
                        } else {
                            self.statusText = completionStatusText
                            if shouldPersistRawDictationFallback {
                                self.scheduleOverlayDismissAfterFailureIndicator(after: 2.5)
                            } else {
                                self.clearPendingOverlayDismissToken()
                                self.overlayManager.dismiss()
                            }

                            let pendingClipboardRestore = self.writeTranscriptToPasteboard(trimmedFinalTranscript)
                            self.pasteAtCursorWhenShortcutReleased {
                                self.restoreClipboardIfNeeded(pendingClipboardRestore)
                            }
                        }

                        self.audioRecorder.cleanup()
                        self.refreshAvailableMicrophonesIfNeeded()

                        self.scheduleReadyStatusReset(after: 3, matching: [completionStatusText, "Nothing to transcribe"])
                    }
                } catch is CancellationError {
                    await MainActor.run {
                        self.transcriptionTask = nil
                    }
                } catch {
                    let resolvedContext: AppContext
                    if let sessionContext {
                        resolvedContext = sessionContext
                    } else if let inFlightContext = await inFlightContextTask?.value {
                        resolvedContext = inFlightContext
                    } else {
                        resolvedContext = self.fallbackContextAtStop()
                    }
                    await MainActor.run {
                        guard self.isTranscribing else { return }
                        self.transcriptionTask = nil
                        self.transcribingIndicatorTask?.cancel()
                        self.transcribingIndicatorTask = nil
                        self.transcribingAudioFileName = nil
                        self.errorMessage = error.localizedDescription
                        self.isTranscribing = false
                        self.statusText = "Error"
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
                            processingStatus: "Error: \(error.localizedDescription)",
                            intent: sessionIntent,
                            audioFileName: savedAudioFile?.fileName
                        )
                        self.audioRecorder.cleanup()
                        self.refreshAvailableMicrophonesIfNeeded()
                    }
                }
            }
        }
    }

    private func recordPipelineHistoryEntry(
        rawTranscript: String,
        postProcessedTranscript: String,
        postProcessingPrompt: String,
        context: AppContext,
        processingStatus: String,
        intent: SessionIntent,
        audioFileName: String? = nil
    ) {
        let newEntry = PipelineHistoryItem(
            intent: intent.persistedIntent,
            selectedText: intent.persistedSelectedText,
            timestamp: Date(),
            rawTranscript: rawTranscript,
            postProcessedTranscript: postProcessedTranscript,
            postProcessingPrompt: postProcessingPrompt,
            contextSummary: context.contextSummary,
            contextPrompt: context.contextPrompt,
            contextScreenshotDataURL: context.screenshotDataURL,
            contextScreenshotStatus: context.screenshotError
                ?? "available (\(context.screenshotMimeType ?? "image"))",
            postProcessingStatus: processingStatus,
            debugStatus: debugStatusMessage,
            customVocabulary: customVocabulary,
            audioFileName: audioFileName
        )
        do {
            let removedAudioFileNames = try pipelineHistoryStore.append(newEntry, maxCount: maxPipelineHistoryCount)
            for audioFileName in removedAudioFileNames {
                Self.deleteAudioFile(audioFileName)
            }
            pipelineHistory = pipelineHistoryStore.loadAllHistory()
        } catch {
            errorMessage = "Unable to save run history entry: \(error.localizedDescription)"
        }
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
        let windowTitle = focusedWindowTitle(for: frontmostApp)
        return AppContext(
            appName: frontmostApp?.localizedName,
            bundleIdentifier: frontmostApp?.bundleIdentifier,
            windowTitle: windowTitle,
            selectedText: nil,
            currentActivity: "Could not refresh app context at stop time; using text-only post-processing.",
            contextPrompt: nil,
            screenshotDataURL: nil,
            screenshotMimeType: nil,
            screenshotError: "No app context captured before stop"
        )
    }

    private func focusedWindowTitle(for app: NSRunningApplication?) -> String? {
        guard let app else { return nil }
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        return focusedWindowTitle(from: appElement)
    }

    private func focusedWindowTitle(from appElement: AXUIElement) -> String? {
        guard let focusedWindow = accessibilityElement(from: appElement, attribute: kAXFocusedWindowAttribute as CFString) else {
            return nil
        }

        guard let windowTitle = accessibilityString(from: focusedWindow, attribute: kAXTitleAttribute as CFString) else {
            return nil
        }

        return trimmedText(windowTitle)
    }

    private func accessibilityElement(from element: AXUIElement, attribute: CFString) -> AXUIElement? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute, &value)
        guard result == .success,
              let rawValue = value,
              CFGetTypeID(rawValue) == AXUIElementGetTypeID() else {
            return nil
        }
        return unsafeBitCast(rawValue, to: AXUIElement.self)
    }

    private func accessibilityString(from element: AXUIElement, attribute: CFString) -> String? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute, &value)
        guard result == .success, let stringValue = value as? String else { return nil }
        return stringValue
    }

    private func trimmedText(_ value: String) -> String? {
        let trimmed = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")
        return trimmed.isEmpty ? nil : trimmed
    }

    private func handleScreenshotCaptureIssue(_ message: String?) {
        guard let message, !message.isEmpty else {
            hasShownScreenshotPermissionAlert = false
            return
        }

        os_log(.error, "Screenshot capture issue: %{public}@", message)

        if isScreenCapturePermissionError(message) && !hasShownScreenshotPermissionAlert {
            hasScreenRecordingPermission = false
            guard currentSessionIntent.isCommandMode else { return }
            errorMessage = message
            hasShownScreenshotPermissionAlert = true

            // Permission errors are fatal — stop recording
            audioRecorder.cancelRecording()
            audioLevelCancellable?.cancel()
            audioLevelCancellable = nil
            contextCaptureTask?.cancel()
            contextCaptureTask = nil
            capturedContext = nil
            isRecording = false
            shortcutSessionController.reset()
            activeRecordingTriggerMode = nil
            statusText = "Screenshot Required"
            overlayManager.dismiss()

            playAlertSound(named: "Basso")
            showScreenshotPermissionAlert(message: message)
        }
        // Non-permission errors (transient failures) — continue recording without context
    }

    private func isScreenCapturePermissionError(_ message: String) -> Bool {
        let lowered = message.lowercased()
        return lowered.contains("permission") || lowered.contains("screen recording")
    }

    private func showScreenshotPermissionAlert(message: String) {
        let alert = NSAlert()
        alert.messageText = "Screen Recording Permission Required"
        alert.informativeText = "\(message)\n\nFreeFlow requires Screen Recording permission to capture screenshots for context-aware transcription.\n\nGo to System Settings > Privacy & Security > Screen Recording and enable FreeFlow."
        alert.alertStyle = .critical
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Dismiss")
        alert.icon = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: nil)

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            openScreenCaptureSettings()
        }
    }

    private func showScreenshotCaptureErrorAlert(message: String) {
        let alert = NSAlert()
        alert.messageText = "Screenshot Capture Failed"
        alert.informativeText = "\(message)\n\nA screenshot is required for context-aware transcription. Recording has been stopped."
        alert.alertStyle = .critical
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
        clearPendingOverlayDismissToken()
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
        clearPendingOverlayDismissToken()
        overlayManager.dismiss()
    }

    private func clearPendingOverlayDismissToken() {
        pendingOverlayDismissToken = nil
    }

    private func scheduleOverlayDismissAfterFailureIndicator(after delay: TimeInterval) {
        let dismissToken = UUID()
        pendingOverlayDismissToken = dismissToken
        overlayManager.showFailureIndicator()
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, self.pendingOverlayDismissToken == dismissToken else { return }
            self.pendingOverlayDismissToken = nil
            self.overlayManager.dismiss()
        }
    }

    func toggleDebugPanel() {
        selectedSettingsTab = .runLog
        NotificationCenter.default.post(name: .showSettings, object: nil)
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

    private func writeTranscriptToPasteboard(_ transcript: String) -> PendingClipboardRestore? {
        let pasteboard = NSPasteboard.general
        let snapshot = preserveClipboard ? PreservedPasteboardSnapshot(pasteboard: pasteboard) : nil

        pasteboard.clearContents()
        pasteboard.setString(transcript, forType: .string)

        guard let snapshot else { return nil }
        return PendingClipboardRestore(snapshot: snapshot, expectedChangeCount: pasteboard.changeCount)
    }

    private func restoreClipboardIfNeeded(_ pendingRestore: PendingClipboardRestore?) {
        guard let pendingRestore else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + clipboardRestoreDelay) {
            let pasteboard = NSPasteboard.general
            guard pasteboard.changeCount == pendingRestore.expectedChangeCount else { return }
            pendingRestore.snapshot.restore(to: pasteboard)
        }
    }

    private func pasteAtCursorWhenShortcutReleased(attempt: Int = 0, completion: (() -> Void)? = nil) {
        let maxAttempts = 24
        if hotkeyManager.hasPressedShortcutInputs && attempt < maxAttempts {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.025) { [weak self] in
                self?.pasteAtCursorWhenShortcutReleased(attempt: attempt + 1, completion: completion)
            }
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) { [weak self] in
            self?.pasteAtCursor()
            completion?()
        }
    }

    private func cancelRecordingInitializationTimer() {
        recordingInitializationTimer?.cancel()
        recordingInitializationTimer = nil
    }

    private func scheduleReadyStatusReset(after delay: TimeInterval, matching statuses: Set<String>? = nil) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else { return }
            if let statuses, !statuses.contains(self.statusText) {
                return
            }
            self.statusText = "Ready"
        }
    }
}
