enum LocalTranscriptionPolicyTests {
    static func run() {
        let local = LocalTranscriptionPolicy(isEnabled: true)
        TestSupport.expect(!local.allowsContextCapture, "Local mode allowed context capture")
        TestSupport.expect(!local.allowsRealtimeStreaming, "Local mode allowed realtime streaming")
        TestSupport.expect(!local.allowsLanguageModelProcessing, "Local mode allowed LLM processing")

        let remote = LocalTranscriptionPolicy(isEnabled: false)
        TestSupport.expect(remote.allowsContextCapture, "Remote mode lost context capture")
        TestSupport.expect(remote.allowsRealtimeStreaming, "Remote mode lost realtime streaming")
        TestSupport.expect(remote.allowsLanguageModelProcessing, "Remote mode lost LLM processing")
    }
}
