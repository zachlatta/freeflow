struct LocalTranscriptionPolicy: Equatable {
    let isEnabled: Bool

    var allowsContextCapture: Bool { !isEnabled }
    var allowsRealtimeStreaming: Bool { !isEnabled }
    var allowsLanguageModelProcessing: Bool { !isEnabled }
}
