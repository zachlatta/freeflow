import Foundation

public struct VoiceMacro: Codable, Identifiable, Equatable, Hashable {
    public var id: UUID
    public var command: String
    public var payload: String

    public init(id: UUID = UUID(), command: String, payload: String) {
        self.id = id
        self.command = command
        self.payload = payload
    }
}

enum VoiceMacroMatcher {
    static func findMatch(for transcript: String, in macros: [VoiceMacro]) -> VoiceMacro? {
        let normalizedTranscript = normalize(transcript)
        guard !normalizedTranscript.isEmpty else { return nil }
        return macros.first { normalizedTranscript == normalize($0.command) }
    }

    private static func normalize(_ text: String) -> String {
        let lowercased = text.lowercased()
        let stripped = lowercased.components(separatedBy: CharacterSet.punctuationCharacters).joined()
        return stripped.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
