import Foundation

struct VoiceMacro: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var command: String
    var payload: String

    init(id: UUID = UUID(), command: String, payload: String) {
        self.id = id
        self.command = command
        self.payload = payload
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        command = try container.decode(String.self, forKey: .command)
        payload = try container.decode(String.self, forKey: .payload)
    }
}

enum JSONPreferences {
    static func data(forKey key: String, in defaults: UserDefaults = .standard) -> Data? {
        if let data = defaults.data(forKey: key) {
            return data
        }
        return (defaults.object(forKey: key) as? String)?.data(using: .utf8)
    }
}
