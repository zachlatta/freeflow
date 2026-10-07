import Foundation

/// A streaming transcription socket that receives microphone audio while the
/// user dictates and produces the transcript when the dictation ends.
///
/// Two implementations exist because the providers speak different protocols:
/// ``RealtimeTranscriptionService`` for OpenAI-compatible realtime endpoints,
/// and ``GeminiLiveTranscriptionService`` for the Gemini Live API.
protocol RealtimeTranscriptBackend: AnyObject {
    /// Partial transcript updates, delivered on the main queue.
    var onPartialUpdate: ((String) -> Void)? { get set }

    func start() throws
    func appendPCM16(_ data: Data)
    func commitAndAwaitFinal() async throws -> String
    func cancel()
}
