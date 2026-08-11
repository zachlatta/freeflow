import Foundation

enum PipelineHistoryItemIntent: String, Codable {
    case dictation
    case commandAutomatic = "command:automatic"
    case commandManual = "command:manual"
}

struct PipelineHistoryItem: Identifiable, Codable {
    let intent: PipelineHistoryItemIntent
    let selectedText: String?
    let capturedSelection: String?
    let id: UUID
    let timestamp: Date
    let rawTranscript: String
    let postProcessedTranscript: String
    let postProcessingPrompt: String?
    let systemPrompt: String?
    let contextSummary: String
    let contextSystemPrompt: String?
    let contextPrompt: String?
    let contextScreenshotDataURL: String?
    let contextScreenshotStatus: String
    let postProcessingStatus: String
    let debugStatus: String
    let customVocabulary: String
    let audioFileName: String?
    let contextAppName: String?
    let contextBundleIdentifier: String?
    let contextWindowTitle: String?
    /// Text just before the cursor when this dictation ran (nil if the read failed).
    let precedingText: String?
    /// Text just after the cursor when this dictation ran (nil if the read failed).
    let followingText: String?
    /// The transcript after smart-paste formatting (spacing/casing) was applied.
    let formattedTranscript: String?
    /// Where the cursor sat in the field (e.g. start/middle/end/unknown) for this dictation.
    /// Persisted for parity with the live debug panel; not shown in the history list.
    let cursorPosition: String?
    /// Which smart-paste formatting rule was applied to this dictation.
    let contextFormatRule: String?
    /// True when the accessibility read found no surrounding text (a "blind" app).
    /// Persisted for parity with the live debug panel; not shown in the history list.
    /// Optional so history persisted before these fields existed still decodes.
    let isBlindApp: Bool?
    /// Which read method produced the surrounding text (e.g. axAPI, axWebTextMarker).
    let extractionMethod: String?
    /// App kind: "native", "webView", or "unknown". Optional for backward-compatible decoding.
    let appKind: String?

    init(
        intent: PipelineHistoryItemIntent = .dictation,
        selectedText: String? = nil,
        capturedSelection: String? = nil,
        id: UUID = UUID(),
        timestamp: Date,
        rawTranscript: String,
        postProcessedTranscript: String,
        postProcessingPrompt: String?,
        systemPrompt: String? = nil,
        contextSummary: String,
        contextSystemPrompt: String? = nil,
        contextPrompt: String? = nil,
        contextScreenshotDataURL: String?,
        contextScreenshotStatus: String,
        postProcessingStatus: String,
        debugStatus: String,
        customVocabulary: String,
        audioFileName: String? = nil,
        contextAppName: String? = nil,
        contextBundleIdentifier: String? = nil,
        contextWindowTitle: String? = nil,
        precedingText: String? = nil,
        followingText: String? = nil,
        formattedTranscript: String? = nil,
        cursorPosition: String? = nil,
        contextFormatRule: String? = nil,
        isBlindApp: Bool? = false,
        extractionMethod: String? = nil,
        appKind: String? = nil
    ) {
        self.intent = intent
        self.selectedText = selectedText
        self.capturedSelection = capturedSelection
        self.id = id
        self.timestamp = timestamp
        self.rawTranscript = rawTranscript
        self.postProcessedTranscript = postProcessedTranscript
        self.postProcessingPrompt = postProcessingPrompt
        self.systemPrompt = systemPrompt
        self.contextSummary = contextSummary
        self.contextSystemPrompt = contextSystemPrompt
        self.contextPrompt = contextPrompt
        self.contextScreenshotDataURL = contextScreenshotDataURL
        self.contextScreenshotStatus = contextScreenshotStatus
        self.postProcessingStatus = postProcessingStatus
        self.debugStatus = debugStatus
        self.customVocabulary = customVocabulary
        self.audioFileName = audioFileName
        self.contextAppName = contextAppName
        self.contextBundleIdentifier = contextBundleIdentifier
        self.contextWindowTitle = contextWindowTitle
        self.precedingText = precedingText
        self.followingText = followingText
        self.formattedTranscript = formattedTranscript
        self.cursorPosition = cursorPosition
        self.contextFormatRule = contextFormatRule
        self.isBlindApp = isBlindApp
        self.extractionMethod = extractionMethod
        self.appKind = appKind
    }
}
